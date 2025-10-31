/// Recording engine with metronome and count-in support
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use std::f32::consts::PI;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

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
}

impl Recorder {
    /// Create a new recorder
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(RecordingState::Idle)),
            recorded_samples: Arc::new(Mutex::new(Vec::new())),
            sample_counter: Arc::new(AtomicU64::new(0)),
            count_in_bars: Arc::new(Mutex::new(2)), // Default: 2 bars
            tempo: Arc::new(Mutex::new(120.0)), // Default: 120 BPM
            metronome_enabled: Arc::new(AtomicBool::new(true)),
            time_signature: Arc::new(Mutex::new(4)), // Default: 4/4
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
        *self.state.lock().unwrap()
    }

    /// Set count-in duration in bars
    pub fn set_count_in_bars(&self, bars: u32) {
        *self.count_in_bars.lock().unwrap() = bars;
    }

    /// Get count-in duration in bars
    pub fn get_count_in_bars(&self) -> u32 {
        *self.count_in_bars.lock().unwrap()
    }

    /// Set tempo in BPM
    pub fn set_tempo(&self, bpm: f64) {
        *self.tempo.lock().unwrap() = bpm.clamp(20.0, 300.0);
    }

    /// Get tempo in BPM
    pub fn get_tempo(&self) -> f64 {
        *self.tempo.lock().unwrap()
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
        self.recorded_samples.lock().unwrap().len()
    }

    /// Get recorded duration in seconds
    pub fn get_recorded_duration(&self) -> f64 {
        let sample_count = self.get_recorded_sample_count();
        let frame_count = sample_count / 2; // Stereo
        frame_count as f64 / TARGET_SAMPLE_RATE as f64
    }

    /// Reset metronome beat position (called when transport stops)
    pub fn reset_metronome(&self) {
        let old_value = self.sample_counter.swap(0, Ordering::SeqCst);
        eprintln!("🔄 [Recorder] Metronome reset: {} → 0", old_value);
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
            let state = self.state.lock().unwrap();
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

        let tempo = *self.tempo.lock().unwrap();
        let time_sig = *self.time_signature.lock().unwrap();
        let metronome_enabled = self.metronome_enabled.load(Ordering::SeqCst);

        // Calculate beat information
        let samples_per_beat = (60.0 / tempo * TARGET_SAMPLE_RATE as f64) as u64;
        let samples_per_bar = samples_per_beat * time_sig as u64;

        // Generate metronome click
        let mut metronome_output = 0.0;

        if metronome_enabled {
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
                let count_in_bars = *self.count_in_bars.lock().unwrap();
                let count_in_samples = samples_per_bar * count_in_bars as u64;

                if sample_idx >= count_in_samples {
                    // Count-in finished, start recording (need to re-acquire lock for state change)
                    eprintln!("✅ [Recorder] Count-in complete! Transitioning to Recording state (sample: {})", sample_idx);
                    let mut state = self.state.lock().unwrap();
                    *state = RecordingState::Recording;
                    drop(state); // Release immediately
                    self.sample_counter.store(0, Ordering::SeqCst);
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

