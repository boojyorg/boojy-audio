/// Recording engine with metronome and count-in support
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use std::f32::consts::PI;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};

/// Recording state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordingState {
    Idle,
    CountingIn,
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
}

impl Recorder {
    /// Create a new recorder
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(RecordingState::Idle)),
            recorded_samples: Arc::new(Mutex::new(Vec::new())),
            sample_counter: Arc::new(AtomicU64::new(0)),
            count_in_bars: Arc::new(Mutex::new(1)), // Default: 1 bar
            tempo: Arc::new(Mutex::new(120.0)), // Default: 120 BPM
            metronome_enabled: Arc::new(AtomicBool::new(true)),
            time_signature: Arc::new(Mutex::new(4)), // Default: 4/4
            seek_cooldown: Arc::new(AtomicU64::new(0)),
            recording_start_seconds: Arc::new(Mutex::new(0.0)),
            count_in_beat: Arc::new(AtomicU32::new(0)),
            count_in_progress: Arc::new(AtomicU32::new(0)),
        }
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
        }
    }

    /// Start recording with optional count-in
    pub fn start_recording(&self) -> Result<(), String> {
        let mut state = self.state.lock().map_err(|e| e.to_string())?;

        if *state != RecordingState::Idle {
            return Err("Already recording or counting in".to_string());
        }

        // Clear previous recording
        {
            let mut samples = self.recorded_samples.lock().map_err(|e| e.to_string())?;
            samples.clear();
            eprintln!("🎙️  [Recorder] Cleared {} previous samples", samples.len());
        }

        self.sample_counter.store(0, Ordering::SeqCst);

        // Check if count-in is enabled
        let count_in = *self.count_in_bars.lock().map_err(|e| e.to_string())?;

        if count_in > 0 {
            *state = RecordingState::CountingIn;
            eprintln!("🎙️  [Recorder] Starting with count-in: {} bars", count_in);
        } else {
            *state = RecordingState::Recording;
            eprintln!("🎙️  [Recorder] Starting recording immediately (no count-in)");
        }

        Ok(())
    }

    /// Stop recording and return the recorded audio clip
    pub fn stop_recording(&self) -> Result<Option<AudioClip>, String> {
        let mut state = self.state.lock().map_err(|e| e.to_string())?;
        
        if *state == RecordingState::Idle {
            return Ok(None);
        }

        *state = RecordingState::Idle;
        self.count_in_beat.store(0, Ordering::Relaxed);
        self.count_in_progress.store(0, Ordering::Relaxed);

        // Get recorded samples
        let samples = {
            let samples_lock = self.recorded_samples.lock().map_err(|e| e.to_string())?;
            samples_lock.clone()
        };

        if samples.is_empty() {
            return Ok(None);
        }

        // Create audio clip from recorded samples
        let frame_count = samples.len() / 2; // Stereo
        let duration_seconds = frame_count as f64 / TARGET_SAMPLE_RATE as f64;

        let clip = AudioClip {
            samples,
            channels: 2,
            sample_rate: TARGET_SAMPLE_RATE,
            duration_seconds,
            file_path: format!("recorded_{}.wav", 
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs()
            ),
        };

        Ok(Some(clip))
    }

    /// Get current recording state
    pub fn get_state(&self) -> RecordingState {
        *self.state.lock().expect("mutex poisoned")
    }

    /// Set count-in duration in bars
    pub fn set_count_in_bars(&self, bars: u32) {
        *self.count_in_bars.lock().expect("mutex poisoned") = bars;
    }

    /// Get count-in duration in bars
    pub fn get_count_in_bars(&self) -> u32 {
        *self.count_in_bars.lock().expect("mutex poisoned")
    }

    /// Set tempo in BPM
    pub fn set_tempo(&self, bpm: f64) {
        *self.tempo.lock().expect("mutex poisoned") = bpm.clamp(20.0, 300.0);
    }

    /// Get tempo in BPM
    pub fn get_tempo(&self) -> f64 {
        *self.tempo.lock().expect("mutex poisoned")
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
        self.recorded_samples.lock().expect("mutex poisoned").len()
    }

    /// Get recorded duration in seconds
    pub fn get_recorded_duration(&self) -> f64 {
        let sample_count = self.get_recorded_sample_count();
        let frame_count = sample_count / 2; // Stereo
        frame_count as f64 / TARGET_SAMPLE_RATE as f64
    }

    /// Get recording waveform preview (downsampled for display)
    /// Returns a list of peak values suitable for UI display
    /// Each peak represents multiple samples averaged together
    pub fn get_recording_waveform(&self, num_peaks: usize) -> Vec<f32> {
        if let Ok(samples) = self.recorded_samples.lock() {
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
        } else {
            Vec::new()
        }
    }

    /// Reset metronome beat position (called when transport stops)
    pub fn reset_metronome(&self) {
        let old_value = self.sample_counter.swap(0, Ordering::SeqCst);
        eprintln!("🔄 [Recorder] Metronome reset: {} → 0", old_value);
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
        let mut ts = self.time_signature.lock().expect("mutex poisoned");
        *ts = beats_per_bar;
        eprintln!("⏱️  [Recorder] Time signature set to {}/4", beats_per_bar);
    }

    /// Get time signature (beats per bar)
    pub fn get_time_signature(&self) -> u32 {
        *self.time_signature.lock().expect("mutex poisoned")
    }

    /// Set the timeline position (in seconds) where the recording should be placed
    pub fn set_recording_start_seconds(&self, seconds: f64) {
        *self.recording_start_seconds.lock().expect("mutex poisoned") = seconds;
        eprintln!("🎙️  [Recorder] Recording start position set to {:.3}s", seconds);
    }

    /// Get the timeline position (in seconds) where the recording should be placed
    pub fn get_recording_start_seconds(&self) -> f64 {
        *self.recording_start_seconds.lock().expect("mutex poisoned")
    }

    /// Get current count-in beat number (1-indexed, 0 when not counting in)
    pub fn get_count_in_beat(&self) -> u32 {
        self.count_in_beat.load(Ordering::Relaxed)
    }

    /// Get count-in progress (0.0-1.0)
    pub fn get_count_in_progress(&self) -> f32 {
        self.count_in_progress.load(Ordering::Relaxed) as f32 / 10000.0
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
}

