/// Audio effects for M4: Mixing & Effects
///
/// This module implements all built-in DSP effects:
/// - Parametric EQ (4-band with biquad filters)
/// - Compressor (RMS/peak with attack/release)
/// - Reverb (Freeverb algorithm)
/// - Delay (tempo-synced or time-based)
/// - Limiter (brick-wall, for master track)
/// - Chorus (modulated delay with LFO)

use crate::audio_file::TARGET_SAMPLE_RATE;
use std::f32::consts::PI;

/// Effect trait: all effects implement this
pub trait Effect: Send {
    /// Process a stereo frame (left, right) → (left_out, right_out)
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32);

    /// Reset internal state (clear buffers, etc.)
    fn reset(&mut self);

    /// Get effect name
    fn name(&self) -> &str;
}

/// Unique identifier for effects
pub type EffectId = u64;

// ========================================================================
// BIQUAD FILTER (used by EQ)
// ========================================================================

/// Biquad filter types
#[derive(Debug, Clone, Copy)]
pub enum BiquadType {
    LowShelf,
    HighShelf,
    Parametric,
}

/// Biquad filter (2nd-order IIR filter)
///
/// Used for EQ bands. Implements cookbook formulae from:
/// "Audio EQ Cookbook" by Robert Bristow-Johnson
#[derive(Clone)]
struct BiquadFilter {
    // Coefficients
    b0: f32, b1: f32, b2: f32,
    a1: f32, a2: f32,
    // State (Direct Form I)
    x1: f32, x2: f32, // Input history
    y1: f32, y2: f32, // Output history
}

impl BiquadFilter {
    fn new() -> Self {
        Self {
            b0: 1.0, b1: 0.0, b2: 0.0,
            a1: 0.0, a2: 0.0,
            x1: 0.0, x2: 0.0,
            y1: 0.0, y2: 0.0,
        }
    }

    /// Design a biquad filter
    fn design(&mut self, biquad_type: BiquadType, freq: f32, gain_db: f32, q: f32) {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        let alpha = sin_omega / (2.0 * q);
        let a = 10_f32.powf(gain_db / 40.0); // Amplitude

        match biquad_type {
            BiquadType::LowShelf => {
                // Low shelf filter
                let b0 = a * ((a + 1.0) - (a - 1.0) * cos_omega + 2.0 * a.sqrt() * alpha);
                let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cos_omega);
                let b2 = a * ((a + 1.0) - (a - 1.0) * cos_omega - 2.0 * a.sqrt() * alpha);
                let a0 = (a + 1.0) + (a - 1.0) * cos_omega + 2.0 * a.sqrt() * alpha;
                let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cos_omega);
                let a2 = (a + 1.0) + (a - 1.0) * cos_omega - 2.0 * a.sqrt() * alpha;

                // Normalize
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            BiquadType::HighShelf => {
                // High shelf filter
                let b0 = a * ((a + 1.0) + (a - 1.0) * cos_omega + 2.0 * a.sqrt() * alpha);
                let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_omega);
                let b2 = a * ((a + 1.0) + (a - 1.0) * cos_omega - 2.0 * a.sqrt() * alpha);
                let a0 = (a + 1.0) - (a - 1.0) * cos_omega + 2.0 * a.sqrt() * alpha;
                let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cos_omega);
                let a2 = (a + 1.0) - (a - 1.0) * cos_omega - 2.0 * a.sqrt() * alpha;

                // Normalize
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            BiquadType::Parametric => {
                // Parametric/peaking EQ
                let b0 = 1.0 + alpha * a;
                let b1 = -2.0 * cos_omega;
                let b2 = 1.0 - alpha * a;
                let a0 = 1.0 + alpha / a;
                let a1 = -2.0 * cos_omega;
                let a2 = 1.0 - alpha / a;

                // Normalize
                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
        }
    }

    /// Process one sample
    fn process(&mut self, input: f32) -> f32 {
        // Direct Form I
        let output = self.b0 * input + self.b1 * self.x1 + self.b2 * self.x2
                   - self.a1 * self.y1 - self.a2 * self.y2;

        // Shift history
        self.x2 = self.x1;
        self.x1 = input;
        self.y2 = self.y1;
        self.y1 = output;

        output
    }

    fn reset(&mut self) {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }
}

