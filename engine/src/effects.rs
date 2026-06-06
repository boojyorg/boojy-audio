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
    /// Process a stereo frame (left, right) → (`left_out`, `right_out`)
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32);

    /// Process a block of stereo frames in-place.
    /// Default implementation calls `process_frame` per sample.
    /// Override for effects that benefit from batched processing (e.g., VST3 plugins).
    fn process_block(&mut self, left: &mut [f32], right: &mut [f32]) {
        let len = left.len().min(right.len());
        for i in 0..len {
            let (l, r) = self.process_frame(left[i], right[i]);
            left[i] = l;
            right[i] = r;
        }
    }

    /// Reset internal state (clear buffers, etc.)
    fn reset(&mut self);

    /// Get effect name
    fn name(&self) -> &str;

    /// Update the effect's sample rate, recomputing any rate-dependent
    /// coefficients. Default no-op: effects whose DSP is rate-agnostic, or that
    /// size buffers at construction, can ignore this. Filter-based effects
    /// (EQ, Compressor, Limiter) override it so their coefficients track the
    /// real device rate instead of a hardcoded constant.
    fn set_sample_rate(&mut self, _sample_rate: f32) {}
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
    /// 2nd-order high-pass (used for the EQ's fixed Low Cut). `gain_db` ignored.
    HighPass,
    /// 2nd-order low-pass (used for the EQ's fixed High Cut). `gain_db` ignored.
    LowPass,
}

/// Biquad filter (2nd-order IIR filter)
///
/// Used for EQ bands. Implements cookbook formulae from:
/// "Audio EQ Cookbook" by Robert Bristow-Johnson
#[derive(Clone)]
pub(crate) struct BiquadFilter {
    // Coefficients
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    // State (Direct Form I)
    x1: f32,
    x2: f32, // Input history
    y1: f32,
    y2: f32, // Output history
}

impl BiquadFilter {
    fn new() -> Self {
        Self {
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            x1: 0.0,
            x2: 0.0,
            y1: 0.0,
            y2: 0.0,
        }
    }

