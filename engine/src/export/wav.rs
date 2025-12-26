//! WAV file export with configurable bit depth
//!
//! Supports 16-bit, 24-bit, and 32-bit float WAV formats.

use super::dither::{convert_to_16bit, convert_to_24bit};
use super::options::{ExportOptions, ExportResult, WavBitDepth};
use super::normalize::normalize_peak;
use super::resample::{resample_stereo, stereo_to_mono, mono_to_stereo};
use std::path::Path;

/// Internal sample rate used by the audio engine
pub const ENGINE_SAMPLE_RATE: u32 = 48000;

/// Export audio samples to WAV file
///
/// # Arguments
/// * `samples` - Stereo interleaved f32 samples from render_offline
/// * `output_path` - Path to output WAV file
/// * `options` - Export options (bit depth, sample rate, normalize, dither)
///
/// # Returns
/// Export result with file info
pub fn export_wav(
    samples: &[f32],
    output_path: &Path,
    options: &ExportOptions,
) -> Result<ExportResult, String> {
    eprintln!(
        "🎵 [WAV Export] Starting export to {:?}",
        output_path
    );

    // Get bit depth from options
    let bit_depth = match &options.format {
        super::options::ExportFormat::Wav { bit_depth } => *bit_depth,
        _ => return Err("export_wav called with non-WAV format".to_string()),
    };

    // Make a mutable copy of samples for processing
    let mut processed = samples.to_vec();

    // Apply mono mixdown if requested
    if options.mono {
        eprintln!("🔊 [WAV Export] Converting to mono");
        processed = stereo_to_mono(&processed);
        processed = mono_to_stereo(&processed); // Convert back for stereo output file
    }

    // Apply sample rate conversion if needed
    if options.sample_rate != ENGINE_SAMPLE_RATE {
        eprintln!(
            "🔄 [WAV Export] Resampling {}Hz → {}Hz",
            ENGINE_SAMPLE_RATE, options.sample_rate
        );
        processed = resample_stereo(&processed, ENGINE_SAMPLE_RATE, options.sample_rate)?;
    }

    // Apply normalization if requested
    if options.normalize {
        eprintln!("📊 [WAV Export] Normalizing to -0.1 dBFS");
        normalize_peak(&mut processed, -0.1);
    }

    // Calculate duration
    let num_frames = processed.len() / 2;
    let duration = num_frames as f64 / options.sample_rate as f64;

    // Write WAV based on bit depth
    let format_description = match bit_depth {
        WavBitDepth::Int16 => {
            write_wav_16bit(&processed, output_path, options.sample_rate, options.dither)?;
            "WAV 16-bit".to_string()
        }
        WavBitDepth::Int24 => {
            write_wav_24bit(&processed, output_path, options.sample_rate, options.dither)?;
            "WAV 24-bit".to_string()
        }
        WavBitDepth::Float32 => {
            write_wav_float32(&processed, output_path, options.sample_rate)?;
            "WAV 32-bit float".to_string()
        }
    };

    // Get file size
    let file_size = std::fs::metadata(output_path)
        .map(|m| m.len())
        .unwrap_or(0);

    eprintln!(
        "✅ [WAV Export] Complete: {:.2}s, {:.2} MB, {}",
        duration,
        file_size as f64 / 1024.0 / 1024.0,
        format_description
    );

    Ok(ExportResult::new(
        output_path.to_string_lossy().to_string(),
        file_size,
        duration,
        options.sample_rate,
        format_description,
    ))
}

/// Write 16-bit WAV file
fn write_wav_16bit(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
    dither: bool,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {}", e))?;

    // Convert to 16-bit with optional dithering
    let samples_16 = convert_to_16bit(samples, dither);

    for sample in samples_16 {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {}", e))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {}", e))?;

    Ok(())
}

/// Write 24-bit WAV file
fn write_wav_24bit(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
    dither: bool,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate,
        bits_per_sample: 24,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {}", e))?;

    // Convert to 24-bit with optional dithering
    let samples_24 = convert_to_24bit(samples, dither);

    for sample in samples_24 {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {}", e))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {}", e))?;

    Ok(())
}

/// Write 32-bit float WAV file
fn write_wav_float32(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {}", e))?;

    for &sample in samples {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {}", e))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {}", e))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn create_test_samples() -> Vec<f32> {
        // Create 1 second of stereo 440Hz sine wave at 48kHz
        let mut samples = Vec::with_capacity(48000 * 2);
        for i in 0..48000 {
            let t = i as f32 / 48000.0;
            let val = 0.5 * (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
            samples.push(val); // Left
            samples.push(val); // Right
        }
        samples
    }

    #[test]
    fn test_export_wav_16bit() {
        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_16bit.wav");

        let options = ExportOptions::wav(WavBitDepth::Int16)
            .with_sample_rate(44100)
            .with_dither(true);

        let result = export_wav(&samples, &temp_path, &options);
        assert!(result.is_ok());

        let result = result.unwrap();
        assert!(result.file_size > 0);
        assert!(result.duration > 0.9);
        assert_eq!(result.sample_rate, 44100);

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }

    #[test]
    fn test_export_wav_24bit() {
        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_24bit.wav");

        let options = ExportOptions::wav(WavBitDepth::Int24);

        let result = export_wav(&samples, &temp_path, &options);
        assert!(result.is_ok());

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }

    #[test]
    fn test_export_wav_float32() {
        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_float32.wav");

        let options = ExportOptions::wav(WavBitDepth::Float32)
            .with_normalize(true);

        let result = export_wav(&samples, &temp_path, &options);
        assert!(result.is_ok());

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }
}
