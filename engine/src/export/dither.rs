//! Dithering algorithms for bit depth reduction
//!
//! Implements TPDF (Triangular Probability Density Function) dithering
//! to reduce quantization distortion when converting to lower bit depths.

use std::sync::atomic::{AtomicU64, Ordering};

/// LFSR-based pseudo-random number generator for dithering
/// Uses a 64-bit LFSR for high-quality random noise
struct DitherRng {
    state: AtomicU64,
}

impl DitherRng {
    /// Create a new RNG with the given seed
    fn new(seed: u64) -> Self {
        Self {
            state: AtomicU64::new(if seed == 0 { 0xDEADBEEF } else { seed }),
        }
    }

    /// Generate next random value (0.0 to 1.0)
    fn next_f32(&self) -> f32 {
        // LFSR with taps at 64, 63, 61, 60 (maximal period)
        let mut state = self.state.load(Ordering::Relaxed);
        let bit = ((state >> 63) ^ (state >> 62) ^ (state >> 60) ^ (state >> 59)) & 1;
        state = (state << 1) | bit;
        self.state.store(state, Ordering::Relaxed);

        // Convert to 0.0-1.0 range
        (state & 0xFFFFFF) as f32 / 0xFFFFFF as f32
    }

    /// Generate TPDF noise (-1.0 to 1.0, triangular distribution)
    fn next_tpdf(&self) -> f32 {
        // Sum of two uniform distributions creates triangular distribution
        let r1 = self.next_f32();
        let r2 = self.next_f32();
        r1 - r2  // Range: -1.0 to 1.0, peak at 0
    }
}

/// Apply TPDF dithering to a single sample for 16-bit conversion
///
/// # Arguments
/// * `sample` - Input sample (-1.0 to 1.0)
/// * `dither_noise` - Pre-generated TPDF noise value (-1.0 to 1.0)
///
/// # Returns
/// Dithered and quantized 16-bit sample
pub fn dither_to_16bit(sample: f32, dither_noise: f32) -> i16 {
    // 16-bit range: -32768 to 32767
    // 1 LSB = 1/32768 = 0.0000305
    const LSB: f32 = 1.0 / 32768.0;

    // Scale sample to 16-bit range and add dither
    let scaled = sample * 32767.0;
    let dithered = scaled + dither_noise * LSB * 32767.0;

    // Quantize and clamp
    dithered.round().clamp(-32768.0, 32767.0) as i16
}

/// Apply TPDF dithering to a single sample for 24-bit conversion
///
/// # Arguments
/// * `sample` - Input sample (-1.0 to 1.0)
/// * `dither_noise` - Pre-generated TPDF noise value (-1.0 to 1.0)
///
/// # Returns
/// Dithered and quantized 24-bit sample as i32 (lower 24 bits used)
pub fn dither_to_24bit(sample: f32, dither_noise: f32) -> i32 {
    // 24-bit range: -8388608 to 8388607
    // 1 LSB = 1/8388608
    const LSB: f32 = 1.0 / 8388608.0;

    // Scale sample to 24-bit range and add dither
    let scaled = sample * 8388607.0;
    let dithered = scaled + dither_noise * LSB * 8388607.0;

    // Quantize and clamp
    dithered.round().clamp(-8388608.0, 8388607.0) as i32
}

/// Convert 32-bit float samples to 16-bit with optional dithering
///
/// # Arguments
/// * `samples` - Input samples (stereo interleaved, -1.0 to 1.0)
/// * `apply_dither` - Whether to apply TPDF dithering
///
/// # Returns
/// 16-bit samples (stereo interleaved)
pub fn convert_to_16bit(samples: &[f32], apply_dither: bool) -> Vec<i16> {
    let rng = DitherRng::new(0x12345678);

    samples
        .iter()
        .map(|&sample| {
            if apply_dither {
                dither_to_16bit(sample, rng.next_tpdf())
            } else {
                // Simple quantization without dither
                (sample * 32767.0).round().clamp(-32768.0, 32767.0) as i16
            }
        })
        .collect()
}

/// Convert 32-bit float samples to 24-bit with optional dithering
///
/// # Arguments
/// * `samples` - Input samples (stereo interleaved, -1.0 to 1.0)
/// * `apply_dither` - Whether to apply TPDF dithering
///
/// # Returns
/// 24-bit samples as i32 (stereo interleaved, lower 24 bits used)
pub fn convert_to_24bit(samples: &[f32], apply_dither: bool) -> Vec<i32> {
    let rng = DitherRng::new(0x87654321);

    samples
        .iter()
        .map(|&sample| {
            if apply_dither {
                dither_to_24bit(sample, rng.next_tpdf())
            } else {
                // Simple quantization without dither
                (sample * 8388607.0).round().clamp(-8388608.0, 8388607.0) as i32
            }
        })
        .collect()
}

/// Pack 24-bit samples into bytes (little-endian, 3 bytes per sample)
///
/// # Arguments
/// * `samples` - 24-bit samples as i32
///
/// # Returns
/// Packed bytes (3 bytes per sample)
pub fn pack_24bit_to_bytes(samples: &[i32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(samples.len() * 3);

    for &sample in samples {
        // Little-endian: LSB first
        bytes.push((sample & 0xFF) as u8);
        bytes.push(((sample >> 8) & 0xFF) as u8);
        bytes.push(((sample >> 16) & 0xFF) as u8);
    }

    bytes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_16bit_range() {
        // Test full scale positive
        let result = dither_to_16bit(1.0, 0.0);
        assert_eq!(result, 32767);

        // Test full scale negative
        let result = dither_to_16bit(-1.0, 0.0);
        assert_eq!(result, -32767);

        // Test silence
        let result = dither_to_16bit(0.0, 0.0);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_24bit_range() {
        // Test full scale positive
        let result = dither_to_24bit(1.0, 0.0);
        assert_eq!(result, 8388607);

        // Test full scale negative
        let result = dither_to_24bit(-1.0, 0.0);
        assert_eq!(result, -8388607);

        // Test silence
        let result = dither_to_24bit(0.0, 0.0);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_dither_rng() {
        let rng = DitherRng::new(12345);

        // Generate some values and check they're in range
        for _ in 0..100 {
            let val = rng.next_tpdf();
            assert!(val >= -1.0 && val <= 1.0);
        }
    }

    #[test]
    fn test_24bit_packing() {
        let samples = vec![0x123456i32, -1i32];
        let bytes = pack_24bit_to_bytes(&samples);

        // First sample: 0x123456 -> [0x56, 0x34, 0x12]
        assert_eq!(bytes[0], 0x56);
        assert_eq!(bytes[1], 0x34);
        assert_eq!(bytes[2], 0x12);

        // Second sample: -1 -> [0xFF, 0xFF, 0xFF]
        assert_eq!(bytes[3], 0xFF);
        assert_eq!(bytes[4], 0xFF);
        assert_eq!(bytes[5], 0xFF);
    }

    #[test]
    fn test_batch_conversion() {
        let samples = vec![0.5f32, -0.5, 0.0, 1.0, -1.0];

        // 16-bit without dither
        let i16_samples = convert_to_16bit(&samples, false);
        assert_eq!(i16_samples.len(), 5);
        assert_eq!(i16_samples[2], 0); // Silence

        // 24-bit without dither
        let i24_samples = convert_to_24bit(&samples, false);
        assert_eq!(i24_samples.len(), 5);
        assert_eq!(i24_samples[2], 0); // Silence
    }
}