    /// Design a biquad filter at the given sample rate
    fn design(&mut self, biquad_type: BiquadType, freq: f32, gain_db: f32, q: f32, sample_rate: f32) {
        let omega = 2.0 * PI * freq / sample_rate;
        let sin_omega = omega.sin();
        let cos_omega = omega.cos();
        // Guard q=0 → divide-by-zero → NaN coefficients on the audio thread.
        let q = q.max(0.01);
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
            BiquadType::HighPass => {
                // 2nd-order Butterworth-ish high-pass (RBJ cookbook). gain_db unused.
                let b0 = f32::midpoint(1.0, cos_omega); // (1 + cos)/2
                let b1 = -(1.0 + cos_omega);
                let b2 = b0;
                let a0 = 1.0 + alpha;
                let a1 = -2.0 * cos_omega;
                let a2 = 1.0 - alpha;

                self.b0 = b0 / a0;
                self.b1 = b1 / a0;
                self.b2 = b2 / a0;
                self.a1 = a1 / a0;
                self.a2 = a2 / a0;
            }
            BiquadType::LowPass => {
                // 2nd-order low-pass (RBJ cookbook). gain_db unused.
                let b0 = f32::midpoint(1.0, -cos_omega); // (1 - cos)/2
                let b1 = 1.0 - cos_omega;
                let b2 = b0;
                let a0 = 1.0 + alpha;
                let a1 = -2.0 * cos_omega;
                let a2 = 1.0 - alpha;

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
            - self.a1 * self.y1
            - self.a2 * self.y2;

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
// GRAPHIC EQ (variable-band)
// ========================================================================

/// Maximum number of bands a Graphic EQ can hold (spec §7).
pub(crate) const MAX_EQ_BANDS: usize = 8;
/// Fixed Low Cut (high-pass) corner frequency.
const LOW_CUT_FREQ: f32 = 80.0;
/// Fixed High Cut (low-pass) corner frequency.
const HIGH_CUT_FREQ: f32 = 12_000.0;
/// Internal Q for the fixed-slope shelves and the cut filters (spec §6.2).
const SHELF_Q: f32 = 0.707;

/// The role/shape of an EQ band. Determines its filter type and whether Focus
/// (Q) applies. A band keeps its shape regardless of where it is dragged.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BandShape {
    LowShelf,
    Bell,
    HighShelf,
}

impl BandShape {
    /// Encode for the flat param/persistence map (0 = low shelf, 1 = bell, 2 = high shelf).
    fn to_code(self) -> f32 {
        match self {
            BandShape::LowShelf => 0.0,
            BandShape::Bell => 1.0,
            BandShape::HighShelf => 2.0,
        }
    }
    fn from_code(v: f32) -> Self {
        match v.round() as i32 {
            0 => BandShape::LowShelf,
            2 => BandShape::HighShelf,
            _ => BandShape::Bell,
        }
    }
    fn biquad_type(self) -> BiquadType {
        match self {
            BandShape::LowShelf => BiquadType::LowShelf,
            BandShape::Bell => BiquadType::Parametric,
            BandShape::HighShelf => BiquadType::HighShelf,
        }
    }
}

/// One adjustable EQ band (a draggable dot in the UI).
#[derive(Clone)]
struct EqBand {
    freq: f32,
    gain_db: f32,
    /// 0.0..1.0 "Focus" — how narrow the band is. Only meaningful for Bell shapes.
    focus: f32,
    shape: BandShape,
    bypassed: bool,
    filter_l: BiquadFilter,
    filter_r: BiquadFilter,
}

impl EqBand {
    fn new(freq: f32, gain_db: f32, focus: f32, shape: BandShape) -> Self {
        Self {
            freq,
            gain_db,
            focus,
            shape,
            bypassed: false,
            filter_l: BiquadFilter::new(),
            filter_r: BiquadFilter::new(),
        }
    }

    /// Map Focus (0..1) to Q geometrically: `Q = 0.4 * 15^focus` (spec §6.1).
    /// Shelves use a fixed gentle slope (spec §6.2).
    fn q(&self) -> f32 {
        match self.shape {
            BandShape::Bell => 0.4 * 15_f32.powf(self.focus.clamp(0.0, 1.0)),
            _ => SHELF_Q,
        }
    }

    fn update(&mut self, sample_rate: f32) {
        let bt = self.shape.biquad_type();
        let q = self.q();
        self.filter_l.design(bt, self.freq, self.gain_db, q, sample_rate);
        self.filter_r.design(bt, self.freq, self.gain_db, q, sample_rate);
    }

    fn reset(&mut self) {
        self.filter_l.reset();
        self.filter_r.reset();
    }
}

/// Variable-band graphic EQ: 3 default bands (Low shelf / Mid bell / High shelf),
/// up to [`MAX_EQ_BANDS`]. Plus a fixed Low Cut (HPF) and High Cut (LPF) and an
/// output trim. The struct name stays `ParametricEQ` so `EffectType` is unchanged.
#[derive(Clone)]
pub struct ParametricEQ {
    bands: Vec<EqBand>,
    low_cut: [BiquadFilter; 2],
    high_cut: [BiquadFilter; 2],
    low_cut_on: bool,
    high_cut_on: bool,
    output_gain_db: f32,
    sample_rate: f32,
}

impl Default for ParametricEQ {
    fn default() -> Self {
        Self::new()
    }
}

impl ParametricEQ {
    pub fn new() -> Self {
        // Three flat default bands → the EQ does nothing until touched (spec §5).
        let mut eq = Self {
            bands: vec![
                EqBand::new(100.0, 0.0, 0.4, BandShape::LowShelf),
                EqBand::new(1000.0, 0.0, 0.4, BandShape::Bell),
                EqBand::new(10_000.0, 0.0, 0.4, BandShape::HighShelf),
            ],
            low_cut: [BiquadFilter::new(), BiquadFilter::new()],
            high_cut: [BiquadFilter::new(), BiquadFilter::new()],
            low_cut_on: false,
            high_cut_on: false,
            output_gain_db: 0.0,
            sample_rate: TARGET_SAMPLE_RATE as f32,
        };
        eq.update_coefficients();
        eq
    }

    pub fn band_count(&self) -> usize {
        self.bands.len()
    }

    /// Recompute every band + cut filter for the current sample rate.
    pub fn update_coefficients(&mut self) {
        let sr = self.sample_rate;
        for band in &mut self.bands {
            band.update(sr);
        }
        for f in &mut self.low_cut {
            f.design(BiquadType::HighPass, LOW_CUT_FREQ, 0.0, SHELF_Q, sr);
        }
        for f in &mut self.high_cut {
            f.design(BiquadType::LowPass, HIGH_CUT_FREQ, 0.0, SHELF_Q, sr);
        }
    }

    /// Add a default bell band (1 kHz, 0 dB, focus 0.4). Returns the new band's
    /// index, or `None` if already at [`MAX_EQ_BANDS`].
    pub fn add_band(&mut self) -> Option<usize> {
        if self.bands.len() >= MAX_EQ_BANDS {
            return None;
        }
        let mut band = EqBand::new(1000.0, 0.0, 0.4, BandShape::Bell);
        band.update(self.sample_rate);
        self.bands.push(band);
        Some(self.bands.len() - 1)
    }

    /// Insert a default bell band at `index` (clamped to the end). Used by undo
    /// of a band removal so the band returns to its original slot — keeping every
    /// other band's index stable, which the index-addressed param keys rely on.
    /// Returns false if already at [`MAX_EQ_BANDS`].
    pub fn insert_band(&mut self, index: usize) -> bool {
        if self.bands.len() >= MAX_EQ_BANDS {
            return false;
        }
        let mut band = EqBand::new(1000.0, 0.0, 0.4, BandShape::Bell);
        band.update(self.sample_rate);
        let i = index.min(self.bands.len());
        self.bands.insert(i, band);
        true
    }

    /// Remove the band at `index`. Returns false if out of range.
    pub fn remove_band(&mut self, index: usize) -> bool {
        if index < self.bands.len() {
            self.bands.remove(index);
            true
        } else {
            false
        }
    }

    /// Set a per-band parameter by key: `freq`, `gain`, `focus`, `shape`, `on`.
    pub fn set_band_param(&mut self, index: usize, key: &str, value: f32) -> Result<(), String> {
        let sr = self.sample_rate;
        let band = self
            .bands
            .get_mut(index)
            .ok_or_else(|| format!("EQ band index {index} out of range"))?;
        match key {
            "freq" => band.freq = value.clamp(20.0, 20_000.0),
            "gain" => band.gain_db = value.clamp(-12.0, 12.0),
            "focus" => band.focus = value.clamp(0.0, 1.0),
            "shape" => band.shape = BandShape::from_code(value),
            "on" => band.bypassed = value < 0.5,
            _ => return Err(format!("Unknown EQ band param: {key}")),
        }
        band.update(sr);
        Ok(())
    }

    pub fn set_low_cut(&mut self, on: bool) {
        self.low_cut_on = on;
    }

    pub fn set_high_cut(&mut self, on: bool) {
        self.high_cut_on = on;
    }

    pub fn set_output_gain(&mut self, gain_db: f32) {
        self.output_gain_db = gain_db.clamp(-12.0, 12.0);
    }

    /// Emit the full state as flat `key, value` pairs (bands indexed
    /// `band_N_freq` / `_gain` / `_focus` / `_shape` / `_on`). Shared by
    /// `get_effect_info` serialization and project save. Not realtime.
    pub fn write_params(&self, out: &mut dyn FnMut(&str, f32)) {
        out("band_count", self.bands.len() as f32);
        for (i, b) in self.bands.iter().enumerate() {
            out(&format!("band_{i}_freq"), b.freq);
            out(&format!("band_{i}_gain"), b.gain_db);
            out(&format!("band_{i}_focus"), b.focus);
            out(&format!("band_{i}_shape"), b.shape.to_code());
            out(&format!("band_{i}_on"), if b.bypassed { 0.0 } else { 1.0 });
        }
        out("low_cut_on", if self.low_cut_on { 1.0 } else { 0.0 });
        out("high_cut_on", if self.high_cut_on { 1.0 } else { 0.0 });
        out("output_gain", self.output_gain_db);
    }

    /// Rebuild bands + cuts + output from a flat lookup (project load). Returns
    /// false if no `band_count` key was present (an old-format project) so the
    /// caller can keep the flat default bands rather than dropping the EQ.
    pub fn load_params(&mut self, get: &dyn Fn(&str) -> Option<f32>) -> bool {
        let Some(count) = get("band_count") else {
            return false; // old-format project → keep default flat bands
        };
        let count = (count.round() as usize).min(MAX_EQ_BANDS);
        let mut bands = Vec::with_capacity(count);
        for i in 0..count {
            let freq = get(&format!("band_{i}_freq")).unwrap_or(1000.0);
            let gain = get(&format!("band_{i}_gain")).unwrap_or(0.0);
            let focus = get(&format!("band_{i}_focus")).unwrap_or(0.4);
            let shape = BandShape::from_code(get(&format!("band_{i}_shape")).unwrap_or(1.0));
            let mut band = EqBand::new(freq, gain, focus, shape);
            band.bypassed = get(&format!("band_{i}_on")).unwrap_or(1.0) < 0.5;
            bands.push(band);
        }
        if !bands.is_empty() {
            self.bands = bands;
        }
        self.low_cut_on = get("low_cut_on").unwrap_or(0.0) >= 0.5;
        self.high_cut_on = get("high_cut_on").unwrap_or(0.0) >= 0.5;
        self.output_gain_db = get("output_gain").unwrap_or(0.0);
        self.update_coefficients();
        true
    }
}

impl Effect for ParametricEQ {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let mut l = left;
        let mut r = right;

        // Low Cut → bands (in order) → High Cut → output trim (spec §10 signal flow).
        if self.low_cut_on {
            l = self.low_cut[0].process(l);
            r = self.low_cut[1].process(r);
        }
        for band in &mut self.bands {
            if !band.bypassed {
                l = band.filter_l.process(l);
                r = band.filter_r.process(r);
            }
        }
        if self.high_cut_on {
            l = self.high_cut[0].process(l);
            r = self.high_cut[1].process(r);
        }

        let gain = 10_f32.powf(self.output_gain_db / 20.0);
        (l * gain, r * gain)
    }

    fn reset(&mut self) {
        for band in &mut self.bands {
            band.reset();
        }
        for f in &mut self.low_cut {
            f.reset();
        }
        for f in &mut self.high_cut {
            f.reset();
        }
    }

    fn name(&self) -> &'static str {
        "Graphic EQ"
    }

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            self.update_coefficients();
        }
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
    pub ratio: f32, // 1.0 = no compression, 10.0 = heavy compression
    pub attack_ms: f32,
    pub release_ms: f32,
    pub makeup_gain_db: f32,
    pub wet_dry_mix: f32, // 0.0 = dry, 1.0 = wet

    // State
    envelope: f32, // Current gain reduction envelope
    attack_coeff: f32,
    release_coeff: f32,
    sample_rate: f32,
}

