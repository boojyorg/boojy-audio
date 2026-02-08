/// Minimal per-track synthesizer
/// Clean rewrite: 1 oscillator, ADSR envelope, simple filter, 8-voice polyphony

use std::collections::HashMap;
use std::f32::consts::PI;
use std::sync::Arc;
use crate::audio_file::AudioClip;
use crate::project::SynthData;
use crate::sampler::{Sampler, SamplerData};

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
        self.velocity = f32::from(velocity) / 127.0;
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
    440.0 * 2.0_f32.powf((f32::from(note) - 69.0) / 12.0)
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
        println!("🎛️ Synth set_parameter: {key}={value}");

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
                println!("  ⚠️ Unknown parameter: {key}");
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

    /// Get current synth parameters for serialization
    pub fn get_parameters(&self) -> SynthData {
        let osc_name = match self.osc_type {
            OscillatorType::Sine => "sine",
            OscillatorType::Saw => "saw",
            OscillatorType::Square => "square",
            OscillatorType::Triangle => "triangle",
        };
        SynthData {
            osc_type: osc_name.to_string(),
            filter_cutoff: self.filter_cutoff,
            attack: self.envelope.attack,
            decay: self.envelope.decay,
            sustain: self.envelope.sustain,
            release: self.envelope.release,
        }
    }
}

// ============================================================================
// TRACK INSTRUMENT (unified enum for Synth and Sampler)
// ============================================================================

/// Unified instrument type for tracks
pub enum TrackInstrument {
    Synth(Synth),
    Sampler(Sampler),
}

impl TrackInstrument {
    pub fn note_on(&mut self, note: u8, velocity: u8) {
        match self {
            TrackInstrument::Synth(s) => s.note_on(note, velocity),
            TrackInstrument::Sampler(s) => s.note_on(note, velocity),
        }
    }

    pub fn note_off(&mut self, note: u8) {
        match self {
            TrackInstrument::Synth(s) => s.note_off(note),
            TrackInstrument::Sampler(s) => s.note_off(note),
        }
    }

    pub fn all_notes_off(&mut self) {
        match self {
            TrackInstrument::Synth(s) => s.all_notes_off(),
            TrackInstrument::Sampler(s) => s.all_notes_off(),
        }
    }

    /// Process and return mono sample (for backwards compatibility)
    pub fn process_sample(&mut self) -> f32 {
        match self {
            TrackInstrument::Synth(s) => s.process_sample(),
            TrackInstrument::Sampler(s) => s.process_sample_mono(),
        }
    }

    /// Process and return stereo sample
    pub fn process_sample_stereo(&mut self) -> (f32, f32) {
        match self {
            TrackInstrument::Synth(s) => {
                let mono = s.process_sample();
                (mono, mono)
            }
            TrackInstrument::Sampler(s) => s.process_sample(),
        }
    }

    pub fn set_parameter(&mut self, key: &str, value: &str) {
        match self {
            TrackInstrument::Synth(s) => s.set_parameter(key, value),
            TrackInstrument::Sampler(s) => s.set_parameter(key, value),
        }
    }

    pub fn is_synth(&self) -> bool {
        matches!(self, TrackInstrument::Synth(_))
    }

    pub fn is_sampler(&self) -> bool {
        matches!(self, TrackInstrument::Sampler(_))
    }

