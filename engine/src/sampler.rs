/// Sampler instrument - plays audio samples triggered by MIDI notes
/// Similar to Synth but uses sample playback instead of oscillators
/// Supports pitch shifting based on root note and Attack/Release envelope

use std::sync::Arc;
use crate::audio_file::AudioClip;

const MAX_VOICES: usize = 8;

// ============================================================================
// ENVELOPE (simplified AR - Attack/Release only)
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq)]
enum EnvelopeState {
    Idle,
    Attack,
    Sustain,
    Release,
}

#[derive(Debug, Clone, Copy)]
pub struct SamplerEnvelope {
    pub attack_ms: f32,  // 0-5000ms
    pub release_ms: f32, // 0-5000ms
}

impl Default for SamplerEnvelope {
    fn default() -> Self {
        Self {
            attack_ms: 1.0,    // 1ms default (prevents clicks)
            release_ms: 50.0,  // 50ms default
        }
    }
}

// ============================================================================
// SAMPLER VOICE
// ============================================================================

#[derive(Debug, Clone)]
struct SamplerVoice {
    note: u8,
    velocity: f32,
    playback_position: f64, // Frame position (sub-sample accuracy)
    playback_rate: f64,     // 1.0 = original pitch, 2.0 = octave up
    env_state: EnvelopeState,
    env_level: f32,
    env_time: f32,
    release_start_level: f32, // Level when release started (for smooth fade)
    is_active: bool,
}

impl SamplerVoice {
    fn new() -> Self {
        Self {
            note: 0,
            velocity: 0.0,
            playback_position: 0.0,
            playback_rate: 1.0,
            env_state: EnvelopeState::Idle,
            env_level: 0.0,
            env_time: 0.0,
            release_start_level: 0.0,
            is_active: false,
        }
    }

    fn note_on(&mut self, note: u8, velocity: u8, playback_rate: f64) {
        self.note = note;
        self.velocity = f32::from(velocity) / 127.0;
        self.playback_position = 0.0;
        self.playback_rate = playback_rate;
        self.env_state = EnvelopeState::Attack;
        self.env_level = 0.0;
        self.env_time = 0.0;
        self.release_start_level = 0.0;
        self.is_active = true;
    }

    fn note_off(&mut self) {
        if self.is_active && self.env_state != EnvelopeState::Release {
            self.release_start_level = self.env_level;
            self.env_state = EnvelopeState::Release;
            self.env_time = 0.0;
        }
    }

    fn process(
        &mut self,
        sample: &AudioClip,
        envelope: &SamplerEnvelope,
        sample_rate: f32,
    ) -> (f32, f32) {
        if !self.is_active {
            return (0.0, 0.0);
        }

        // Get sample with linear interpolation
        let frame_f = self.playback_position;
        let frame_i = frame_f as usize;
        let frac = (frame_f - frame_i as f64) as f32;

        let frame_count = sample.frame_count();

        // Check if sample ended
        if frame_i >= frame_count {
            // Sample finished - check envelope state
            if self.env_state == EnvelopeState::Release || self.env_state == EnvelopeState::Idle {
                self.is_active = false;
                return (0.0, 0.0);
            }
            // Still holding key but sample ended - start release
            self.release_start_level = self.env_level;
            self.env_state = EnvelopeState::Release;
            self.env_time = 0.0;
        }

        // Linear interpolation between samples
        let (left, right) = if frame_i < frame_count {
            let l0 = sample.get_sample(frame_i, 0).unwrap_or(0.0);
            let r0 = sample.get_sample(frame_i, 1).unwrap_or(l0);

            let l1 = sample.get_sample(frame_i + 1, 0).unwrap_or(l0);
            let r1 = sample.get_sample(frame_i + 1, 1).unwrap_or(r0);

            let left = l0 + (l1 - l0) * frac;
            let right = r0 + (r1 - r0) * frac;
            (left, right)
        } else {
            (0.0, 0.0)
        };

        // Advance playback position
        self.playback_position += self.playback_rate;

        // Process envelope
        let env_out = self.process_envelope(envelope, sample_rate);

        // Check if voice finished
        if self.env_state == EnvelopeState::Idle {
            self.is_active = false;
            return (0.0, 0.0);
        }

        (left * env_out * self.velocity, right * env_out * self.velocity)
    }

