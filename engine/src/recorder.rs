/// Recording engine with metronome and count-in support
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use parking_lot::Mutex;
use std::f32::consts::PI;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;

/// Realtime lock-contention counter for the recorder's per-sample reads on the
/// audio thread (`process_frame`). Incremented with `Relaxed` ordering when a
/// `try_lock` fails and we fall back to a blocking lock — the same pattern the
/// renderer uses (`SYNTH_LOCK_CONTENTION`/`EFFECT_LOCK_CONTENTION`). This, plus
/// removing the audio-thread `eprintln!`s, keeps the recording/count-in path
/// off the non-realtime patterns the renderer was already hardened against.
static RECORDER_LOCK_CONTENTION: AtomicU64 = AtomicU64::new(0);

/// Recorder realtime lock-contention count since process start. A climbing
/// value points at audio-thread stalls during recording.
// Exposed for future diagnostics / an audio-health FFI; not yet consumed.
#[allow(dead_code)]
pub fn recorder_lock_contention_count() -> u64 {
    RECORDER_LOCK_CONTENTION.load(Ordering::Relaxed)
}

/// Recording state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingState {
    Idle,
    CountingIn,
    WaitingForPunchIn,
    Recording,
}

/// The recording engine that manages audio recording
pub struct Recorder {
    /// Current recording state
    state: Arc<Mutex<RecordingState>>,
    /// Recorded audio buffer (interleaved stereo samples)
    recorded_samples: Arc<Mutex<Vec<f32>>>,
    /// Sample count since recording started
    sample_counter: Arc<AtomicU64>,
    /// Count-in duration in bars
    count_in_bars: Arc<Mutex<u32>>,
    /// Tempo in BPM
    tempo: Arc<Mutex<f64>>,
    /// Metronome enabled
    metronome_enabled: Arc<AtomicBool>,
    /// Time signature (beats per bar)
    time_signature: Arc<Mutex<u32>>,
    /// Samples remaining to suppress metronome after seek (prevents click overlap)
    seek_cooldown: Arc<AtomicU64>,
    /// Playhead position (in seconds) where recording should be placed on the timeline
    recording_start_seconds: Arc<Mutex<f64>>,
    /// Current count-in beat number (1-indexed, 0 when not counting in)
    count_in_beat: Arc<AtomicU32>,
    /// Count-in progress as fixed-point (0-10000 maps to 0.0-1.0)
    count_in_progress: Arc<AtomicU32>,
    /// Punch-in enabled (auto-start recording at region start)
    punch_in_enabled: Arc<AtomicBool>,
    /// Punch-out enabled (auto-stop recording at region end)
    punch_out_enabled: Arc<AtomicBool>,
    /// Punch-in position in seconds (= loop/region start)
    punch_in_seconds: Arc<Mutex<f64>>,
    /// Punch-out position in seconds (= loop/region end)
    punch_out_seconds: Arc<Mutex<f64>>,
    /// Set by audio callback when auto-punch-out fires
    punch_complete: Arc<AtomicBool>,
    /// Monotonic processed-frame count — never reset (unlike `sample_counter`,
    /// which seeks/loops rewind). Time base for the click refractory guard.
    monotonic_frames: Arc<AtomicU64>,
    /// `monotonic_frames` value at which the current click started, or
    /// `NO_CLICK` when none is sounding. Restarting a click within half a
    /// beat of the last one is suppressed — the loop-wrap seek lands the
    /// counter back on a beat boundary a few frames after the boundary click
    /// already fired, which used to double the downbeat as an audible flam.
    click_started_at: Arc<AtomicU64>,
    /// True when the sounding click is a downbeat (1200 Hz vs 800 Hz).
    click_is_downbeat: Arc<AtomicBool>,
    /// True when the current take's count-in (partly) plays "in place" —
    /// recording started too close to bar 1 for a full pre-roll seekback.
    /// The renderer mutes track playback during the count-in in this case
    /// (the metronome is mixed in later, so it stays audible).
    count_in_in_place: Arc<AtomicBool>,
}

/// Sentinel for `click_started_at`: no click is sounding.
const NO_CLICK: u64 = u64::MAX;

/// Metronome click length in frames: ~80ms at 48kHz (increased from 40ms for
/// better audibility).
const CLICK_FRAMES: u64 = 4000;

impl Default for Recorder {
    fn default() -> Self {
        Self::new()
    }
}

