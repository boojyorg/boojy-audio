//! Latency Test Module
//!
//! Measures real round-trip audio latency by:
//! 1. Playing a test tone burst through output
//! 2. Recording through input simultaneously
//! 3. Detecting the tone's arrival via peak detection
//! 4. Calculating latency from sample offset

use std::sync::atomic::{AtomicU8, AtomicU64, AtomicU32, Ordering};
use std::sync::Mutex;
use std::f32::consts::PI;

/// Test states
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum LatencyTestState {
    Idle = 0,
    WaitingForSilence = 1,  // Wait for input to be quiet before starting
    Playing = 2,             // Generating test tone
    Listening = 3,           // Waiting to detect tone in input
    Analyzing = 4,           // Processing captured data
    Done = 5,                // Result available
    Error = 6,               // Test failed
}

impl From<u8> for LatencyTestState {
    fn from(value: u8) -> Self {
        match value {
            0 => Self::Idle,
            1 => Self::WaitingForSilence,
            2 => Self::Playing,
            3 => Self::Listening,
            4 => Self::Analyzing,
            5 => Self::Done,
            6 => Self::Error,
            _ => Self::Idle,
        }
    }
}

/// Configuration for the latency test
pub struct LatencyTestConfig {
    /// Frequency of test tone in Hz
    pub tone_frequency: f32,
    /// Duration of test tone in samples
    pub tone_duration_samples: u32,
    /// How long to wait for silence before starting (samples)
    pub silence_wait_samples: u32,
    /// Maximum time to listen for response (samples)
    pub max_listen_samples: u32,
    /// Threshold for detecting tone (0.0-1.0)
    pub detection_threshold: f32,
    /// Sample rate
    pub sample_rate: u32,
}

impl Default for LatencyTestConfig {
    fn default() -> Self {
        Self {
            tone_frequency: 1000.0,        // 1kHz test tone
            tone_duration_samples: 4800,   // 100ms at 48kHz
            silence_wait_samples: 4800,    // 100ms wait for silence
            max_listen_samples: 48000,     // 1 second max listen time
            detection_threshold: 0.1,      // 10% of max amplitude
            sample_rate: 48000,
        }
    }
}

/// Latency test engine - measures real audio round-trip latency
pub struct LatencyTest {
    /// Current state of the test
    state: AtomicU8,

    /// Sample index when tone started playing
    tone_start_sample: AtomicU64,

    /// Sample index when tone was detected in input
    detected_sample: AtomicU64,

    /// Counter for current phase duration
    phase_counter: AtomicU32,

    /// Measured latency result in milliseconds
    result_ms: Mutex<Option<f32>>,

    /// Error message if test failed
    error_message: Mutex<Option<String>>,

    /// Configuration
    config: LatencyTestConfig,

    /// Input buffer for analysis (circular, stores recent samples)
    input_buffer: Mutex<Vec<f32>>,

    /// Current write position in input buffer
    input_write_pos: AtomicU32,
}

impl LatencyTest {
    pub fn new(sample_rate: u32) -> Self {
        let mut config = LatencyTestConfig::default();
        config.sample_rate = sample_rate;

        // Adjust durations based on sample rate
        let samples_per_100ms = sample_rate / 10;
        config.tone_duration_samples = samples_per_100ms;
        config.silence_wait_samples = samples_per_100ms;
        config.max_listen_samples = sample_rate; // 1 second

        // Pre-allocate input buffer for 1 second of audio
        let buffer_size = sample_rate as usize;

        Self {
            state: AtomicU8::new(LatencyTestState::Idle as u8),
            tone_start_sample: AtomicU64::new(0),
            detected_sample: AtomicU64::new(0),
            phase_counter: AtomicU32::new(0),
            result_ms: Mutex::new(None),
            error_message: Mutex::new(None),
            config,
            input_buffer: Mutex::new(vec![0.0; buffer_size]),
            input_write_pos: AtomicU32::new(0),
        }
    }