impl RecorderCallbackRefs {
    /// Process audio for recording and generate metronome
    /// Returns metronome output (left, right) and updates recording state
    pub fn process_frame(
        &self,
        input_left: f32,
        input_right: f32,
        is_playing: bool,
    ) -> (f32, f32) {
        // Read state once and drop lock immediately to avoid blocking UI thread
        let current_state = {
            let state = self.state.lock().expect("mutex poisoned");
            *state
        }; // Lock released here

        // Only increment counter when playing or recording
        // This ensures metronome resets properly when stopped
        let should_tick = is_playing || current_state != RecordingState::Idle;

        let sample_idx = if should_tick {
            self.sample_counter.fetch_add(1, Ordering::SeqCst)
        } else {
            let val = self.sample_counter.load(Ordering::SeqCst);
            // Debug: Log when we're NOT ticking (should stay at 0 after reset)
            static LAST_LOGGED: AtomicU64 = AtomicU64::new(u64::MAX);
            if val != LAST_LOGGED.load(Ordering::Relaxed) && val % 96000 == 0 {
                eprintln!("🔇 [Recorder] Not ticking, counter at: {} (is_playing={}, state={:?})",
                    val, is_playing, current_state);
                LAST_LOGGED.store(val, Ordering::Relaxed);
            }
            val
        };

        let tempo = *self.tempo.lock().expect("mutex poisoned");
        let time_sig = *self.time_signature.lock().expect("mutex poisoned");
        let metronome_enabled = self.metronome_enabled.load(Ordering::SeqCst);

        // Calculate beat information
        let samples_per_beat = (60.0 / tempo * TARGET_SAMPLE_RATE as f64) as u64;
        let samples_per_bar = samples_per_beat * time_sig as u64;

        // Check and decrement seek cooldown (prevents click overlap on short loops)
        let cooldown = self.seek_cooldown.load(Ordering::SeqCst);
        if cooldown > 0 {
            self.seek_cooldown.fetch_sub(1, Ordering::SeqCst);
        }

        // Generate metronome click
        let mut metronome_output = 0.0;

        // Only generate click if not in cooldown period (prevents overlapping clicks after seek)
        if metronome_enabled && cooldown == 0 {
            let position_in_bar = sample_idx % samples_per_bar;
            let beat_in_bar = position_in_bar / samples_per_beat;
            let position_in_beat = position_in_bar % samples_per_beat;

            // Generate click (short sine burst)
            if position_in_beat < 4000 { // ~80ms click at 48kHz (increased from 40ms for better audibility)
                let t = position_in_beat as f32 / TARGET_SAMPLE_RATE as f32;
                let freq = if beat_in_bar == 0 { 1200.0 } else { 800.0 }; // Higher pitch on downbeat
                let envelope = (1.0 - (position_in_beat as f32 / 4000.0)).powi(2);
                metronome_output = (2.0 * PI * freq * t).sin() * 0.6 * envelope; // Increased volume from 0.3 to 0.6
            }
        }

        // Handle count-in and recording state transitions
        match current_state {
            RecordingState::CountingIn => {
                let count_in_bars = *self.count_in_bars.lock().expect("mutex poisoned");
                let count_in_samples = samples_per_bar * count_in_bars as u64;

                // Calculate and store beat/progress for UI ring timer
                let beat_in_bar = ((sample_idx % samples_per_bar) / samples_per_beat) as u32 + 1; // 1-indexed
                let progress = (sample_idx as f64 / count_in_samples.max(1) as f64).min(1.0);
                self.count_in_beat.store(beat_in_bar, Ordering::Relaxed);
                self.count_in_progress.store((progress * 10000.0) as u32, Ordering::Relaxed);

                if sample_idx >= count_in_samples {
                    // Count-in finished, start recording (need to re-acquire lock for state change)
                    eprintln!("✅ [Recorder] Count-in complete! Transitioning to Recording state (sample: {})", sample_idx);
                    let mut state = self.state.lock().expect("mutex poisoned");
                    *state = RecordingState::Recording;
                    drop(state); // Release immediately
                    self.sample_counter.store(0, Ordering::SeqCst);
                    self.count_in_beat.store(0, Ordering::Relaxed);
                    self.count_in_progress.store(0, Ordering::Relaxed);
                }
                // During count-in, only output metronome, don't record
            }
            RecordingState::Recording => {
                // Record input samples
                if let Ok(mut samples) = self.recorded_samples.lock() {
                    samples.push(input_left);
                    samples.push(input_right);

                    // Log every second of recording
                    if samples.len() % 96000 == 0 {
                        eprintln!("🎙️  [Recorder] Recording... {} samples ({:.1}s)",
                            samples.len(), samples.len() as f32 / (TARGET_SAMPLE_RATE as f32 * 2.0));
                    }
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
        
        // Set count-in to 0 for immediate recording
        recorder.set_count_in_bars(0);
        
        assert!(recorder.start_recording().is_ok());
        assert_eq!(recorder.get_state(), RecordingState::Recording);
        
        let result = recorder.stop_recording();
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
        assert_eq!(recorder.get_tempo(), 140.0);
        
        // Test clamping
        recorder.set_tempo(500.0);
        assert_eq!(recorder.get_tempo(), 300.0);
        
        recorder.set_tempo(10.0);
        assert_eq!(recorder.get_tempo(), 20.0);
    }

    #[test]
    fn test_metronome_toggle() {
        let recorder = Recorder::new();
        assert!(recorder.is_metronome_enabled()); // Default is enabled
        
        recorder.set_metronome_enabled(false);
        assert!(!recorder.is_metronome_enabled());
    }
}