impl Recorder {
    /// Create a new recorder
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(RecordingState::Idle)),
            recorded_samples: Arc::new(Mutex::new(Vec::new())),
            sample_counter: Arc::new(AtomicU64::new(0)),
            count_in_bars: Arc::new(Mutex::new(1)), // Default: 1 bar
            tempo: Arc::new(Mutex::new(120.0)),     // Default: 120 BPM
            metronome_enabled: Arc::new(AtomicBool::new(true)),
            time_signature: Arc::new(Mutex::new(4)), // Default: 4/4
            seek_cooldown: Arc::new(AtomicU64::new(0)),
            recording_start_seconds: Arc::new(Mutex::new(0.0)),
            count_in_beat: Arc::new(AtomicU32::new(0)),
            count_in_progress: Arc::new(AtomicU32::new(0)),
            punch_in_enabled: Arc::new(AtomicBool::new(false)),
            punch_out_enabled: Arc::new(AtomicBool::new(false)),
            punch_in_seconds: Arc::new(Mutex::new(0.0)),
            punch_out_seconds: Arc::new(Mutex::new(0.0)),
            punch_complete: Arc::new(AtomicBool::new(false)),
            monotonic_frames: Arc::new(AtomicU64::new(0)),
            click_started_at: Arc::new(AtomicU64::new(NO_CLICK)),
            click_is_downbeat: Arc::new(AtomicBool::new(false)),
            count_in_in_place: Arc::new(AtomicBool::new(false)),
        }
    }

    /// Flag the current take's count-in as playing (partly) in place.
    /// Set by `api::start_recording` on every take; stale values are harmless
    /// because the renderer only reads it while the state is `CountingIn`.
    pub fn set_count_in_in_place(&self, in_place: bool) {
        self.count_in_in_place.store(in_place, Ordering::SeqCst);
    }

    /// Get clones of internal Arcs for use in audio callback
    pub fn get_callback_refs(&self) -> RecorderCallbackRefs {
        RecorderCallbackRefs {
            state: self.state.clone(),
            recorded_samples: self.recorded_samples.clone(),
            sample_counter: self.sample_counter.clone(),
            count_in_bars: self.count_in_bars.clone(),
            tempo: self.tempo.clone(),
            metronome_enabled: self.metronome_enabled.clone(),
            time_signature: self.time_signature.clone(),
            seek_cooldown: self.seek_cooldown.clone(),
            count_in_beat: self.count_in_beat.clone(),
            count_in_progress: self.count_in_progress.clone(),
            punch_in_enabled: self.punch_in_enabled.clone(),
            punch_out_enabled: self.punch_out_enabled.clone(),
            punch_in_seconds: self.punch_in_seconds.clone(),
            punch_out_seconds: self.punch_out_seconds.clone(),
            punch_complete: self.punch_complete.clone(),
            monotonic_frames: self.monotonic_frames.clone(),
            click_started_at: self.click_started_at.clone(),
            click_is_downbeat: self.click_is_downbeat.clone(),
            count_in_in_place: self.count_in_in_place.clone(),
        }
    }

    /// Start recording with optional count-in
    pub fn start_recording(&self) -> Result<(), String> {
        let mut state = self.state.lock();

        if *state != RecordingState::Idle {
            return Err("Already recording or counting in".to_string());
        }

        // Clear previous recording
        {
            let mut samples = self.recorded_samples.lock();
            samples.clear();
            eprintln!("🎙️  [Recorder] Cleared {} previous samples", samples.len());
        }

        self.sample_counter.store(0, Ordering::SeqCst);
        self.punch_complete.store(false, Ordering::SeqCst);

        // Check if count-in is enabled
        let count_in = *self.count_in_bars.lock();
        let punch_in = self.punch_in_enabled.load(Ordering::SeqCst);

        if count_in > 0 {
            *state = RecordingState::CountingIn;
            eprintln!(
                "🎙️  [Recorder] Starting with count-in: {count_in} bars (punch_in={punch_in})"
            );
        } else if punch_in {
            // No count-in but punch-in enabled: wait for punch point
            *state = RecordingState::WaitingForPunchIn;
            eprintln!("🎙️  [Recorder] Waiting for punch-in (no count-in)");
        } else {
            *state = RecordingState::Recording;
            eprintln!("🎙️  [Recorder] Starting recording immediately (no count-in)");
        }

        Ok(())
    }

    /// Stop recording and return the recorded audio clip.
    ///
    /// `stream_sample_rate` is the rate the audio stream actually ran at —
    /// the recorded frames accrued one per output callback frame, so duration
    /// math must use the real rate, not assume `TARGET_SAMPLE_RATE` (C22).
    /// When the stream wasn't at the engine rate, the audio is resampled to
    /// `TARGET_SAMPLE_RATE` so playback (whose time-math is fixed at the
    /// engine rate, like every imported file) has the correct pitch/speed.
    pub fn stop_recording(&self, stream_sample_rate: u32) -> Result<Option<AudioClip>, String> {
        let mut state = self.state.lock();
        let punch_completed = self.punch_complete.load(Ordering::SeqCst);

        // If idle and no auto-punch-out fired, nothing to return
        if *state == RecordingState::Idle && !punch_completed {
            return Ok(None);
        }

        let was_waiting = *state == RecordingState::WaitingForPunchIn;
        *state = RecordingState::Idle;
        self.count_in_beat.store(0, Ordering::Relaxed);
        self.count_in_progress.store(0, Ordering::Relaxed);
        self.punch_complete.store(false, Ordering::SeqCst);

        // If stopped while waiting for punch-in, nothing was recorded
        if was_waiting {
            eprintln!("🎙️  [Recorder] Stopped while waiting for punch-in — no audio captured");
            return Ok(None);
        }

        // Get recorded samples
        let samples = {
            let samples_lock = self.recorded_samples.lock();
            samples_lock.clone()
        };

        if samples.is_empty() {
            return Ok(None);
        }

        // Bring the recording to the engine rate if the stream ran elsewhere,
        // so it plays back at the correct pitch/speed like any imported file.
        let stream_sample_rate = if stream_sample_rate == 0 {
            TARGET_SAMPLE_RATE
        } else {
            stream_sample_rate
        };
        let samples = if stream_sample_rate == TARGET_SAMPLE_RATE {
            samples
        } else {
            crate::audio_file::resample_audio(&samples, stream_sample_rate, TARGET_SAMPLE_RATE, 2)
                .map_err(|e| format!("Failed to resample recording: {e}"))?
        };

        // Create audio clip from recorded samples
        let frame_count = samples.len() / 2; // Stereo
        let duration_seconds = frame_count as f64 / f64::from(TARGET_SAMPLE_RATE);

        let clip = AudioClip {
            samples,
            channels: 2,
            sample_rate: TARGET_SAMPLE_RATE,
            duration_seconds,
            file_path: format!(
                "recorded_{}.wav",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs()
            ),
        };

        Ok(Some(clip))
    }

    /// Get current recording state
    pub fn get_state(&self) -> RecordingState {
        *self.state.lock()
    }

    /// Set count-in duration in bars
    pub fn set_count_in_bars(&self, bars: u32) {
        *self.count_in_bars.lock() = bars;
    }

    /// Get count-in duration in bars
    pub fn get_count_in_bars(&self) -> u32 {
        *self.count_in_bars.lock()
    }

    /// Set tempo in BPM
    pub fn set_tempo(&self, bpm: f64) {
        *self.tempo.lock() = bpm.clamp(20.0, 300.0);
    }

    /// Get tempo in BPM
    pub fn get_tempo(&self) -> f64 {
        *self.tempo.lock()
    }

    /// Enable/disable metronome
    pub fn set_metronome_enabled(&self, enabled: bool) {
        self.metronome_enabled.store(enabled, Ordering::SeqCst);
    }

    /// Check if metronome is enabled
    pub fn is_metronome_enabled(&self) -> bool {
        self.metronome_enabled.load(Ordering::SeqCst)
    }

    /// Get recorded sample count
    pub fn get_recorded_sample_count(&self) -> usize {
        self.recorded_samples.lock().len()
    }

    /// Get recorded duration in seconds
    pub fn get_recorded_duration(&self) -> f64 {
        let sample_count = self.get_recorded_sample_count();
        let frame_count = sample_count / 2; // Stereo
        frame_count as f64 / f64::from(TARGET_SAMPLE_RATE)
    }

    /// Get recording waveform preview (downsampled for display)
    /// Returns a list of peak values suitable for UI display
    /// Each peak represents multiple samples averaged together
    pub fn get_recording_waveform(&self, num_peaks: usize) -> Vec<f32> {
        let samples = self.recorded_samples.lock();
        if samples.is_empty() || num_peaks == 0 {
            return Vec::new();
        }

        let frame_count = samples.len() / 2; // Stereo interleaved
        let frames_per_peak = (frame_count / num_peaks).max(1);
        let mut peaks = Vec::with_capacity(num_peaks);

        for i in 0..num_peaks {
            let start_frame = i * frames_per_peak;
            let end_frame = ((i + 1) * frames_per_peak).min(frame_count);

            if start_frame >= frame_count {
                break;
            }

            let mut max_amplitude: f32 = 0.0;
            for frame in start_frame..end_frame {
                let left = samples.get(frame * 2).copied().unwrap_or(0.0).abs();
                let right = samples.get(frame * 2 + 1).copied().unwrap_or(0.0).abs();
                let amplitude = left.max(right);
                if amplitude > max_amplitude {
                    max_amplitude = amplitude;
                }
            }
            peaks.push(max_amplitude);
        }

        peaks
    }

    /// Reset metronome beat position (called when transport stops)
    pub fn reset_metronome(&self) {
        let old_value = self.sample_counter.swap(0, Ordering::SeqCst);
        // Forget the sounding click so the next play's first downbeat fires
        // immediately (the refractory guard only suppresses *seek* doubles).
        self.click_started_at.store(NO_CLICK, Ordering::Relaxed);
        eprintln!("🔄 [Recorder] Metronome reset: {old_value} → 0");
    }

    /// Seek metronome to a specific sample position (called when transport seeks)
    /// This ensures metronome stays in sync when looping or seeking
    pub fn seek_metronome(&self, sample_position: u64) {
        self.sample_counter.store(sample_position, Ordering::SeqCst);
        // No cooldown - we want the first beat to play immediately after loop wrap.
        // The previous 4000-sample cooldown was causing the first beat to be missed.
        // If click overlap becomes an issue on manual seeks, we can add smarter
        // beat-alignment detection here instead.
        self.seek_cooldown.store(0, Ordering::SeqCst);
    }

    /// Set time signature (beats per bar)
    pub fn set_time_signature(&self, beats_per_bar: u32) {
        let mut ts = self.time_signature.lock();
        *ts = beats_per_bar;
        eprintln!("⏱️  [Recorder] Time signature set to {beats_per_bar}/4");
    }

    /// Get time signature (beats per bar)
    pub fn get_time_signature(&self) -> u32 {
        *self.time_signature.lock()
    }

    /// Set the timeline position (in seconds) where the recording should be placed
    pub fn set_recording_start_seconds(&self, seconds: f64) {
        *self.recording_start_seconds.lock() = seconds;
        eprintln!("🎙️  [Recorder] Recording start position set to {seconds:.3}s");
    }

    /// Get the timeline position (in seconds) where the recording should be placed
    pub fn get_recording_start_seconds(&self) -> f64 {
        *self.recording_start_seconds.lock()
    }

    /// Get current count-in beat number (1-indexed, 0 when not counting in)
    pub fn get_count_in_beat(&self) -> u32 {
        self.count_in_beat.load(Ordering::Relaxed)
    }

    /// Get count-in progress (0.0-1.0)
    pub fn get_count_in_progress(&self) -> f32 {
        self.count_in_progress.load(Ordering::Relaxed) as f32 / 10000.0
    }

    // ── Punch In/Out ──────────────────────────────────────────────

    pub fn set_punch_in_enabled(&self, enabled: bool) {
        self.punch_in_enabled.store(enabled, Ordering::SeqCst);
    }

    pub fn is_punch_in_enabled(&self) -> bool {
        self.punch_in_enabled.load(Ordering::SeqCst)
    }

    pub fn set_punch_out_enabled(&self, enabled: bool) {
        self.punch_out_enabled.store(enabled, Ordering::SeqCst);
    }

    pub fn is_punch_out_enabled(&self) -> bool {
        self.punch_out_enabled.load(Ordering::SeqCst)
    }

    pub fn set_punch_region(&self, in_seconds: f64, out_seconds: f64) {
        *self.punch_in_seconds.lock() = in_seconds;
        *self.punch_out_seconds.lock() = out_seconds;
    }

    pub fn get_punch_in_seconds(&self) -> f64 {
        *self.punch_in_seconds.lock()
    }

    pub fn get_punch_out_seconds(&self) -> f64 {
        *self.punch_out_seconds.lock()
    }

    pub fn is_punch_complete(&self) -> bool {
        self.punch_complete.load(Ordering::SeqCst)
    }

    pub fn clear_punch_complete(&self) {
        self.punch_complete.store(false, Ordering::SeqCst);
    }
}