impl Default for Compressor {
    fn default() -> Self {
        Self::new()
    }
}

impl Compressor {
    pub fn new() -> Self {
        let mut comp = Self {
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            makeup_gain_db: 0.0,
            wet_dry_mix: 1.0,
            envelope: 1.0, // Start at no gain reduction
            attack_coeff: 0.0,
            release_coeff: 0.0,
            sample_rate: TARGET_SAMPLE_RATE as f32,
        };
        comp.update_coefficients();
        comp
    }

    /// Update attack/release coefficients when parameters change
    pub fn update_coefficients(&mut self) {
        let sample_rate = self.sample_rate;
        // Clamp to a small positive min: 0 → -inf exponent, negative → coeff > 1 (blowup).
        let attack_ms = self.attack_ms.max(0.01);
        let release_ms = self.release_ms.max(0.01);
        self.attack_coeff = (-1.0 / (attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-1.0 / (release_ms * 0.001 * sample_rate)).exp();
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
            let gain_reduction_db = over_db * (1.0 - 1.0 / self.ratio.max(1.0));
            10_f32.powf(-gain_reduction_db / 20.0)
        }
    }
}

impl Effect for Compressor {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        // Calculate RMS level (stereo average)
        let level = f32::midpoint(left * left, right * right).sqrt();

        // Calculate target gain reduction
        let target_gain = self.calculate_gain_reduction(level);

        // Smooth gain reduction with attack/release
        if target_gain < self.envelope {
            // Attack (gain reduction increasing)
            self.envelope =
                self.attack_coeff * self.envelope + (1.0 - self.attack_coeff) * target_gain;
        } else {
            // Release (gain reduction decreasing)
            self.envelope =
                self.release_coeff * self.envelope + (1.0 - self.release_coeff) * target_gain;
        }

        // Apply gain reduction + makeup gain
        let makeup_gain = 10_f32.powf(self.makeup_gain_db / 20.0);
        let total_gain = self.envelope * makeup_gain;

        let comp_left = left * total_gain;
        let comp_right = right * total_gain;

        // Wet/dry blend
        let mix = self.wet_dry_mix;
        (
            left * (1.0 - mix) + comp_left * mix,
            right * (1.0 - mix) + comp_right * mix,
        )
    }

    fn reset(&mut self) {
        self.envelope = 1.0;
    }

    fn name(&self) -> &'static str {
        "Compressor"
    }

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            self.update_coefficients();
        }
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
    pub feedback: f32,    // 0.0 to 0.99
    pub wet_dry_mix: f32, // 0.0 = dry, 1.0 = wet

    // Buffers
    buffer_left: Vec<f32>,
    buffer_right: Vec<f32>,
    write_pos: usize,

    // Device sample rate — delay time in ms only maps to the right number of
    // samples if this matches the rate the stream actually runs at (C2).
    sample_rate: f32,
}

impl Default for Delay {
    fn default() -> Self {
        Self::new()
    }
}

impl Delay {
    /// Maximum delay time, which sizes the ring buffers.
    const MAX_DELAY_SECONDS: f32 = 2.0;

    pub fn new() -> Self {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let max_samples = (sample_rate * Self::MAX_DELAY_SECONDS) as usize;
        Self {
            delay_time_ms: 500.0,
            feedback: 0.4,
            wet_dry_mix: 0.3,
            buffer_left: vec![0.0; max_samples],
            buffer_right: vec![0.0; max_samples],
            write_pos: 0,
            sample_rate,
        }
    }

    fn get_delay_samples(&self) -> usize {
        ((self.delay_time_ms * 0.001 * self.sample_rate) as usize).min(self.buffer_left.len() - 1)
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

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            // Resize the ring buffers so MAX_DELAY_SECONDS still fits at the
            // new rate (C6 — at 96 kHz the old fixed buffer held only 1 s).
            let max_samples = (sample_rate * Self::MAX_DELAY_SECONDS) as usize;
            self.buffer_left = vec![0.0; max_samples];
            self.buffer_right = vec![0.0; max_samples];
            self.write_pos = 0;
        }
    }

    fn name(&self) -> &'static str {
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
    pub room_size: f32,   // 0.0 to 1.0
    pub damping: f32,     // 0.0 to 1.0
    pub wet_dry_mix: f32, // 0.0 = dry, 1.0 = wet

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

    // Device sample rate — the comb/allpass delay lengths are tuned in
    // samples-at-44.1kHz and must be rescaled to the real rate (C2/C9).
    sample_rate: f32,
}

