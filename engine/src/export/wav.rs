//! WAV file export with configurable bit depth
//!
//! Supports 16-bit, 24-bit, and 32-bit float WAV formats.

use super::dither::{convert_to_16bit, convert_to_24bit};
use super::normalize::{normalize_lufs, normalize_peak};
use super::options::{ExportOptions, ExportResult, WavBitDepth};
use super::resample::{resample_mono, resample_stereo, stereo_to_mono};
use std::path::Path;

/// Internal sample rate used by the audio engine
pub const ENGINE_SAMPLE_RATE: u32 = 48000;

/// Trim rendered audio to the export range requested in the options (C18).
///
/// `samples` are stereo interleaved at `ENGINE_SAMPLE_RATE` (the raw
/// `render_offline` output, before any mixdown/resampling). With no range
/// set this is just a copy of the full render.
pub(crate) fn slice_export_range(
    samples: &[f32],
    options: &ExportOptions,
) -> Result<Vec<f32>, String> {
    if options.start_time.is_none() && options.end_time.is_none() {
        return Ok(samples.to_vec());
    }

    let num_frames = samples.len() / 2;
    let start_secs = options.start_time.unwrap_or(0.0).max(0.0);
    let end_secs = options.end_time.unwrap_or(f64::MAX);
    if end_secs <= start_secs {
        return Err(format!(
            "Export range is empty ({start_secs:.2}s – {end_secs:.2}s)"
        ));
    }

    let start_frame = ((start_secs * f64::from(ENGINE_SAMPLE_RATE)) as usize).min(num_frames);
    let end_frame = if options.end_time.is_some() {
        ((end_secs * f64::from(ENGINE_SAMPLE_RATE)) as usize).min(num_frames)
    } else {
        num_frames
    };
    if start_frame >= end_frame {
        return Err(format!(
            "Export range ({start_secs:.2}s onwards) starts after the end of the audio"
        ));
    }

    eprintln!("✂️ [Export] Trimming to range: {start_secs:.2}s – frame {start_frame}..{end_frame}");
    Ok(samples[start_frame * 2..end_frame * 2].to_vec())
}

/// Apply the platform LUFS target if one is set (C16). Returns whether a
/// target was applied — peak normalization must then be skipped, since
/// re-scaling to a peak level afterwards would silently break the loudness
/// target.
///
/// Must run on stereo interleaved audio at the engine rate (the LUFS
/// measurement assumes stereo), so callers apply it before any mono
/// mixdown/resampling; the uniform gain survives both unchanged.
pub(crate) fn apply_platform_lufs(
    processed: &mut [f32],
    options: &ExportOptions,
    label: &str,
) -> bool {
    let Some(target) = options.platform_target.target_lufs() else {
        return false;
    };
    eprintln!("📊 [{label}] Applying platform loudness target: {target:.1} LUFS");
    normalize_lufs(processed, ENGINE_SAMPLE_RATE, target);
    if options.normalize {
        eprintln!(
            "📊 [{label}] Skipping peak normalization — the platform LUFS target supersedes it"
        );
    }
    true
}

