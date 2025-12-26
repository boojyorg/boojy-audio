//! Audio normalization algorithms
//!
//! Provides peak normalization and LUFS-based loudness normalization
//! for mastering and platform-specific export.

/// Peak normalize audio to a target amplitude
///
/// # Arguments
/// * `samples` - Audio samples (modified in place)
/// * `target_db` - Target peak level in dB (e.g., -0.1 for -0.1 dBFS)
///
/// # Returns
/// The gain applied (linear scale)
pub fn normalize_peak(samples: &mut [f32], target_db: f32) -> f32 {
    // Find peak amplitude
    let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, |a, b| a.max(b));

    if peak <= 0.0 {
        eprintln!("⚠️ [Normalize] No audio content (peak = 0)");
        return 1.0;
    }

    // Convert target dB to linear
    let target_amplitude = 10.0f32.powf(target_db / 20.0);

    // Calculate and apply gain
    let gain = target_amplitude / peak;

    eprintln!(
        "📊 [Normalize] Peak: {:.4} ({:.1} dB), Target: {:.4} ({:.1} dB), Gain: {:.4}",
        peak,
        20.0 * peak.log10(),
        target_amplitude,
        target_db,
        gain
    );

    for sample in samples.iter_mut() {
        *sample *= gain;
    }

    gain
}

/// Calculate RMS (Root Mean Square) level of audio
///
/// # Arguments
/// * `samples` - Audio samples
///
/// # Returns
/// RMS amplitude (0.0 to ~1.0)
pub fn calculate_rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }

    let sum_squares: f64 = samples.iter().map(|&s| (s as f64) * (s as f64)).sum();
    (sum_squares / samples.len() as f64).sqrt() as f32
}

/// Calculate integrated loudness using a simplified LUFS algorithm
///
/// This is a simplified implementation of ITU-R BS.1770-4.
/// For production use, consider using a dedicated loudness library.
///
/// # Arguments
/// * `samples` - Stereo interleaved audio samples
/// * `sample_rate` - Sample rate in Hz
///
/// # Returns
/// Integrated loudness in LUFS
pub fn calculate_lufs(samples: &[f32], sample_rate: u32) -> f64 {
    if samples.is_empty() {
        return -70.0; // Return very quiet value for empty audio
    }

    // Deinterleave stereo
    let num_frames = samples.len() / 2;
    let mut left: Vec<f64> = Vec::with_capacity(num_frames);
    let mut right: Vec<f64> = Vec::with_capacity(num_frames);

    for i in 0..num_frames {
        left.push(samples[i * 2] as f64);
        right.push(samples[i * 2 + 1] as f64);
    }

    // Apply K-weighting filter (simplified: just high-shelf boost)
    // A proper implementation would use the exact filter coefficients from BS.1770
    let left_filtered = apply_k_weighting(&left, sample_rate);
    let right_filtered = apply_k_weighting(&right, sample_rate);

    // Calculate mean square for each channel
    let left_ms: f64 = left_filtered.iter().map(|&s| s * s).sum::<f64>() / left_filtered.len() as f64;
    let right_ms: f64 = right_filtered.iter().map(|&s| s * s).sum::<f64>() / right_filtered.len() as f64;

    // Combine channels (no weighting for L/R, 1.0 each per BS.1770)
    let combined_ms = left_ms + right_ms;

    // Convert to LUFS
    // LUFS = -0.691 + 10 * log10(mean_square)
    if combined_ms > 0.0 {
        -0.691 + 10.0 * combined_ms.log10()
    } else {
        -70.0 // Very quiet
    }
}

/// Apply simplified K-weighting filter
///
/// K-weighting consists of:
/// 1. High-shelf filter (boost high frequencies)
/// 2. High-pass filter (reduce low frequencies)
///
/// This is a simplified single-pole approximation.
fn apply_k_weighting(samples: &[f64], sample_rate: u32) -> Vec<f64> {
    let mut output = Vec::with_capacity(samples.len());

    // Simple high-shelf boost approximation
    // Real K-weighting uses specific biquad filters from ITU-R BS.1770
    let alpha = 0.98; // High-pass coefficient

    let mut prev_input = 0.0;
    let mut prev_output = 0.0;

    for &sample in samples {
        // Simple high-pass filter (removes DC and low bass)
        let high_passed = alpha * (prev_output + sample - prev_input);
        prev_input = sample;
        prev_output = high_passed;

        // Apply slight high-frequency boost (simplified K-weighting character)
        // Real implementation would use the exact shelf filter from BS.1770
        let _ = sample_rate; // Acknowledge parameter (would be used for exact coefficients)
        output.push(high_passed * 1.05); // ~+0.4 dB boost approximation
    }

    output
}

