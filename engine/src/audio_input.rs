use anyhow::Result;
/// Audio input and recording functionality
use cpal::traits::{DeviceTrait, HostTrait};
use parking_lot::Mutex;
use ringbuf::{
    traits::{Consumer, Observer, Producer},
    HeapRb,
};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;

use crate::audio_file::TARGET_SAMPLE_RATE;

/// Represents an audio input device
#[derive(Clone, Debug)]
pub struct AudioInputDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

/// Which input device the user asked for (Settings → Audio → Input).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum InputChoice {
    /// Follow the operating system's default input, looked up each time the
    /// input opens so plugging in an interface just works.
    #[default]
    SystemDefault,
    /// A specific device, by name. Falls back to the system default when it
    /// isn't connected.
    Named(String),
    /// Never open an input.
    Off,
}

/// The device an [`InputChoice`] resolves to right now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResolvedInput {
    pub name: String,
    /// The named device wasn't connected, so the system default was used.
    pub fell_back: bool,
}

/// Pick the device to open for `choice` from the connected `devices`.
/// `None` when the input is off or nothing is connected.
pub fn resolve_input(
    choice: &InputChoice,
    devices: &[String],
    system_default: Option<&str>,
) -> Option<ResolvedInput> {
    let default_name = || {
        system_default
            .filter(|d| devices.iter().any(|n| n == d))
            .or_else(|| devices.first().map(String::as_str))
            .map(str::to_string)
    };
    match choice {
        InputChoice::Off => None,
        InputChoice::SystemDefault => default_name().map(|name| ResolvedInput {
            name,
            fell_back: false,
        }),
        InputChoice::Named(wanted) => {
            if devices.iter().any(|n| n == wanted) {
                Some(ResolvedInput {
                    name: wanted.clone(),
                    fell_back: false,
                })
            } else {
                default_name().map(|name| ResolvedInput {
                    name,
                    fell_back: true,
                })
            }
        }
    }
}

/// Audio input manager that handles device enumeration and recording
pub struct AudioInputManager {
    /// Available input devices
    devices: Vec<AudioInputDevice>,
    /// The device the user asked for
    choice: InputChoice,
    /// The device the input last opened on (or would open on, after a probe)
    active: Option<ResolvedInput>,
    /// Input stream (if active)
    input_stream: Option<cpal::Stream>,
    /// Ring buffer for captured audio (lock-free, thread-safe)
    /// Stores raw samples (mono or stereo depending on device)
    input_buffer: Option<Arc<Mutex<HeapRb<f32>>>>,
    /// Number of input channels (1 = mono, 2 = stereo)
    input_channels: u16,
    /// Peak levels per channel (stored as f32 bits in `AtomicU32` for lock-free access)
    /// Updated in the input callback, read by the UI for metering
    input_peak_left: Arc<AtomicU32>,
    input_peak_right: Arc<AtomicU32>,
}

impl AudioInputManager {
    /// Create a new audio input manager
    pub fn new() -> Result<Self> {
        Ok(Self {
            devices: Vec::new(),
            choice: InputChoice::default(),
            active: None,
            input_stream: None,
            input_buffer: None,
            input_channels: 1, // Default to mono
            input_peak_left: Arc::new(AtomicU32::new(0)),
            input_peak_right: Arc::new(AtomicU32::new(0)),
        })
    }

    /// Enumerate available audio input devices
    pub fn enumerate_devices(&mut self) -> Result<Vec<AudioInputDevice>> {
        let host = cpal::default_host();
        let mut devices = Vec::new();

        // Get default input device
        let default_device = host.default_input_device();
        let default_name = default_device
            .as_ref()
            .and_then(|d| d.name().ok())
            .unwrap_or_else(|| "Unknown".to_string());

        // Enumerate all input devices
        for (idx, device) in host.input_devices()?.enumerate() {
            let name = device
                .name()
                .unwrap_or_else(|_| format!("Input Device {idx}"));
            let is_default = name == default_name;

            devices.push(AudioInputDevice {
                id: format!("input_{idx}"),
                name,
                is_default,
            });
        }

        // If no devices found but we have a default, add it
        if devices.is_empty() && default_device.is_some() {
            devices.push(AudioInputDevice {
                id: "input_0".to_string(),
                name: default_name,
                is_default: true,
            });
        }

        self.devices.clone_from(&devices);
        Ok(devices)
    }

    /// Get the list of available input devices
    pub fn get_devices(&self) -> Vec<AudioInputDevice> {
        self.devices.clone()
    }

    /// Set which input to use. Takes effect the next time the input opens.
    pub fn set_choice(&mut self, choice: InputChoice) {
        self.choice = choice;
    }

    pub fn choice(&self) -> &InputChoice {
        &self.choice
    }

    /// The device the input last opened on or was last probed for.
    pub fn active(&self) -> Option<&ResolvedInput> {
        self.active.as_ref()
    }