// ========================================================================
// PARAMETRIC EQ (4-band)
// ========================================================================

/// 4-band parametric EQ
#[derive(Clone)]
pub struct ParametricEQ {
    // Bands: low shelf, mid1, mid2, high shelf
    low_shelf: BiquadFilter,
    mid1: BiquadFilter,
    mid2: BiquadFilter,
    high_shelf: BiquadFilter,

    // Stereo: duplicate filters for right channel
    low_shelf_r: BiquadFilter,
    mid1_r: BiquadFilter,
    mid2_r: BiquadFilter,
    high_shelf_r: BiquadFilter,

    // Parameters
    pub low_freq: f32,
    pub low_gain_db: f32,
    pub mid1_freq: f32,
    pub mid1_gain_db: f32,
    pub mid1_q: f32,
    pub mid2_freq: f32,
    pub mid2_gain_db: f32,
    pub mid2_q: f32,
    pub high_freq: f32,
    pub high_gain_db: f32,
}

impl ParametricEQ {
    pub fn new() -> Self {
        let mut eq = Self {
            low_shelf: BiquadFilter::new(),
            mid1: BiquadFilter::new(),
            mid2: BiquadFilter::new(),
            high_shelf: BiquadFilter::new(),
            low_shelf_r: BiquadFilter::new(),
            mid1_r: BiquadFilter::new(),
            mid2_r: BiquadFilter::new(),
            high_shelf_r: BiquadFilter::new(),
            low_freq: 100.0,
            low_gain_db: 0.0,
            mid1_freq: 500.0,
            mid1_gain_db: 0.0,
            mid1_q: 1.0,
            mid2_freq: 2000.0,
            mid2_gain_db: 0.0,
            mid2_q: 1.0,
            high_freq: 8000.0,
            high_gain_db: 0.0,
        };
        eq.update_coefficients();
        eq
    }

    /// Update filter coefficients when parameters change
    pub fn update_coefficients(&mut self) {
        self.low_shelf.design(BiquadType::LowShelf, self.low_freq, self.low_gain_db, 0.707);
        self.mid1.design(BiquadType::Parametric, self.mid1_freq, self.mid1_gain_db, self.mid1_q);
        self.mid2.design(BiquadType::Parametric, self.mid2_freq, self.mid2_gain_db, self.mid2_q);
        self.high_shelf.design(BiquadType::HighShelf, self.high_freq, self.high_gain_db, 0.707);

        // Copy to right channel
        self.low_shelf_r.design(BiquadType::LowShelf, self.low_freq, self.low_gain_db, 0.707);
        self.mid1_r.design(BiquadType::Parametric, self.mid1_freq, self.mid1_gain_db, self.mid1_q);
        self.mid2_r.design(BiquadType::Parametric, self.mid2_freq, self.mid2_gain_db, self.mid2_q);
        self.high_shelf_r.design(BiquadType::HighShelf, self.high_freq, self.high_gain_db, 0.707);
    }
}

impl Effect for ParametricEQ {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Process left channel through all bands
        let mut left_out = left;
        left_out = self.low_shelf.process(left_out);
        left_out = self.mid1.process(left_out);
        left_out = self.mid2.process(left_out);
        left_out = self.high_shelf.process(left_out);

        // Process right channel through all bands
        let mut right_out = right;
        right_out = self.low_shelf_r.process(right_out);
        right_out = self.mid1_r.process(right_out);
        right_out = self.mid2_r.process(right_out);
        right_out = self.high_shelf_r.process(right_out);

        (left_out, right_out)
    }

    fn reset(&mut self) {
        self.low_shelf.reset();
        self.mid1.reset();
        self.mid2.reset();
        self.high_shelf.reset();
        self.low_shelf_r.reset();
        self.mid1_r.reset();
        self.mid2_r.reset();
        self.high_shelf_r.reset();
    }

    fn name(&self) -> &str {
        "Parametric EQ"
    }
}