/// Normalize audio to target LUFS
///
/// # Arguments
/// * `samples` - Stereo interleaved audio samples (modified in place)
/// * `sample_rate` - Sample rate in Hz
/// * `target_lufs` - Target loudness in LUFS (e.g., -14.0 for Spotify)
///
/// # Returns
/// The gain applied in dB
pub fn normalize_lufs(samples: &mut [f32], sample_rate: u32, target_lufs: f64) -> f64 {
    let current_lufs = calculate_lufs(samples, sample_rate);

    if current_lufs < -60.0 {
        eprintln!("⚠️ [LUFS] Audio too quiet to measure ({:.1} LUFS)", current_lufs);
        return 0.0;
    }

    let gain_db = target_lufs - current_lufs;
    let gain_linear = 10.0f64.powf(gain_db / 20.0) as f32;

    eprintln!(
        "📊 [LUFS] Current: {:.1} LUFS, Target: {:.1} LUFS, Gain: {:.1} dB",
        current_lufs, target_lufs, gain_db
    );

    // Apply gain
    for sample in samples.iter_mut() {
        *sample *= gain_linear;
    }

    // Check for clipping and apply limiter if needed
    let peak_after: f32 = samples.iter().map(|s| s.abs()).fold(0.0f32, |a, b| a.max(b));

    if peak_after > 1.0 {
        eprintln!(
            "⚠️ [LUFS] Clipping detected (peak {:.2}), applying limiter",
            peak_after
        );

        // Simple soft-clipping limiter
        for sample in samples.iter_mut() {
            if *sample > 0.99 {
                *sample = 0.99 + (*sample - 0.99).tanh() * 0.01;
            } else if *sample < -0.99 {
                *sample = -0.99 + (*sample + 0.99).tanh() * 0.01;
            }
        }
    }

    gain_db
}

/// Apply a simple soft limiter to prevent clipping
///
/// # Arguments
/// * `samples` - Audio samples (modified in place)
/// * `threshold_db` - Threshold in dB (e.g., -0.1)
pub fn apply_limiter(samples: &mut [f32], threshold_db: f32) {
    let threshold = 10.0f32.powf(threshold_db / 20.0);

    for sample in samples.iter_mut() {
        let abs_sample = sample.abs();
        if abs_sample > threshold {
            // Soft clip using tanh
            let sign = sample.signum();
            let excess = abs_sample - threshold;
            *sample = sign * (threshold + excess.tanh() * (1.0 - threshold));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_peak_normalize() {
        let mut samples = vec![0.5f32, -0.3, 0.8, -0.8];

        let gain = normalize_peak(&mut samples, -0.1);

        // Peak was 0.8, target is ~0.989, so gain should be ~1.236
        assert!(gain > 1.0);

        // Check new peak is at target
        let new_peak = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        assert!((new_peak - 0.989).abs() < 0.01);
    }

    #[test]
    fn test_rms_calculation() {
        // Constant signal should have RMS equal to amplitude
        let samples = vec![0.5f32; 1000];
        let rms = calculate_rms(&samples);
        assert!((rms - 0.5).abs() < 0.01);

        // Silence should have 0 RMS
        let silence = vec![0.0f32; 1000];
        let rms_silence = calculate_rms(&silence);
        assert!(rms_silence.abs() < 0.001);
    }

    #[test]
    fn test_lufs_calculation() {
        // Generate a 1-second stereo sine wave at -20 dBFS
        let sample_rate = 48000u32;
        let amplitude = 0.1f32; // ~-20 dBFS

        let mut samples = Vec::with_capacity(sample_rate as usize * 2);
        for i in 0..sample_rate {
            let t = i as f32 / sample_rate as f32;
            let val = amplitude * (t * 1000.0 * 2.0 * std::f32::consts::PI).sin();
            samples.push(val); // Left
            samples.push(val); // Right
        }

        let lufs = calculate_lufs(&samples, sample_rate);

        // Should be approximately -20 LUFS (simplified algorithm may differ slightly)
        assert!(lufs < -10.0);
        assert!(lufs > -40.0);
    }

    #[test]
    fn test_limiter() {
        let mut samples = vec![1.5f32, -1.2, 0.5, 0.8];

        apply_limiter(&mut samples, -0.1);

        // All samples should now be <= 1.0
        for sample in &samples {
            assert!(sample.abs() <= 1.0);
        }
    }
}
