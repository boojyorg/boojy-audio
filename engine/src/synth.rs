use crate::audio_file::AudioClip;
use crate::drum_kit::{DrumKit, DrumKitData};
use crate::project::SynthData;
use crate::sampler::{Sampler, SamplerData};
/// Minimal per-track synthesizer
/// Clean rewrite: 1 oscillator, ADSR envelope, simple filter, 8-voice polyphony
use std::collections::HashMap;
use std::f32::consts::PI;
use std::sync::Arc;

const MAX_VOICES: usize = 8;

/// Fade-out time for a stolen voice — long enough to avoid a click, short
/// enough to be inaudible as a "note".
const STEAL_FADE_SECS: f32 = 0.005;

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
    pub fn parse(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "sine" => OscillatorType::Sine,
            "square" => OscillatorType::Square,
            "triangle" => OscillatorType::Triangle,
            // "saw" and any unrecognized string default to Saw
            _ => OscillatorType::Saw,
        }
    }
}

fn generate_waveform(osc_type: OscillatorType, phase: f32) -> f32 {
    match osc_type {
        OscillatorType::Sine => (phase * 2.0 * PI).sin(),
        OscillatorType::Saw => 2.0 * phase - 1.0,
        OscillatorType::Square => {
            if phase < 0.5 {
                1.0
            } else {
                -1.0
            }
        }
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
            attack: 0.01, // 10ms
            decay: 0.1,   // 100ms
            sustain: 0.7, // 70%
            release: 0.3, // 300ms
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
    release_start_level: f32, // level when release started (for smooth fade)
    is_active: bool,
    sustain_pending: bool, // note-off received while sustain pedal held
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
            release_start_level: 0.0,
            is_active: false,
            sustain_pending: false,
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
        self.release_start_level = 0.0;
        self.is_active = true;
        self.sustain_pending = false;
    }

    fn note_off(&mut self, sustain_held: bool) {
        if self.is_active && self.env_state != EnvelopeState::Release {
            if sustain_held {
                self.sustain_pending = true;
            } else {
                self.enter_release();
            }
        }
    }

    fn release_sustain(&mut self) {
        if self.sustain_pending {
            self.sustain_pending = false;
            self.enter_release();
        }
    }

    /// Begin the release phase from the envelope's *current* level — a
    /// note-off during attack/decay must fade from where it is, not jump to
    /// the sustain level (audible click on staccato notes).
    fn enter_release(&mut self) {
        self.release_start_level = self.env_level;
        self.env_state = EnvelopeState::Release;
        self.env_time = 0.0;
    }

    fn process(
        &mut self,
        osc_type: OscillatorType,
        env_params: &EnvelopeParams,
        sample_rate: f32,
    ) -> f32 {
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
                    // Fade from the level captured at note-off (not the
                    // sustain level — the note may still be in attack/decay)
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
        self.env_level.clamp(0.0, 1.0)
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
    // Stolen voices fading out over STEAL_FADE_SECS so reusing their slot
    // doesn't cut the old note dead mid-waveform (audible click).
    // Heap-allocated (Vec) to keep the TrackInstrument enum small.
    steal_tails: Vec<Voice>,
    pub osc_type: OscillatorType,
    pub filter_cutoff: f32, // 0.0-1.0
    pub envelope: EnvelopeParams,
    sample_rate: f32,
    // Simple one-pole lowpass filter state
    filter_state: f32,
    sustain_held: bool,
}

impl Synth {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            voices: [Voice::new(); MAX_VOICES],
            steal_tails: vec![Voice::new(); MAX_VOICES],
            osc_type: OscillatorType::Saw,
            filter_cutoff: 1.0, // Fully open
            envelope: EnvelopeParams::default(),
            sample_rate,
            filter_state: 0.0,
            sustain_held: false,
        }
    }

    pub fn note_on(&mut self, note: u8, velocity: u8) {
        // Find free voice or steal one
        let idx = self.find_free_voice_index();
        if self.voices[idx].is_active {
            self.start_steal_fade(self.voices[idx]);
        }
        self.voices[idx].note_on(note, velocity);
    }

    /// Move a stolen voice into a fade-out tail so the new note can start
    /// immediately while the old one ramps to silence.
    fn start_steal_fade(&mut self, mut stolen: Voice) {
        stolen.enter_release();
        let slot = self
            .steal_tails
            .iter()
            .position(|t| !t.is_active)
            .unwrap_or(0);
        self.steal_tails[slot] = stolen;
    }

    pub fn note_off(&mut self, note: u8) {
        for voice in &mut self.voices {
            if voice.is_active && voice.note == note {
                voice.note_off(self.sustain_held);
            }
        }
    }

    /// Handle MIDI Control Change — CC64 = sustain pedal
    pub fn control_change(&mut self, controller: u8, value: u8) {
        if controller == 64 {
            let pedal_on = value >= 64;
            self.sustain_held = pedal_on;

            if !pedal_on {
                for voice in &mut self.voices {
                    voice.release_sustain();
                }
            }
        }
    }

    pub fn all_notes_off(&mut self) {
        for voice in self.voices.iter_mut().chain(self.steal_tails.iter_mut()) {
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

        // Mix stolen voices with a fast declick fade instead of the
        // patch's release time
        let fade_params = EnvelopeParams {
            release: STEAL_FADE_SECS,
            ..self.envelope
        };
        for tail in &mut self.steal_tails {
            output += tail.process(self.osc_type, &fade_params, self.sample_rate);
        }

        // Apply simple one-pole lowpass filter
        output = self.apply_filter(output);

        // Reduce volume to prevent clipping with multiple voices
        output * 0.3
    }

    fn apply_filter(&mut self, input: f32) -> f32 {
        // Map cutoff 0.0-1.0 to a one-pole coefficient, anchored at 48 kHz so
        // the knob filters the same *frequency* at every device rate (C11).
        //
        // The knob historically fed the coefficient directly at 48 kHz, which
        // pinned a cutoff *frequency* per knob position only at that rate. A
        // one-pole `y = c·x + (1−c)·y` has fc = −ln(1−c)·fs/2π, so keeping fc
        // fixed across rates means c(fs) = 1 − (1−c₄₈)^(48000/fs). At 48 kHz
        // this is exactly the old behavior (existing projects are unchanged);
        // cutoff=1.0 stays a perfect pass-through at every rate.
        let knob = self.filter_cutoff.clamp(0.01, 1.0);
        let anchor = crate::audio_file::TARGET_SAMPLE_RATE as f32;
        let coeff = if (self.sample_rate - anchor).abs() < f32::EPSILON {
            knob
        } else {
            1.0 - (1.0 - knob).powf(anchor / self.sample_rate)
        };

        // Simple one-pole lowpass: y[n] = coeff * x[n] + (1-coeff) * y[n-1]
        self.filter_state = coeff * input + (1.0 - coeff) * self.filter_state;
        self.filter_state
    }

    pub fn set_parameter(&mut self, key: &str, value: &str) {
        println!("🎛️ Synth set_parameter: {key}={value}");

        match key {
            "osc_type" | "osc1_type" => {
                self.osc_type = OscillatorType::parse(value);
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
        // All voices active — prefer stealing one that's already fading out
        // (least audible to cut short), otherwise take the first
        self.voices
            .iter()
            .position(|v| v.env_state == EnvelopeState::Release)
            .unwrap_or(0)
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
    DrumKit(DrumKit),
}

impl TrackInstrument {
    pub fn note_on(&mut self, note: u8, velocity: u8) {
        match self {
            TrackInstrument::Synth(s) => s.note_on(note, velocity),
            TrackInstrument::Sampler(s) => s.note_on(note, velocity),
            TrackInstrument::DrumKit(k) => k.note_on(note, velocity),
        }
    }

    pub fn note_off(&mut self, note: u8) {
        match self {
            TrackInstrument::Synth(s) => s.note_off(note),
            TrackInstrument::Sampler(s) => s.note_off(note),
            TrackInstrument::DrumKit(k) => k.note_off(note),
        }
    }

    pub fn control_change(&mut self, controller: u8, value: u8) {
        match self {
            TrackInstrument::Synth(s) => s.control_change(controller, value),
            // Samplers and drum kits don't handle CC yet
            TrackInstrument::Sampler(_) | TrackInstrument::DrumKit(_) => {}
        }
    }

    pub fn all_notes_off(&mut self) {
        match self {
            TrackInstrument::Synth(s) => s.all_notes_off(),
            TrackInstrument::Sampler(s) => s.all_notes_off(),
            TrackInstrument::DrumKit(k) => k.all_notes_off(),
        }
    }

    /// Process and return mono sample (for backwards compatibility)
    pub fn process_sample(&mut self) -> f32 {
        match self {
            TrackInstrument::Synth(s) => s.process_sample(),
            TrackInstrument::Sampler(s) => s.process_sample_mono(),
            TrackInstrument::DrumKit(k) => k.process_sample_mono(),
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
            TrackInstrument::DrumKit(k) => k.process_sample(),
        }
    }

    pub fn set_parameter(&mut self, key: &str, value: &str) {
        match self {
            TrackInstrument::Synth(s) => s.set_parameter(key, value),
            TrackInstrument::Sampler(s) => s.set_parameter(key, value),
            // Drum-kit parameters are per-pad; use set_drum_pad_parameter instead.
            TrackInstrument::DrumKit(_) => {}
        }
    }

    pub fn is_synth(&self) -> bool {
        matches!(self, TrackInstrument::Synth(_))
    }

    pub fn is_sampler(&self) -> bool {
        matches!(self, TrackInstrument::Sampler(_))
    }

    pub fn is_drum_kit(&self) -> bool {
        matches!(self, TrackInstrument::DrumKit(_))
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

    pub fn as_drum_kit(&self) -> Option<&DrumKit> {
        match self {
            TrackInstrument::DrumKit(k) => Some(k),
            _ => None,
        }
    }

    pub fn as_drum_kit_mut(&mut self) -> Option<&mut DrumKit> {
        match self {
            TrackInstrument::DrumKit(k) => Some(k),
            _ => None,
        }
    }
}

// ============================================================================
// TRACK SYNTH MANAGER (manages both Synths and Samplers)
// ============================================================================

pub struct TrackSynthManager {
    instruments: HashMap<u64, TrackInstrument>,
    bypass_states: HashMap<u64, bool>,
    sample_rate: f32,
}

impl TrackSynthManager {
    pub fn new(sample_rate: f32) -> Self {
        Self {
            instruments: HashMap::new(),
            bypass_states: HashMap::new(),
            sample_rate,
        }
    }

    /// Create a synthesizer for a track
    pub fn create_synth(&mut self, track_id: u64) -> u64 {
        let synth = Synth::new(self.sample_rate);
        self.instruments
            .insert(track_id, TrackInstrument::Synth(synth));
        println!("✅ Created synth for track {track_id}");
        track_id
    }

    /// Create a sampler for a track
    pub fn create_sampler(&mut self, track_id: u64) -> u64 {
        let sampler = Sampler::new(self.sample_rate);
        self.instruments
            .insert(track_id, TrackInstrument::Sampler(sampler));
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

    /// Unload the sample from a sampler track. Returns false if the track
    /// is not a sampler.
    pub fn unload_sample(&mut self, track_id: u64) -> bool {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get_mut(&track_id) {
            sampler.unload_sample();
            true
        } else {
            println!("⚠️ unload_sample: Track {track_id} is not a sampler");
            false
        }
    }

    /// Currently loaded sample path for a sampler track (None when the track
    /// is not a sampler or has no sample).
    pub fn sampler_sample_path(&self, track_id: u64) -> Option<String> {
        if let Some(TrackInstrument::Sampler(sampler)) = self.instruments.get(&track_id) {
            sampler.sample_path().map(str::to_string)
        } else {
            None
        }
    }

    pub fn set_parameter(&mut self, track_id: u64, key: &str, value: &str) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.set_parameter(key, value);
        } else {
            println!(
                "⚠️ No instrument for track {} (available: {:?})",
                track_id,
                self.instruments.keys().collect::<Vec<_>>()
            );
        }
    }

    pub fn note_on(&mut self, track_id: u64, note: u8, velocity: u8) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.note_on(note, velocity);
        } else {
            eprintln!(
                "⚠️ note_on: No instrument for track {}. Available tracks: {:?}",
                track_id,
                self.instruments.keys().collect::<Vec<_>>()
            );
        }
    }

    pub fn note_off(&mut self, track_id: u64, note: u8) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.note_off(note);
        }
    }

    pub fn control_change(&mut self, track_id: u64, controller: u8, value: u8) {
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.control_change(controller, value);
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
        if self.is_bypassed(track_id) {
            return (0.0, 0.0);
        }
        if let Some(inst) = self.instruments.get_mut(&track_id) {
            inst.process_sample_stereo()
        } else {
            (0.0, 0.0)
        }
    }

    pub fn set_bypass(&mut self, track_id: u64, bypassed: bool) {
        self.bypass_states.insert(track_id, bypassed);
    }

    pub fn is_bypassed(&self, track_id: u64) -> bool {
        self.bypass_states.get(&track_id).copied().unwrap_or(false)
    }

    pub fn has_synth(&self, track_id: u64) -> bool {
        self.instruments.contains_key(&track_id)
    }

    /// Check if track has a sampler specifically
    pub fn has_sampler(&self, track_id: u64) -> bool {
        self.instruments
            .get(&track_id)
            .is_some_and(TrackInstrument::is_sampler)
    }

    /// Check if track has a synthesizer specifically
    pub fn is_synth(&self, track_id: u64) -> bool {
        self.instruments
            .get(&track_id)
            .is_some_and(TrackInstrument::is_synth)
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
        static LOGGED_COUNT: std::sync::atomic::AtomicBool =
            std::sync::atomic::AtomicBool::new(false);
        if !LOGGED_COUNT.swap(true, std::sync::atomic::Ordering::Relaxed) {
            eprintln!(
                "🔊 process_all_synths: {} instruments available, tracks: {:?}",
                self.instruments.len(),
                self.instruments.keys().collect::<Vec<_>>()
            );
        }

        let mut output = 0.0;
        for (track_id, inst) in &mut self.instruments {
            let sample = inst.process_sample();
            if sample.abs() > 0.001 {
                // Debug: only log once per note
                static LOGGED: std::sync::atomic::AtomicBool =
                    std::sync::atomic::AtomicBool::new(false);
                if !LOGGED.swap(true, std::sync::atomic::Ordering::Relaxed) {
                    eprintln!(
                        "🔊 process_all_synths: track {track_id} producing sample {sample:.4}"
                    );
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
            self.instruments
                .insert(dest_id, TrackInstrument::Synth(new_synth));
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
            println!(
                "✅ Restored synth parameters for track {}: osc={}",
                track_id, data.osc_type
            );
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
                sample_rate: f64::from(sampler.sample_sample_rate()),
                loop_enabled: sampler.loop_enabled,
                loop_start_seconds: sampler.frames_to_seconds(sampler.loop_start),
                loop_end_seconds: sampler.frames_to_seconds(sampler.loop_end),
                root_note: i32::from(sampler.root_note),
                attack_ms: f64::from(sampler.envelope.attack_ms),
                release_ms: f64::from(sampler.envelope.release_ms),
                volume_db: f64::from(sampler.volume_db),
                transpose_semitones: sampler.transpose_semitones,
                fine_cents: sampler.fine_cents,
                reversed: sampler.reversed,
                original_bpm: sampler.original_bpm,
                warp_enabled: sampler.warp_enabled,
                warp_mode: i32::from(sampler.warp_mode),
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
            if peaks.is_empty() {
                None
            } else {
                Some(peaks)
            }
        } else {
            None
        }
    }

    // ========================================================================
    // DRUM KIT
    // ========================================================================

    /// Create a drum-kit instrument for a track.
    pub fn create_drum_kit(&mut self, track_id: u64) -> u64 {
        self.instruments.insert(
            track_id,
            TrackInstrument::DrumKit(DrumKit::new(self.sample_rate)),
        );
        println!("✅ Created drum kit for track {track_id}");
        track_id
    }

    /// Add an empty pad pinned to `pinned_note`. Returns the new pad index, or `None` if the track
    /// isn't a drum kit or the note is already taken.
    pub fn add_drum_pad(&mut self, track_id: u64, pinned_note: u8) -> Option<u8> {
        self.instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
            .and_then(|k| k.add_pad(pinned_note))
    }

    /// Remove a pad by index. Returns `true` if a pad was removed.
    pub fn remove_drum_pad(&mut self, track_id: u64, pad_index: u8) -> bool {
        self.instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
            .is_some_and(|k| k.remove_pad(pad_index))
    }

    /// Load a sample into a drum pad.
    pub fn load_drum_pad_sample(
        &mut self,
        track_id: u64,
        pad_index: u8,
        clip: Arc<AudioClip>,
    ) -> bool {
        self.instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
            .is_some_and(|k| k.load_pad_sample(pad_index, clip))
    }

    /// Set a per-pad parameter (`pan`, `muted`, `soloed`, `volume_db`, `attack`, `release`,
    /// `transpose_semitones`, `reversed`, …).
    pub fn set_drum_pad_parameter(&mut self, track_id: u64, pad_index: u8, key: &str, value: &str) {
        if let Some(k) = self
            .instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
        {
            k.set_pad_parameter(pad_index, key, value);
        }
    }

    /// Check if a track has a drum kit specifically.
    pub fn has_drum_kit(&self, track_id: u64) -> bool {
        self.instruments
            .get(&track_id)
            .is_some_and(TrackInstrument::is_drum_kit)
    }

    /// The next free MIDI note for a new pad, searching from `start` upward.
    pub fn drum_next_free_note(&self, track_id: u64, start: u8) -> Option<u8> {
        self.instruments
            .get(&track_id)
            .and_then(TrackInstrument::as_drum_kit)
            .and_then(|k| k.next_free_note(start))
    }

    /// Drum-kit parameters for serialization / UI sync.
    pub fn get_drum_kit_parameters(&self, track_id: u64) -> Option<DrumKitData> {
        self.instruments
            .get(&track_id)
            .and_then(TrackInstrument::as_drum_kit)
            .map(DrumKit::get_parameters)
    }

    /// Restore a pad's metadata (call before loading its sample).
    pub fn restore_drum_pad_meta(&mut self, track_id: u64, data: &crate::drum_kit::DrumSlotData) {
        if let Some(k) = self
            .instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
        {
            k.restore_pad_meta(data);
        }
    }

    /// Restore a pad's sampler parameters (call after loading its sample).
    pub fn restore_drum_pad_sampler(&mut self, track_id: u64, pad_index: u8, data: &SamplerData) {
        if let Some(k) = self
            .instruments
            .get_mut(&track_id)
            .and_then(TrackInstrument::as_drum_kit_mut)
        {
            k.restore_pad_sampler(pad_index, data);
        }
    }

    /// Waveform peaks for a single pad's loaded sample.
    pub fn get_drum_pad_waveform_peaks(
        &self,
        track_id: u64,
        pad_index: u8,
        resolution: usize,
    ) -> Option<Vec<f32>> {
        let kit = self
            .instruments
            .get(&track_id)
            .and_then(TrackInstrument::as_drum_kit)?;
        let slot = kit.slots().iter().find(|s| s.pad_index == pad_index)?;
        let peaks = slot.sampler.get_waveform_peaks(resolution);
        if peaks.is_empty() {
            None
        } else {
            Some(peaks)
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
        // Voice may still be active during release phase
        let _count = synth.active_voice_count();
    }

    #[test]
    fn filter_mapping_is_anchored_at_48k() {
        // C11: the cutoff knob historically fed the one-pole coefficient
        // directly at 48 kHz. The rate-independent mapping must (a) be
        // bit-identical at 48 kHz so existing projects don't change timbre,
        // and (b) track the same cutoff *frequency* at other rates:
        // c(fs) = 1 − (1−c₄₈)^(48000/fs).
        let mut synth_48k = Synth::new(48_000.0);
        synth_48k.filter_cutoff = 0.5;
        // One-pole from zero state: y[0] = coeff · x[0].
        assert!((synth_48k.apply_filter(1.0) - 0.5).abs() < 1e-6);

        let mut synth_96k = Synth::new(96_000.0);
        synth_96k.filter_cutoff = 0.5;
        let expected = 1.0 - 0.5_f32.powf(0.5); // ≈ 0.2929
        assert!((synth_96k.apply_filter(1.0) - expected).abs() < 1e-6);

        // cutoff = 1.0 stays a perfect pass-through at every rate.
        let mut open_44k = Synth::new(44_100.0);
        open_44k.filter_cutoff = 1.0;
        assert!((open_44k.apply_filter(0.7) - 0.7).abs() < 1e-6);
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
    fn release_anchors_to_level_at_note_off() {
        // Note-off mid-attack must fade from the attack level, not jump up
        // to the sustain level (C7).
        let mut voice = Voice::new();
        let params = EnvelopeParams {
            attack: 0.1,
            decay: 0.1,
            sustain: 0.7,
            release: 0.3,
        };
        let sample_rate = 48000.0;

        voice.note_on(60, 100);
        // Run ~5ms of the 100ms attack → env_level ≈ 0.05
        for _ in 0..240 {
            voice.process_envelope(&params, sample_rate);
        }
        let level_before = voice.env_level;
        assert!(level_before < 0.1, "expected early-attack level, got {level_before}");

        voice.note_off(false);
        let level_after = voice.process_envelope(&params, sample_rate);
        // One release sample later the level must be continuous with the
        // pre-release level — not snapped to sustain (0.7).
        assert!(
            (level_after - level_before).abs() < 0.01,
            "release jumped from {level_before} to {level_after}"
        );
    }

    #[test]
    fn voice_steal_fades_old_note_instead_of_cutting() {
        let mut synth = Synth::new(48000.0);
        // Fill all voices and let them reach sustain
        for note in 0..MAX_VOICES {
            synth.note_on(60 + u8::try_from(note).unwrap(), 100);
        }
        for _ in 0..48000 / 2 {
            synth.process_sample();
        }
        assert_eq!(synth.active_voice_count(), MAX_VOICES);

        // 9th note steals a voice: the stolen note must keep sounding via a
        // fade tail (C10), not vanish in a single sample.
        synth.note_on(100, 100);
        let tail_active = synth.steal_tails.iter().any(|t| t.is_active);
        assert!(tail_active, "stolen voice was cut with no fade tail");

        // After the 5ms fade (240 samples @ 48kHz) the tail must be finished.
        for _ in 0..480 {
            synth.process_sample();
        }
        assert!(
            synth.steal_tails.iter().all(|t| !t.is_active),
            "steal tail still active after the fade window"
        );
    }

    #[test]
    fn test_track_synth_manager() {
        let mut manager = TrackSynthManager::new(48000.0);

        manager.create_synth(1);
        assert!(manager.has_synth(1));
        assert!(!manager.has_synth(2));

        manager.set_parameter(1, "osc_type", "sine");
        manager.note_on(1, 60, 100);

        // Should produce some audio (may be 0 during attack phase)
        let _ = manager.process_sample(1);
    }
}
