use anyhow::Result;
/// Audio input and recording functionality
use cpal::traits::{DeviceTrait, HostTrait};
use parking_lot::Mutex;
use ringbuf::{
    traits::{Consumer, Observer, Producer, Split},
    HeapCons, HeapRb,
};
use std::sync::atomic::{AtomicBool, AtomicU16, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// Input ring size. Small on purpose: the audio thread reads one frame per
/// output frame, so whatever sits in the ring is latency.
const RING_SECONDS: f64 = 0.5;

/// More than this many frames waiting (≈ 40 ms at 48 kHz) means the input has
/// run ahead of the output (different clocks, or the output paused); the
/// oldest are dropped down to [`BACKLOG_TARGET_FRAMES`] so you keep hearing
/// yourself without delay.
const MAX_BACKLOG_FRAMES: usize = 2048;
const BACKLOG_TARGET_FRAMES: usize = 512;

/// The audio thread's end of the input. Separate from [`AudioInputManager`]
/// so the audio thread never waits on the manager's lock, which the UI takes
/// many times a second for meters and health (each miss used to drop a
/// sample: a click). Its own lock is only taken when the input opens or
/// closes.
#[derive(Default)]
pub struct InputTap {
    consumer: Mutex<Option<HeapCons<f32>>>,
    /// Channels per frame in the ring: 1 or 2.
    channels: AtomicU16,
}

impl InputTap {
    /// Pop one frame for the audio callback without allocating. Mono is
    /// duplicated to both sides; a closed or empty input gives silence.
    #[inline]
    pub fn read_frame(&self) -> (f32, f32) {
        let Some(mut guard) = self.consumer.try_lock() else {
            return (0.0, 0.0);
        };
        let Some(cons) = guard.as_mut() else {
            return (0.0, 0.0);
        };
        let channels = usize::from(self.channels.load(Ordering::Relaxed).max(1));
        let backlog = cons.occupied_len() / channels;
        if backlog > MAX_BACKLOG_FRAMES {
            cons.skip((backlog - BACKLOG_TARGET_FRAMES) * channels);
        }
        let left = cons.try_pop().unwrap_or(0.0);
        if channels == 1 {
            (left, left)
        } else {
            (left, cons.try_pop().unwrap_or(0.0))
        }
    }

    fn attach(&self, consumer: HeapCons<f32>, channels: u16) {
        let mut slot = self.consumer.lock();
        self.channels.store(channels, Ordering::Relaxed);
        *slot = Some(consumer);
    }

    fn detach(&self) {
        *self.consumer.lock() = None;
    }
}

/// Pick an `f32` input config at `rate` from `(channels, min, max)` ranges,
/// preferring the device's default channel count. `None` when no range has it.
pub fn pick_input_config_index(
    ranges: &[(u16, u32, u32)],
    rate: u32,
    default_channels: u16,
) -> Option<usize> {
    ranges
        .iter()
        .enumerate()
        .filter(|(_, &(_, min, max))| min <= rate && rate <= max)
        .max_by_key(|(_, &(ch, _, _))| ch == default_channels)
        .map(|(i, _)| i)
}

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

/// How long an open input may deliver exact digital silence before it counts
/// as unheard. Any real microphone picks up some noise within a few buffers;
/// a closed-lid MacBook mic or a denied microphone permission gives zeros.
pub const SILENCE_GRACE: Duration = Duration::from_millis(1500);

/// What the input is doing, for the UI's "can't hear your input" notice.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InputHealth {
    /// Not open: no audio track is armed.
    Closed,
    /// The user turned input off in Settings.
    Off,
    /// Open, nothing above zero yet, still inside [`SILENCE_GRACE`].
    Waiting,
    /// Open and sound has arrived.
    Heard,
    /// Open but only exact zeros for longer than [`SILENCE_GRACE`].
    Silent,
    /// Opening the input failed (no device, or the device refused).
    Failed,
}

impl InputHealth {
    /// Stable code for the FFI.
    pub fn code(self) -> i32 {
        match self {
            Self::Closed => 0,
            Self::Off => 1,
            Self::Waiting => 2,
            Self::Heard => 3,
            Self::Silent => 4,
            Self::Failed => 5,
        }
    }
}

/// Decide the input's health from its raw state. `open_for` is how long the
/// input has been open (`None` when closed).
pub fn input_health(
    off: bool,
    failed: bool,
    open_for: Option<Duration>,
    heard: bool,
) -> InputHealth {
    match open_for {
        Some(_) if heard => InputHealth::Heard,
        Some(t) if t >= SILENCE_GRACE => InputHealth::Silent,
        Some(_) => InputHealth::Waiting,
        None if off => InputHealth::Off,
        None if failed => InputHealth::Failed,
        None => InputHealth::Closed,
    }
}

