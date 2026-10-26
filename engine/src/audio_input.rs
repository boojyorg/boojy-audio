use crate::audio_file::TARGET_SAMPLE_RATE;
use crate::audio_health::INPUT_SKIPS;
use crate::rate_convert::InputConverter;
use anyhow::Result;
/// Audio input and recording functionality
use cpal::traits::{DeviceTrait, HostTrait};
use parking_lot::Mutex;
use ringbuf::{
    traits::{Consumer, Observer, Producer, Split},
    HeapCons, HeapProd, HeapRb,
};
use std::sync::atomic::{AtomicBool, AtomicU16, AtomicU32, AtomicU64, AtomicUsize, Ordering};
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

/// Converted input: frames kept in hand beyond one of the output's reads,
/// so the output never finds the ring empty.
const CUSHION_MARGIN: usize = 64;

/// The audio thread's end of the input. Separate from [`AudioInputManager`]
/// so the audio thread never waits on the manager's lock, which the UI takes
/// many times a second for meters and health (each miss used to drop a
/// sample: a click). Its own lock is only taken when the input opens or
/// closes.
///
/// A converted input (a microphone that can't run at 48 kHz) holds a cushion
/// of frames: reads wait until the input callback has filled it, the input
/// steers its conversion to stay there, and the cushion is re-filled if the
/// ring ever runs dry. A 48 kHz input reads as it always did.
#[derive(Default)]
pub struct InputTap {
    consumer: Mutex<Option<HeapCons<f32>>>,
    /// Channels per frame in the ring: 1 or 2.
    channels: AtomicU16,
    /// The input is converted (see above).
    converted: AtomicBool,
    /// Converted input: frames to hold, and the level above which the
    /// oldest are dropped back down to it. Set by the input callback.
    cushion: AtomicUsize,
    max_backlog: AtomicUsize,
    /// Converted input: reads give silence until the input callback says
    /// the cushion has filled...
    priming: AtomicBool,
    /// ...and then skip this many frames it overfilled by.
    release_skip: AtomicUsize,
    /// The largest number of frames one render has read since it opened.
    largest_read_block: AtomicUsize,
    /// Renders so far: tells the input whether the output read since its
    /// last callback.
    reads: AtomicU64,
    /// Converted input: engine frames a sound is delayed by, in the
    /// converter and waiting in the ring behind the cushion (f32 bits),
    /// published by the input callback.
    added_delay: AtomicU32,
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
        if self.converted.load(Ordering::Relaxed) {
            if self.priming.load(Ordering::Acquire) {
                return (0.0, 0.0);
            }
            let skip = self.release_skip.swap(0, Ordering::Relaxed).min(backlog);
            cons.skip(skip * channels);
            let backlog = backlog - skip;
            let cushion = self.cushion.load(Ordering::Relaxed);
            if backlog == 0 {
                // Ran dry: a click. Count it and build the cushion back up.
                INPUT_SKIPS.fetch_add(1, Ordering::Relaxed);
                self.priming.store(true, Ordering::Relaxed);
                return (0.0, 0.0);
            }
            if backlog > self.max_backlog.load(Ordering::Relaxed) {
                INPUT_SKIPS.fetch_add(1, Ordering::Relaxed);
                cons.skip((backlog - cushion) * channels);
            }
        } else if backlog > MAX_BACKLOG_FRAMES {
            INPUT_SKIPS.fetch_add(1, Ordering::Relaxed);
            cons.skip((backlog - BACKLOG_TARGET_FRAMES) * channels);
        }
        let left = cons.try_pop().unwrap_or(0.0);
        if channels == 1 {
            (left, left)
        } else {
            (left, cons.try_pop().unwrap_or(0.0))
        }
    }

    /// Called by the renderer at the start of each render, with the frames
    /// it's about to read, so a converted input knows how big a cushion to
    /// keep.
    #[inline]
    pub fn begin_block(&self, frames: usize) {
        self.largest_read_block.fetch_max(frames, Ordering::Relaxed);
        self.reads.fetch_add(1, Ordering::Relaxed);
    }

    /// The largest render the output has asked for since the input opened.
    fn largest_read_block(&self) -> usize {
        self.largest_read_block.load(Ordering::Relaxed)
    }

    fn set_limits(&self, cushion: usize, max_backlog: usize) {
        self.cushion.store(cushion, Ordering::Relaxed);
        self.max_backlog.store(max_backlog, Ordering::Relaxed);
    }

    /// Engine frames conversion delays the input by. Zero for an
    /// unconverted input.
    fn added_delay(&self) -> f64 {
        if !self.converted.load(Ordering::Relaxed) {
            return 0.0;
        }
        f64::from(f32::from_bits(self.added_delay.load(Ordering::Relaxed)))
    }

    fn attach(&self, consumer: HeapCons<f32>, channels: u16, converted: bool) {
        let mut slot = self.consumer.lock();
        self.channels.store(channels, Ordering::Relaxed);
        self.converted.store(converted, Ordering::Relaxed);
        self.priming.store(converted, Ordering::Relaxed);
        self.release_skip.store(0, Ordering::Relaxed);
        self.set_limits(0, MAX_BACKLOG_FRAMES);
        self.largest_read_block.store(0, Ordering::Relaxed);
        self.added_delay.store(0f32.to_bits(), Ordering::Relaxed);
        *slot = Some(consumer);
    }

    fn detach(&self) {
        *self.consumer.lock() = None;
    }
}