    /// Resolve the choice against the devices connected right now and open
    /// nothing. Returns the device's channel count (0 when off or absent).
    pub fn probe(&mut self) -> Result<u16> {
        let Some(device) = self.resolve_device()? else {
            return Ok(0);
        };
        Ok(device.default_input_config()?.channels())
    }

    /// Find the cpal device for the current choice, refreshing the device
    /// list and `active` on the way.
    fn resolve_device(&mut self) -> Result<Option<cpal::Device>> {
        let host = cpal::default_host();
        let default_name = host.default_input_device().and_then(|d| d.name().ok());
        let mut connected: Vec<(String, cpal::Device)> = host
            .input_devices()?
            .filter_map(|d| d.name().ok().map(|name| (name, d)))
            .collect();
        let names: Vec<String> = connected.iter().map(|(n, _)| n.clone()).collect();

        self.active = resolve_input(&self.choice, &names, default_name.as_deref());
        let Some(active) = &self.active else {
            return Ok(None);
        };
        let idx = connected
            .iter()
            .position(|(n, _)| n == &active.name)
            .ok_or_else(|| anyhow::anyhow!("Input device disappeared: {}", active.name))?;
        Ok(Some(connected.swap_remove(idx).1))
    }

    /// Start capturing audio from the chosen input device
    /// This creates an input stream and begins filling the ring buffer
    pub fn start_capture(&mut self, buffer_size_seconds: f64) -> Result<()> {
        use cpal::traits::StreamTrait;

        if self.choice == InputChoice::Off {
            return Err(anyhow::anyhow!("Input is off"));
        }
        let device = self
            .resolve_device()?
            .ok_or_else(|| anyhow::anyhow!("No audio input device connected"))?;
        let config = device.default_input_config()?;

        println!("Starting audio capture:");
        println!("  Device: {}", device.name()?);
        println!("  Config: {config:?}");

        // Store the number of input channels
        self.input_channels = config.channels();
        eprintln!(
            "🎙️  [AudioInput] Input channels: {} (1=mono, 2=stereo)",
            self.input_channels
        );

        // Create ring buffer (stereo, size based on buffer_size_seconds)
        let buffer_samples = (buffer_size_seconds * f64::from(TARGET_SAMPLE_RATE) * 2.0) as usize;
        let ring_buffer: HeapRb<f32> = HeapRb::new(buffer_samples);
        let ring_buffer_arc = Arc::new(Mutex::new(ring_buffer));
        let ring_buffer_clone = ring_buffer_arc.clone();

        // Clone peak tracking atomics for use in the callback
        let peak_left = self.input_peak_left.clone();
        let peak_right = self.input_peak_right.clone();
        let num_channels = self.input_channels;

        // Create input stream
        let stream = device.build_input_stream(
            &config.into(),
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                // Track peak levels per channel
                let mut max_left: f32 = 0.0;
                let mut max_right: f32 = 0.0;

                if num_channels == 1 {
                    // Mono: all samples are the same channel
                    for &sample in data {
                        let abs = sample.abs();
                        if abs > max_left {
                            max_left = abs;
                        }
                    }
                    max_right = max_left;
                } else {
                    // Stereo (or more): interleaved L R L R ...
                    for (i, &sample) in data.iter().enumerate() {
                        let abs = sample.abs();
                        if i % 2 == 0 {
                            if abs > max_left {
                                max_left = abs;
                            }
                        } else if abs > max_right {
                            max_right = abs;
                        }
                    }
                }

                // Update peak atomics (store f32 bits as u32)
                peak_left.store(max_left.to_bits(), Ordering::Relaxed);
                peak_right.store(max_right.to_bits(), Ordering::Relaxed);

                // Write input samples to ring buffer
                {
                    let mut buffer = ring_buffer_clone.lock();
                    for &sample in data {
                        // If buffer is full, drop oldest samples
                        if buffer.is_full() {
                            let _ = buffer.try_pop();
                        }
                        let _ = buffer.try_push(sample);
                    }
                }
            },
            move |err| {
                eprintln!("Audio input stream error: {err}");
            },
            None,
        )?;

        stream.play()?;

        self.input_stream = Some(stream);
        self.input_buffer = Some(ring_buffer_arc);