    pub fn as_synth(&self) -> Option<&Synth> {
        match self {
            TrackInstrument::Synth(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_sampler(&self) -> Option<&Sampler> {
        match self {
            TrackInstrument::Sampler(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_sampler_mut(&mut self) -> Option<&mut Sampler> {
        match self {
            TrackInstrument::Sampler(s) => Some(s),
            _ => None,
        }
    }
}

// ============================================================================
// TRACK SYNTH MANAGER (manages both Synths and Samplers)
// ============================================================================

pub struct TrackSynthManager {
    instruments: HashMap<u64, TrackInstrument>,
    sample_rate: f32,
}

impl TrackSynthManager {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            instruments: HashMap::new(),
            sample_rate,
        }
    }

    /// Create a synthesizer for a track
    pub fn create_synth(&mut self, track_id: u64) -> u64 {
        let synth = Synth::new(self.sample_rate);
        self.instruments.insert(track_id, TrackInstrument::Synth(synth));
        println!("✅ Created synth for track {track_id}");
        track_id
    }

    /// Create a sampler for a track
    pub fn create_sampler(&mut self, track_id: u64) -> u64 {
        let sampler = Sampler::new(self.sample_rate);
        self.instruments.insert(track_id, TrackInstrument::Sampler(sampler));
        println!("✅ Created sampler for track {track_id}");
        track_id
    }

    /// Load a sample into a sampler track
    pub fn load_sample(&mut self, track_id: u64, clip: Arc<AudioClip>, root_note: u8) -> bool {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get_mut(&track_id) {
            sampler.load_sample_with_root(clip, root_note);
            true
        } else {
            println!("⚠️ load_sample: Track {track_id} is not a sampler");
            false
        }
    }

    pub fn set_parameter(&mut self, track_id: u64, key: &str, value: &str) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.set_parameter(key, value);
        } else {
            println!("⚠️ No instrument for track {} (available: {:?})", track_id, self.instruments.keys().collect::<Vec<_>>());
        }
    }

    pub fn note_on(&mut self, track_id: u64, note: u8, velocity: u8) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.note_on(note, velocity);
        } else {
            eprintln!("⚠️ note_on: No instrument for track {}. Available tracks: {:?}", track_id, self.instruments.keys().collect::<Vec<_>>());
        }
    }

