//! Sample rate conversion using the rubato crate
//!
//! Provides high-quality resampling for converting between sample rates,
//! primarily 48kHz to 44.1kHz for CD-quality exports.

use rubato::{FftFixedInOut, Resampler};

/// Resample stereo audio from one sample rate to another
///
/// # Arguments
/// * `samples` - Input samples (stereo interleaved, -1.0 to 1.0)
/// * `from_rate` - Source sample rate in Hz
/// * `to_rate` - Target sample rate in Hz
///
/// # Returns
/// Resampled audio (stereo interleaved)
pub fn resample_stereo(samples: &[f32], from_rate: u32, to_rate: u32) -> Result<Vec<f32>, String> {
    // No conversion needed if rates match
    if from_rate == to_rate {
        return Ok(samples.to_vec());
    }

    eprintln!(
        "🔄 [Resample] Converting {}Hz → {}Hz ({} samples)",
        from_rate,
        to_rate,
        samples.len()
    );

    // Deinterleave stereo to separate channels
    let num_frames = samples.len() / 2;
    let mut left = Vec::with_capacity(num_frames);
    let mut right = Vec::with_capacity(num_frames);

    for i in 0..num_frames {
        left.push(samples[i * 2] as f64);
        right.push(samples[i * 2 + 1] as f64);
    }

    // Create resampler
    // FftFixedInOut provides high quality with fixed input/output chunk sizes
    let chunk_size = 1024;
    let mut resampler = FftFixedInOut::<f64>::new(
        from_rate as usize,
        to_rate as usize,
        chunk_size,
        2, // stereo
    )
    .map_err(|e| format!("Failed to create resampler: {}", e))?;

    // Calculate output size
    let output_frames = ((num_frames as f64 * to_rate as f64) / from_rate as f64).ceil() as usize;
    let mut output_left = Vec::with_capacity(output_frames);
    let mut output_right = Vec::with_capacity(output_frames);

    // Process in chunks
    let frames_needed = resampler.input_frames_next();
    let mut pos = 0;

    while pos + frames_needed <= num_frames {
        let input_chunk = vec![
            left[pos..pos + frames_needed].to_vec(),
            right[pos..pos + frames_needed].to_vec(),
        ];

        let output_chunk = resampler
            .process(&input_chunk, None)
            .map_err(|e| format!("Resampling error: {}", e))?;

        output_left.extend_from_slice(&output_chunk[0]);
        output_right.extend_from_slice(&output_chunk[1]);

        pos += frames_needed;
    }

    // Process remaining samples with padding
    if pos < num_frames {
        let remaining = num_frames - pos;
        let mut padded_left = left[pos..].to_vec();
        let mut padded_right = right[pos..].to_vec();

        // Pad with zeros to fill chunk
        padded_left.resize(frames_needed, 0.0);
        padded_right.resize(frames_needed, 0.0);

        let input_chunk = vec![padded_left, padded_right];

        let output_chunk = resampler
            .process(&input_chunk, None)
            .map_err(|e| format!("Resampling error: {}", e))?;

        // Only take the samples we need (proportional to remaining input)
        let output_needed = ((remaining as f64 * to_rate as f64) / from_rate as f64).ceil() as usize;
        let take_count = output_needed.min(output_chunk[0].len());

        output_left.extend_from_slice(&output_chunk[0][..take_count]);
        output_right.extend_from_slice(&output_chunk[1][..take_count]);
    }

    // Interleave back to stereo
    let output_len = output_left.len().min(output_right.len());
    let mut output = Vec::with_capacity(output_len * 2);

    for i in 0..output_len {
        output.push(output_left[i] as f32);
        output.push(output_right[i] as f32);
    }

    eprintln!(
        "✅ [Resample] Converted {} → {} samples",
        samples.len(),
        output.len()
    );

    Ok(output)
}