        Ok(())
    }

    /// Stop capturing audio
    pub fn stop_capture(&mut self) -> Result<()> {
        if let Some(stream) = self.input_stream.take() {
            use cpal::traits::StreamTrait;
            stream.pause()?;
            drop(stream);
        }
        self.input_buffer = None;
        Ok(())
    }

    /// Check if currently capturing audio
    pub fn is_capturing(&self) -> bool {
        self.input_stream.is_some()
    }

    /// Read captured audio samples from the ring buffer
    /// Returns samples in interleaved stereo format
    pub fn read_samples(&self, num_samples: usize) -> Option<Vec<f32>> {
        if let Some(buffer_arc) = &self.input_buffer {
            {
                let mut buffer = buffer_arc.lock();
                let mut samples = Vec::with_capacity(num_samples);
                for _ in 0..num_samples {
                    if let Some(sample) = buffer.try_pop() {
                        samples.push(sample);
                    } else {
                        break;
                    }
                }
                return Some(samples);
            }
        }
        None
    }

    /// Get the number of samples currently in the buffer
    pub fn get_buffer_fill(&self) -> usize {
        if let Some(buffer_arc) = &self.input_buffer {
            {
                let buffer = buffer_arc.lock();
                return buffer.occupied_len();
            }
        }
        0
    }

    /// Clear the input buffer
    pub fn clear_buffer(&self) {
        if let Some(buffer_arc) = &self.input_buffer {
            {
                let mut buffer = buffer_arc.lock();
                buffer.clear();
            }
        }
    }

    /// Get the number of input channels (1 = mono, 2 = stereo)
    pub fn get_input_channels(&self) -> u16 {
        self.input_channels
    }

    /// Get peak level for a specific input channel (0 = left, 1 = right)
    /// Returns the peak amplitude (0.0 to 1.0+) from the most recent input callback.
    /// Used for live input metering in the UI.
    pub fn get_channel_peak(&self, channel: u32) -> f32 {
        let bits = if channel == 0 {
            self.input_peak_left.load(Ordering::Relaxed)
        } else {
            self.input_peak_right.load(Ordering::Relaxed)
        };
        f32::from_bits(bits)
    }

    /// Get both channel peaks as (left, right)
    pub fn get_peaks(&self) -> (f32, f32) {
        let left = f32::from_bits(self.input_peak_left.load(Ordering::Relaxed));
        let right = f32::from_bits(self.input_peak_right.load(Ordering::Relaxed));
        (left, right)
    }
}

// SAFETY: AudioInputManager is only accessed through Mutex in API layer
unsafe impl Send for AudioInputManager {}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn system_default_follows_the_os_default() {
        let devices = names(&["MacBook Air Microphone", "Scarlett 2i2 USB"]);
        let resolved = resolve_input(
            &InputChoice::SystemDefault,
            &devices,
            Some("Scarlett 2i2 USB"),
        );
        assert_eq!(
            resolved,
            Some(ResolvedInput {
                name: "Scarlett 2i2 USB".into(),
                fell_back: false
            })
        );
    }

    #[test]
    fn named_device_is_used_when_connected() {
        let devices = names(&["MacBook Air Microphone", "Scarlett 2i2 USB"]);
        let choice = InputChoice::Named("MacBook Air Microphone".into());
        let resolved = resolve_input(&choice, &devices, Some("Scarlett 2i2 USB"));
        assert_eq!(
            resolved.map(|r| (r.name, r.fell_back)),
            Some(("MacBook Air Microphone".into(), false))
        );
    }

    #[test]
    fn missing_named_device_falls_back_to_the_default() {
        let devices = names(&["MacBook Air Microphone"]);
        let choice = InputChoice::Named("Scarlett 2i2 USB".into());
        let resolved = resolve_input(&choice, &devices, Some("MacBook Air Microphone"));
        assert_eq!(
            resolved.map(|r| (r.name, r.fell_back)),
            Some(("MacBook Air Microphone".into(), true))
        );
    }

    #[test]
    fn off_opens_nothing() {
        let devices = names(&["MacBook Air Microphone"]);
        assert_eq!(
            resolve_input(&InputChoice::Off, &devices, Some("MacBook Air Microphone")),
            None
        );
    }

    #[test]
    fn nothing_connected_resolves_to_none() {
        assert_eq!(resolve_input(&InputChoice::SystemDefault, &[], None), None);
        let choice = InputChoice::Named("Scarlett 2i2 USB".into());
        assert_eq!(resolve_input(&choice, &[], None), None);
    }

    #[test]
    fn stale_os_default_uses_the_first_connected_device() {
        let devices = names(&["MacBook Air Microphone"]);
        let resolved = resolve_input(&InputChoice::SystemDefault, &devices, Some("Gone"));
        assert_eq!(
            resolved.map(|r| r.name),
            Some("MacBook Air Microphone".into())
        );
    }

    #[test]
    fn test_input_manager_creation() {
        let manager = AudioInputManager::new();
        assert!(manager.is_ok());
    }

    #[test]
    fn test_device_enumeration() {
        let mut manager = AudioInputManager::new().unwrap();
        let result = manager.enumerate_devices();

        // This might fail in CI without audio devices, so just check it doesn't panic
        match result {
            Ok(devices) => {
                println!("Found {} input devices", devices.len());
                for device in devices {
                    println!("  - {} (default: {})", device.name, device.is_default);
                }
            }
            Err(e) => {
                println!("Device enumeration failed (expected in CI): {e}");
            }
        }
    }
}