/// Export audio samples to WAV file
///
/// # Arguments
/// * `samples` - Stereo interleaved f32 samples from `render_offline`
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
        "🎵 [WAV Export] Starting export to {}",
        output_path.display()
    );

    // Get bit depth from options
    let bit_depth = match &options.format {
        super::options::ExportFormat::Wav { bit_depth } => *bit_depth,
        super::options::ExportFormat::Mp3 { .. } => {
            return Err("export_wav called with non-WAV format".to_string())
        }
    };

    // Trim to the requested export range first — everything downstream
    // (mixdown, resample, loudness) operates on the trimmed audio. (C18)
    let mut processed = slice_export_range(samples, options)?;

    // Platform LUFS target runs on the stereo engine-rate buffer. (C16)
    let lufs_applied = apply_platform_lufs(&mut processed, options, "WAV Export");

    // Output channel count. A mono export writes a true single-channel WAV
    // (half the size, correctly tagged mono) rather than a dual-mono stereo
    // file with two identical channels. (C22)
    let channels: u16 = if options.mono { 1 } else { 2 };

    // Apply mono mixdown if requested
    if options.mono {
        eprintln!("🔊 [WAV Export] Converting to mono");
        processed = stereo_to_mono(&processed);
    }

    // Apply sample rate conversion if needed
    if options.sample_rate != ENGINE_SAMPLE_RATE {
        eprintln!(
            "🔄 [WAV Export] Resampling {}Hz → {}Hz",
            ENGINE_SAMPLE_RATE, options.sample_rate
        );
        processed = if options.mono {
            resample_mono(&processed, ENGINE_SAMPLE_RATE, options.sample_rate)?
        } else {
            resample_stereo(&processed, ENGINE_SAMPLE_RATE, options.sample_rate)?
        };
    }

    // Apply peak normalization if requested (peak scan is channel-agnostic;
    // runs last so resampling can't shift the final peak). Skipped when a
    // platform LUFS target was applied — that target owns the loudness.
    if options.normalize && !lufs_applied {
        eprintln!("📊 [WAV Export] Normalizing to -0.1 dBFS");
        normalize_peak(&mut processed, -0.1);
    }

    // Calculate duration
    let num_frames = processed.len() / channels as usize;
    let duration = num_frames as f64 / f64::from(options.sample_rate);

    // Write WAV based on bit depth
    let format_description = match bit_depth {
        WavBitDepth::Int16 => {
            write_wav_16bit(
                &processed,
                output_path,
                options.sample_rate,
                channels,
                options.dither,
            )?;
            "WAV 16-bit".to_string()
        }
        WavBitDepth::Int24 => {
            write_wav_24bit(
                &processed,
                output_path,
                options.sample_rate,
                channels,
                options.dither,
            )?;
            "WAV 24-bit".to_string()
        }
        WavBitDepth::Float32 => {
            write_wav_float32(&processed, output_path, options.sample_rate, channels)?;
            "WAV 32-bit float".to_string()
        }
    };

    // Get file size
    let file_size = std::fs::metadata(output_path).map_or(0, |m| m.len());

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
    channels: u16,
    dither: bool,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {e}"))?;

    // Convert to 16-bit with optional dithering
    let samples_16 = convert_to_16bit(samples, dither);

    for sample in samples_16 {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {e}"))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {e}"))?;

    Ok(())
}

/// Write 24-bit WAV file
fn write_wav_24bit(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
    channels: u16,
    dither: bool,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 24,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {e}"))?;

    // Convert to 24-bit with optional dithering
    let samples_24 = convert_to_24bit(samples, dither);

    for sample in samples_24 {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {e}"))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {e}"))?;

    Ok(())
}