/// References for use in audio callback
pub struct RecorderCallbackRefs {
    pub state: Arc<Mutex<RecordingState>>,
    pub recorded_samples: Arc<Mutex<Vec<f32>>>,
    pub sample_counter: Arc<AtomicU64>,
    pub count_in_bars: Arc<Mutex<u32>>,
    pub tempo: Arc<Mutex<f64>>,
    pub metronome_enabled: Arc<AtomicBool>,
    pub time_signature: Arc<Mutex<u32>>,
    pub seek_cooldown: Arc<AtomicU64>,
    pub count_in_beat: Arc<AtomicU32>,
    pub count_in_progress: Arc<AtomicU32>,
    pub punch_in_enabled: Arc<AtomicBool>,
    pub punch_out_enabled: Arc<AtomicBool>,
    pub punch_in_seconds: Arc<Mutex<f64>>,
    pub punch_out_seconds: Arc<Mutex<f64>>,
    pub punch_complete: Arc<AtomicBool>,
    pub monotonic_frames: Arc<AtomicU64>,
    pub click_started_at: Arc<AtomicU64>,
    pub click_is_downbeat: Arc<AtomicBool>,
    pub count_in_in_place: Arc<AtomicBool>,
}

impl RecorderCallbackRefs {
    /// Process audio for recording and generate metronome
    /// Returns metronome output (left, right) and updates recording state
    pub fn process_frame(
        &self,
        input_left: f32,
        input_right: f32,
        is_playing: bool,
        playhead_seconds: f64,
    ) -> (f32, f32) {
        // Read state once and drop lock immediately. try_lock first so a UI
        // thread mid-write can't stall the audio thread per sample (C2); only
        // count + fall back to a blocking lock on the rare contended frame.
        let current_state = if let Some(state) = self.state.try_lock() {
            *state
        } else {
            RECORDER_LOCK_CONTENTION.fetch_add(1, Ordering::Relaxed);
            *self.state.lock()
        };

        // Only increment counter when playing or recording
        // This ensures metronome resets properly when stopped
        let should_tick = is_playing || current_state != RecordingState::Idle;

        let sample_idx = if should_tick {
            self.sample_counter.fetch_add(1, Ordering::SeqCst)
        } else {
            self.sample_counter.load(Ordering::SeqCst)
        };

        // Same try_lock-or-count treatment for the two per-sample reads below —
        // both are written only when the user drags the tempo / time-sig
        // control, so contention is rare but must never block the audio thread.
        let tempo = if let Some(tempo) = self.tempo.try_lock() {
            *tempo
        } else {
            RECORDER_LOCK_CONTENTION.fetch_add(1, Ordering::Relaxed);
            *self.tempo.lock()
        };
        let time_sig = if let Some(time_sig) = self.time_signature.try_lock() {
            *time_sig
        } else {
            RECORDER_LOCK_CONTENTION.fetch_add(1, Ordering::Relaxed);
            *self.time_signature.lock()
        };
        let metronome_enabled = self.metronome_enabled.load(Ordering::SeqCst);

        // Calculate beat information
        let samples_per_beat = (60.0 / tempo * f64::from(TARGET_SAMPLE_RATE)) as u64;
        let samples_per_bar = samples_per_beat * u64::from(time_sig);

        // Check and decrement seek cooldown (prevents click overlap on short loops)
        let cooldown = self.seek_cooldown.load(Ordering::SeqCst);
        if cooldown > 0 {
            self.seek_cooldown.fetch_sub(1, Ordering::SeqCst);
        }

        // Generate metronome click
        let mut metronome_output = 0.0;

        // Monotonic frame clock for the click — unlike `sample_idx`, this
        // never rewinds on seek/loop, so a sounding click rides smoothly
        // through a loop wrap instead of being truncated and restarted.
        let monotonic = self.monotonic_frames.fetch_add(1, Ordering::Relaxed);

        // Only generate click if not in cooldown period (prevents overlapping clicks after seek)
        if metronome_enabled && cooldown == 0 {
            let position_in_bar = sample_idx % samples_per_bar;
            let beat_in_bar = position_in_bar / samples_per_beat;
            let position_in_beat = position_in_bar % samples_per_beat;

            // A beat boundary starts a click — unless one started less than
            // half a beat ago. Real consecutive beats are a full beat apart;
            // only the loop-wrap seek (which lands `sample_idx` back on a
            // beat boundary a buffer after that beat already clicked) gets
            // closer, and used to double the downbeat as an audible flam.
            if position_in_beat == 0 && should_tick {
                let last = self.click_started_at.load(Ordering::Relaxed);
                if last == NO_CLICK || monotonic.wrapping_sub(last) >= samples_per_beat / 2 {
                    self.click_started_at.store(monotonic, Ordering::Relaxed);
                    self.click_is_downbeat
                        .store(beat_in_bar == 0, Ordering::Relaxed);
                }
            }

            // Render the sounding click (short sine burst) from the monotonic
            // clock, so its envelope is immune to seeks.
            let started = self.click_started_at.load(Ordering::Relaxed);
            if started != NO_CLICK {
                let since = monotonic.wrapping_sub(started);
                if since < CLICK_FRAMES {
                    let t = since as f32 / TARGET_SAMPLE_RATE as f32;
                    // Higher pitch on downbeat
                    let freq = if self.click_is_downbeat.load(Ordering::Relaxed) {
                        1200.0
                    } else {
                        800.0
                    };
                    let envelope = (1.0 - (since as f32 / CLICK_FRAMES as f32)).powi(2);
                    metronome_output = (2.0 * PI * freq * t).sin() * 0.6 * envelope;
                }
            }
        }

        // Read punch state (atomics are lock-free)
        let punch_in = self.punch_in_enabled.load(Ordering::SeqCst);
        let punch_out = self.punch_out_enabled.load(Ordering::SeqCst);

        // Handle count-in and recording state transitions
        match current_state {
            RecordingState::CountingIn => {
                let count_in_bars = *self.count_in_bars.lock();
                let count_in_samples = samples_per_bar * u64::from(count_in_bars);

                // Calculate and store beat/progress for UI ring timer
                let beat_in_bar = ((sample_idx % samples_per_bar) / samples_per_beat) as u32 + 1; // 1-indexed
                let progress = (sample_idx as f64 / count_in_samples.max(1) as f64).min(1.0);
                self.count_in_beat.store(beat_in_bar, Ordering::Relaxed);
                self.count_in_progress
                    .store((progress * 10000.0) as u32, Ordering::Relaxed);

                if sample_idx >= count_in_samples {
                    self.count_in_beat.store(0, Ordering::Relaxed);
                    self.count_in_progress.store(0, Ordering::Relaxed);

                    if punch_in {
                        // Punch-in enabled: wait for playhead to reach region start
                        let punch_in_s = *self.punch_in_seconds.lock();
                        if playhead_seconds >= punch_in_s {
                            // Already past punch-in point, start recording immediately.
                            // (No audio-thread logging here — see C3.)
                            let mut state = self.state.lock();
                            *state = RecordingState::Recording;
                            drop(state);
                        } else {
                            let mut state = self.state.lock();
                            *state = RecordingState::WaitingForPunchIn;
                            drop(state);
                        }
                        self.sample_counter.store(0, Ordering::SeqCst);
                    } else {
                        // No punch-in: start recording immediately (existing behavior)
                        let mut state = self.state.lock();
                        *state = RecordingState::Recording;
                        drop(state);
                        self.sample_counter.store(0, Ordering::SeqCst);
                    }
                }
                // During count-in, only output metronome, don't record
            }
            RecordingState::WaitingForPunchIn => {
                // Transport is playing, waiting for playhead to reach punch-in point
                let punch_in_s = *self.punch_in_seconds.lock();
                if playhead_seconds >= punch_in_s {
                    // Clear buffer and start recording
                    {
                        let mut samples = self.recorded_samples.lock();
                        samples.clear();
                    }
                    self.sample_counter.store(0, Ordering::SeqCst);
                    let mut state = self.state.lock();
                    *state = RecordingState::Recording;
                }
                // Continue metronome during wait
            }
            RecordingState::Recording => {
                // Check punch-out boundary
                if punch_out {
                    let punch_out_s = *self.punch_out_seconds.lock();
                    if playhead_seconds >= punch_out_s {
                        let mut state = self.state.lock();
                        *state = RecordingState::Idle;
                        drop(state);
                        self.punch_complete.store(true, Ordering::SeqCst);
                        // Don't record this frame — we're past the boundary
                        return (metronome_output, metronome_output);
                    }
                }

                // Record input samples
                {
                    let mut samples = self.recorded_samples.lock();
                    samples.push(input_left);
                    samples.push(input_right);
                    // (No per-second audio-thread progress logging — see C3.)
                }
            }
            RecordingState::Idle => {
                // Don't reset counter - allow metronome to continue counting through beats
                // Counter only resets when starting a new recording (via start_recording method)
            }
        }

        (metronome_output, metronome_output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_recorder_creation() {
        let recorder = Recorder::new();
        assert_eq!(recorder.get_state(), RecordingState::Idle);
    }

    #[test]
    fn test_start_stop_recording() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);

        assert!(recorder.start_recording().is_ok());
        assert_eq!(recorder.get_state(), RecordingState::Recording);

        let result = recorder.stop_recording(TARGET_SAMPLE_RATE);
        assert!(result.is_ok());
        assert_eq!(recorder.get_state(), RecordingState::Idle);
    }