    /// Start a new latency test
    pub fn start(&self) -> Result<(), String> {
        let current_state = LatencyTestState::from(self.state.load(Ordering::SeqCst));

        if current_state != LatencyTestState::Idle && current_state != LatencyTestState::Done && current_state != LatencyTestState::Error {
            return Err("Test already in progress".to_string());
        }

        // Reset state
        self.tone_start_sample.store(0, Ordering::SeqCst);
        self.detected_sample.store(0, Ordering::SeqCst);
        self.phase_counter.store(0, Ordering::SeqCst);

        if let Ok(mut result) = self.result_ms.lock() {
            *result = None;
        }
        if let Ok(mut error) = self.error_message.lock() {
            *error = None;
        }
        if let Ok(mut buffer) = self.input_buffer.lock() {
            buffer.fill(0.0);
        }
        self.input_write_pos.store(0, Ordering::SeqCst);

        // Start with waiting for silence
        self.state.store(LatencyTestState::WaitingForSilence as u8, Ordering::SeqCst);

        eprintln!("🎚️ [LatencyTest] Started - waiting for silence...");
        Ok(())
    }

    /// Stop/cancel the test
    pub fn stop(&self) {
        self.state.store(LatencyTestState::Idle as u8, Ordering::SeqCst);
        eprintln!("🎚️ [LatencyTest] Stopped");
    }

    /// Get current state
    pub fn get_state(&self) -> LatencyTestState {
        LatencyTestState::from(self.state.load(Ordering::SeqCst))
    }

    /// Get result in milliseconds (if available)
    pub fn get_result(&self) -> Option<f32> {
        if let Ok(result) = self.result_ms.lock() {
            *result
        } else {
            None
        }
    }

    /// Get error message (if any)
    pub fn get_error(&self) -> Option<String> {
        if let Ok(error) = self.error_message.lock() {
            error.clone()
        } else {
            None
        }
    }

    /// Generate test tone sample (called from audio callback)
    /// Returns the sample to add to output, or 0.0 if not playing
    pub fn generate_output(&self, current_sample: u64) -> f32 {
        let state = self.get_state();

        if state != LatencyTestState::Playing {
            return 0.0;
        }

        let tone_start = self.tone_start_sample.load(Ordering::SeqCst);
        if tone_start == 0 {
            return 0.0;
        }

        let samples_since_start = current_sample.saturating_sub(tone_start) as u32;

        if samples_since_start >= self.config.tone_duration_samples {
            // Tone finished, switch to listening
            self.state.store(LatencyTestState::Listening as u8, Ordering::SeqCst);
            self.phase_counter.store(0, Ordering::SeqCst);
            eprintln!("🎚️ [LatencyTest] Tone complete, now listening...");
            return 0.0;
        }

        // Generate sine wave with fade in/out to avoid clicks
        let t = samples_since_start as f32 / self.config.sample_rate as f32;
        let phase = 2.0 * PI * self.config.tone_frequency * t;
        let mut sample = phase.sin();

        // Apply fade in/out envelope (10ms each)
        let fade_samples = self.config.sample_rate / 100; // 10ms
        if samples_since_start < fade_samples {
            let fade = samples_since_start as f32 / fade_samples as f32;
            sample *= fade;
        } else if samples_since_start > self.config.tone_duration_samples - fade_samples {
            let fade = (self.config.tone_duration_samples - samples_since_start) as f32 / fade_samples as f32;
            sample *= fade;
        }

        // Scale to reasonable level (not too loud)
        sample * 0.5
    }