    fn process_envelope(&mut self, params: &SamplerEnvelope, sample_rate: f32) -> f32 {
        let time_step = 1.0 / sample_rate;
        let attack_secs = params.attack_ms / 1000.0;
        let release_secs = params.release_ms / 1000.0;

        match self.env_state {
            EnvelopeState::Idle => {
                self.env_level = 0.0;
            }
            EnvelopeState::Attack => {
                if attack_secs > 0.0 {
                    self.env_level = self.env_time / attack_secs;
                    if self.env_level >= 1.0 {
                        self.env_level = 1.0;
                        self.env_state = EnvelopeState::Sustain;
                        self.env_time = 0.0;
                    }
                } else {
                    self.env_level = 1.0;
                    self.env_state = EnvelopeState::Sustain;
                    self.env_time = 0.0;
                }
            }
            EnvelopeState::Sustain => {
                self.env_level = 1.0;
            }
            EnvelopeState::Release => {
                if release_secs > 0.0 {
                    let release_progress = self.env_time / release_secs;
                    self.env_level = self.release_start_level * (1.0 - release_progress);
                    if self.env_level <= 0.001 {
                        self.env_level = 0.0;
                        self.env_state = EnvelopeState::Idle;
                    }
                } else {
                    self.env_level = 0.0;
                    self.env_state = EnvelopeState::Idle;
                }
            }
        }

        self.env_time += time_step;
        self.env_level.max(0.0).min(1.0)
    }
}

// ============================================================================
// SAMPLER
// ============================================================================

pub struct Sampler {
    voices: Vec<SamplerVoice>,
    sample: Option<Arc<AudioClip>>,
    pub root_note: u8,      // MIDI note that plays sample at original pitch (default 60 = C4)
    pub envelope: SamplerEnvelope,
    sample_rate: f32,
}

impl Sampler {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            voices: (0..MAX_VOICES).map(|_| SamplerVoice::new()).collect(),
            sample: None,
            root_note: 60, // C4
            envelope: SamplerEnvelope::default(),
            sample_rate,
        }
    }

    /// Load a sample from an `AudioClip`
    pub fn load_sample(&mut self, clip: Arc<AudioClip>) {
        println!("🎹 Sampler: Loaded sample '{}' ({:.2}s, {} channels)",
            clip.file_path,
            clip.duration_seconds,
            clip.channels
        );
        self.sample = Some(clip);
    }

    /// Load sample and set root note
    pub fn load_sample_with_root(&mut self, clip: Arc<AudioClip>, root_note: u8) {
        self.load_sample(clip);
        self.root_note = root_note;
    }

    /// Get the loaded sample path (for serialization)
    pub fn sample_path(&self) -> Option<&str> {
        self.sample.as_ref().map(|s| s.file_path.as_str())
    }

    /// Check if a sample is loaded
    pub fn has_sample(&self) -> bool {
        self.sample.is_some()
    }

    pub fn note_on(&mut self, note: u8, velocity: u8) {
        if self.sample.is_none() {
            println!("⚠️ Sampler: No sample loaded, ignoring note_on");
            return;
        }

        // Calculate playback rate based on pitch difference from root note
        let playback_rate = Self::calculate_playback_rate(self.root_note, note);

        // Find free voice or steal oldest
        let idx = self.find_free_voice_index();
        self.voices[idx].note_on(note, velocity, playback_rate);
    }

    pub fn note_off(&mut self, note: u8) {
        for voice in &mut self.voices {
            if voice.is_active && voice.note == note {
                voice.note_off();
            }
        }
    }

    pub fn all_notes_off(&mut self) {
        for voice in &mut self.voices {
            voice.is_active = false;
            voice.env_state = EnvelopeState::Idle;
            voice.env_level = 0.0;
        }
    }

    /// Process one sample frame, returning stereo output (left, right)
    pub fn process_sample(&mut self) -> (f32, f32) {
        let Some(ref sample) = self.sample else {
            return (0.0, 0.0);
        };

        let mut left_out = 0.0;
        let mut right_out = 0.0;

        for voice in &mut self.voices {
            let (l, r) = voice.process(sample, &self.envelope, self.sample_rate);
            left_out += l;
            right_out += r;
        }

        // Reduce volume to prevent clipping with multiple voices
        (left_out * 0.4, right_out * 0.4)
    }

    /// Process and return mono (for compatibility with existing synth interface)
    pub fn process_sample_mono(&mut self) -> f32 {
        let (left, right) = self.process_sample();
        (left + right) * 0.5
    }

    pub fn set_parameter(&mut self, key: &str, value: &str) {
        println!("🎛️ Sampler set_parameter: {key}={value}");

        match key {
            "root_note" => {
                if let Ok(v) = value.parse::<u8>() {
                    self.root_note = v.clamp(0, 127);
                    println!("  → root_note = {} ({})", self.root_note, note_name(self.root_note));
                }
            }
            "attack" | "attack_ms" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.attack_ms = v.clamp(0.0, 5000.0);
                    println!("  → attack_ms = {}", self.envelope.attack_ms);
                }
            }
            "release" | "release_ms" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.release_ms = v.clamp(0.0, 5000.0);
                    println!("  → release_ms = {}", self.envelope.release_ms);
                }
            }
            _ => {
                println!("  ⚠️ Unknown sampler parameter: {key}");
            }
        }
    }

    fn find_free_voice_index(&self) -> usize {
        // Find inactive voice
        for (i, voice) in self.voices.iter().enumerate() {
            if !voice.is_active {
                return i;
            }
        }
        // All voices active - steal first one (simple voice stealing)
        0
    }

    pub fn active_voice_count(&self) -> usize {
        self.voices.iter().filter(|v| v.is_active).count()
    }

    /// Calculate playback rate for pitch shifting
    /// `root_note` = note that plays at original pitch
    /// `target_note` = note being triggered
    fn calculate_playback_rate(root_note: u8, target_note: u8) -> f64 {
        // Pitch ratio = 2^(semitones/12)
        let semitone_diff = f64::from(target_note) - f64::from(root_note);
        2.0_f64.powf(semitone_diff / 12.0)
    }
}

