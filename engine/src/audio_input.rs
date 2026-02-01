/// Audio input and recording functionality
use cpal::traits::{DeviceTrait, HostTrait};
use ringbuf::{traits::*, HeapRb};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU32, Ordering};
use anyhow::Result;

use crate::audio_file::TARGET_SAMPLE_RATE;

/// Represents an audio input device
#[derive(Clone, Debug)]
pub struct AudioInputDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

/// Audio input manager that handles device enumeration and recording
pub struct AudioInputManager {
    /// Available input devices
    devices: Vec<AudioInputDevice>,
    /// Currently selected device index
    selected_device_index: Option<usize>,
    /// Input stream (if active)
    input_stream: Option<cpal::Stream>,
    /// Ring buffer for captured audio (lock-free, thread-safe)
    /// Stores raw samples (mono or stereo depending on device)
    input_buffer: Option<Arc<Mutex<HeapRb<f32>>>>,
    /// Number of input channels (1 = mono, 2 = stereo)
    input_channels: u16,
    /// Peak levels per channel (stored as f32 bits in AtomicU32 for lock-free access)
    /// Updated in the input callback, read by the UI for metering
    input_peak_left: Arc<AtomicU32>,
    input_peak_right: Arc<AtomicU32>,
}

impl AudioInputManager {
    /// Create a new audio input manager
    pub fn new() -> Result<Self> {
        Ok(Self {
            devices: Vec::new(),
            selected_device_index: None,
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
            let name = device.name().unwrap_or_else(|_| format!("Input Device {}", idx));
            let is_default = name == default_name;

            devices.push(AudioInputDevice {
                id: format!("input_{}", idx),
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

        self.devices = devices.clone();

        // Auto-select default device
        if let Some(default_idx) = devices.iter().position(|d| d.is_default) {
            self.selected_device_index = Some(default_idx);
        } else if !devices.is_empty() {
            self.selected_device_index = Some(0);
        }

        Ok(devices)
    }

    /// Get the list of available input devices
    pub fn get_devices(&self) -> Vec<AudioInputDevice> {
        self.devices.clone()
    }

    /// Select an input device by index
    pub fn select_device(&mut self, device_index: usize) -> Result<()> {
        if device_index >= self.devices.len() {
            return Err(anyhow::anyhow!("Invalid device index"));
        }
        self.selected_device_index = Some(device_index);
        Ok(())
    }

    /// Get the currently selected device index
    pub fn get_selected_device_index(&self) -> Option<usize> {
        self.selected_device_index
    }

    /// Start capturing audio from the selected input device
    /// This creates an input stream and begins filling the ring buffer
    pub fn start_capture(&mut self, buffer_size_seconds: f64) -> Result<()> {
        let device_index = self.selected_device_index
            .ok_or_else(|| anyhow::anyhow!("No input device selected"))?;

        let host = cpal::default_host();
        let mut input_devices: Vec<_> = host.input_devices()?.collect();

        if device_index >= input_devices.len() {
            return Err(anyhow::anyhow!("Device index out of range"));
        }

        let device = input_devices.remove(device_index);
        let config = device.default_input_config()?;

        println!("Starting audio capture:");
        println!("  Device: {}", device.name()?);
        println!("  Config: {:?}", config);

        // Store the number of input channels
        self.input_channels = config.channels();
        eprintln!("🎙️  [AudioInput] Input channels: {} (1=mono, 2=stereo)", self.input_channels);

        // Create ring buffer (stereo, size based on buffer_size_seconds)
        let buffer_samples = (buffer_size_seconds * TARGET_SAMPLE_RATE as f64 * 2.0) as usize;
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
                        if abs > max_left { max_left = abs; }
                    }
                    max_right = max_left;
                } else {
                    // Stereo (or more): interleaved L R L R ...
                    for (i, &sample) in data.iter().enumerate() {
                        let abs = sample.abs();
                        if i % 2 == 0 {
                            if abs > max_left { max_left = abs; }
                        } else {
                            if abs > max_right { max_right = abs; }
                        }
                    }
                }

                // Update peak atomics (store f32 bits as u32)
                peak_left.store(max_left.to_bits(), Ordering::Relaxed);
                peak_right.store(max_right.to_bits(), Ordering::Relaxed);

                // Write input samples to ring buffer
                if let Ok(mut buffer) = ring_buffer_clone.lock() {
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
                eprintln!("Audio input stream error: {}", err);
            },
            None,
        )?;

        use cpal::traits::StreamTrait;
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
            if let Ok(mut buffer) = buffer_arc.lock() {
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
            if let Ok(buffer) = buffer_arc.lock() {
                return buffer.occupied_len();
            }
        }
        0
    }

    /// Clear the input buffer
    pub fn clear_buffer(&self) {
        if let Some(buffer_arc) = &self.input_buffer {
            if let Ok(mut buffer) = buffer_arc.lock() {
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
                println!("Device enumeration failed (expected in CI): {}", e);
            }
        }
    }
}