    /// Process input sample (called from audio callback)
    pub fn process_input(&self, input_sample: f32, current_sample: u64) {
        let state = self.get_state();

        match state {
            LatencyTestState::WaitingForSilence => {
                let counter = self.phase_counter.fetch_add(1, Ordering::SeqCst);

                // Check if input is quiet enough
                if input_sample.abs() > 0.05 {
                    // Reset counter if we detect noise
                    self.phase_counter.store(0, Ordering::SeqCst);
                } else if counter >= self.config.silence_wait_samples {
                    // Silence detected, start playing
                    self.tone_start_sample.store(current_sample, Ordering::SeqCst);
                    self.state.store(LatencyTestState::Playing as u8, Ordering::SeqCst);
                    eprintln!("🎚️ [LatencyTest] Silence detected, playing tone at sample {}", current_sample);
                }
            }

            LatencyTestState::Playing | LatencyTestState::Listening => {
                // Store input for analysis
                if let Ok(mut buffer) = self.input_buffer.lock() {
                    let pos = self.input_write_pos.fetch_add(1, Ordering::SeqCst) as usize;
                    if pos < buffer.len() {
                        buffer[pos] = input_sample;
                    }
                }

                // In listening mode, check for tone detection
                if state == LatencyTestState::Listening {
                    let counter = self.phase_counter.fetch_add(1, Ordering::SeqCst);

                    // Simple peak detection
                    if input_sample.abs() > self.config.detection_threshold {
                        self.detected_sample.store(current_sample, Ordering::SeqCst);
                        self.state.store(LatencyTestState::Analyzing as u8, Ordering::SeqCst);
                        eprintln!("🎚️ [LatencyTest] Tone detected at sample {}", current_sample);

                        // Calculate result
                        self.calculate_result();
                    } else if counter >= self.config.max_listen_samples {
                        // Timeout - no tone detected
                        self.state.store(LatencyTestState::Error as u8, Ordering::SeqCst);
                        if let Ok(mut error) = self.error_message.lock() {
                            *error = Some("Timeout: No audio detected. Check loopback connection.".to_string());
                        }
                        eprintln!("🎚️ [LatencyTest] Timeout - no tone detected");
                    }
                }
            }

            _ => {}
        }
    }

    /// Calculate the latency result
    fn calculate_result(&self) {
        let tone_start = self.tone_start_sample.load(Ordering::SeqCst);
        let detected = self.detected_sample.load(Ordering::SeqCst);

        if detected > tone_start {
            let latency_samples = detected - tone_start;
            let latency_ms = (latency_samples as f32 / self.config.sample_rate as f32) * 1000.0;

            if let Ok(mut result) = self.result_ms.lock() {
                *result = Some(latency_ms);
            }

            self.state.store(LatencyTestState::Done as u8, Ordering::SeqCst);
            eprintln!("🎚️ [LatencyTest] Result: {:.1}ms ({} samples)", latency_ms, latency_samples);
        } else {
            self.state.store(LatencyTestState::Error as u8, Ordering::SeqCst);
            if let Ok(mut error) = self.error_message.lock() {
                *error = Some("Invalid sample timing".to_string());
            }
        }
    }

    /// Get status as (state_code, result_ms)
    /// state_code: 0=Idle, 1=WaitingForSilence, 2=Playing, 3=Listening, 4=Analyzing, 5=Done, 6=Error
    pub fn get_status(&self) -> (i32, f32) {
        let state = self.get_state() as i32;
        let result = self.get_result().unwrap_or(-1.0);
        (state, result)
    }
}

impl Default for LatencyTest {
    fn default() -> Self {
        Self::new(48000)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_latency_test_creation() {
        let test = LatencyTest::new(48000);
        assert_eq!(test.get_state(), LatencyTestState::Idle);
    }

    #[test]
    fn test_latency_test_start() {
        let test = LatencyTest::new(48000);
        assert!(test.start().is_ok());
        assert_eq!(test.get_state(), LatencyTestState::WaitingForSilence);
    }

    #[test]
    fn test_tone_generation() {
        let test = LatencyTest::new(48000);
        test.start().unwrap();

        // Simulate silence detection
        for i in 0..5000 {
            test.process_input(0.0, i);
        }

        // Should now be playing
        assert_eq!(test.get_state(), LatencyTestState::Playing);

        // Generate some tone samples
        let sample = test.generate_output(5000);
        assert!(sample.abs() > 0.0);
    }
}