impl Default for Reverb {
    fn default() -> Self {
        Self::new()
    }
}

impl Reverb {
    /// Freeverb comb filter lengths, in samples at 44.1 kHz.
    const COMB_LENGTHS_44K: [usize; 8] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
    /// Freeverb allpass filter lengths, in samples at 44.1 kHz.
    const ALLPASS_LENGTHS_44K: [usize; 4] = [556, 441, 341, 225];

    pub fn new() -> Self {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let (comb_buffers_l, comb_buffers_r, allpass_buffers_l, allpass_buffers_r) =
            Self::alloc_buffers(sample_rate);

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
            sample_rate,
        }
    }

    /// Allocate the comb/allpass delay lines for a device rate, scaling the
    /// canonical 44.1 kHz Freeverb tunings so the reverb's character (mode
    /// spacing, tail timing) is rate-independent.
    #[allow(clippy::type_complexity)]
    fn alloc_buffers(
        sample_rate: f32,
    ) -> (Vec<Vec<f32>>, Vec<Vec<f32>>, Vec<Vec<f32>>, Vec<Vec<f32>>) {
        let scale = sample_rate / 44100.0;

        let mut comb_buffers_l = Vec::new();
        let mut comb_buffers_r = Vec::new();
        for &len in &Self::COMB_LENGTHS_44K {
            let len = ((len as f32 * scale) as usize).max(1);
            comb_buffers_l.push(vec![0.0; len]);
            comb_buffers_r.push(vec![0.0; len + 23]); // Stereo spread
        }

        let mut allpass_buffers_l = Vec::new();
        let mut allpass_buffers_r = Vec::new();
        for &len in &Self::ALLPASS_LENGTHS_44K {
            let len = ((len as f32 * scale) as usize).max(1);
            allpass_buffers_l.push(vec![0.0; len]);
            allpass_buffers_r.push(vec![0.0; len + 11]); // Stereo spread
        }

        (
            comb_buffers_l,
            comb_buffers_r,
            allpass_buffers_l,
            allpass_buffers_r,
        )
    }

    fn process_comb(
        input: f32,
        feedback: f32,
        damp: f32,
        buffer: &mut [f32],
        pos: &mut usize,
        filter_state: &mut f32,
    ) -> f32 {
        let output = buffer[*pos];

        // One-pole lowpass in the feedback path (Freeverb damping).
        *filter_state = output * (1.0 - damp) + *filter_state * damp;

        buffer[*pos] = input + *filter_state * feedback;
        *pos = (*pos + 1) % buffer.len();

        output
    }

    fn process_allpass(input: f32, buffer: &mut [f32], pos: &mut usize) -> f32 {
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

        // Map the user-facing 0..1 controls to Freeverb's resonant ranges.
        // The comb feedback must sit in ~0.7..0.98 for the tail to build up;
        // feeding room_size in directly (≈0.5) made the reverb ~1000x too
        // quiet — effectively silent when used at 100% wet as a send effect.
        let feedback = self.room_size * 0.28 + 0.7;
        let damp = self.damping * 0.4;

        // Process comb filters (parallel) - separate positions for L and R
        let mut comb_out_l = 0.0;
        let mut comb_out_r = 0.0;
        for i in 0..8 {
            comb_out_l += Self::process_comb(
                mono_input,
                feedback,
                damp,
                &mut self.comb_buffers_l[i],
                &mut self.comb_positions_l[i],
                &mut self.comb_filter_state_l[i],
            );
            comb_out_r += Self::process_comb(
                mono_input,
                feedback,
                damp,
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

        // Mix wet/dry. WET_GAIN normalises the comb/allpass network's broadband
        // output so a 100%-wet reverb sits at a usable, present level. The old
        // value (0.015) left the wet signal ~36 dB down — effectively silent
        // when used as a 100%-wet send return.
        let wet_gain = 0.075_f32;
        let final_left = left * (1.0 - self.wet_dry_mix) + out_l * self.wet_dry_mix * wet_gain;
        let final_right = right * (1.0 - self.wet_dry_mix) + out_r * self.wet_dry_mix * wet_gain;

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

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            let (comb_l, comb_r, allpass_l, allpass_r) = Self::alloc_buffers(sample_rate);
            self.comb_buffers_l = comb_l;
            self.comb_buffers_r = comb_r;
            self.allpass_buffers_l = allpass_l;
            self.allpass_buffers_r = allpass_r;
            self.reset();
        }
    }

    fn name(&self) -> &'static str {
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
    pub wet_dry_mix: f32, // 0.0 = dry, 1.0 = wet

    envelope_left: f32,
    envelope_right: f32,
    release_coeff: f32,
    sample_rate: f32,
}

impl Default for Limiter {
    fn default() -> Self {
        Self::new()
    }
}

impl Limiter {
    pub fn new() -> Self {
        let mut limiter = Self {
            threshold_db: -0.1, // Just below 0 dBFS
            release_ms: 50.0,
            wet_dry_mix: 1.0,
            envelope_left: 0.0,
            envelope_right: 0.0,
            release_coeff: 0.0,
            sample_rate: TARGET_SAMPLE_RATE as f32,
        };
        limiter.update_coefficients();
        limiter
    }

    pub fn update_coefficients(&mut self) {
        let sample_rate = self.sample_rate;
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
            self.envelope_left *= self.release_coeff;
        }

        if right_abs > self.envelope_right {
            self.envelope_right = right_abs;
        } else {
            self.envelope_right *= self.release_coeff;
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

        let lim_left = left * gain;
        let lim_right = right * gain;

        // Wet/dry blend
        let mix = self.wet_dry_mix;
        (
            left * (1.0 - mix) + lim_left * mix,
            right * (1.0 - mix) + lim_right * mix,
        )
    }

    fn reset(&mut self) {
        self.envelope_left = 0.0;
        self.envelope_right = 0.0;
    }

    fn name(&self) -> &'static str {
        "Limiter"
    }

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            self.update_coefficients();
        }
    }
}

// ========================================================================
// CHORUS
// ========================================================================

/// Chorus effect (modulated delay)
#[derive(Clone)]
pub struct Chorus {
    pub rate_hz: f32, // LFO rate
    pub depth: f32,   // Modulation depth (0.0 to 1.0)
    pub wet_dry_mix: f32,

    // Delay buffers
    buffer_left: Vec<f32>,
    buffer_right: Vec<f32>,
    write_pos: usize,