// ========================================================================
// COMPRESSOR
// ========================================================================

/// Dynamic range compressor
#[derive(Clone)]
pub struct Compressor {
    // Parameters
    pub threshold_db: f32,
    pub ratio: f32,          // 1.0 = no compression, 10.0 = heavy compression
    pub attack_ms: f32,
    pub release_ms: f32,
    pub makeup_gain_db: f32,

    // State
    envelope: f32,           // Current gain reduction envelope
    attack_coeff: f32,
    release_coeff: f32,
}

impl Compressor {
    pub fn new() -> Self {
        let mut comp = Self {
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            makeup_gain_db: 0.0,
            envelope: 1.0,       // Start at no gain reduction
            attack_coeff: 0.0,
            release_coeff: 0.0,
        };
        comp.update_coefficients();
        comp
    }

    /// Update attack/release coefficients when parameters change
    pub fn update_coefficients(&mut self) {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        self.attack_coeff = (-1.0 / (self.attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();
    }

    /// Calculate gain reduction for a given input level (in linear)
    fn calculate_gain_reduction(&self, input_level: f32) -> f32 {
        if input_level <= 0.0 {
            return 1.0; // No gain reduction for silence
        }

        let input_db = 20.0 * input_level.log10();

        if input_db < self.threshold_db {
            1.0 // No compression below threshold
        } else {
            let over_db = input_db - self.threshold_db;
            let gain_reduction_db = over_db * (1.0 - 1.0 / self.ratio);
            10_f32.powf(-gain_reduction_db / 20.0)
        }
    }
}

impl Effect for Compressor {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Calculate RMS level (stereo average)
        let level = ((left * left + right * right) / 2.0).sqrt();

        // Calculate target gain reduction
        let target_gain = self.calculate_gain_reduction(level);

        // Smooth gain reduction with attack/release
        if target_gain < self.envelope {
            // Attack (gain reduction increasing)
            self.envelope = self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * target_gain;
        } else {
            // Release (gain reduction decreasing)
            self.envelope = self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target_gain;
        }

        // Apply gain reduction + makeup gain
        let makeup_gain = 10_f32.powf(self.makeup_gain_db / 20.0);
        let total_gain = self.envelope * makeup_gain;

        (left * total_gain, right * total_gain)
    }

    fn reset(&mut self) {
        self.envelope = 1.0;
    }

    fn name(&self) -> &str {
        "Compressor"
    }
}

// ========================================================================
// DELAY
// ========================================================================

/// Stereo delay effect
#[derive(Clone)]
pub struct Delay {
    // Parameters
    pub delay_time_ms: f32,
    pub feedback: f32,       // 0.0 to 0.99
    pub wet_dry_mix: f32,    // 0.0 = dry, 1.0 = wet

    // Buffers
    buffer_left: Vec<f32>,
    buffer_right: Vec<f32>,
    write_pos: usize,
}

impl Delay {
    pub fn new() -> Self {
        // Max 2 seconds delay
        let max_samples = (TARGET_SAMPLE_RATE as f32 * 2.0) as usize;
        Self {
            delay_time_ms: 500.0,
            feedback: 0.4,
            wet_dry_mix: 0.3,
            buffer_left: vec![0.0; max_samples],
            buffer_right: vec![0.0; max_samples],
            write_pos: 0,
        }
    }

    fn get_delay_samples(&self) -> usize {
        ((self.delay_time_ms * 0.001 * TARGET_SAMPLE_RATE as f32) as usize)
            .min(self.buffer_left.len() - 1)
    }
}

impl Effect for Delay {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let delay_samples = self.get_delay_samples();
        let buffer_size = self.buffer_left.len();

        // Calculate read position
        let read_pos = (self.write_pos + buffer_size - delay_samples) % buffer_size;

        // Read delayed samples
        let delayed_left = self.buffer_left[read_pos];
        let delayed_right = self.buffer_right[read_pos];

        // Write input + feedback to buffer
        self.buffer_left[self.write_pos] = left + delayed_left * self.feedback;
        self.buffer_right[self.write_pos] = right + delayed_right * self.feedback;

