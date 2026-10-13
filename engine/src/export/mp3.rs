//! MP3 file export, encoded in-process by LAME (`mp3lame-encoder`, built
//! from source with the engine, so there is nothing for the user to install).

use super::normalize::normalize_peak;
use super::options::{ExportOptions, ExportResult, Mp3Bitrate};
use super::resample::{mono_to_stereo, resample_stereo, stereo_to_mono};
use super::wav::{apply_platform_lufs, slice_export_range, ENGINE_SAMPLE_RATE};
use mp3lame_encoder::{Bitrate, Builder, FlushGap, InterleavedPcm, Quality};
use std::num::NonZeroU32;
use std::path::Path;

/// Export audio samples to MP3 file
///
/// # Arguments
/// * `samples` - Stereo interleaved f32 samples from `render_offline`
/// * `output_path` - Path to output MP3 file
/// * `options` - Export options (bitrate, sample rate, normalize)
/// * `on_block` - Called as encoding goes with the fraction done (0–1);
///   returning `false` stops it with "Export cancelled" and writes nothing
///
/// # Returns
/// Export result with file info
pub fn export_mp3(
    samples: &[f32],
    output_path: &Path,
    options: &ExportOptions,
    on_block: &mut dyn FnMut(f64) -> bool,
) -> Result<ExportResult, String> {
    eprintln!(
        "🎵 [MP3 Export] Starting export to {}",
        output_path.display()
    );

    // Get bitrate from options
    let bitrate = match &options.format {
        super::options::ExportFormat::Mp3 { bitrate } => *bitrate,
        super::options::ExportFormat::Wav { .. } => {
            return Err("export_mp3 called with non-MP3 format".to_string())
        }
    };

    // Trim to the requested export range first — everything downstream
    // (mixdown, resample, loudness) operates on the trimmed audio. (C18)
    let mut processed = slice_export_range(samples, options)?;

    // Platform LUFS target runs on the stereo engine-rate buffer. (C16)
    let lufs_applied = apply_platform_lufs(&mut processed, options, "MP3 Export");

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

    // Apply peak normalization if requested (runs last so resampling can't
    // shift the final peak). Skipped when a platform LUFS target was
    // applied — that target owns the loudness.
    if options.normalize && !lufs_applied {
        eprintln!("📊 [MP3 Export] Normalizing to -0.1 dBFS");
        normalize_peak(&mut processed, -0.1);
    }

    // Calculate duration
    let num_frames = processed.len() / 2;
    let duration = num_frames as f64 / f64::from(options.sample_rate);

    let mp3 = encode_mp3(&processed, options.sample_rate, bitrate, on_block)?;
    std::fs::write(output_path, &mp3).map_err(|e| format!("Failed to write MP3 file: {e}"))?;

    // Get file size
    let file_size = std::fs::metadata(output_path).map_or(0, |m| m.len());

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

/// Encode stereo interleaved samples to MP3 bytes: constant bitrate, LAME
/// quality 2 (its recommended high-quality setting), and the LAME header
/// frame so players show the right length and skip the encoder's start-up
/// silence.
fn encode_mp3(
    samples: &[f32],
    sample_rate: u32,
    bitrate: Mp3Bitrate,
    on_block: &mut dyn FnMut(f64) -> bool,
) -> Result<Vec<u8>, String> {
    fn lame_error(e: impl std::fmt::Display) -> String {
        format!("MP3 encoder: {e}")
    }
    let mut builder = Builder::new().ok_or("MP3 encoder: out of memory")?;
    builder.set_num_channels(2).map_err(lame_error)?;
    builder.set_sample_rate(sample_rate).map_err(lame_error)?;
    // Keep the export's rate; left unset, LAME may pick another.
    builder
        .set_output_sample_rate(NonZeroU32::new(sample_rate))
        .map_err(lame_error)?;
    builder
        .set_brate(match bitrate {
            Mp3Bitrate::Kbps128 => Bitrate::Kbps128,
            Mp3Bitrate::Kbps192 => Bitrate::Kbps192,
            Mp3Bitrate::Kbps320 => Bitrate::Kbps320,
        })
        .map_err(lame_error)?;
    builder.set_quality(Quality::NearBest).map_err(lame_error)?;
    let mut encoder = builder.build().map_err(lame_error)?;

    // About a second at a time, so progress moves and Cancel is quick.
    let block = sample_rate as usize * 2;
    let mut mp3 = Vec::with_capacity(mp3lame_encoder::max_required_buffer_size(samples.len() / 2));
    let mut clipped = Vec::with_capacity(block);
    let mut encoded = 0;
    for chunk in samples.chunks(block) {
        clipped.clear();
        clipped.extend(chunk.iter().map(|s| s.clamp(-1.0, 1.0)));
        mp3.reserve(mp3lame_encoder::max_required_buffer_size(chunk.len() / 2));
        encoder
            .encode_to_vec(InterleavedPcm(clipped.as_slice()), &mut mp3)
            .map_err(lame_error)?;
        encoded += chunk.len();
        if !on_block(encoded as f64 / samples.len() as f64) {
            return Err("Export cancelled".to_string());
        }
    }
    // The plain flush: the "no gap" one (for joining files) drops the end.
    mp3.reserve(7200);
    encoder
        .flush_to_vec::<FlushGap>(&mut mp3)
        .map_err(lame_error)?;

    // LAME left room for its header frame at the start; fill it in.
    let mut tag = Vec::with_capacity(encoder.lame_tag_size());
    if let Some(len) = encoder.lame_tag_encode_to_vec(&mut tag) {
        if len.get() <= mp3.len() {
            mp3[..len.get()].copy_from_slice(&tag);
        }
    }
    Ok(mp3)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio_file::load_audio_file;
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

    fn export(name: &str, options: &ExportOptions) -> (std::path::PathBuf, ExportResult) {
        let path = env::temp_dir().join(name);
        let result = export_mp3(&create_test_samples(), &path, options, &mut |_| true)
            .expect("export succeeds");
        (path, result)
    }

    /// Frames a player that reads the LAME header plays back.
    fn gapless_frames(path: &Path) -> u64 {
        use symphonia::core::codecs::DecoderOptions;
        use symphonia::core::formats::FormatOptions;
        use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
        use symphonia::core::meta::MetadataOptions;
        use symphonia::core::probe::Hint;

        let file = std::fs::File::open(path).unwrap();
        let stream = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
        let mut format = symphonia::default::get_probe()
            .format(
                &Hint::new(),
                stream,
                &FormatOptions {
                    enable_gapless: true,
                    ..Default::default()
                },
                &MetadataOptions::default(),
            )
            .unwrap()
            .format;
        let track = format.default_track().unwrap();
        let track_id = track.id;
        let mut decoder = symphonia::default::get_codecs()
            .make(&track.codec_params, &DecoderOptions::default())
            .unwrap();
        let mut frames = 0;
        while let Ok(packet) = format.next_packet() {
            if packet.track_id() == track_id {
                frames += decoder.decode(&packet).unwrap().frames() as u64;
            }
        }
        frames
    }

    #[test]
    fn an_mp3_is_exactly_as_long_as_the_audio() {
        // Without the LAME header, players add the encoder's start-up
        // silence; with the "no gap" flush, the last 35 ms went missing.
        let options = ExportOptions::mp3(Mp3Bitrate::Kbps192).with_sample_rate(44_100);
        let (path, _) = export("test_export_length.mp3", &options);
        assert_eq!(gapless_frames(&path), 44_100);
        let _ = std::fs::remove_file(&path);
    }

    fn peak(samples: &[f32]) -> f32 {
        samples.iter().fold(0.0f32, |m, s| m.max(s.abs()))
    }

    #[test]
    fn an_mp3_plays_back_as_the_sound_that_went_in() {
        for rate in [44_100, 48_000] {
            let options = ExportOptions::mp3(Mp3Bitrate::Kbps320).with_sample_rate(rate);
            let (path, result) = export(&format!("test_export_{rate}.mp3"), &options);
            assert_eq!(result.sample_rate, rate);

            let decoded = load_audio_file(&path).expect("the MP3 decodes");
            assert!(
                (decoded.duration_seconds - 1.0).abs() < 0.06,
                "{rate} Hz: lasts {}s, not about 1s",
                decoded.duration_seconds
            );
            let level = peak(&decoded.samples[9600..86400]);
            assert!(
                (0.45..0.55).contains(&level),
                "{rate} Hz: peak {level}, not about 0.5"
            );
            let _ = std::fs::remove_file(&path);
        }
    }

    #[test]
    fn a_lower_bitrate_makes_a_smaller_file() {
        let (path_128, at_128) = export(
            "test_export_128.mp3",
            &ExportOptions::mp3(Mp3Bitrate::Kbps128),
        );
        let (path_320, at_320) = export(
            "test_export_320.mp3",
            &ExportOptions::mp3(Mp3Bitrate::Kbps320),
        );

        // Constant bitrate: about bitrate × 1 s of bytes.
        assert!(
            (14_000..20_000).contains(&at_128.file_size),
            "{}",
            at_128.file_size
        );
        assert!(
            (38_000..46_000).contains(&at_320.file_size),
            "{}",
            at_320.file_size
        );

        let _ = std::fs::remove_file(&path_128);
        let _ = std::fs::remove_file(&path_320);
    }

    #[test]
    fn normalize_raises_the_peak() {
        let options = ExportOptions::mp3(Mp3Bitrate::Kbps192).with_normalize(true);
        let (path, _) = export("test_export_normalized.mp3", &options);

        let decoded = load_audio_file(&path).unwrap();
        assert!(peak(&decoded.samples) > 0.9);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn stopping_mid_encode_writes_nothing() {
        let path = env::temp_dir().join("test_export_stopped.mp3");
        let _ = std::fs::remove_file(&path);
        let long: Vec<f32> = create_test_samples().repeat(5);
        let mut seen = Vec::new();

        let result = export_mp3(
            &long,
            &path,
            &ExportOptions::mp3(Mp3Bitrate::Kbps192),
            &mut |done| {
                seen.push(done);
                done < 0.3
            },
        );

        assert_eq!(result.err(), Some("Export cancelled".to_string()));
        assert!(
            seen.len() >= 2 && *seen.last().unwrap() < 1.0,
            "stopped part way: {seen:?}"
        );
        assert!(!path.exists());
    }
}
