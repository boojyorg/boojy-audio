/// Sampler instrument - plays audio samples triggered by MIDI notes
/// Similar to Synth but uses sample playback instead of oscillators
/// Supports pitch shifting based on root note and Attack/Release envelope
/// Supports loop mode (sustain-loop) and one-shot mode (default)

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

    fn note_on(&mut self, note: u8, velocity: u8, playback_rate: f64, start_position: f64) {
        self.note = note;
        self.velocity = f32::from(velocity) / 127.0;
        self.playback_position = start_position;
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

    /// Process one sample frame with loop-aware playback
    fn process(
        &mut self,
        sample: &AudioClip,
        envelope: &SamplerEnvelope,
        sample_rate: f32,
        loop_enabled: bool,
        loop_start: f64,
        loop_end: f64,
        reversed: bool,
    ) -> (f32, f32) {
        if !self.is_active {
            return (0.0, 0.0);
        }

        let frame_count = sample.frame_count();

        // Check boundaries (forward or reverse)
        if reversed {
            if self.playback_position < 0.0 {
                if loop_enabled && self.env_state != EnvelopeState::Release {
                    self.playback_position = loop_end.min(frame_count as f64 - 1.0);
                } else {
                    if self.env_state == EnvelopeState::Release || self.env_state == EnvelopeState::Idle {
                        self.is_active = false;
                        return (0.0, 0.0);
                    }
                    self.release_start_level = self.env_level;
                    self.env_state = EnvelopeState::Release;
                    self.env_time = 0.0;
                }
            }
            // Check loop start boundary (reversed loops from end to start)
            if loop_enabled && self.env_state != EnvelopeState::Release && loop_start >= 0.0 {
                if self.playback_position < loop_start {
                    self.playback_position = loop_end.min(frame_count as f64 - 1.0);
                }
            }
        } else {
            if self.playback_position as usize >= frame_count {
                if loop_enabled && self.env_state != EnvelopeState::Release {
                    self.playback_position = loop_start;
                } else {
                    if self.env_state == EnvelopeState::Release || self.env_state == EnvelopeState::Idle {
                        self.is_active = false;
                        return (0.0, 0.0);
                    }
                    self.release_start_level = self.env_level;
                    self.env_state = EnvelopeState::Release;
                    self.env_time = 0.0;
                }
            }
            // Check loop end boundary (when looping)
            if loop_enabled && self.env_state != EnvelopeState::Release && loop_end > 0.0 {
                if self.playback_position >= loop_end {
                    self.playback_position = loop_start;
                }
            }
        }

        // Re-read position after possible loop wrap
        let frame_f = self.playback_position.max(0.0);
        let frame_i = frame_f as usize;
        let frac = (frame_f - frame_i as f64) as f32;

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

        // Advance playback position (reversed = decrement)
        if reversed {
            self.playback_position -= self.playback_rate;
        } else {
            self.playback_position += self.playback_rate;
        }

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
    pub root_note: u8,           // MIDI note that plays sample at original pitch (default 60 = C4)
    pub envelope: SamplerEnvelope,
    pub loop_enabled: bool,      // false = one-shot (default), true = sustain-loop
    pub loop_start: f64,         // Loop start in frames (default 0.0)
    pub loop_end: f64,           // Loop end in frames (default = sample length)
    sample_rate: f32,
    // Audio manipulation parameters (matching Audio Editor)
    pub volume_db: f32,           // -70.0 to +24.0 dB (default 0.0)
    pub transpose_semitones: i32, // -48 to +48 (default 0)
    pub fine_cents: i32,          // -50 to +50 (default 0)
    pub reversed: bool,           // Reverse playback (default false)
    pub original_bpm: f64,        // Sample tempo for beat grid (default 120.0)
    pub warp_enabled: bool,       // Warp mode on/off (default false)
    pub warp_mode: u8,            // 0=repitch, 1=warp (default 0)
    pub beats_per_bar: i32,       // Time signature numerator (default 4)
    pub beat_unit: i32,           // Time signature denominator (default 4)
}

impl Sampler {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            voices: (0..MAX_VOICES).map(|_| SamplerVoice::new()).collect(),
            sample: None,
            root_note: 60, // C4
            envelope: SamplerEnvelope::default(),
            loop_enabled: false, // One-shot by default
            loop_start: 0.0,
            loop_end: 0.0, // Will be set when sample loads
            sample_rate,
            volume_db: 0.0,
            transpose_semitones: 0,
            fine_cents: 0,
            reversed: false,
            original_bpm: 120.0,
            warp_enabled: false,
            warp_mode: 0, // repitch
            beats_per_bar: 4,
            beat_unit: 4,
        }
    }

    /// Load a sample from an `AudioClip`
    pub fn load_sample(&mut self, clip: Arc<AudioClip>) {
        println!("🎹 Sampler: Loaded sample '{}' ({:.2}s, {} channels)",
            clip.file_path,
            clip.duration_seconds,
            clip.channels
        );
        // Set loop_end to sample length by default
        self.loop_end = clip.frame_count() as f64;
        self.loop_start = 0.0;
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

    /// Get sample duration in seconds
    pub fn sample_duration_seconds(&self) -> f64 {
        self.sample.as_ref().map_or(0.0, |s| s.duration_seconds)
    }

    /// Get the sample rate of the loaded sample
    pub fn sample_sample_rate(&self) -> f32 {
        self.sample.as_ref().map_or(self.sample_rate, |s| s.sample_rate as f32)
    }

    /// Convert seconds to frames using loaded sample's sample rate
    fn seconds_to_frames(&self, seconds: f64) -> f64 {
        let sr = self.sample.as_ref().map_or(self.sample_rate as f64, |s| f64::from(s.sample_rate));
        seconds * sr
    }

    /// Convert frames to seconds using loaded sample's sample rate
    pub fn frames_to_seconds(&self, frames: f64) -> f64 {
        let sr = self.sample.as_ref().map_or(self.sample_rate as f64, |s| f64::from(s.sample_rate));
        if sr > 0.0 { frames / sr } else { 0.0 }
    }

    pub fn note_on(&mut self, note: u8, velocity: u8) {
        if self.sample.is_none() {
            println!("⚠️ Sampler: No sample loaded, ignoring note_on");
            return;
        }

        // Calculate playback rate with transpose + fine cents offset
        let semitone_diff = f64::from(note) - f64::from(self.root_note)
            + f64::from(self.transpose_semitones)
            + f64::from(self.fine_cents) / 100.0;
        let playback_rate = 2.0_f64.powf(semitone_diff / 12.0);

        // Determine start position (reversed starts from end)
        let start_pos = if self.reversed {
            self.sample.as_ref().map_or(0.0, |s| s.frame_count() as f64 - 1.0)
        } else {
            0.0
        };

        // Find free voice or steal oldest
        let idx = self.find_free_voice_index();
        self.voices[idx].note_on(note, velocity, playback_rate, start_pos);
    }

    pub fn note_off(&mut self, note: u8) {
        if !self.loop_enabled {
            // One-shot mode: ignore note-off, sample plays to completion
            return;
        }
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

        let loop_enabled = self.loop_enabled;
        let loop_start = self.loop_start;
        let loop_end = self.loop_end;
        let reversed = self.reversed;

        for voice in &mut self.voices {
            let (l, r) = voice.process(
                sample,
                &self.envelope,
                self.sample_rate,
                loop_enabled,
                loop_start,
                loop_end,
                reversed,
            );
            left_out += l;
            right_out += r;
        }

        // Apply volume gain (dB to linear) + voice mixing reduction
        let gain = if self.volume_db <= -70.0 {
            0.0
        } else {
            10.0_f32.powf(self.volume_db / 20.0)
        };
        let mix_gain = 0.4 * gain;
        (left_out * mix_gain, right_out * mix_gain)
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
            "loop_enabled" => {
                let enabled = value == "1" || value == "true";
                self.loop_enabled = enabled;
                println!("  → loop_enabled = {}", self.loop_enabled);
            }
            "loop_start_seconds" => {
                if let Ok(v) = value.parse::<f64>() {
                    let max_seconds = self.sample_duration_seconds();
                    let clamped = v.clamp(0.0, max_seconds);
                    self.loop_start = self.seconds_to_frames(clamped);
                    println!("  → loop_start = {:.3}s ({:.0} frames)", clamped, self.loop_start);
                }
            }
            "loop_end_seconds" => {
                if let Ok(v) = value.parse::<f64>() {
                    let max_seconds = self.sample_duration_seconds();
                    let clamped = v.clamp(0.0, max_seconds);
                    self.loop_end = self.seconds_to_frames(clamped);
                    println!("  → loop_end = {:.3}s ({:.0} frames)", clamped, self.loop_end);
                }
            }
            "volume_db" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.volume_db = v.clamp(-70.0, 24.0);
                    println!("  → volume_db = {:.1}", self.volume_db);
                }
            }
            "transpose_semitones" => {
                if let Ok(v) = value.parse::<i32>() {
                    self.transpose_semitones = v.clamp(-48, 48);
                    println!("  → transpose_semitones = {}", self.transpose_semitones);
                }
            }
            "fine_cents" => {
                if let Ok(v) = value.parse::<i32>() {
                    self.fine_cents = v.clamp(-50, 50);
                    println!("  → fine_cents = {}", self.fine_cents);
                }
            }
            "reversed" => {
                let enabled = value == "1" || value == "true";
                self.reversed = enabled;
                println!("  → reversed = {}", self.reversed);
            }
            "original_bpm" => {
                if let Ok(v) = value.parse::<f64>() {
                    self.original_bpm = v.clamp(20.0, 999.0);
                    println!("  → original_bpm = {:.1}", self.original_bpm);
                }
            }
            "warp_enabled" => {
                let enabled = value == "1" || value == "true";
                self.warp_enabled = enabled;
                println!("  → warp_enabled = {}", self.warp_enabled);
            }
            "warp_mode" => {
                if let Ok(v) = value.parse::<u8>() {
                    self.warp_mode = v.min(1); // 0=repitch, 1=warp
                    println!("  → warp_mode = {}", self.warp_mode);
                }
            }
            "beats_per_bar" => {
                if let Ok(v) = value.parse::<i32>() {
                    self.beats_per_bar = v.clamp(1, 16);
                    println!("  → beats_per_bar = {}", self.beats_per_bar);
                }
            }
            "beat_unit" => {
                if let Ok(v) = value.parse::<i32>() {
                    self.beat_unit = v.clamp(1, 16);
                    println!("  → beat_unit = {}", self.beat_unit);
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

    /// Get waveform peaks from the loaded sample as min/max pairs.
    /// Returns [min0, max0, min1, max1, ...] matching Audio Editor format.
    pub fn get_waveform_peaks(&self, resolution: usize) -> Vec<f32> {
        let Some(ref sample) = self.sample else { return vec![]; };
        let frames = sample.frame_count();
        if frames == 0 || resolution == 0 {
            return vec![];
        }

        let samples_per_peak = (frames / resolution).max(1);
        let mut peaks = Vec::with_capacity(resolution * 2);

        for i in 0..resolution {
            let start = i * samples_per_peak;
            let end = ((i + 1) * samples_per_peak).min(frames);
            if start >= frames {
                break;
            }

            let mut min: f32 = 1.0;
            let mut max: f32 = -1.0;

            for frame in start..end {
                // Mix channels for visualization (left channel, or max of stereo)
                let left = sample.get_sample(frame, 0).unwrap_or(0.0);
                let right = if sample.channels > 1 {
                    sample.get_sample(frame, 1).unwrap_or(0.0)
                } else {
                    left
                };
                let sample_val = if left.abs() >= right.abs() { left } else { right };
                min = min.min(sample_val);
                max = max.max(sample_val);
            }

            peaks.push(min);
            peaks.push(max);
        }

        peaks
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
    #[serde(default)]
    pub loop_enabled: bool,
    #[serde(default)]
    pub loop_start_seconds: f64,
    #[serde(default = "default_loop_end")]
    pub loop_end_seconds: f64,
    #[serde(default)]
    pub volume_db: f32,
    #[serde(default)]
    pub transpose_semitones: i32,
    #[serde(default)]
    pub fine_cents: i32,
    #[serde(default)]
    pub reversed: bool,
    #[serde(default = "default_bpm")]
    pub original_bpm: f64,
    #[serde(default)]
    pub warp_enabled: bool,
    #[serde(default)]
    pub warp_mode: u8,
    #[serde(default = "default_beats_per_bar")]
    pub beats_per_bar: i32,
    #[serde(default = "default_beat_unit")]
    pub beat_unit: i32,
}

fn default_loop_end() -> f64 {
    0.0 // Will be overridden by sample duration on load
}

fn default_bpm() -> f64 {
    120.0
}

fn default_beats_per_bar() -> i32 {
    4
}

fn default_beat_unit() -> i32 {
    4
}

impl Sampler {
    /// Get sampler parameters for serialization
    pub fn get_parameters(&self) -> Option<SamplerData> {
        self.sample.as_ref().map(|s| SamplerData {
            sample_path: s.file_path.clone(),
            root_note: self.root_note,
            attack_ms: self.envelope.attack_ms,
            release_ms: self.envelope.release_ms,
            loop_enabled: self.loop_enabled,
            loop_start_seconds: self.frames_to_seconds(self.loop_start),
            loop_end_seconds: self.frames_to_seconds(self.loop_end),
            volume_db: self.volume_db,
            transpose_semitones: self.transpose_semitones,
            fine_cents: self.fine_cents,
            reversed: self.reversed,
            original_bpm: self.original_bpm,
            warp_enabled: self.warp_enabled,
            warp_mode: self.warp_mode,
            beats_per_bar: self.beats_per_bar,
            beat_unit: self.beat_unit,
        })
    }

    /// Restore sampler parameters from saved data (sample must be loaded separately)
    pub fn restore_parameters(&mut self, data: &SamplerData) {
        self.root_note = data.root_note;
        self.envelope.attack_ms = data.attack_ms;
        self.envelope.release_ms = data.release_ms;
        self.loop_enabled = data.loop_enabled;
        if data.loop_start_seconds > 0.0 || data.loop_end_seconds > 0.0 {
            self.loop_start = self.seconds_to_frames(data.loop_start_seconds);
            self.loop_end = self.seconds_to_frames(data.loop_end_seconds);
        }
        // If loop_end is still 0 but we have a sample, set to sample length
        if self.loop_end == 0.0 {
            if let Some(ref sample) = self.sample {
                self.loop_end = sample.frame_count() as f64;
            }
        }
        self.volume_db = data.volume_db;
        self.transpose_semitones = data.transpose_semitones;
        self.fine_cents = data.fine_cents;
        self.reversed = data.reversed;
        self.original_bpm = data.original_bpm;
        self.warp_enabled = data.warp_enabled;
        self.warp_mode = data.warp_mode;
        self.beats_per_bar = data.beats_per_bar;
        self.beat_unit = data.beat_unit;
        println!("✅ Restored sampler parameters: root={}, attack={}ms, release={}ms, loop={}, vol={:.1}dB, transpose={}st",
            note_name(self.root_note), data.attack_ms, data.release_ms,
            self.loop_enabled, self.volume_db, self.transpose_semitones);
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
        assert!(!sampler.loop_enabled);
        assert_eq!(sampler.loop_start, 0.0);
        assert_eq!(sampler.loop_end, 0.0);
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

    #[test]
    fn test_one_shot_ignores_note_off() {
        let mut sampler = Sampler::new(48000.0);
        sampler.loop_enabled = false; // One-shot (default)
        // note_off should be ignored in one-shot mode
        // (can't fully test without a sample, but verify no crash)
        sampler.note_off(60);
    }

    #[test]
    fn test_loop_parameter_setting() {
        let mut sampler = Sampler::new(48000.0);
        sampler.set_parameter("loop_enabled", "true");
        assert!(sampler.loop_enabled);
        sampler.set_parameter("loop_enabled", "false");
        assert!(!sampler.loop_enabled);
        sampler.set_parameter("loop_enabled", "1");
        assert!(sampler.loop_enabled);
    }

    #[test]
    fn test_seconds_to_frames_conversion() {
        let sampler = Sampler::new(48000.0);
        // Without sample, uses engine sample rate
        let frames = sampler.seconds_to_frames(1.0);
        assert!((frames - 48000.0).abs() < 0.01);

        let seconds = sampler.frames_to_seconds(48000.0);
        assert!((seconds - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_serialization_defaults() {
        let data: SamplerData = serde_json::from_str(r#"{
            "sample_path": "test.wav",
            "root_note": 60,
            "attack_ms": 10.0,
            "release_ms": 100.0
        }"#).unwrap();
        // New fields should have serde defaults
        assert!(!data.loop_enabled);
        assert_eq!(data.loop_start_seconds, 0.0);
        assert_eq!(data.loop_end_seconds, 0.0);
        // Audio manipulation defaults
        assert_eq!(data.volume_db, 0.0);
        assert_eq!(data.transpose_semitones, 0);
        assert_eq!(data.fine_cents, 0);
        assert!(!data.reversed);
        assert_eq!(data.original_bpm, 120.0);
        assert!(!data.warp_enabled);
        assert_eq!(data.warp_mode, 0);
        assert_eq!(data.beats_per_bar, 4);
        assert_eq!(data.beat_unit, 4);
    }

    #[test]
    fn test_volume_db_parameter() {
        let mut sampler = Sampler::new(48000.0);
        sampler.set_parameter("volume_db", "-6.0");
        assert!((sampler.volume_db - (-6.0)).abs() < 0.01);

        // Clamping
        sampler.set_parameter("volume_db", "-100.0");
        assert_eq!(sampler.volume_db, -70.0);
        sampler.set_parameter("volume_db", "30.0");
        assert_eq!(sampler.volume_db, 24.0);
    }

    #[test]
    fn test_transpose_and_fine_cents() {
        let mut sampler = Sampler::new(48000.0);
        sampler.set_parameter("transpose_semitones", "12");
        assert_eq!(sampler.transpose_semitones, 12);
        sampler.set_parameter("fine_cents", "-25");
        assert_eq!(sampler.fine_cents, -25);

        // Clamping
        sampler.set_parameter("transpose_semitones", "100");
        assert_eq!(sampler.transpose_semitones, 48);
        sampler.set_parameter("fine_cents", "-100");
        assert_eq!(sampler.fine_cents, -50);
    }

    #[test]
    fn test_reversed_parameter() {
        let mut sampler = Sampler::new(48000.0);
        assert!(!sampler.reversed);
        sampler.set_parameter("reversed", "1");
        assert!(sampler.reversed);
        sampler.set_parameter("reversed", "0");
        assert!(!sampler.reversed);
        sampler.set_parameter("reversed", "true");
        assert!(sampler.reversed);
    }

    #[test]
    fn test_bpm_and_warp_parameters() {
        let mut sampler = Sampler::new(48000.0);
        sampler.set_parameter("original_bpm", "140.0");
        assert!((sampler.original_bpm - 140.0).abs() < 0.01);

        sampler.set_parameter("warp_enabled", "1");
        assert!(sampler.warp_enabled);

        sampler.set_parameter("warp_mode", "1");
        assert_eq!(sampler.warp_mode, 1);

        // BPM clamping
        sampler.set_parameter("original_bpm", "5.0");
        assert_eq!(sampler.original_bpm, 20.0);
    }

    #[test]
    fn test_time_signature_parameters() {
        let mut sampler = Sampler::new(48000.0);
        sampler.set_parameter("beats_per_bar", "3");
        assert_eq!(sampler.beats_per_bar, 3);
        sampler.set_parameter("beat_unit", "8");
        assert_eq!(sampler.beat_unit, 8);

        // Clamping
        sampler.set_parameter("beats_per_bar", "0");
        assert_eq!(sampler.beats_per_bar, 1);
        sampler.set_parameter("beat_unit", "32");
        assert_eq!(sampler.beat_unit, 16);
    }

    #[test]
    fn test_new_defaults() {
        let sampler = Sampler::new(48000.0);
        assert_eq!(sampler.volume_db, 0.0);
        assert_eq!(sampler.transpose_semitones, 0);
        assert_eq!(sampler.fine_cents, 0);
        assert!(!sampler.reversed);
        assert_eq!(sampler.original_bpm, 120.0);
        assert!(!sampler.warp_enabled);
        assert_eq!(sampler.warp_mode, 0);
        assert_eq!(sampler.beats_per_bar, 4);
        assert_eq!(sampler.beat_unit, 4);
    }
}