/// Write 32-bit float WAV file
fn write_wav_float32(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
    channels: u16,
) -> Result<(), String> {
    let spec = hound::WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };

    let mut writer = hound::WavWriter::create(output_path, spec)
        .map_err(|e| format!("Failed to create WAV file: {e}"))?;

    for &sample in samples {
        writer
            .write_sample(sample)
            .map_err(|e| format!("Failed to write sample: {e}"))?;
    }

    writer
        .finalize()
        .map_err(|e| format!("Failed to finalize WAV: {e}"))?;

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

        let options = ExportOptions::wav(WavBitDepth::Float32).with_normalize(true);

        let result = export_wav(&samples, &temp_path, &options);
        assert!(result.is_ok());

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }

    /// A mono export must write a genuine single-channel WAV — not a
    /// dual-mono stereo file with two identical channels. (C22)
    #[test]
    fn test_export_wav_mono_is_single_channel() {
        let samples = create_test_samples(); // 48000 stereo frames
        let temp_path = env::temp_dir().join("test_export_mono.wav");

        // Pin the export rate to the engine rate so no resampling alters the
        // frame count — we want to assert the mono mixdown preserves frames.
        let options = ExportOptions::wav(WavBitDepth::Int16)
            .with_mono(true)
            .with_sample_rate(ENGINE_SAMPLE_RATE);
        let result = export_wav(&samples, &temp_path, &options).unwrap();

        // Read the file header back and confirm it is truly mono with the
        // same frame count / duration as the stereo source.
        let reader = hound::WavReader::open(&temp_path).unwrap();
        let spec = reader.spec();
        assert_eq!(spec.channels, 1, "mono export must be 1 channel");
        assert_eq!(
            reader.duration(),
            48000,
            "mono frame count must match source"
        );
        assert!((result.duration - 1.0).abs() < 0.01);

        let _ = std::fs::remove_file(&temp_path);
    }

    /// The export range must actually trim the output (C18) — a 1s render
    /// exported with a 0.25s–0.5s range produces a 0.25s file.
    #[test]
    fn export_range_trims_output() {
        let samples = create_test_samples(); // 1 second @ 48kHz stereo
        let temp_path = env::temp_dir().join("test_export_range.wav");

        let options = ExportOptions::wav(WavBitDepth::Int16)
            .with_sample_rate(ENGINE_SAMPLE_RATE)
            .with_range(0.25, 0.5);
        let result = export_wav(&samples, &temp_path, &options).unwrap();

        assert!(
            (result.duration - 0.25).abs() < 0.01,
            "expected 0.25s export, got {:.3}s",
            result.duration
        );

        let _ = std::fs::remove_file(&temp_path);
    }

    /// An end time past the end of the audio clamps instead of erroring.
    #[test]
    fn export_range_end_clamps_to_audio_length() {
        let samples = create_test_samples(); // 1 second
        let options = ExportOptions::wav(WavBitDepth::Int16).with_range(0.5, 99.0);
        let sliced = slice_export_range(&samples, &options).unwrap();
        assert_eq!(sliced.len(), 48000); // 0.5s of stereo frames
    }

    /// An empty or inverted range is an error, not a silent full export.
    #[test]
    fn export_range_empty_is_an_error() {
        let samples = create_test_samples();
        let options = ExportOptions::wav(WavBitDepth::Int16).with_range(0.5, 0.5);
        assert!(slice_export_range(&samples, &options).is_err());

        let inverted = ExportOptions::wav(WavBitDepth::Int16).with_range(0.8, 0.2);
        assert!(slice_export_range(&samples, &inverted).is_err());

        let past_end = ExportOptions::wav(WavBitDepth::Int16).with_range(5.0, 9.0);
        assert!(slice_export_range(&samples, &past_end).is_err());
    }

    /// A platform LUFS target must change the audio (C16 — it used to be
    /// dead code), and must suppress the conflicting peak normalization.
    #[test]
    fn platform_target_applies_lufs_gain() {
        use super::super::options::PlatformTarget;

        let samples = create_test_samples(); // 0.5-amplitude sine
        let mut with_target = samples.clone();
        let options = ExportOptions::wav(WavBitDepth::Float32)
            .with_normalize(true)
            .with_platform(PlatformTarget::Custom(-30.0));

        let applied = apply_platform_lufs(&mut with_target, &options, "test");
        assert!(applied, "platform target must report as applied");

        // -30 LUFS is far below the source loudness → audio must get quieter.
        let peak_before = samples.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let peak_after = with_target.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        assert!(
            peak_after < peak_before * 0.5,
            "expected significant attenuation toward -30 LUFS: {peak_before} -> {peak_after}"
        );

        // No platform target → not applied, peak normalize stays in charge.
        let no_target = ExportOptions::wav(WavBitDepth::Float32).with_normalize(true);
        let mut untouched = samples.clone();
        assert!(!apply_platform_lufs(&mut untouched, &no_target, "test"));
        assert_eq!(untouched, samples);
    }

    /// A default (non-mono) export stays stereo. Guards against the mono
    /// fix accidentally collapsing every export to one channel.
    #[test]
    fn test_export_wav_stereo_is_two_channels() {
        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_stereo_channels.wav");

        let options = ExportOptions::wav(WavBitDepth::Int16);
        export_wav(&samples, &temp_path, &options).unwrap();

        let reader = hound::WavReader::open(&temp_path).unwrap();
        assert_eq!(reader.spec().channels, 2, "default export must be stereo");

        let _ = std::fs::remove_file(&temp_path);
    }
}