        // Advance write position
        self.write_pos = (self.write_pos + 1) % buffer_size;

        // Mix wet/dry
        let out_left = left * (1.0 - self.wet_dry_mix) + delayed_left * self.wet_dry_mix;
        let out_right = right * (1.0 - self.wet_dry_mix) + delayed_right * self.wet_dry_mix;

        (out_left, out_right)
    }

    fn reset(&mut self) {
        self.buffer_left.fill(0.0);
        self.buffer_right.fill(0.0);
        self.write_pos = 0;
    }

    fn name(&self) -> &str {
        "Delay"
    }
}

// ========================================================================
// REVERB (Freeverb)
// ========================================================================

/// Simple reverb based on Freeverb algorithm
#[derive(Clone)]
pub struct Reverb {
    // Parameters
    pub room_size: f32,      // 0.0 to 1.0
    pub damping: f32,        // 0.0 to 1.0
    pub wet_dry_mix: f32,    // 0.0 = dry, 1.0 = wet

    // Comb filters (8 per channel for stereo)
    comb_buffers_l: Vec<Vec<f32>>,
    comb_buffers_r: Vec<Vec<f32>>,
    comb_positions_l: Vec<usize>,
    comb_positions_r: Vec<usize>,
    comb_filter_state_l: Vec<f32>,
    comb_filter_state_r: Vec<f32>,

    // Allpass filters (4 per channel)
    allpass_buffers_l: Vec<Vec<f32>>,
    allpass_buffers_r: Vec<Vec<f32>>,
    allpass_positions_l: Vec<usize>,
    allpass_positions_r: Vec<usize>,
}

impl Reverb {
    pub fn new() -> Self {
        // Freeverb comb filter lengths (in samples at 44.1 kHz, scaled to 48 kHz)
        let comb_lengths = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
            .iter()
            .map(|&len| (len as f32 * TARGET_SAMPLE_RATE as f32 / 44100.0) as usize)
            .collect::<Vec<_>>();

        // Allpass filter lengths
        let allpass_lengths = [556, 441, 341, 225]
            .iter()
            .map(|&len| (len as f32 * TARGET_SAMPLE_RATE as f32 / 44100.0) as usize)
            .collect::<Vec<_>>();

        let mut comb_buffers_l = Vec::new();
        let mut comb_buffers_r = Vec::new();
        for &len in &comb_lengths {
            comb_buffers_l.push(vec![0.0; len]);
            comb_buffers_r.push(vec![0.0; len + 23]); // Stereo spread
        }

        let mut allpass_buffers_l = Vec::new();
        let mut allpass_buffers_r = Vec::new();
        for &len in &allpass_lengths {
            allpass_buffers_l.push(vec![0.0; len]);
            allpass_buffers_r.push(vec![0.0; len + 11]); // Stereo spread
        }

        Self {
            room_size: 0.5,
            damping: 0.5,
            wet_dry_mix: 0.3,
            comb_buffers_l,
            comb_buffers_r,
            comb_positions_l: vec![0; 8],
            comb_positions_r: vec![0; 8],
            comb_filter_state_l: vec![0.0; 8],
            comb_filter_state_r: vec![0.0; 8],
            allpass_buffers_l,
            allpass_buffers_r,
            allpass_positions_l: vec![0; 4],
            allpass_positions_r: vec![0; 4],
        }
    }

    fn process_comb(
        input: f32,
        room_size: f32,
        damping: f32,
        buffer: &mut Vec<f32>,
        pos: &mut usize,
        filter_state: &mut f32,
    ) -> f32 {
        let output = buffer[*pos];

        // Damped feedback
        let dampened = *filter_state * (1.0 - damping) + output * damping;
        *filter_state = dampened;

        buffer[*pos] = input + dampened * room_size;
        *pos = (*pos + 1) % buffer.len();

        output
    }

    fn process_allpass(
        input: f32,
        buffer: &mut Vec<f32>,
        pos: &mut usize,
    ) -> f32 {
        let delayed = buffer[*pos];
        buffer[*pos] = input + delayed * 0.5;
        *pos = (*pos + 1) % buffer.len();

        delayed - input * 0.5
    }
}

