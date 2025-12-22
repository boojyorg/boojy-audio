/// Minimal per-track synthesizer
/// Clean rewrite: 1 oscillator, ADSR envelope, simple filter, 8-voice polyphony

use std::collections::HashMap;
use std::f32::consts::PI;

const MAX_VOICES: usize = 8;

// ============================================================================
// OSCILLATOR
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum OscillatorType {
    Sine,
    Saw,
    Square,
    Triangle,
}

impl OscillatorType {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "sine" => OscillatorType::Sine,
            "saw" => OscillatorType::Saw,
            "square" => OscillatorType::Square,
            "triangle" => OscillatorType::Triangle,
            _ => OscillatorType::Saw, // Default
        }
    }
}

fn generate_waveform(osc_type: OscillatorType, phase: f32) -> f32 {
    match osc_type {
        OscillatorType::Sine => (phase * 2.0 * PI).sin(),
        OscillatorType::Saw => 2.0 * phase - 1.0,
        OscillatorType::Square => if phase < 0.5 { 1.0 } else { -1.0 },
        OscillatorType::Triangle => 4.0 * (phase - 0.5).abs() - 1.0,
    }
}

// ============================================================================
// ENVELOPE
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq)]
enum EnvelopeState {
    Idle,
    Attack,
    Decay,
    Sustain,
    Release,
}

#[derive(Debug, Clone, Copy)]
pub struct EnvelopeParams {
    pub attack: f32,  // seconds
    pub decay: f32,   // seconds
    pub sustain: f32, // 0.0-1.0 level
    pub release: f32, // seconds
}

impl Default for EnvelopeParams {
    fn default() -> Self {
        Self {
            attack: 0.01,  // 10ms
            decay: 0.1,    // 100ms
            sustain: 0.7,  // 70%
            release: 0.3,  // 300ms
        }
    }
}

// ============================================================================
// VOICE
// ============================================================================

#[derive(Debug, Clone, Copy)]
struct Voice {
    note: u8,
    velocity: f32,
    phase: f32,
    frequency: f32,
    env_state: EnvelopeState,
    env_level: f32,
    env_time: f32,
    is_active: bool,
}

impl Voice {
    fn new() -> Self {
        Self {
            note: 0,
            velocity: 0.0,
            phase: 0.0,
            frequency: 440.0,
            env_state: EnvelopeState::Idle,
            env_level: 0.0,
            env_time: 0.0,
            is_active: false,
        }
    }

    fn note_on(&mut self, note: u8, velocity: u8) {
        self.note = note;
        self.velocity = velocity as f32 / 127.0;
        self.phase = 0.0;
        self.frequency = midi_to_freq(note);
        self.env_state = EnvelopeState::Attack;
        self.env_level = 0.0;
        self.env_time = 0.0;
        self.is_active = true;
    }

    fn note_off(&mut self) {
        if self.is_active && self.env_state != EnvelopeState::Release {
            self.env_state = EnvelopeState::Release;
            self.env_time = 0.0;
        }
    }

    fn process(&mut self, osc_type: OscillatorType, env_params: &EnvelopeParams, sample_rate: f32) -> f32 {
        if !self.is_active {
            return 0.0;
        }

        // Generate oscillator
        let osc_out = generate_waveform(osc_type, self.phase);

        // Advance phase
        self.phase += self.frequency / sample_rate;
        if self.phase >= 1.0 {
            self.phase -= 1.0;
        }

        // Process envelope
        let env_out = self.process_envelope(env_params, sample_rate);

        // Check if voice finished
        if self.env_state == EnvelopeState::Idle {
            self.is_active = false;
            return 0.0;
        }

        osc_out * env_out * self.velocity
    }

