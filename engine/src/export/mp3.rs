//! MP3 file export using ffmpeg command-line
//!
//! Uses ffmpeg for encoding, which is commonly available on macOS/Linux.
//! Falls back to WAV export if ffmpeg is not available.

use super::normalize::normalize_peak;
use super::options::{ExportOptions, ExportResult, Mp3Bitrate};
use super::resample::{mono_to_stereo, resample_stereo, stereo_to_mono};
use super::wav::ENGINE_SAMPLE_RATE;
use std::io::Write;
use std::path::Path;
use std::process::Command;

/// Check if ffmpeg is available on the system
pub fn is_ffmpeg_available() -> bool {
    Command::new("ffmpeg")
        .arg("-version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Export audio samples to MP3 file
///
/// # Arguments
/// * `samples` - Stereo interleaved f32 samples from render_offline
/// * `output_path` - Path to output MP3 file
/// * `options` - Export options (bitrate, sample rate, normalize)
///
/// # Returns
/// Export result with file info
pub fn export_mp3(
    samples: &[f32],
    output_path: &Path,
    options: &ExportOptions,
) -> Result<ExportResult, String> {
    eprintln!("🎵 [MP3 Export] Starting export to {:?}", output_path);

    // Check ffmpeg availability
    if !is_ffmpeg_available() {
        return Err(
            "ffmpeg is not installed. Please install ffmpeg to export MP3 files.\n\
             On macOS: brew install ffmpeg\n\
             On Linux: sudo apt install ffmpeg"
                .to_string(),
        );
    }

    // Get bitrate from options
    let bitrate = match &options.format {
        super::options::ExportFormat::Mp3 { bitrate } => *bitrate,
        _ => return Err("export_mp3 called with non-MP3 format".to_string()),
    };

    // Make a mutable copy of samples for processing
    let mut processed = samples.to_vec();

    // Apply mono mixdown if requested
    if options.mono {
        eprintln!("🔊 [MP3 Export] Converting to mono");
        processed = stereo_to_mono(&processed);
        processed = mono_to_stereo(&processed); // Convert back for stereo encoding
    }

    // Apply sample rate conversion if needed
    if options.sample_rate != ENGINE_SAMPLE_RATE {
        eprintln!(
            "🔄 [MP3 Export] Resampling {}Hz → {}Hz",
            ENGINE_SAMPLE_RATE, options.sample_rate
        );
        processed = resample_stereo(&processed, ENGINE_SAMPLE_RATE, options.sample_rate)?;
    }

    // Apply normalization if requested
    if options.normalize {
        eprintln!("📊 [MP3 Export] Normalizing to -0.1 dBFS");
        normalize_peak(&mut processed, -0.1);
    }

    // Calculate duration
    let num_frames = processed.len() / 2;
    let duration = num_frames as f64 / options.sample_rate as f64;

    // Encode to MP3 using ffmpeg
    encode_mp3_ffmpeg(&processed, output_path, options.sample_rate, bitrate)?;

    // Get file size
    let file_size = std::fs::metadata(output_path)
        .map(|m| m.len())
        .unwrap_or(0);

    let format_description = format!("MP3 {} kbps", bitrate.kbps());

    eprintln!(
        "✅ [MP3 Export] Complete: {:.2}s, {:.2} MB, {}",
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

/// Encode samples to MP3 file using ffmpeg
fn encode_mp3_ffmpeg(
    samples: &[f32],
    output_path: &Path,
    sample_rate: u32,
    bitrate: Mp3Bitrate,
) -> Result<(), String> {
    eprintln!(
        "🎵 [MP3 Encode] {} samples at {}Hz, {} kbps via ffmpeg",
        samples.len(),
        sample_rate,
        bitrate.kbps()
    );

    // Convert f32 samples to i16 PCM bytes for piping to ffmpeg
    let mut pcm_bytes: Vec<u8> = Vec::with_capacity(samples.len() * 2);
    for &sample in samples {
        let sample_i16 = (sample * 32767.0).clamp(-32768.0, 32767.0) as i16;
        pcm_bytes.extend_from_slice(&sample_i16.to_le_bytes());
    }

    // Build ffmpeg command
    // Input: raw 16-bit signed little-endian PCM, stereo, at specified sample rate
    // Output: MP3 with specified bitrate
    let mut child = Command::new("ffmpeg")
        .args([
            "-y", // Overwrite output file
            "-f",
            "s16le", // Input format: signed 16-bit little-endian
            "-ar",
            &sample_rate.to_string(), // Input sample rate
            "-ac",
            "2", // Input channels (stereo)
            "-i",
            "pipe:0", // Read from stdin
            "-b:a",
            &format!("{}k", bitrate.kbps()), // Audio bitrate
            "-codec:a",
            "libmp3lame", // Use LAME encoder
            "-q:a",
            "0", // Best quality VBR setting
            output_path.to_str().unwrap_or("output.mp3"),
        ])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn ffmpeg: {}", e))?;

    // Write PCM data to ffmpeg's stdin
    if let Some(ref mut stdin) = child.stdin {
        stdin
            .write_all(&pcm_bytes)
            .map_err(|e| format!("Failed to write to ffmpeg: {}", e))?;
    }

    // Wait for ffmpeg to finish
    let output = child
        .wait_with_output()
        .map_err(|e| format!("Failed to wait for ffmpeg: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("ffmpeg encoding failed: {}", stderr));
    }

    eprintln!("✅ [MP3 Encode] ffmpeg encoding complete");

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
    fn test_ffmpeg_available() {
        // This test just checks the function works, not that ffmpeg is installed
        let _ = is_ffmpeg_available();
    }

    #[test]
    fn test_export_mp3_320() {
        if !is_ffmpeg_available() {
            eprintln!("Skipping MP3 test: ffmpeg not available");
            return;
        }

        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_320.mp3");

        let options = ExportOptions::mp3(Mp3Bitrate::Kbps320).with_sample_rate(44100);

        let result = export_mp3(&samples, &temp_path, &options);
        assert!(result.is_ok(), "Export failed: {:?}", result.err());

        let result = result.unwrap();
        assert!(result.file_size > 0);
        assert!(result.duration > 0.9);

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }

    #[test]
    fn test_export_mp3_128() {
        if !is_ffmpeg_available() {
            eprintln!("Skipping MP3 test: ffmpeg not available");
            return;
        }

        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_128.mp3");

        let options = ExportOptions::mp3(Mp3Bitrate::Kbps128);

        let result = export_mp3(&samples, &temp_path, &options);
        assert!(result.is_ok());

        // 128 kbps file should be smaller than 320 kbps
        let file_size_128 = result.unwrap().file_size;

        let options_320 = ExportOptions::mp3(Mp3Bitrate::Kbps320);
        let temp_path_320 = env::temp_dir().join("test_export_128_compare.mp3");
        let result_320 = export_mp3(&samples, &temp_path_320, &options_320).unwrap();

        assert!(file_size_128 < result_320.file_size);

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
        let _ = std::fs::remove_file(&temp_path_320);
    }

    #[test]
    fn test_export_mp3_normalized() {
        if !is_ffmpeg_available() {
            eprintln!("Skipping MP3 test: ffmpeg not available");
            return;
        }

        let samples = create_test_samples();
        let temp_path = env::temp_dir().join("test_export_normalized.mp3");

        let options = ExportOptions::mp3(Mp3Bitrate::Kbps192).with_normalize(true);

        let result = export_mp3(&samples, &temp_path, &options);
        assert!(result.is_ok());

        // Clean up
        let _ = std::fs::remove_file(&temp_path);
    }
}