impl Effect for Reverb {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Mix to mono for input
        let mono_input = (left + right) * 0.5;

        // Process comb filters (parallel) - separate positions for L and R
        let mut comb_out_l = 0.0;
        let mut comb_out_r = 0.0;
        for i in 0..8 {
            comb_out_l += Self::process_comb(
                mono_input,
                self.room_size,
                self.damping,
                &mut self.comb_buffers_l[i],
                &mut self.comb_positions_l[i],
                &mut self.comb_filter_state_l[i],
            );
            comb_out_r += Self::process_comb(
                mono_input,
                self.room_size,
                self.damping,
                &mut self.comb_buffers_r[i],
                &mut self.comb_positions_r[i],
                &mut self.comb_filter_state_r[i],
            );
        }

        // Process allpass filters (series) - separate positions for L and R
        let mut out_l = comb_out_l;
        let mut out_r = comb_out_r;
        for i in 0..4 {
            out_l = Self::process_allpass(
                out_l,
                &mut self.allpass_buffers_l[i],
                &mut self.allpass_positions_l[i],
            );
            out_r = Self::process_allpass(
                out_r,
                &mut self.allpass_buffers_r[i],
                &mut self.allpass_positions_r[i],
            );
        }

        // Mix wet/dry
        let final_left = left * (1.0 - self.wet_dry_mix) + out_l * self.wet_dry_mix * 0.015;
        let final_right = right * (1.0 - self.wet_dry_mix) + out_r * self.wet_dry_mix * 0.015;

        (final_left, final_right)
    }

    fn reset(&mut self) {
        for buffer in &mut self.comb_buffers_l {
            buffer.fill(0.0);
        }
        for buffer in &mut self.comb_buffers_r {
            buffer.fill(0.0);
        }
        for buffer in &mut self.allpass_buffers_l {
            buffer.fill(0.0);
        }
        for buffer in &mut self.allpass_buffers_r {
            buffer.fill(0.0);
        }
        self.comb_positions_l.fill(0);
        self.comb_positions_r.fill(0);
        self.comb_filter_state_l.fill(0.0);
        self.comb_filter_state_r.fill(0.0);
        self.allpass_positions_l.fill(0);
        self.allpass_positions_r.fill(0);
    }

    fn name(&self) -> &str {
        "Reverb"
    }
}

// ========================================================================
// LIMITER
// ========================================================================

/// Brick-wall limiter (for master track)
#[derive(Clone)]
pub struct Limiter {
    pub threshold_db: f32,
    pub release_ms: f32,

    envelope_left: f32,
    envelope_right: f32,
    release_coeff: f32,
}

impl Limiter {
    pub fn new() -> Self {
        let mut limiter = Self {
            threshold_db: -0.1, // Just below 0 dBFS
            release_ms: 50.0,
            envelope_left: 0.0,
            envelope_right: 0.0,
            release_coeff: 0.0,
        };
        limiter.update_coefficients();
        limiter
    }

    pub fn update_coefficients(&mut self) {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        self.release_coeff = (-1.0 / (self.release_ms * 0.001 * sample_rate)).exp();
    }
}

impl Effect for Limiter {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let threshold_linear = 10_f32.powf(self.threshold_db / 20.0);

        // Track peaks with release
        let left_abs = left.abs();
        let right_abs = right.abs();

        if left_abs > self.envelope_left {
            self.envelope_left = left_abs;
        } else {
            self.envelope_left = self.release_coeff * self.envelope_left;
        }

        if right_abs > self.envelope_right {
            self.envelope_right = right_abs;
        } else {
            self.envelope_right = self.release_coeff * self.envelope_right;
        }

        // Calculate gain reduction
        let gain_left = if self.envelope_left > threshold_linear {
            threshold_linear / self.envelope_left
        } else {
            1.0
        };

        let gain_right = if self.envelope_right > threshold_linear {
            threshold_linear / self.envelope_right
        } else {
            1.0
        };

        // Use minimum gain for both channels (link)
        let gain = gain_left.min(gain_right);