    // LFO
    lfo_phase: f32,

    // Device sample rate — drives both the LFO phase increment and the
    // ms→samples mapping of the modulated delay (C9).
    sample_rate: f32,
}

impl Default for Chorus {
    fn default() -> Self {
        Self::new()
    }
}

impl Chorus {
    /// Maximum modulated delay time, which sizes the ring buffers.
    const MAX_DELAY_SECONDS: f32 = 0.05;

    pub fn new() -> Self {
        let sample_rate = TARGET_SAMPLE_RATE as f32;
        let max_samples = (sample_rate * Self::MAX_DELAY_SECONDS) as usize;
        Self {
            rate_hz: 1.5,
            depth: 0.5,
            wet_dry_mix: 0.5,
            buffer_left: vec![0.0; max_samples],
            buffer_right: vec![0.0; max_samples],
            write_pos: 0,
            lfo_phase: 0.0,
            sample_rate,
        }
    }
}

impl Effect for Chorus {
    fn process_frame(&mut self, left: f32, right: f32) -> (f32, f32) {
        let buffer_size = self.buffer_left.len();

        // LFO (sine wave)
        let lfo = (self.lfo_phase * 2.0 * PI).sin();
        self.lfo_phase += self.rate_hz / self.sample_rate;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= 1.0;
        }

        // Calculate delay time (5ms to 30ms)
        let base_delay_ms = 15.0;
        let delay_variation_ms = 10.0 * self.depth;
        let delay_ms = base_delay_ms + lfo * delay_variation_ms;
        let delay_samples = ((delay_ms * 0.001 * self.sample_rate) as usize).min(buffer_size - 1);

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

    fn set_sample_rate(&mut self, sample_rate: f32) {
        if sample_rate > 0.0 && (sample_rate - self.sample_rate).abs() > f32::EPSILON {
            self.sample_rate = sample_rate;
            let max_samples = ((sample_rate * Self::MAX_DELAY_SECONDS) as usize).max(1);
            self.buffer_left = vec![0.0; max_samples];
            self.buffer_right = vec![0.0; max_samples];
            self.write_pos = 0;
            self.lfo_phase = 0.0;
        }
    }

    fn name(&self) -> &'static str {
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
    VST3(crate::vst3_host::VST3Effect), // M7: VST3 plugin support (desktop only)
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

    /// Process a whole block of stereo frames in-place.
    ///
    /// Built-in effects fall through to the [`Effect`] trait's default
    /// `process_block` (a loop over `process_frame`), so their output is
    /// bit-identical to per-sample processing. `VST3Effect` overrides
    /// `process_block` to call the plugin once per buffer — the real win.
    pub fn process_block(&mut self, left: &mut [f32], right: &mut [f32]) {
        match self {
            EffectType::EQ(fx) => fx.process_block(left, right),
            EffectType::Compressor(fx) => fx.process_block(left, right),
            EffectType::Reverb(fx) => fx.process_block(left, right),
            EffectType::Delay(fx) => fx.process_block(left, right),
            EffectType::Limiter(fx) => fx.process_block(left, right),
            EffectType::Chorus(fx) => fx.process_block(left, right),
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            EffectType::VST3(fx) => fx.process_block(left, right),
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

    pub fn set_sample_rate(&mut self, sample_rate: f32) {
        match self {
            EffectType::EQ(fx) => fx.set_sample_rate(sample_rate),
            EffectType::Compressor(fx) => fx.set_sample_rate(sample_rate),
            EffectType::Reverb(fx) => fx.set_sample_rate(sample_rate),
            EffectType::Delay(fx) => fx.set_sample_rate(sample_rate),
            EffectType::Limiter(fx) => fx.set_sample_rate(sample_rate),
            EffectType::Chorus(fx) => fx.set_sample_rate(sample_rate),
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            EffectType::VST3(fx) => fx.set_sample_rate(sample_rate),
        }
    }
}

// ========================================================================
// EFFECT MANAGER
// ========================================================================

use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::Arc;

/// Effect manager: holds all effect instances
pub struct EffectManager {
    effects: HashMap<EffectId, Arc<Mutex<EffectType>>>,
    /// Bypass state per effect (true = bypassed, audio passes through unchanged)
    bypass_states: HashMap<EffectId, bool>,
    /// Per-effect output peak levels (linear 0.0+), written by audio thread
    peak_levels: HashMap<EffectId, (f32, f32)>,
    next_id: EffectId,
    /// Current device sample rate, applied to new effects and fanned out on change.
    sample_rate: f32,
}

impl Default for EffectManager {
    fn default() -> Self {
        Self::new()
    }
}

impl EffectManager {
    pub fn new() -> Self {
        Self {
            effects: HashMap::new(),
            bypass_states: HashMap::new(),
            peak_levels: HashMap::new(),
            next_id: 0,
            sample_rate: TARGET_SAMPLE_RATE as f32,
        }
    }

    /// Set the device sample rate and fan it out to every existing effect.
    /// Called by the renderer once the real stream rate is known.
    pub fn set_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        for effect in self.effects.values() {
            effect.lock().set_sample_rate(sample_rate);
        }
    }

    /// The sample rate the effects are currently configured for.
    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    /// Set the rate on built-in effects only, leaving VST3 plugins untouched.
    ///
    /// Used by the offline renderer to pin built-in DSP to the export rate
    /// (`TARGET_SAMPLE_RATE`) and restore the live stream rate afterwards.
    /// VST3 is excluded for the same reason `reset_builtin_fx_offline` skips
    /// it: a VST3 rate change is a full deactivate/reinitialize/activate
    /// cycle, far too heavy to fire twice per export (VST3 export fidelity is
    /// its own later cycle, C27–C30).
    pub fn set_builtin_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        for effect in self.effects.values() {
            let mut effect = effect.lock();
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            if matches!(*effect, EffectType::VST3(_)) {
                continue;
            }
            effect.set_sample_rate(sample_rate);
        }
    }