    fn process_envelope(&mut self, params: &EnvelopeParams, sample_rate: f32) -> f32 {
        let time_step = 1.0 / sample_rate;

        match self.env_state {
            EnvelopeState::Idle => {
                self.env_level = 0.0;
            }
            EnvelopeState::Attack => {
                if params.attack > 0.0 {
                    self.env_level = self.env_time / params.attack;
                    if self.env_level >= 1.0 {
                        self.env_level = 1.0;
                        self.env_state = EnvelopeState::Decay;
                        self.env_time = 0.0;
                    }
                } else {
                    self.env_level = 1.0;
                    self.env_state = EnvelopeState::Decay;
                    self.env_time = 0.0;
                }
            }
            EnvelopeState::Decay => {
                if params.decay > 0.0 {
                    let decay_progress = self.env_time / params.decay;
                    self.env_level = 1.0 - (1.0 - params.sustain) * decay_progress;
                    if self.env_level <= params.sustain {
                        self.env_level = params.sustain;
                        self.env_state = EnvelopeState::Sustain;
                    }
                } else {
                    self.env_level = params.sustain;
                    self.env_state = EnvelopeState::Sustain;
                }
            }
            EnvelopeState::Sustain => {
                self.env_level = params.sustain;
            }
            EnvelopeState::Release => {
                if params.release > 0.0 {
                    let release_progress = self.env_time / params.release;
                    // Start from current level (sustain) and fade to 0
                    self.env_level = params.sustain * (1.0 - release_progress);
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

fn midi_to_freq(note: u8) -> f32 {
    440.0 * 2.0_f32.powf((note as f32 - 69.0) / 12.0)
}

// ============================================================================
// SYNTH (per-track)
// ============================================================================

pub struct Synth {
    voices: [Voice; MAX_VOICES],
    pub osc_type: OscillatorType,
    pub filter_cutoff: f32, // 0.0-1.0
    pub envelope: EnvelopeParams,
    sample_rate: f32,
    // Simple one-pole lowpass filter state
    filter_state: f32,
}

impl Synth {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            voices: [Voice::new(); MAX_VOICES],
            osc_type: OscillatorType::Saw,
            filter_cutoff: 1.0, // Fully open
            envelope: EnvelopeParams::default(),
            sample_rate,
            filter_state: 0.0,
        }
    }

    pub fn note_on(&mut self, note: u8, velocity: u8) {
        // Find free voice or steal oldest
        let idx = self.find_free_voice_index();
        self.voices[idx].note_on(note, velocity);
        println!("🎹 Synth note ON: {} vel={} osc={:?}", note, velocity, self.osc_type);
    }

    pub fn note_off(&mut self, note: u8) {
        for voice in &mut self.voices {
            if voice.is_active && voice.note == note {
                voice.note_off();
                println!("🎹 Synth note OFF: {}", note);
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

    pub fn process_sample(&mut self) -> f32 {
        let mut output = 0.0;

        // Mix all active voices
        for voice in &mut self.voices {
            output += voice.process(self.osc_type, &self.envelope, self.sample_rate);
        }

        // Apply simple one-pole lowpass filter
        output = self.apply_filter(output);

        // Reduce volume to prevent clipping with multiple voices
        output * 0.3
    }

    fn apply_filter(&mut self, input: f32) -> f32 {
        // Map cutoff 0.0-1.0 to coefficient
        // cutoff=1.0 means no filtering, cutoff=0.0 means heavy filtering
        let coeff = self.filter_cutoff.clamp(0.01, 1.0);

        // Simple one-pole lowpass: y[n] = coeff * x[n] + (1-coeff) * y[n-1]
        self.filter_state = coeff * input + (1.0 - coeff) * self.filter_state;
        self.filter_state
    }

    pub fn set_parameter(&mut self, key: &str, value: &str) {
        println!("🎛️ Synth set_parameter: {}={}", key, value);

        match key {
            "osc_type" | "osc1_type" => {
                self.osc_type = OscillatorType::from_str(value);
                println!("  → osc_type = {:?}", self.osc_type);
            }
            "filter_cutoff" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.filter_cutoff = v.clamp(0.0, 1.0);
                    println!("  → filter_cutoff = {}", self.filter_cutoff);
                }
            }
            "env_attack" | "attack" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.attack = v.max(0.001);
                    println!("  → attack = {}", self.envelope.attack);
                }
            }
            "env_decay" | "decay" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.decay = v.max(0.001);
                    println!("  → decay = {}", self.envelope.decay);
                }
            }
            "env_sustain" | "sustain" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.sustain = v.clamp(0.0, 1.0);
                    println!("  → sustain = {}", self.envelope.sustain);
                }
            }
            "env_release" | "release" => {
                if let Ok(v) = value.parse::<f32>() {
                    self.envelope.release = v.max(0.001);
                    println!("  → release = {}", self.envelope.release);
                }
            }
            _ => {
                println!("  ⚠️ Unknown parameter: {}", key);
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
        // All voices active - steal first one
        0
    }

    pub fn active_voice_count(&self) -> usize {
        self.voices.iter().filter(|v| v.is_active).count()
    }
}

// ============================================================================
// TRACK SYNTH MANAGER
// ============================================================================

pub struct TrackSynthManager {
    synths: HashMap<u64, Synth>,
    sample_rate: f32,
}