/// The input callback's work after metering: hand the microphone's frames to
/// the audio thread through the ring, converted to the engine rate when the
/// input needs it.
struct InputFeed {
    producer: HeapProd<f32>,
    tap: Arc<InputTap>,
    /// Channels per device frame, and how many of them are kept (1 or 2).
    stride: usize,
    kept: usize,
    converter: Option<InputConverter>,
    /// The largest callback so far, in engine frames.
    largest_callback: usize,
    /// Frames already waiting in the ring when a callback's frames arrive,
    /// beyond those a 48 kHz input would have waiting (the ones pushed since
    /// the output last read), averaged: each new frame is read that many
    /// frames later than it would be without conversion.
    waiting: f64,
    /// The tap's render count at the last callback, and the frames pushed
    /// since that count last changed.
    reads_seen: u64,
    pushed_since_read: usize,
}

impl InputFeed {
    fn new(
        producer: HeapProd<f32>,
        tap: Arc<InputTap>,
        stride: usize,
        kept: usize,
        converter: Option<InputConverter>,
    ) -> Self {
        Self {
            producer,
            tap,
            stride,
            kept,
            converter,
            largest_callback: 0,
            waiting: f64::NAN,
            reads_seen: 0,
            pushed_since_read: 0,
        }
    }

    fn feed(&mut self, data: &[f32]) {
        let reads = self.tap.reads.load(Ordering::Relaxed);
        if reads != self.reads_seen {
            self.reads_seen = reads;
            self.pushed_since_read = 0;
        }
        let waiting =
            (self.producer.occupied_len() / self.kept).saturating_sub(self.pushed_since_read);
        let (producer, kept) = (&mut self.producer, self.kept);
        let mut dropped = false;
        let mut pushed = 0;
        let mut push = |left: f32, right: f32| {
            pushed += 1;
            dropped |= producer.try_push(left).is_err();
            if kept == 2 {
                dropped |= producer.try_push(right).is_err();
            }
        };
        let Some(converter) = &mut self.converter else {
            // Keep the first two channels of each frame; an interface's
            // inputs 3+ aren't selectable yet.
            for frame in data.chunks_exact(self.stride) {
                push(frame[0], frame.get(1).copied().unwrap_or(0.0));
            }
            if dropped {
                INPUT_SKIPS.fetch_add(1, Ordering::Relaxed);
            }
            return;
        };
        converter.process(data, self.stride, &mut push);
        if dropped {
            INPUT_SKIPS.fetch_add(1, Ordering::Relaxed);
        }
        self.pushed_since_read += pushed;

        // Keep one of the output's reads (plus a margin) waiting beyond what
        // a 48 kHz input would have, so a read can come at any moment
        // between two callbacks without finding the ring empty. The reader
        // holds off until that and a read are in hand, so the extra starts
        // where steering keeps it, and the delay is steady from the start.
        let frames = data.len() / self.stride;
        let engine_frames = (frames as f64 * converter.engine_per_device()).ceil() as usize;
        self.largest_callback = self.largest_callback.max(engine_frames);
        let reads = self.tap.largest_read_block();
        let extra = reads + CUSHION_MARGIN;
        let cushion = extra + reads;
        self.tap
            .set_limits(cushion, cushion + self.largest_callback + reads + 256);

        // While the cushion fills nothing is read: no steering, and the delay
        // average starts afresh once reads begin. Reads begin with exactly
        // `extra` waiting: any more is skipped.
        if self.tap.priming.load(Ordering::Relaxed) {
            self.waiting = f64::NAN;
            if waiting >= extra {
                self.tap
                    .release_skip
                    .store(waiting - extra, Ordering::Relaxed);
                self.tap.priming.store(false, Ordering::Release);
            }
        } else {
            converter.steer(waiting, extra, engine_frames);
            self.waiting = crate::rate_convert::smooth(self.waiting, waiting as f64, engine_frames);
        }
        let waited = if self.waiting.is_nan() {
            0.0
        } else {
            self.waiting
        };
        let delay = (converter.delay_engine_frames() + waited) as f32;
        self.tap
            .added_delay
            .store(delay.to_bits(), Ordering::Relaxed);
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

    /// Start capturing from the chosen input device. It opens at 48 kHz when
    /// it can. Otherwise it opens at its own rate and its frames are
    /// converted to 48 kHz on the way in, steered to keep pace with the
    /// output (its clock never runs at quite the same speed).
    pub fn start_capture(&mut self) -> Result<()> {
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
        let config: cpal::StreamConfig = if let Some(i) =
            pick_input_config_index(&triples, TARGET_SAMPLE_RATE, default.channels())
        {
            ranges[i]
                .with_sample_rate(cpal::SampleRate(TARGET_SAMPLE_RATE))
                .config()
        } else {
            default.config()
        };
        let device_name = device.name()?;
        let rate = config.sample_rate.0;

        println!("Starting audio capture:");
        println!("  Device: {device_name}");
        println!("  Config: {config:?}");

        self.input_channels = config.channels;
        let num_channels = usize::from(config.channels.max(1));
        let kept = num_channels.min(2);

        let converter = if rate == TARGET_SAMPLE_RATE {
            None
        } else {
            println!("  Converting {rate} Hz to {TARGET_SAMPLE_RATE} Hz");
            Some(
                InputConverter::new(rate, kept)
                    .ok_or_else(|| anyhow::anyhow!("Can't convert input from {rate} Hz"))?,
            )
        };
        let converted = converter.is_some();

        // Ring frames are at the engine rate once converted.
        let ring_rate = if converted { TARGET_SAMPLE_RATE } else { rate };
        let ring: HeapRb<f32> = HeapRb::new((RING_SECONDS * f64::from(ring_rate) * 2.0) as usize);
        let (producer, consumer) = ring.split();
        let mut feed = InputFeed::new(producer, self.tap.clone(), num_channels, kept, converter);

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
                for frame in data.chunks_exact(num_channels) {
                    max_left = max_left.max(frame[0].abs());
                    if kept == 2 {
                        max_right = max_right.max(frame[1].abs());
                    }
                }
                feed.feed(data);
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

        self.tap.attach(consumer, kept as u16, converted);
        self.input_stream = Some(stream);
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
    pub fn sync_open(&mut self, want_open: bool) {
        let should_open = want_open && self.choice != InputChoice::Off;
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
        if let Err(e) = self.start_capture() {
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

    /// Engine frames the open input's conversion delays a recording by:
    /// the converter's own delay plus the extra it waits in the ring. Zero
    /// when the input isn't converted.
    pub fn convert_delay(&self) -> usize {
        if !self.is_capturing() {
            return 0;
        }
        self.tap.added_delay().round() as usize
    }

    /// Check if currently capturing audio
    pub fn is_capturing(&self) -> bool {
        self.input_stream.is_some()
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
        manager.sync_open(true);
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
    fn input_config_prefers_the_engine_rate() {
        // A Scarlett offering 44.1k–192k on 2 channels: pick 48k there.
        let ranges = [(2, 44_100, 192_000)];
        assert_eq!(pick_input_config_index(&ranges, 48_000, 2), Some(0));
        // Prefer the default channel count when several ranges fit.
        let ranges = [(1, 48_000, 48_000), (2, 48_000, 48_000)];
        assert_eq!(pick_input_config_index(&ranges, 48_000, 2), Some(1));
        // Nothing at 48k: caller opens at the device default and converts.
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
        tap.attach(cons, 1, false);
        assert_eq!(tap.read_frame(), (0.1, 0.1));
        assert_eq!(tap.read_frame(), (0.2, 0.2));

        let (mut prod, cons) = HeapRb::<f32>::new(16).split();
        prod.push_slice(&[0.1, 0.2, 0.3, 0.4]);
        tap.attach(cons, 2, false);
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
        tap.attach(cons, 1, false);
        // 4096 waiting > MAX_BACKLOG_FRAMES: skip to the newest 512 (+ 1 read).
        assert_eq!(tap.read_frame().0, (4096 - BACKLOG_TARGET_FRAMES) as f32);
    }

    /// A converted input from a device at `rate`, as the input callback
    /// builds it, and its tap.
    fn converted_feed(rate: u32) -> (InputFeed, Arc<InputTap>) {
        let tap = Arc::new(InputTap::default());
        let (producer, consumer) = HeapRb::<f32>::new(48_000).split();
        tap.attach(consumer, 1, true);
        let feed = InputFeed::new(producer, tap.clone(), 1, 1, InputConverter::new(rate, 1));
        (feed, tap)
    }

    fn ring_level(tap: &InputTap) -> usize {
        tap.consumer
            .lock()
            .as_ref()
            .map_or(0, Observer::occupied_len)
    }

    /// Run a converted 44.1 kHz microphone whose clock runs at `drift` × its
    /// rate against a 48 kHz output for two minutes. Returns the ring's lowest
    /// and highest level after the first ten seconds, and the tap.
    fn drifting_mic(drift: f64) -> (usize, usize, Arc<InputTap>) {
        let (in_rate, in_block, read_block) = (44_100.0, 441, 512);
        let (mut feed, tap) = converted_feed(44_100);
        let data = vec![0.1f32; in_block];
        let (mut next_in, mut next_read) = (0.0f64, 0.0f64);
        let (mut lowest, mut highest) = (usize::MAX, 0);
        while next_in.min(next_read) < 120.0 {
            if next_in <= next_read {
                feed.feed(&data);
                next_in += in_block as f64 / (in_rate * drift);
            } else {
                tap.begin_block(read_block);
                if next_read > 10.0 {
                    highest = highest.max(ring_level(&tap));
                }
                for _ in 0..read_block {
                    let _ = tap.read_frame();
                }
                if next_read > 10.0 {
                    lowest = lowest.min(ring_level(&tap));
                }
                next_read += read_block as f64 / f64::from(TARGET_SAMPLE_RATE);
            }
        }
        (lowest, highest, tap)
    }

    #[test]
    fn a_microphone_on_its_own_clock_keeps_pace() {
        // 0.1% fast or slow: unsteered, that's 48 frames a second too many or
        // too few, so within a minute the ring overflows (a skip) or runs
        // dry (a click). Steered, it holds its level.
        for drift in [1.001, 0.999] {
            let (lowest, highest, tap) = drifting_mic(drift);
            let cushion = tap.cushion.load(Ordering::Relaxed);
            assert!(lowest > 0, "{drift}: ran dry");
            assert!(!tap.priming.load(Ordering::Relaxed), "{drift}: ran dry");
            assert!(
                highest <= cushion + 512,
                "{drift}: ran high: {highest} with a cushion of {cushion}"
            );
        }
    }

    /// Play an impulse at engine frame `at` through a device at `rate` whose
    /// input hears its own output (a loopback cable), with input and output
    /// callbacks every `in_ms` and `out_ms` milliseconds, and record what
    /// comes back for a second after it. Returns the frame the impulse lands
    /// on in the take once the conversion delay (read at the end, as Stop
    /// does) is taken off.
    fn loopback(rate: u32, at: usize, in_ms: usize, out_ms: usize) -> i64 {
        let in_block = rate as usize * in_ms / 1000;
        let out_block = rate as usize * out_ms / 1000;
        let tap = Arc::new(InputTap::default());
        let (producer, consumer) = HeapRb::<f32>::new(96_000).split();
        let converter = (rate != TARGET_SAMPLE_RATE).then(|| InputConverter::new(rate, 1).unwrap());
        tap.attach(consumer, 1, converter.is_some());
        let mut feed = InputFeed::new(producer, tap.clone(), 1, 1, converter);
        let mut output = crate::rate_convert::OutputConverter::new(rate);

        // The engine: plays the impulse, records the input frame by frame.
        let mut frame = 0usize;
        let mut take = Vec::new();
        let mut engine = |buf: &mut [f32]| {
            tap.begin_block(buf.len() / 2);
            for out in buf.as_chunks_mut::<2>().0 {
                take.push(tap.read_frame().0);
                let s = if frame == at { 1.0 } else { 0.0 };
                *out = [s, s];
                frame += 1;
            }
        };
        // Device time in device frames. The output callback at time t fills
        // the buffer that plays from t + out_block; the input callback at t
        // delivers what played over the last in_block frames.
        let mut played = vec![0.0f32; out_block];
        let (mut next_in, mut next_out) = (in_block, 0);
        let end = (at + 48_000) * rate as usize / TARGET_SAMPLE_RATE as usize;
        while next_in.min(next_out) < end {
            if next_in <= next_out {
                feed.feed(&played[next_in - in_block..next_in]);
                next_in += in_block;
            } else {
                let mut buf = vec![0.0f32; out_block];
                if let Some(conv) = &mut output {
                    conv.fill(out_block, &mut engine, |i, l, _| buf[i] = l);
                } else {
                    let mut stereo = vec![0.0; out_block * 2];
                    engine(&mut stereo);
                    for (i, f) in stereo.as_chunks::<2>().0.iter().enumerate() {
                        buf[i] = f[0];
                    }
                }
                played.extend(buf);
                next_out += out_block;
            }
        }
        let output_delay = output.as_ref().map_or(
            0.0,
            crate::rate_convert::OutputConverter::delay_engine_frames,
        );
        let late = (output_delay + tap.added_delay()).round() as i64;
        let peak = (0..take.len())
            .max_by(|&a, &b| take[a].abs().total_cmp(&take[b].abs()))
            .unwrap();
        peak as i64 - late
    }

    /// How far a converted take lands from the 48 kHz take, for each rate.
    fn misalignment(at: usize, in_ms: usize, out_ms: usize) -> Vec<(u32, i64)> {
        let reference = loopback(TARGET_SAMPLE_RATE, at, in_ms, out_ms);
        [16_000, 44_100, 96_000]
            .into_iter()
            .map(|rate| (rate, loopback(rate, at, in_ms, out_ms) - reference))
            .collect()
    }

    #[test]
    fn a_converted_take_lands_where_a_48k_take_does() {
        // Settled (ten seconds after arming) and straight after arming, with
        // equal and unequal input and output buffers. Unconverted, these
        // takes would land 1000-4000 frames (20-80 ms) late.
        for (at, in_ms, out_ms) in [
            (480_000, 10, 10),
            (480_000, 10, 40),
            (480_000, 40, 10),
            (4_800, 10, 10),
            (4_800, 10, 40),
            (9_600, 40, 10),
        ] {
            for (rate, off) in misalignment(at, in_ms, out_ms) {
                assert!(
                    off.abs() <= 64,
                    "{rate} Hz, impulse at {at}, {in_ms} ms in / {out_ms} ms out: \
                     {off} frames off"
                );
            }
        }
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