    /// Create a new effect and return its ID
    pub fn create_effect(&mut self, mut effect: EffectType) -> EffectId {
        let id = self.next_id;
        self.next_id += 1;

        eprintln!(
            "🎛️ [EffectManager] Created {} effect (ID: {})",
            effect.name(),
            id
        );

        // New effects inherit the current device rate so their coefficients are
        // correct even if the stream isn't running at TARGET_SAMPLE_RATE.
        effect.set_sample_rate(self.sample_rate);
        self.effects.insert(id, Arc::new(Mutex::new(effect)));
        self.bypass_states.insert(id, false); // Effects start not bypassed
        self.peak_levels.insert(id, (0.0, 0.0));
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
            self.peak_levels.remove(&id);
            eprintln!("🗑️ [EffectManager] Removed effect {id}");
            true
        } else {
            false
        }
    }

    /// Set bypass state for an effect
    pub fn set_bypass(&mut self, id: EffectId, bypassed: bool) -> bool {
        if self.effects.contains_key(&id) {
            self.bypass_states.insert(id, bypassed);
            eprintln!("🎛️ [EffectManager] Effect {id} bypass: {bypassed}");
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

    /// Update peak levels for an effect (called per-sample from audio thread).
    /// Accumulates the maximum level since last read.
    pub fn update_peaks(&mut self, id: EffectId, left: f32, right: f32) {
        let entry = self.peak_levels.entry(id).or_insert((0.0, 0.0));
        entry.0 = entry.0.max(left);
        entry.1 = entry.1.max(right);
    }

    /// Get peak levels for an effect as dB values, then reset for next poll.
    pub fn get_peak_db(&mut self, id: EffectId) -> (f32, f32) {
        let (left, right) = self.peak_levels.get(&id).copied().unwrap_or((0.0, 0.0));
        // Reset after reading so next poll gets fresh max
        self.peak_levels.insert(id, (0.0, 0.0));
        let left_db = if left > 0.0 {
            20.0 * left.log10()
        } else {
            -96.0
        };
        let right_db = if right > 0.0 {
            20.0 * right.log10()
        } else {
            -96.0
        };
        (left_db, right_db)
    }

    /// Get all effect IDs
    pub fn get_all_effect_ids(&self) -> Vec<EffectId> {
        self.effects.keys().copied().collect()
    }

    /// Duplicate an effect (deep copy with new ID)
    /// Returns new effect ID on success, None if source effect not found
    pub fn duplicate_effect(&mut self, source_effect_id: EffectId) -> Option<EffectId> {
        if let Some(source_effect_arc) = self.effects.get(&source_effect_id) {
            let source_effect = source_effect_arc.lock();

            // Clone the effect (deep copy)
            let cloned_effect = source_effect.clone();
            drop(source_effect); // Release lock

            // Create new effect with cloned data
            let new_id = self.next_id;
            self.next_id += 1;

            self.effects
                .insert(new_id, Arc::new(Mutex::new(cloned_effect)));
            eprintln!(
                "🎛️ [EffectManager] Duplicated effect {} → {} ({})",
                source_effect_id,
                new_id,
                self.effects.get(&new_id).unwrap().lock().name()
            );

            Some(new_id)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod effect_energy_tests {
    use super::*;

    /// Feed an effect 0.5 s of a 220 Hz sawtooth (amplitude 0.3) followed by
    /// 1.0 s of silence (to capture any tail), and return
    /// `(output_energy / input_energy, all_outputs_finite)`.
    ///
    /// This mirrors the send/return use case — a 100%-wet effect on a return
    /// bus must produce sane, audible, finite output. These are broad sanity
    /// guards, not a DSP spec: they catch the class of bug where an effect
    /// ships silent (the reverb was ~36 dB down / ratio ≈ 0.001 before its
    /// fix) or blows up, without asserting an exact frequency response.
    ///
    /// The sawtooth is harmonically rich (excites comb/allpass resonances far
    /// better than a pure sine), so it stresses the resonant effects too.
    fn wet_energy_ratio<E: Effect>(effect: &mut E) -> (f64, bool) {
        let mut in_energy = 0.0f64;
        let mut out_energy = 0.0f64;
        let mut all_finite = true;
        let note_frames = TARGET_SAMPLE_RATE as usize / 2; // 0.5 s
        let tail_frames = TARGET_SAMPLE_RATE as usize; // 1.0 s
        for i in 0..(note_frames + tail_frames) {
            let input = if i < note_frames {
                let phase = (i as f32 * 220.0 / TARGET_SAMPLE_RATE as f32).fract();
                (2.0 * phase - 1.0) * 0.3
            } else {
                0.0
            };
            in_energy += f64::from(input * input * 2.0); // stereo (L+R)
            let (l, r) = effect.process_frame(input, input);
            if !l.is_finite() || !r.is_finite() {
                all_finite = false;
            }
            out_energy += f64::from(l * l + r * r);
        }
        (out_energy / in_energy, all_finite)
    }

    #[test]
    fn reverb_full_wet_produces_comparable_output_energy() {
        // A 100%-wet reverb must return a substantial fraction of the energy it
        // receives, otherwise it is silent as a send return. Guards against the
        // regression where the wet output sat ~36 dB down (ratio ≈ 0.001).
        let mut rev = Reverb::new();
        rev.wet_dry_mix = 1.0;
        let (ratio, finite) = wet_energy_ratio(&mut rev);
        assert!(finite, "reverb produced non-finite output");
        assert!(
            ratio > 0.1,
            "reverb wet output too quiet to function as a send return (ratio={ratio:.4})"
        );
    }

    #[test]
    fn eq_flat_is_near_pass_through() {
        // A flat EQ (all bands at 0 dB) at full wet should pass the signal
        // through roughly unchanged — guards against a band mis-scaling the
        // level to silence or a blow-up.
        let mut eq = ParametricEQ::new();
        let (ratio, finite) = wet_energy_ratio(&mut eq);
        assert!(finite, "EQ produced non-finite output");
        assert!(
            (0.5..=1.5).contains(&ratio),
            "flat EQ should be near pass-through (ratio={ratio:.4})"
        );
    }

    #[test]
    fn eq_defaults_to_three_flat_bands() {
        let eq = ParametricEQ::new();
        assert_eq!(eq.band_count(), 3);
        let mut count = 0.0;
        eq.write_params(&mut |k, v| {
            if k == "band_count" {
                count = v;
            }
        });
        assert_eq!(count, 3.0);
    }

    #[test]
    fn eq_add_band_caps_at_max() {
        let mut eq = ParametricEQ::new(); // starts with 3
        for _ in 0..(MAX_EQ_BANDS - 3) {
            assert!(eq.add_band().is_some());
        }
        assert_eq!(eq.band_count(), MAX_EQ_BANDS);
        assert!(eq.add_band().is_none(), "should refuse a 9th band");
        assert_eq!(eq.band_count(), MAX_EQ_BANDS);
    }

    #[test]
    fn eq_remove_then_insert_restores_count() {
        let mut eq = ParametricEQ::new();
        let before = eq.band_count();
        assert!(eq.remove_band(1));
        assert_eq!(eq.band_count(), before - 1);
        assert!(!eq.remove_band(99), "out-of-range remove is a no-op");
        assert!(eq.insert_band(1));
        assert_eq!(eq.band_count(), before);
    }

    #[test]
    fn eq_params_round_trip() {
        let mut eq = ParametricEQ::new();
        eq.set_band_param(1, "gain", 6.0).unwrap();
        eq.set_band_param(1, "freq", 800.0).unwrap();
        eq.set_band_param(1, "focus", 0.8).unwrap();
        eq.set_low_cut(true);
        eq.set_output_gain(-3.0);

        let mut map = HashMap::new();
        eq.write_params(&mut |k, v| {
            map.insert(k.to_string(), v);
        });

        let mut eq2 = ParametricEQ::new();
        assert!(eq2.load_params(&|k| map.get(k).copied()));

        let mut map2 = HashMap::new();
        eq2.write_params(&mut |k, v| {
            map2.insert(k.to_string(), v);
        });
        assert_eq!(map, map2, "EQ state must round-trip through save/load");
    }

    #[test]
    fn eq_old_project_keeps_defaults() {
        // A param map without band_count (old 4-band project) → load_params
        // returns false and the EQ keeps its 3 flat defaults, never dropped.
        let mut eq = ParametricEQ::new();
        let old = HashMap::from([
            ("low_freq".to_string(), 120.0_f32),
            ("mid1_gain_db".to_string(), 4.0_f32),
        ]);
        assert!(!eq.load_params(&|k| old.get(k).copied()));
        assert_eq!(eq.band_count(), 3);
    }

    #[test]
    fn eq_low_cut_attenuates_low_frequency() {
        // With Low Cut on, a 40 Hz tone (an octave below the 80 Hz corner) must
        // come out quieter than it went in.
        let mut eq = ParametricEQ::new();
        eq.set_low_cut(true);
        let sr = TARGET_SAMPLE_RATE as f32;
        let n = TARGET_SAMPLE_RATE as usize;
        let mut in_e = 0.0f64;
        let mut out_e = 0.0f64;
        for i in 0..n {
            let s = (2.0 * PI * 40.0 * i as f32 / sr).sin() * 0.5;
            let (l, _r) = eq.process_frame(s, s);
            if i > n / 2 {
                // skip filter warm-up
                in_e += f64::from(s * s);
                out_e += f64::from(l * l);
            }
        }
        assert!(
            out_e < in_e * 0.6,
            "low cut should attenuate 40 Hz (in={in_e:.3}, out={out_e:.3})"
        );
    }

    #[test]
    fn compressor_reduces_but_preserves_energy() {
        // Default compressor (−20 dB threshold, 4:1) attenuates a 0.3-amplitude
        // sawtooth but must not crush it to silence or blow up.
        let mut comp = Compressor::new();
        comp.wet_dry_mix = 1.0;
        let (ratio, finite) = wet_energy_ratio(&mut comp);
        assert!(finite, "compressor produced non-finite output");
        assert!(
            (0.1..=1.2).contains(&ratio),
            "compressor output outside the sane range (ratio={ratio:.4})"
        );
    }

    #[test]
    fn delay_full_wet_is_audible() {
        // At 100% wet, the delay's output (delayed taps + feedback tail) must
        // carry real energy, not silence.
        let mut delay = Delay::new();
        delay.wet_dry_mix = 1.0;
        let (ratio, finite) = wet_energy_ratio(&mut delay);
        assert!(finite, "delay produced non-finite output");
        assert!(ratio > 0.1, "delay wet output too quiet (ratio={ratio:.4})");
    }

    #[test]
    fn limiter_below_threshold_is_pass_through() {
        // A 0.3-amplitude signal sits well under the −0.1 dBFS ceiling, so the
        // limiter should pass it through essentially untouched.
        let mut limiter = Limiter::new();
        limiter.wet_dry_mix = 1.0;
        let (ratio, finite) = wet_energy_ratio(&mut limiter);
        assert!(finite, "limiter produced non-finite output");
        assert!(
            (0.5..=1.5).contains(&ratio),
            "limiter should pass a sub-threshold signal through (ratio={ratio:.4})"
        );
    }

    #[test]
    fn chorus_full_wet_is_audible() {
        // Modulated delay shouldn't attenuate; at full wet the chorus must
        // produce substantial output energy.
        let mut chorus = Chorus::new();
        chorus.wet_dry_mix = 1.0;
        let (ratio, finite) = wet_energy_ratio(&mut chorus);
        assert!(finite, "chorus produced non-finite output");
        assert!(
            ratio > 0.1,
            "chorus wet output too quiet (ratio={ratio:.4})"
        );
    }
}

#[cfg(test)]
mod process_block_equivalence_tests {
    //! The per-buffer render path (PR C / #1) calls `Effect::process_block`
    //! once per buffer instead of `process_frame` per sample. For every
    //! built-in effect that relies on the trait's default `process_block` (a
    //! loop over `process_frame`), the two MUST produce bit-identical output —
    //! that is the safety property the whole render-loop rewrite leans on.
    //! These tests pin it so a future override of a built-in's `process_block`
    //! can't silently diverge per-sample vs per-buffer behaviour.
    //!
    //! (VST3 deliberately overrides `process_block` with a real per-buffer
    //! call and is not — cannot be — covered here; it's validated by listening.)
    #![allow(clippy::float_cmp)]
    use super::*;

    /// A harmonically rich, deterministic stereo test signal: a 220 Hz sawtooth
    /// in the left channel and a 330 Hz sawtooth in the right, so left ≠ right
    /// (a bug that collapses channels would show up).
    fn make_signal(len: usize) -> (Vec<f32>, Vec<f32>) {
        let mut l = Vec::with_capacity(len);
        let mut r = Vec::with_capacity(len);
        for i in 0..len {
            let pl = (i as f32 * 220.0 / TARGET_SAMPLE_RATE as f32).fract();
            let pr = (i as f32 * 330.0 / TARGET_SAMPLE_RATE as f32).fract();
            l.push((2.0 * pl - 1.0) * 0.3);
            r.push((2.0 * pr - 1.0) * 0.3);
        }
        (l, r)
    }

    /// Assert that running `effect` over a whole buffer via `process_block`
    /// matches a fresh, identically-constructed effect run sample-by-sample.
    fn assert_block_matches_frames<E: Effect>(mut block_fx: E, mut frame_fx: E) {
        // Span several typical buffer sizes incl. the 512 max VST3 block.
        let len = 1024;
        let (in_l, in_r) = make_signal(len);

        let mut block_l = in_l.clone();
        let mut block_r = in_r.clone();
        block_fx.process_block(&mut block_l, &mut block_r);

        for i in 0..len {
            let (fl, fr) = frame_fx.process_frame(in_l[i], in_r[i]);
            assert_eq!(
                block_l[i],
                fl,
                "{} L diverged at sample {i}: block={} frame={fl}",
                block_fx.name(),
                block_l[i]
            );
            assert_eq!(
                block_r[i],
                fr,
                "{} R diverged at sample {i}: block={} frame={fr}",
                block_fx.name(),
                block_r[i]
            );
        }
    }

    #[test]
    fn eq_block_matches_frames() {
        assert_block_matches_frames(ParametricEQ::new(), ParametricEQ::new());
    }

    #[test]
    fn compressor_block_matches_frames() {
        assert_block_matches_frames(Compressor::new(), Compressor::new());
    }

    #[test]
    fn reverb_block_matches_frames() {
        assert_block_matches_frames(Reverb::new(), Reverb::new());
    }

    #[test]
    fn delay_block_matches_frames() {
        assert_block_matches_frames(Delay::new(), Delay::new());
    }

    #[test]
    fn limiter_block_matches_frames() {
        assert_block_matches_frames(Limiter::new(), Limiter::new());
    }

    #[test]
    fn chorus_block_matches_frames() {
        assert_block_matches_frames(Chorus::new(), Chorus::new());
    }
}

#[cfg(test)]
mod sample_rate_tests {
    //! v0.5.2 P8 (C2/C6/C9): time-based effects must track the device rate.
    //! The renderer fans the real stream rate out via
    //! `EffectManager::set_sample_rate`; before P8 the Delay/Chorus/Reverb
    //! implementations inherited the no-op trait default, so a 500 ms delay
    //! on a 44.1 kHz stream measured ~544 ms.
    // The compared rates are exact assignments (no arithmetic), so equality
    // is the intended assertion.
    #![allow(clippy::float_cmp)]
    use super::*;

    /// Feed an impulse and return the index of the first sample whose
    /// magnitude exceeds `threshold`, scanning up to `max_len` frames.
    fn first_audible_frame<E: Effect>(fx: &mut E, max_len: usize, threshold: f32) -> Option<usize> {
        for i in 0..max_len {
            let input = if i == 0 { 1.0 } else { 0.0 };
            let (l, _r) = fx.process_frame(input, input);
            if l.abs() > threshold {
                return Some(i);
            }
        }
        None
    }

    #[test]
    fn delay_time_tracks_device_rate() {
        // 100% wet, no feedback: the impulse re-emerges exactly one delay
        // time later. 500 ms must be 24000 frames at 48 kHz and 22050 at
        // 44.1 kHz — the same wall-clock time on both devices (C2).
        for (rate, expected) in [(48_000.0_f32, 24_000_usize), (44_100.0, 22_050)] {
            let mut delay = Delay::new();
            delay.set_sample_rate(rate);
            delay.wet_dry_mix = 1.0;
            delay.feedback = 0.0;
            let got = first_audible_frame(&mut delay, 30_000, 0.5)
                .unwrap_or_else(|| panic!("no echo at {rate} Hz"));
            assert_eq!(got, expected, "500 ms delay at {rate} Hz");
        }
    }

    #[test]
    fn delay_buffer_grows_for_high_rates() {
        // At 96 kHz the old fixed 96000-sample buffer held only 1 s — a
        // 1500 ms delay read wrapped garbage (C6). The buffer must resize so
        // the full 2 s range still fits.
        let mut delay = Delay::new();
        delay.set_sample_rate(96_000.0);
        delay.delay_time_ms = 1500.0;
        delay.wet_dry_mix = 1.0;
        delay.feedback = 0.0;
        let got = first_audible_frame(&mut delay, 150_000, 0.5).expect("no echo at 96 kHz");
        assert_eq!(got, 144_000, "1500 ms delay at 96 kHz");
    }

    #[test]
    fn chorus_center_delay_tracks_device_rate() {
        // depth = 0 pins the modulated delay at its 15 ms centre, so the
        // wet impulse re-emerges 15 ms later regardless of device rate (C9).
        for (rate, expected) in [(48_000.0_f32, 720_usize), (44_100.0, 661)] {
            let mut chorus = Chorus::new();
            chorus.set_sample_rate(rate);
            chorus.depth = 0.0;
            chorus.wet_dry_mix = 1.0;
            let got = first_audible_frame(&mut chorus, 2_000, 0.5)
                .unwrap_or_else(|| panic!("no wet output at {rate} Hz"));
            assert_eq!(got, expected, "15 ms chorus centre delay at {rate} Hz");
        }
    }

    #[test]
    fn reverb_rescales_and_stays_safe_across_rate_changes() {
        // The comb/allpass delay lines are retuned per rate. Shrinking the
        // buffers (48 kHz → 44.1 kHz) must also reset the write positions —
        // stale positions would index out of bounds and panic.
        let impulse_response = |rev: &mut Reverb| -> Vec<f32> {
            (0..4_000)
                .map(|i| {
                    let input = if i == 0 { 1.0 } else { 0.0 };
                    rev.process_frame(input, input).0
                })
                .collect()
        };

        let mut rev = Reverb::new();
        rev.wet_dry_mix = 1.0;
        let at_48k = impulse_response(&mut rev);

        rev.set_sample_rate(44_100.0); // shrink
        let at_44k = impulse_response(&mut rev);
        assert!(at_44k.iter().all(|s| s.is_finite()));
        assert_ne!(at_48k, at_44k, "rate change must retune the delay lines");

        rev.set_sample_rate(96_000.0); // grow — and survive more processing
        let at_96k = impulse_response(&mut rev);
        assert!(at_96k.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn effect_manager_builtin_rate_roundtrip() {
        // The offline renderer pins built-ins to TARGET_SAMPLE_RATE and
        // restores the live rate afterwards — the stored rate must follow.
        let mut mgr = EffectManager::new();
        assert_eq!(mgr.sample_rate(), TARGET_SAMPLE_RATE as f32);
        mgr.set_builtin_sample_rate(44_100.0);
        assert_eq!(mgr.sample_rate(), 44_100.0);
        mgr.set_builtin_sample_rate(TARGET_SAMPLE_RATE as f32);
        assert_eq!(mgr.sample_rate(), TARGET_SAMPLE_RATE as f32);
    }
}