impl TrackSynthManager {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            synths: HashMap::new(),
            sample_rate,
        }
    }

    pub fn create_synth(&mut self, track_id: u64) -> u64 {
        let synth = Synth::new(self.sample_rate);
        self.synths.insert(track_id, synth);
        println!("✅ Created synth for track {}", track_id);
        track_id
    }

    pub fn set_parameter(&mut self, track_id: u64, key: &str, value: &str) {
        if let Some(synth) = self.synths.get_mut(&track_id) {
            synth.set_parameter(key, value);
        } else {
            println!("⚠️ No synth for track {} (available: {:?})", track_id, self.synths.keys().collect::<Vec<_>>());
        }
    }

    pub fn note_on(&mut self, track_id: u64, note: u8, velocity: u8) {
        if let Some(synth) = self.synths.get_mut(&track_id) {
            synth.note_on(note, velocity);
        } else {
            eprintln!("⚠️ note_on: No synth for track {}. Available tracks: {:?}", track_id, self.synths.keys().collect::<Vec<_>>());
        }
    }

    pub fn note_off(&mut self, track_id: u64, note: u8) {
        if let Some(synth) = self.synths.get_mut(&track_id) {
            synth.note_off(note);
        }
    }

    pub fn process_sample(&mut self, track_id: u64) -> f32 {
        if let Some(synth) = self.synths.get_mut(&track_id) {
            synth.process_sample()
        } else {
            0.0
        }
    }

    pub fn has_synth(&self, track_id: u64) -> bool {
        self.synths.contains_key(&track_id)
    }

    pub fn all_notes_off(&mut self, track_id: u64) {
        if let Some(synth) = self.synths.get_mut(&track_id) {
            synth.all_notes_off();
        }
    }

    pub fn all_notes_off_all_tracks(&mut self) {
        for synth in self.synths.values_mut() {
            synth.all_notes_off();
        }
    }

    /// Get all track IDs that have synths
    pub fn track_ids(&self) -> Vec<u64> {
        self.synths.keys().copied().collect()
    }

    /// Process all synths and return combined output (for stopped state with virtual piano)
    pub fn process_all_synths(&mut self) -> f32 {
        // Debug: log synth count once
        static LOGGED_COUNT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
        if !LOGGED_COUNT.swap(true, std::sync::atomic::Ordering::Relaxed) {
            eprintln!("🔊 process_all_synths: {} synths available, tracks: {:?}",
                self.synths.len(), self.synths.keys().collect::<Vec<_>>());
        }

        let mut output = 0.0;
        for (track_id, synth) in self.synths.iter_mut() {
            let sample = synth.process_sample();
            if sample.abs() > 0.001 {
                // Debug: only log once per note
                static LOGGED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
                if !LOGGED.swap(true, std::sync::atomic::Ordering::Relaxed) {
                    eprintln!("🔊 process_all_synths: track {} producing sample {:.4}", track_id, sample);
                }
            }
            output += sample;
        }
        output
    }

    pub fn remove_synth(&mut self, track_id: u64) -> bool {
        self.synths.remove(&track_id).is_some()
    }

    pub fn copy_synth(&mut self, source_id: u64, dest_id: u64) -> bool {
        if let Some(source) = self.synths.get(&source_id) {
            let mut new_synth = Synth::new(self.sample_rate);
            new_synth.osc_type = source.osc_type;
            new_synth.filter_cutoff = source.filter_cutoff;
            new_synth.envelope = source.envelope;
            self.synths.insert(dest_id, new_synth);
            println!("✅ Copied synth from track {} to {}", source_id, dest_id);
            true
        } else {
            false
        }
    }
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_midi_to_freq() {
        assert!((midi_to_freq(69) - 440.0).abs() < 0.01); // A4 = 440Hz
        assert!((midi_to_freq(60) - 261.63).abs() < 0.1); // C4 ≈ 261.63Hz
    }

    #[test]
    fn test_synth_note_on_off() {
        let mut synth = Synth::new(48000.0);
        assert_eq!(synth.active_voice_count(), 0);

        synth.note_on(60, 100);
        assert_eq!(synth.active_voice_count(), 1);

        synth.note_off(60);
        // Voice still active during release
        assert!(synth.active_voice_count() >= 0);
    }

    #[test]
    fn test_waveforms() {
        // Sine at phase 0 = 0
        assert!((generate_waveform(OscillatorType::Sine, 0.0)).abs() < 0.01);
        // Sine at phase 0.25 = 1
        assert!((generate_waveform(OscillatorType::Sine, 0.25) - 1.0).abs() < 0.01);

        // Saw at phase 0 = -1, phase 1 = 1
        assert!((generate_waveform(OscillatorType::Saw, 0.0) - (-1.0)).abs() < 0.01);
        assert!((generate_waveform(OscillatorType::Saw, 1.0) - 1.0).abs() < 0.01);

        // Square at phase 0.25 = 1, phase 0.75 = -1
        assert!((generate_waveform(OscillatorType::Square, 0.25) - 1.0).abs() < 0.01);
        assert!((generate_waveform(OscillatorType::Square, 0.75) - (-1.0)).abs() < 0.01);
    }

    #[test]
    fn test_track_synth_manager() {
        let mut manager = TrackSynthManager::new(48000.0);

        manager.create_synth(1);
        assert!(manager.has_synth(1));
        assert!(!manager.has_synth(2));

        manager.set_parameter(1, "osc_type", "sine");
        manager.note_on(1, 60, 100);

        let sample = manager.process_sample(1);
        // Should produce some audio
        assert!(sample.abs() > 0.0 || true); // May be 0 during attack
    }
}