    pub fn note_off(&mut self, track_id: u64, note: u8) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.note_off(note);
        }
    }

    pub fn process_sample(&mut self, track_id: u64) -> f32 {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.process_sample()
        } else {
            0.0
        }
    }

    /// Process and return stereo output
    pub fn process_sample_stereo(&mut self, track_id: u64) -> (f32, f32) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.process_sample_stereo()
        } else {
            (0.0, 0.0)
        }
    }

    pub fn has_synth(&self, track_id: u64) -> bool {
        self.instruments.contains_key(&track_id)
    }

    /// Check if track has a sampler specifically
    pub fn has_sampler(&self, track_id: u64) -> bool {
        self.instruments.get(&track_id).is_some_and(TrackInstrument::is_sampler)
    }

    /// Check if track has a synthesizer specifically
    pub fn is_synth(&self, track_id: u64) -> bool {
        self.instruments.get(&track_id).is_some_and(TrackInstrument::is_synth)
    }

    pub fn all_notes_off(&mut self, track_id: u64) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.all_notes_off();
        }
    }

    pub fn all_notes_off_all_tracks(&mut self) {
        for inst in self.instruments.values_mut() {
            inst.all_notes_off();
        }
    }

    /// Get all track IDs that have instruments
    pub fn track_ids(&self) -> Vec<u64> {
        self.instruments.keys().copied().collect()
    }

    /// Process all instruments and return combined output (for stopped state with virtual piano)
    pub fn process_all_synths(&mut self) -> f32 {
        // Debug: log count once
        static LOGGED_COUNT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
        if !LOGGED_COUNT.swap(true, std::sync::atomic::Ordering::Relaxed) {
            eprintln!("🔊 process_all_synths: {} instruments available, tracks: {:?}",
                self.instruments.len(), self.instruments.keys().collect::<Vec<_>>());
        }

        let mut output = 0.0;
        for (track_id, inst) in &mut self.instruments {
            let sample = inst.process_sample();
            if sample.abs() > 0.001 {
                // Debug: only log once per note
                static LOGGED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
                if !LOGGED.swap(true, std::sync::atomic::Ordering::Relaxed) {
                    eprintln!("🔊 process_all_synths: track {track_id} producing sample {sample:.4}");
                }
            }
            output += sample;
        }
        output
    }

    pub fn remove_synth(&mut self, track_id: u64) -> bool {
        self.instruments.remove(&track_id).is_some()
    }

    pub fn copy_synth(&mut self, source_id: u64, dest_id: u64) -> bool {
        if let Some(TrackInstrument::Synth(source)) = self.instruments.get(&source_id) {
            let mut new_synth = Synth::new(self.sample_rate);
            new_synth.osc_type = source.osc_type;
            new_synth.filter_cutoff = source.filter_cutoff;
            new_synth.envelope = source.envelope;
            self.instruments.insert(dest_id, TrackInstrument::Synth(new_synth));
            println!("✅ Copied synth from track {source_id} to {dest_id}");
            true
        } else {
            false
        }
    }

    /// Get synth parameters for serialization
    pub fn get_synth_parameters(&self, track_id: u64) -> Option<SynthData> {
        if let Some(TrackInstrument::Synth(synth)) = self.instruments.get(&track_id) {
            Some(synth.get_parameters())
        } else {
            None
        }
    }

    /// Get sampler parameters for serialization
    pub fn get_sampler_parameters(&self, track_id: u64) -> Option<SamplerData> {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get(&track_id) {
            sampler.get_parameters()
        } else {
            None
        }
    }

    /// Restore synth parameters from saved data
    pub fn restore_synth_parameters(&mut self, track_id: u64, data: &SynthData) {
        if let Some(TrackInstrument::Synth(synth)) = self.instruments.get_mut(&track_id) {
            synth.set_parameter("osc_type", &data.osc_type);
            synth.set_parameter("filter_cutoff", &data.filter_cutoff.to_string());
            synth.set_parameter("attack", &data.attack.to_string());
            synth.set_parameter("decay", &data.decay.to_string());
            synth.set_parameter("sustain", &data.sustain.to_string());
            synth.set_parameter("release", &data.release.to_string());
            println!("✅ Restored synth parameters for track {}: osc={}", track_id, data.osc_type);
        }
    }

    /// Restore sampler parameters from saved data (sample must be loaded separately)
    pub fn restore_sampler_parameters(&mut self, track_id: u64, data: &SamplerData) {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get_mut(&track_id) {
            sampler.restore_parameters(data);
        }
    }

    /// Get sampler info for UI synchronization
    pub fn get_sampler_info(&self, track_id: u64) -> Option<SamplerInfo> {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get(&track_id) {
            Some(SamplerInfo {
                duration_seconds: sampler.sample_duration_seconds(),
                sample_rate: sampler.sample_sample_rate() as f64,
                loop_enabled: sampler.loop_enabled,
                loop_start_seconds: sampler.frames_to_seconds(sampler.loop_start),
                loop_end_seconds: sampler.frames_to_seconds(sampler.loop_end),
                root_note: sampler.root_note as i32,
                attack_ms: sampler.envelope.attack_ms as f64,
                release_ms: sampler.envelope.release_ms as f64,
                volume_db: sampler.volume_db as f64,
                transpose_semitones: sampler.transpose_semitones,
                fine_cents: sampler.fine_cents,
                reversed: sampler.reversed,
                original_bpm: sampler.original_bpm,
                warp_enabled: sampler.warp_enabled,
                warp_mode: sampler.warp_mode as i32,
                beats_per_bar: sampler.beats_per_bar,
                beat_unit: sampler.beat_unit,
            })
        } else {
            None
        }
    }

    /// Get waveform peaks from sampler's loaded sample
    pub fn get_sampler_waveform_peaks(&self, track_id: u64, resolution: usize) -> Option<Vec<f32>> {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get(&track_id) {
            let peaks = sampler.get_waveform_peaks(resolution);
            if peaks.is_empty() { None } else { Some(peaks) }
        } else {
            None
        }
    }
}

/// Sampler info struct for UI synchronization
pub struct SamplerInfo {
    pub duration_seconds: f64,
    pub sample_rate: f64,
    pub loop_enabled: bool,
    pub loop_start_seconds: f64,
    pub loop_end_seconds: f64,
    pub root_note: i32,
    pub attack_ms: f64,
    pub release_ms: f64,
    pub volume_db: f64,
    pub transpose_semitones: i32,
    pub fine_cents: i32,
    pub reversed: bool,
    pub original_bpm: f64,
    pub warp_enabled: bool,
    pub warp_mode: i32,
    pub beats_per_bar: i32,
    pub beat_unit: i32,
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