/// True when `input` and `output` look like the same computer's built-in
/// microphone and speakers, where hearing yourself feeds back into a howl.
/// Device names are localised ("Micrófono del MacBook Air" + "Altavoces del
/// MacBook Air"), so this matches what survives translation: the Mac model
/// in both names, or on Windows the same non-USB driver in brackets
/// ("… (Realtek(R) Audio)"). A guess from names: a miss only means
/// monitoring starts on, a false match only that it starts off.
pub fn is_builtin_mic_and_speakers(input: &str, output: &str) -> bool {
    const MAC_MODELS: [&str; 2] = ["MacBook", "iMac"];
    if MAC_MODELS
        .iter()
        .any(|model| input.contains(model) && output.contains(model))
    {
        return true;
    }
    if input == "Built-in Microphone" && output == "Built-in Output" {
        return true;
    }
    let driver = |name: &str| {
        let name = name.trim();
        let open = name.find('(')?;
        name.ends_with(')').then(|| name[open..].to_string())
    };
    match (driver(input), driver(output)) {
        (Some(a), Some(b)) => a == b && !a.to_uppercase().contains("USB"),
        _ => false,
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
    /// The audio thread's end of the input, shared once at stream build.
    tap: Arc<InputTap>,
    /// Channels on the open device (the ring keeps at most the first two).
    input_channels: u16,
    /// Sample rate the input opened at; it must match the output stream.
    open_rate: u32,
    /// Peak levels per channel (stored as f32 bits in `AtomicU32` for lock-free access)
    /// Updated in the input callback, read by the UI for metering
    input_peak_left: Arc<AtomicU32>,
    input_peak_right: Arc<AtomicU32>,
    /// Set by the input callback once any sample above zero arrives; reset
    /// each time the input opens.
    heard: Arc<AtomicBool>,
    /// When the current input stream opened.
    opened_at: Option<Instant>,
    /// Why the last attempt to open the input failed, until it next opens.
    open_error: Option<String>,
    /// Arming held monitoring back because input and output look like the
    /// computer's own mic and speakers. Cleared when the input closes.
    feedback_guarded: bool,
}

impl AudioInputManager {
    /// Create a new audio input manager
    pub fn new() -> Result<Self> {
        Ok(Self {
            devices: Vec::new(),
            choice: InputChoice::default(),
            active: None,
            input_stream: None,
            tap: Arc::new(InputTap::default()),
            input_channels: 1, // Default to mono
            open_rate: 0,
            input_peak_left: Arc::new(AtomicU32::new(0)),
            input_peak_right: Arc::new(AtomicU32::new(0)),
            heard: Arc::new(AtomicBool::new(false)),
            opened_at: None,
            open_error: None,
            feedback_guarded: false,
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

    /// The audio thread's end of the input. Never replaced, so the renderer
    /// clones it once when the output stream is built.
    pub fn tap(&self) -> Arc<InputTap> {
        self.tap.clone()
    }

    /// Start capturing from the chosen input device at `rate`, the output
    /// stream's rate. The audio thread reads one input frame per output
    /// frame, so a different input rate (a Scarlett left at 44.1 kHz under a
    /// 48 kHz engine) runs the ring dry ~8% of the time: crackle in the take
    /// and in monitoring.
    pub fn start_capture(&mut self, rate: u32) -> Result<()> {
        use cpal::traits::StreamTrait;

        if self.choice == InputChoice::Off {
            return Err(anyhow::anyhow!("Input is off"));
        }
        let device = self
            .resolve_device()?
            .ok_or_else(|| anyhow::anyhow!("No audio input device connected"))?;
        let default = device.default_input_config()?;
        let ranges: Vec<cpal::SupportedStreamConfigRange> = device
            .supported_input_configs()?
            .filter(|r| r.sample_format() == cpal::SampleFormat::F32)
            .collect();
        let triples: Vec<(u16, u32, u32)> = ranges
            .iter()
            .map(|r| (r.channels(), r.min_sample_rate().0, r.max_sample_rate().0))
            .collect();
        let config: cpal::StreamConfig =
            if let Some(i) = pick_input_config_index(&triples, rate, default.channels()) {
                ranges[i].with_sample_rate(cpal::SampleRate(rate)).config()
            } else {
                eprintln!(
                    "⚠️  [AudioInput] {} can't run at {rate} Hz; using {:?}. \
                     Input will crackle until sample-rate conversion exists.",
                    device.name().unwrap_or_default(),
                    default.sample_rate()
                );
                default.config()
            };

        println!("Starting audio capture:");
        println!("  Device: {}", device.name()?);
        println!("  Config: {config:?}");

        self.input_channels = config.channels;
        let num_channels = usize::from(config.channels.max(1));
        let kept = num_channels.min(2);

        let ring: HeapRb<f32> =
            HeapRb::new((RING_SECONDS * f64::from(config.sample_rate.0) * 2.0) as usize);
        let (mut producer, consumer) = ring.split();

        // Clone peak tracking atomics for use in the callback
        let peak_left = self.input_peak_left.clone();
        let peak_right = self.input_peak_right.clone();
        let heard = self.heard.clone();
        heard.store(false, Ordering::Relaxed);

        let stream = device.build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                let mut max_left: f32 = 0.0;
                let mut max_right: f32 = 0.0;
                // Keep the first two channels of each frame; an interface's
                // inputs 3+ aren't selectable yet.
                for frame in data.chunks_exact(num_channels) {
                    let left = frame[0];
                    max_left = max_left.max(left.abs());
                    let _ = producer.try_push(left);
                    if kept == 2 {
                        let right = frame[1];
                        max_right = max_right.max(right.abs());
                        let _ = producer.try_push(right);
                    }
                }
                if kept == 1 {
                    max_right = max_left;
                }
                peak_left.store(max_left.to_bits(), Ordering::Relaxed);
                peak_right.store(max_right.to_bits(), Ordering::Relaxed);
                if max_left > 0.0 || max_right > 0.0 {
                    heard.store(true, Ordering::Relaxed);
                }
            },
            move |err| {
                eprintln!("Audio input stream error: {err}");
            },
            None,
        )?;

        stream.play()?;

        self.tap.attach(consumer, kept as u16);
        self.input_stream = Some(stream);
        self.open_rate = rate;
        self.opened_at = Some(Instant::now());
        self.open_error = None;

        Ok(())
    }

    /// Stop capturing audio
    pub fn stop_capture(&mut self) -> Result<()> {
        self.opened_at = None;
        self.feedback_guarded = false;
        self.input_peak_left.store(0, Ordering::Relaxed);
        self.input_peak_right.store(0, Ordering::Relaxed);
        self.tap.detach();
        if let Some(stream) = self.input_stream.take() {
            use cpal::traits::StreamTrait;
            stream.pause()?;
            drop(stream);
        }
        Ok(())
    }

    /// Open the input when `want_open` (an audio track is armed or a take is
    /// running) and the choice isn't Off; close it otherwise. A failed open
    /// is remembered for [`Self::health`] instead of returned, so arming a
    /// track never fails because the microphone did.
    pub fn sync_open(&mut self, want_open: bool, rate: u32) {
        let should_open = want_open && self.choice != InputChoice::Off;
        // The output moved to another rate (device change): reopen to match.
        if should_open && self.is_capturing() && self.open_rate != rate {
            let _ = self.stop_capture();
        }
        if !should_open {
            if self.is_capturing() {
                if let Err(e) = self.stop_capture() {
                    eprintln!("⚠️  [AudioInput] Closing input failed: {e}");
                }
            }
            self.open_error = None;
            return;
        }
        if self.is_capturing() {
            return;
        }
        if let Err(e) = self.start_capture(rate) {
            eprintln!("⚠️  [AudioInput] Opening input failed: {e}");
            self.open_error = Some(e.to_string());
        }
    }

    /// Remember that arming held monitoring back to avoid feedback, so the UI
    /// can suggest headphones.
    pub fn set_feedback_guarded(&mut self, guarded: bool) {
        self.feedback_guarded = guarded;
    }

    pub fn feedback_guarded(&self) -> bool {
        self.feedback_guarded
    }

    /// The input's health right now (see [`InputHealth`]).
    pub fn health(&self) -> InputHealth {
        input_health(
            self.choice == InputChoice::Off,
            self.open_error.is_some(),
            self.opened_at.map(|t| t.elapsed()),
            self.heard.load(Ordering::Relaxed),
        )
    }

    /// Check if currently capturing audio
    pub fn is_capturing(&self) -> bool {
        self.input_stream.is_some()
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
    fn health_closed_off_and_failed() {
        assert_eq!(input_health(false, false, None, false), InputHealth::Closed);
        assert_eq!(input_health(true, false, None, false), InputHealth::Off);
        assert_eq!(input_health(false, true, None, false), InputHealth::Failed);
    }

    #[test]
    fn health_waits_then_calls_exact_zeros_silent() {
        let soon = Some(Duration::from_millis(200));
        let late = Some(SILENCE_GRACE + Duration::from_millis(1));
        assert_eq!(
            input_health(false, false, soon, false),
            InputHealth::Waiting
        );
        assert_eq!(input_health(false, false, late, false), InputHealth::Silent);
        assert_eq!(input_health(false, false, late, true), InputHealth::Heard);
        assert_eq!(input_health(false, false, soon, true), InputHealth::Heard);
    }

    #[test]
    fn closed_manager_reports_closed_and_reads_silence() {
        let manager = AudioInputManager::new().unwrap();
        assert_eq!(manager.health(), InputHealth::Closed);
        assert_eq!(manager.tap().read_frame(), (0.0, 0.0));
    }

    #[test]
    fn input_off_never_opens() {
        let mut manager = AudioInputManager::new().unwrap();
        manager.set_choice(InputChoice::Off);
        manager.sync_open(true, 48_000);
        assert!(!manager.is_capturing());
        assert_eq!(manager.health(), InputHealth::Off);
    }

    #[test]
    fn builtin_mac_mic_and_speakers_are_a_feedback_pair() {
        let pair = is_builtin_mic_and_speakers;
        assert!(pair("MacBook Air Microphone", "MacBook Air Speakers"));
        assert!(pair(
            "Micrófono del MacBook Air",
            "Altavoces del MacBook Air"
        ));
        assert!(pair("iMac Microphone", "iMac Speakers"));
        assert!(pair("Built-in Microphone", "Built-in Output"));
    }

    #[test]
    fn builtin_windows_mic_and_speakers_are_a_feedback_pair() {
        let pair = is_builtin_mic_and_speakers;
        assert!(pair(
            "Microphone Array (Realtek(R) Audio)",
            "Speakers (Realtek(R) Audio)"
        ));
        assert!(pair(
            "Matriz de micrófonos (Realtek(R) Audio)",
            "Altavoces (Realtek(R) Audio)"
        ));
    }

    #[test]
    fn headphones_or_an_interface_are_not_a_feedback_pair() {
        let pair = is_builtin_mic_and_speakers;
        assert!(!pair("MacBook Air Microphone", "External Headphones"));
        assert!(!pair("Micrófono del MacBook Air", "Auriculares externos"));
        assert!(!pair("MacBook Air Microphone", "AirPods Pro"));
        assert!(!pair("Scarlett 2i2 USB", "MacBook Air Speakers"));
        assert!(!pair("Scarlett 2i2 USB", "Scarlett 2i2 USB"));
        assert!(!pair(
            "Microphone (Focusrite USB Audio)",
            "Speakers (Focusrite USB Audio)"
        ));
        assert!(!pair(
            "Microphone (Scarlett 2i2 USB)",
            "Speakers (Realtek(R) Audio)"
        ));
    }

    #[test]
    fn input_config_matches_the_output_rate() {
        // A Scarlett offering 44.1k–192k on 2 channels: pick 48k there.
        let ranges = [(2, 44_100, 192_000)];
        assert_eq!(pick_input_config_index(&ranges, 48_000, 2), Some(0));
        // Prefer the default channel count when several ranges fit.
        let ranges = [(1, 48_000, 48_000), (2, 48_000, 48_000)];
        assert_eq!(pick_input_config_index(&ranges, 48_000, 2), Some(1));
        // Nothing at 48k: caller falls back to the device default.
        assert_eq!(
            pick_input_config_index(&[(2, 44_100, 44_100)], 48_000, 2),
            None
        );
    }

    #[test]
    fn closed_tap_reads_silence() {
        let tap = InputTap::default();
        assert_eq!(tap.read_frame(), (0.0, 0.0));
    }

    #[test]
    fn tap_reads_mono_centred_and_stereo_in_pairs() {
        let tap = InputTap::default();
        let (mut prod, cons) = HeapRb::<f32>::new(16).split();
        prod.push_slice(&[0.1, 0.2]);
        tap.attach(cons, 1);
        assert_eq!(tap.read_frame(), (0.1, 0.1));
        assert_eq!(tap.read_frame(), (0.2, 0.2));

        let (mut prod, cons) = HeapRb::<f32>::new(16).split();
        prod.push_slice(&[0.1, 0.2, 0.3, 0.4]);
        tap.attach(cons, 2);
        assert_eq!(tap.read_frame(), (0.1, 0.2));
        assert_eq!(tap.read_frame(), (0.3, 0.4));
        assert_eq!(tap.read_frame(), (0.0, 0.0));
    }

    #[test]
    #[allow(clippy::float_cmp)] // exact sample values are the point
    fn tap_drops_a_backlog_to_keep_latency_low() {
        let tap = InputTap::default();
        let (mut prod, cons) = HeapRb::<f32>::new(8192).split();
        let frames: Vec<f32> = (0..4096u16).map(f32::from).collect();
        prod.push_slice(&frames);
        tap.attach(cons, 1);
        // 4096 waiting > MAX_BACKLOG_FRAMES: skip to the newest 512 (+ 1 read).
        assert_eq!(tap.read_frame().0, (4096 - BACKLOG_TARGET_FRAMES) as f32);
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