/// Convert MIDI note number to note name (e.g., 60 -> "C4")
fn note_name(note: u8) -> String {
    const NAMES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    let octave = (i32::from(note) / 12) - 1;
    let name = NAMES[(note % 12) as usize];
    format!("{name}{octave}")
}

// ============================================================================
// SERIALIZATION
// ============================================================================

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SamplerData {
    pub sample_path: String,
    pub root_note: u8,
    pub attack_ms: f32,
    pub release_ms: f32,
}

impl Sampler {
    /// Get sampler parameters for serialization
    pub fn get_parameters(&self) -> Option<SamplerData> {
        self.sample.as_ref().map(|s| SamplerData {
            sample_path: s.file_path.clone(),
            root_note: self.root_note,
            attack_ms: self.envelope.attack_ms,
            release_ms: self.envelope.release_ms,
        })
    }

    /// Restore sampler parameters from saved data (sample must be loaded separately)
    pub fn restore_parameters(&mut self, data: &SamplerData) {
        self.root_note = data.root_note;
        self.envelope.attack_ms = data.attack_ms;
        self.envelope.release_ms = data.release_ms;
        println!("✅ Restored sampler parameters: root={}, attack={}ms, release={}ms",
            note_name(self.root_note), data.attack_ms, data.release_ms);
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_playback_rate_calculation() {
        // Same note = 1.0
        assert!((Sampler::calculate_playback_rate(60, 60) - 1.0).abs() < 0.001);

        // Octave up = 2.0
        assert!((Sampler::calculate_playback_rate(60, 72) - 2.0).abs() < 0.001);

        // Octave down = 0.5
        assert!((Sampler::calculate_playback_rate(60, 48) - 0.5).abs() < 0.001);

        // Perfect fifth up ≈ 1.498
        let fifth_ratio = Sampler::calculate_playback_rate(60, 67);
        assert!((fifth_ratio - 1.498).abs() < 0.01);
    }

    #[test]
    fn test_note_name() {
        assert_eq!(note_name(60), "C4");
        assert_eq!(note_name(69), "A4");
        assert_eq!(note_name(0), "C-1");
        assert_eq!(note_name(127), "G9");
    }

    #[test]
    fn test_sampler_creation() {
        let sampler = Sampler::new(48000.0);
        assert!(!sampler.has_sample());
        assert_eq!(sampler.root_note, 60);
        assert_eq!(sampler.active_voice_count(), 0);
    }

    #[test]
    fn test_sampler_without_sample() {
        let mut sampler = Sampler::new(48000.0);
        // Should not crash when no sample loaded
        sampler.note_on(60, 100);
        let (left, right) = sampler.process_sample();
        assert_eq!(left, 0.0);
        assert_eq!(right, 0.0);
    }

    #[test]
    fn test_envelope_defaults() {
        let env = SamplerEnvelope::default();
        assert_eq!(env.attack_ms, 1.0);
        assert_eq!(env.release_ms, 50.0);
    }
}