/// Resample mono audio from one sample rate to another
///
/// # Arguments
/// * `samples` - Input samples (mono, -1.0 to 1.0)
/// * `from_rate` - Source sample rate in Hz
/// * `to_rate` - Target sample rate in Hz
///
/// # Returns
/// Resampled audio (mono)
pub fn resample_mono(samples: &[f32], from_rate: u32, to_rate: u32) -> Result<Vec<f32>, String> {
    // No conversion needed if rates match
    if from_rate == to_rate {
        return Ok(samples.to_vec());
    }

    // Convert to f64 for rubato
    let input: Vec<f64> = samples.iter().map(|&s| s as f64).collect();

    // Create resampler
    let chunk_size = 1024;
    let mut resampler = FftFixedInOut::<f64>::new(
        from_rate as usize,
        to_rate as usize,
        chunk_size,
        1, // mono
    )
    .map_err(|e| format!("Failed to create resampler: {}", e))?;

    // Calculate output size
    let output_frames = ((samples.len() as f64 * to_rate as f64) / from_rate as f64).ceil() as usize;
    let mut output = Vec::with_capacity(output_frames);

    // Process in chunks
    let frames_needed = resampler.input_frames_next();
    let mut pos = 0;

    while pos + frames_needed <= samples.len() {
        let input_chunk = vec![input[pos..pos + frames_needed].to_vec()];

        let output_chunk = resampler
            .process(&input_chunk, None)
            .map_err(|e| format!("Resampling error: {}", e))?;

        output.extend(output_chunk[0].iter().map(|&s| s as f32));

        pos += frames_needed;
    }

    // Process remaining samples with padding
    if pos < samples.len() {
        let remaining = samples.len() - pos;
        let mut padded = input[pos..].to_vec();
        padded.resize(frames_needed, 0.0);

        let input_chunk = vec![padded];

        let output_chunk = resampler
            .process(&input_chunk, None)
            .map_err(|e| format!("Resampling error: {}", e))?;

        // Only take the samples we need
        let output_needed = ((remaining as f64 * to_rate as f64) / from_rate as f64).ceil() as usize;
        let take_count = output_needed.min(output_chunk[0].len());

        output.extend(output_chunk[0][..take_count].iter().map(|&s| s as f32));
    }

    Ok(output)
}

/// Mix stereo to mono (average of left and right)
///
/// # Arguments
/// * `samples` - Stereo interleaved samples
///
/// # Returns
/// Mono samples (half the length)
pub fn stereo_to_mono(samples: &[f32]) -> Vec<f32> {
    let num_frames = samples.len() / 2;
    let mut mono = Vec::with_capacity(num_frames);

    for i in 0..num_frames {
        let left = samples[i * 2];
        let right = samples[i * 2 + 1];
        mono.push((left + right) * 0.5);
    }

    mono
}

/// Convert mono to stereo (duplicate to both channels)
///
/// # Arguments
/// * `samples` - Mono samples
///
/// # Returns
/// Stereo interleaved samples (double the length)
pub fn mono_to_stereo(samples: &[f32]) -> Vec<f32> {
    let mut stereo = Vec::with_capacity(samples.len() * 2);

    for &sample in samples {
        stereo.push(sample);
        stereo.push(sample);
    }

    stereo
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stereo_to_mono() {
        let stereo = vec![0.5f32, 0.3, 0.8, 0.2, 0.0, 0.0];
        let mono = stereo_to_mono(&stereo);

        assert_eq!(mono.len(), 3);
        assert!((mono[0] - 0.4).abs() < 0.001); // (0.5 + 0.3) / 2
        assert!((mono[1] - 0.5).abs() < 0.001); // (0.8 + 0.2) / 2
        assert!((mono[2] - 0.0).abs() < 0.001);
    }

    #[test]
    fn test_mono_to_stereo() {
        let mono = vec![0.5f32, 0.3, 0.8];
        let stereo = mono_to_stereo(&mono);

        assert_eq!(stereo.len(), 6);
        assert_eq!(stereo[0], 0.5);
        assert_eq!(stereo[1], 0.5);
        assert_eq!(stereo[2], 0.3);
        assert_eq!(stereo[3], 0.3);
    }

    #[test]
    fn test_same_rate_passthrough() {
        let samples = vec![0.1f32, 0.2, 0.3, 0.4];
        let result = resample_stereo(&samples, 48000, 48000).unwrap();
        assert_eq!(result, samples);
    }

    #[test]
    fn test_48k_to_44k_basic() {
        // Create a simple stereo test signal (1 second at 48kHz)
        let num_frames = 48000;
        let mut samples = Vec::with_capacity(num_frames * 2);
        for i in 0..num_frames {
            let t = i as f32 / 48000.0;
            let val = (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
            samples.push(val); // Left
            samples.push(val); // Right
        }

        let result = resample_stereo(&samples, 48000, 44100).unwrap();

        // Check output length is approximately correct
        // 48000 samples at 48kHz → should be ~44100 samples at 44.1kHz
        let expected_frames = ((num_frames as f64 * 44100.0) / 48000.0) as usize;
        let actual_frames = result.len() / 2;

        // Allow 1% tolerance due to chunk processing
        assert!(
            (actual_frames as i64 - expected_frames as i64).abs() < (expected_frames as i64 / 100),
            "Expected ~{} frames, got {}",
            expected_frames,
            actual_frames
        );
    }
}