        (left * gain, right * gain)
    }

    fn reset(&mut self) {
        self.envelope_left = 0.0;
        self.envelope_right = 0.0;
    }

    fn name(&self) -> &str {
        "Limiter"
    }
}

// ========================================================================
// CHORUS
// ========================================================================

/// Chorus effect (modulated delay)
#[derive(Clone)]
pub struct Chorus {
    pub rate_hz: f32,        // LFO rate
    pub depth: f32,          // Modulation depth (0.0 to 1.0)
    pub wet_dry_mix: f32,

    // Delay buffers
    buffer_left: Vec<f32>,
    buffer_right: Vec<f32>,
    write_pos: usize,

    // LFO
    lfo_phase: f32,
}

impl Chorus {
    pub fn new() -> Self {
        // Max 50ms delay
        let max_samples = (TARGET_SAMPLE_RATE as f32 * 0.05) as usize;
        Self {
            rate_hz: 1.5,
            depth: 0.5,
            wet_dry_mix: 0.5,
            buffer_left: vec![0.0; max_samples],
            buffer_right: vec![0.0; max_samples],
            write_pos: 0,
            lfo_phase: 0.0,
        }
    }
}

impl Effect for Chorus {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let buffer_size = self.buffer_left.len();

        // LFO (sine wave)
        let lfo = (self.lfo_phase * 2.0 * PI).sin();
        self.lfo_phase += self.rate_hz / TARGET_SAMPLE_RATE as f32;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= 1.0;
        }

        // Calculate delay time (5ms to 30ms)
        let base_delay_ms = 15.0;
        let delay_variation_ms = 10.0 * self.depth;
        let delay_ms = base_delay_ms + lfo * delay_variation_ms;
        let delay_samples = ((delay_ms * 0.001 * TARGET_SAMPLE_RATE as f32) as usize)
            .min(buffer_size - 1);

        // Read from buffer
        let read_pos = (self.write_pos + buffer_size - delay_samples) % buffer_size;
        let delayed_left = self.buffer_left[read_pos];
        let delayed_right = self.buffer_right[read_pos];

        // Write to buffer
        self.buffer_left[self.write_pos] = left;
        self.buffer_right[self.write_pos] = right;
        self.write_pos = (self.write_pos + 1) % buffer_size;

        // Mix
        let out_left = left * (1.0 - self.wet_dry_mix) + delayed_left * self.wet_dry_mix;
        let out_right = right * (1.0 - self.wet_dry_mix) + delayed_right * self.wet_dry_mix;

        (out_left, out_right)
    }

    fn reset(&mut self) {
        self.buffer_left.fill(0.0);
        self.buffer_right.fill(0.0);
        self.write_pos = 0;
        self.lfo_phase = 0.0;
    }

    fn name(&self) -> &str {
        "Chorus"
    }
}

// ========================================================================
// EFFECT CONTAINER
// ========================================================================

/// Container for any effect type
#[derive(Clone)]
pub enum EffectType {
    EQ(ParametricEQ),
    Compressor(Compressor),
    Reverb(Reverb),
    Delay(Delay),
    Limiter(Limiter),
    Chorus(Chorus),
    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
    VST3(crate::vst3_host::VST3Effect),  // M7: VST3 plugin support (desktop only)
}

impl EffectType {
    pub fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        match self {
            EffectType::EQ(fx) => fx.process_frame(left, right),
            EffectType::Compressor(fx) => fx.process_frame(left, right),
            EffectType::Reverb(fx) => fx.process_frame(left, right),
            EffectType::Delay(fx) => fx.process_frame(left, right),
            EffectType::Limiter(fx) => fx.process_frame(left, right),
            EffectType::Chorus(fx) => fx.process_frame(left, right),
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            EffectType::VST3(fx) => fx.process_frame(left, right),
        }
    }

    pub fn reset(&mut self) {
        match self {
            EffectType::EQ(fx) => fx.reset(),
            EffectType::Compressor(fx) => fx.reset(),
            EffectType::Reverb(fx) => fx.reset(),
            EffectType::Delay(fx) => fx.reset(),
            EffectType::Limiter(fx) => fx.reset(),
            EffectType::Chorus(fx) => fx.reset(),
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            EffectType::VST3(fx) => fx.reset(),
        }
    }

    pub fn name(&self) -> &str {
        match self {
            EffectType::EQ(fx) => fx.name(),
            EffectType::Compressor(fx) => fx.name(),
            EffectType::Reverb(fx) => fx.name(),
            EffectType::Delay(fx) => fx.name(),
            EffectType::Limiter(fx) => fx.name(),
            EffectType::Chorus(fx) => fx.name(),
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            EffectType::VST3(fx) => fx.name(),
        }
    }
}