    #[test]
    fn test_count_in() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(2);

        assert_eq!(recorder.get_count_in_bars(), 2);

        assert!(recorder.start_recording().is_ok());
        assert_eq!(recorder.get_state(), RecordingState::CountingIn);
    }

    #[test]
    fn test_tempo() {
        let recorder = Recorder::new();
        recorder.set_tempo(140.0);
        assert!((recorder.get_tempo() - 140.0).abs() < 1e-6);

        recorder.set_tempo(500.0);
        assert!((recorder.get_tempo() - 300.0).abs() < 1e-6);

        recorder.set_tempo(10.0);
        assert!((recorder.get_tempo() - 20.0).abs() < 1e-6);
    }

    #[test]
    fn test_metronome_toggle() {
        let recorder = Recorder::new();
        assert!(recorder.is_metronome_enabled());

        recorder.set_metronome_enabled(false);
        assert!(!recorder.is_metronome_enabled());
    }

    // ── Punch tests ────────────────────────────────────────────

    #[test]
    fn test_punch_defaults() {
        let recorder = Recorder::new();
        assert!(!recorder.is_punch_in_enabled());
        assert!(!recorder.is_punch_out_enabled());
        assert!(!recorder.is_punch_complete());
    }

    #[test]
    fn test_punch_region_setters() {
        let recorder = Recorder::new();
        recorder.set_punch_region(5.0, 10.0);
        assert!((recorder.get_punch_in_seconds() - 5.0).abs() < f64::EPSILON);
        assert!((recorder.get_punch_out_seconds() - 10.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_punch_in_starts_waiting() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_punch_in_enabled(true);
        recorder.set_punch_region(5.0, 10.0);

        assert!(recorder.start_recording().is_ok());
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);
    }

    #[test]
    fn test_stop_while_waiting_returns_none() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_punch_in_enabled(true);
        recorder.set_punch_region(5.0, 10.0);

        recorder.start_recording().unwrap();
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);

        let result = recorder.stop_recording(TARGET_SAMPLE_RATE).unwrap();
        assert!(
            result.is_none(),
            "No audio should be captured when stopped during punch wait"
        );
    }

    #[test]
    fn test_punch_in_triggers_recording() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_punch_in_enabled(true);
        recorder.set_punch_region(0.01, 10.0); // punch-in at 0.01s

        recorder.start_recording().unwrap();
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);

        let refs = recorder.get_callback_refs();
        // Feed frames with playhead before punch-in
        for _ in 0..100 {
            refs.process_frame(0.5, 0.5, true, 0.005);
        }
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);

        // Feed frame at punch-in point
        refs.process_frame(0.5, 0.5, true, 0.01);
        assert_eq!(recorder.get_state(), RecordingState::Recording);
    }

    #[test]
    fn test_punch_out_auto_stops() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_punch_out_enabled(true);
        recorder.set_punch_region(0.0, 0.01); // punch-out at 0.01s

        recorder.start_recording().unwrap();
        assert_eq!(recorder.get_state(), RecordingState::Recording);

        let refs = recorder.get_callback_refs();
        // Record a few frames before punch-out
        for _ in 0..100 {
            refs.process_frame(0.5, 0.5, true, 0.005);
        }
        assert_eq!(recorder.get_state(), RecordingState::Recording);
        assert!(!recorder.is_punch_complete());

        // Feed frame at punch-out point
        refs.process_frame(0.5, 0.5, true, 0.01);
        assert_eq!(recorder.get_state(), RecordingState::Idle);
        assert!(recorder.is_punch_complete());
    }

    #[test]
    fn test_punch_in_and_out_full_cycle() {
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_punch_in_enabled(true);
        recorder.set_punch_out_enabled(true);
        recorder.set_punch_region(1.0, 2.0);

        recorder.start_recording().unwrap();
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);

        let refs = recorder.get_callback_refs();

        // Before punch-in: waiting
        refs.process_frame(0.1, 0.1, true, 0.5);
        assert_eq!(recorder.get_state(), RecordingState::WaitingForPunchIn);

        // At punch-in: starts recording
        refs.process_frame(0.1, 0.1, true, 1.0);
        assert_eq!(recorder.get_state(), RecordingState::Recording);

        // During recording
        refs.process_frame(0.5, 0.5, true, 1.5);
        assert_eq!(recorder.get_state(), RecordingState::Recording);

        // At punch-out: auto-stops
        refs.process_frame(0.5, 0.5, true, 2.0);
        assert_eq!(recorder.get_state(), RecordingState::Idle);
        assert!(recorder.is_punch_complete());

        // stop_recording should return the audio clip even though state is Idle
        // because punch_complete was true (auto-punch-out fired)
        let clip = recorder.stop_recording(TARGET_SAMPLE_RATE).unwrap();
        assert!(
            clip.is_some(),
            "Should return recorded audio after auto-punch-out"
        );
        assert!(!clip.unwrap().samples.is_empty());
    }

    #[test]
    fn stop_recording_honors_the_actual_stream_rate() {
        // C22: recorded frames accrue one per output-callback frame, so when
        // the stream runs at 44.1 kHz, 44100 frames are ONE second of audio —
        // not 0.919 s. The clip must come back resampled to the engine rate
        // with the wall-clock-correct duration.
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.start_recording().unwrap();

        let refs = recorder.get_callback_refs();
        for _ in 0..44_100 {
            refs.process_frame(0.25, 0.25, true, 0.0);
        }

        let clip = recorder
            .stop_recording(44_100)
            .unwrap()
            .expect("clip should be returned");
        assert_eq!(clip.sample_rate, TARGET_SAMPLE_RATE);
        assert!(
            (clip.duration_seconds - 1.0).abs() < 0.01,
            "44100 frames at a 44.1 kHz stream are 1.0 s, got {:.4}s",
            clip.duration_seconds
        );
        // Resampled to the engine rate: ~48000 frames of stereo.
        let frames = clip.samples.len() / 2;
        assert!(
            (frames as f64 - f64::from(TARGET_SAMPLE_RATE)).abs() < 200.0,
            "expected ~48000 frames after resampling, got {frames}"
        );
    }

    #[test]
    fn stop_recording_at_engine_rate_is_untouched() {
        // The common case (stream at 48 kHz) must not resample at all.
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.start_recording().unwrap();

        let refs = recorder.get_callback_refs();
        for _ in 0..4_800 {
            refs.process_frame(0.25, 0.25, true, 0.0);
        }

        let clip = recorder
            .stop_recording(TARGET_SAMPLE_RATE)
            .unwrap()
            .expect("clip should be returned");
        assert_eq!(clip.samples.len(), 4_800 * 2);
        assert!((clip.duration_seconds - 0.1).abs() < 1e-9);
        // Samples pass through bit-exact — no resampler in the path.
        assert!(clip
            .samples
            .iter()
            .all(|&s| (s - 0.25).abs() < f32::EPSILON));
    }

    /// Process `frames` callback frames and return the number of click
    /// onsets heard. An onset is sound following a sustained silent gap —
    /// the click is a sine burst, so instantaneous zero-crossings inside it
    /// must not read as silence (a 1200/800 Hz cycle is 40–60 frames; a real
    /// gap between clicks is thousands).
    fn count_click_onsets(refs: &RecorderCallbackRefs, frames: usize, silent_run: &mut u32) -> u32 {
        let mut onsets = 0;
        for _ in 0..frames {
            let (out, _) = refs.process_frame(0.0, 0.0, true, 0.0);
            if out.abs() < 1e-6 {
                *silent_run += 1;
            } else {
                if *silent_run >= 100 {
                    onsets += 1;
                }
                *silent_run = 0;
            }
        }
        onsets
    }

    #[test]
    fn loop_wrap_does_not_double_the_downbeat() {
        // At a loop wrap the transport plays a few frames past the loop end
        // (the boundary beat clicks), then seeks the metronome back to 0 —
        // which lands on a beat boundary again. That used to restart the
        // downbeat click ~a buffer after it already fired: an audible flam.
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_tempo(120.0); // 24000 frames per beat at 48 kHz
        recorder.set_metronome_enabled(true);
        let refs = recorder.get_callback_refs();
        let mut silent_run = 1000; // long silence before the first frame

        // One full 4/4 bar plus a few frames: beats at 0, 24000, 48000,
        // 72000 and the next bar's downbeat at 96000 (each click's first
        // audible sample lands a frame after its boundary — sin(0) = 0).
        let onsets = count_click_onsets(&refs, 96_010, &mut silent_run);
        assert_eq!(onsets, 5, "one click per beat plus the wrap-boundary beat");

        // The callback runs ~a buffer past the loop end before the UI seek
        // lands, then the metronome is rewound to the loop start.
        count_click_onsets(&refs, 512, &mut silent_run);
        recorder.seek_metronome(0);

        // No new click right after the wrap — the boundary beat just fired.
        let flam = count_click_onsets(&refs, 8_000, &mut silent_run);
        assert_eq!(
            flam, 0,
            "the wrap seek must not restart the downbeat (flam)"
        );

        // …but the next real beat still clicks (the guard isn't a mute).
        let next_beat = count_click_onsets(&refs, 24_000, &mut silent_run);
        assert_eq!(next_beat, 1, "the beat after the wrap must still click");
    }

    #[test]
    fn stop_and_restart_clicks_immediately() {
        // Stopping clears the sounding click, so a fresh play's first
        // downbeat fires immediately even within the refractory window.
        let recorder = Recorder::new();
        recorder.set_count_in_bars(0);
        recorder.set_tempo(120.0);
        recorder.set_metronome_enabled(true);
        let refs = recorder.get_callback_refs();
        let mut silent_run = 1000;

        assert_eq!(count_click_onsets(&refs, 100, &mut silent_run), 1);
        recorder.reset_metronome(); // stop
        silent_run = 1000;
        assert_eq!(
            count_click_onsets(&refs, 100, &mut silent_run),
            1,
            "restart must click its downbeat right away"
        );
    }
}