// ========================================================================
// EFFECT MANAGER
// ========================================================================

use std::sync::{Arc, Mutex};
use std::collections::HashMap;

/// Effect manager: holds all effect instances
pub struct EffectManager {
    effects: HashMap<EffectId, Arc<Mutex<EffectType>>>,
    /// Bypass state per effect (true = bypassed, audio passes through unchanged)
    bypass_states: HashMap<EffectId, bool>,
    next_id: EffectId,
}

impl EffectManager {
    pub fn new() -> Self {
        Self {
            effects: HashMap::new(),
            bypass_states: HashMap::new(),
            next_id: 0,
        }
    }

    /// Create a new effect and return its ID
    pub fn create_effect(&mut self, effect: EffectType) -> EffectId {
        let id = self.next_id;
        self.next_id += 1;

        eprintln!("🎛️ [EffectManager] Created {} effect (ID: {})", effect.name(), id);

        self.effects.insert(id, Arc::new(Mutex::new(effect)));
        self.bypass_states.insert(id, false); // Effects start not bypassed
        id
    }

    /// Get an effect by ID
    pub fn get_effect(&self, id: EffectId) -> Option<Arc<Mutex<EffectType>>> {
        self.effects.get(&id).cloned()
    }

    /// Remove an effect
    pub fn remove_effect(&mut self, id: EffectId) -> bool {
        if self.effects.remove(&id).is_some() {
            self.bypass_states.remove(&id);
            eprintln!("🗑️ [EffectManager] Removed effect {}", id);
            true
        } else {
            false
        }
    }

    /// Set bypass state for an effect
    pub fn set_bypass(&mut self, id: EffectId, bypassed: bool) -> bool {
        if self.effects.contains_key(&id) {
            self.bypass_states.insert(id, bypassed);
            eprintln!("🎛️ [EffectManager] Effect {} bypass: {}", id, bypassed);
            true
        } else {
            false
        }
    }

    /// Get bypass state for an effect
    pub fn get_bypass(&self, id: EffectId) -> Option<bool> {
        self.bypass_states.get(&id).copied()
    }

    /// Check if an effect is bypassed (returns false if effect doesn't exist)
    pub fn is_bypassed(&self, id: EffectId) -> bool {
        self.bypass_states.get(&id).copied().unwrap_or(false)
    }

    /// Get all effect IDs
    pub fn get_all_effect_ids(&self) -> Vec<EffectId> {
        self.effects.keys().copied().collect()
    }

    /// Duplicate an effect (deep copy with new ID)
    /// Returns new effect ID on success, None if source effect not found
    pub fn duplicate_effect(&mut self, source_effect_id: EffectId) -> Option<EffectId> {
        if let Some(source_effect_arc) = self.effects.get(&source_effect_id) {
            let source_effect = source_effect_arc.lock().expect("mutex poisoned");

            // Clone the effect (deep copy)
            let cloned_effect = source_effect.clone();
            drop(source_effect); // Release lock

            // Create new effect with cloned data
            let new_id = self.next_id;
            self.next_id += 1;

            self.effects.insert(new_id, Arc::new(Mutex::new(cloned_effect)));
            eprintln!("🎛️ [EffectManager] Duplicated effect {} → {} ({})",
                      source_effect_id, new_id, self.effects.get(&new_id).unwrap().lock().expect("mutex poisoned").name());

            Some(new_id)
        } else {
            None
        }
    }
}
