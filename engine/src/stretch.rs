/// Pitch-preserved time-stretching using signalsmith-stretch
///
/// This module provides functionality to time-stretch audio while preserving pitch,
/// used when warp_mode = 0 (Warp). When warp_mode = 1 (Re-Pitch), simple sample-rate
/// shifting is used instead (handled in audio_graph.rs).

use signalsmith_stretch::Stretch;
use std::sync::Arc;
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};

/// Apply pitch-preserved time-stretching to an audio clip.
///
/// # Arguments
/// * `clip` - The source audio clip to stretch
/// * `stretch_factor` - Speed multiplier from BPM ratio (project_bpm / clip_bpm)
///   - >1.0 = clip should play FASTER (shorter output) to match higher project tempo
///   - <1.0 = clip should play SLOWER (longer output) to match lower project tempo
///
/// # Returns
/// A new AudioClip with the stretched audio, wrapped in Arc
///
/// # Notes
/// - stretch_factor = project_bpm / clip_original_bpm
/// - stretch_factor of 1.2 means project is 20% faster, so clip needs to be 20% shorter
/// - stretch_factor of 0.8 means project is 20% slower, so clip needs to be 20% longer
pub fn stretch_audio_preserve_pitch(
    clip: &AudioClip,
    stretch_factor: f32,
) -> Arc<AudioClip> {
    eprintln!("🎵 [Stretch] stretch_audio_preserve_pitch called: stretch_factor={:.3}", stretch_factor);

    // If stretch factor is effectively 1.0, return a clone wrapped in Arc
    if (stretch_factor - 1.0).abs() < 0.001 {
        eprintln!("🎵 [Stretch] stretch_factor ~= 1.0, returning clone");
        return Arc::new(clip.clone());
    }

    let channels = clip.channels as u32;
    let sample_rate = clip.sample_rate;
    let input_frames = clip.frame_count();

    // Calculate output length
    // stretch_factor > 1.0 means clip should play FASTER = SHORTER output
    // stretch_factor < 1.0 means clip should play SLOWER = LONGER output
    // So output_frames = input_frames / stretch_factor
    let output_frames = (input_frames as f64 / stretch_factor as f64).ceil() as usize;

    eprintln!("🎵 [Stretch] input_frames={}, output_frames={}, channels={}, sample_rate={}",
        input_frames, output_frames, channels, sample_rate);

    // Create stretcher instance
    let mut stretcher = Stretch::preset_default(channels, sample_rate);

    // Prepare output buffer (interleaved, same format as input)
    let mut output_samples = vec![0.0f32; output_frames * clip.channels];

    // Try exact() first for complete offline batch processing
    // The stretch ratio is determined by input/output buffer size ratio
    let success = stretcher.exact(&clip.samples, &mut output_samples);

    if !success {
        eprintln!("⚠️  [Stretch] exact() failed, falling back to process()");
        // exact() can fail for certain stretch ratios (especially compression)
        // Fall back to process() which always works but may need flushing
        stretcher.reset();
        stretcher.process(&clip.samples, &mut output_samples);

        // Flush any remaining buffered output
        let latency = stretcher.output_latency();
        if latency > 0 {
            let mut flush_buffer = vec![0.0f32; latency * clip.channels];
            stretcher.flush(&mut flush_buffer);
            // Note: We could append this but for now the main output is sufficient
        }
    } else {
        eprintln!("✅ [Stretch] exact() succeeded");
    }

    // Calculate new duration
    let duration_seconds = output_frames as f64 / sample_rate as f64;

    eprintln!("🎵 [Stretch] Output ready: {} samples, {:.3}s duration",
        output_samples.len(), duration_seconds);

    Arc::new(AudioClip {
        samples: output_samples,
        channels: clip.channels,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds,
        file_path: clip.file_path.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_clip(frames: usize, channels: usize) -> AudioClip {
        // Create a simple sine wave for testing
        let mut samples = Vec::with_capacity(frames * channels);
        for frame in 0..frames {
            let t = frame as f32 / 48000.0;
            let sample = (t * 440.0 * 2.0 * std::f32::consts::PI).sin() * 0.5;
            for _ in 0..channels {
                samples.push(sample);
            }
        }
        AudioClip {
            samples,
            channels,
            sample_rate: 48000,
            duration_seconds: frames as f64 / 48000.0,
            file_path: "test.wav".to_string(),
        }
    }

    #[test]
    fn test_no_stretch() {
        let clip = create_test_clip(4800, 2); // 0.1 seconds of stereo audio
        let stretched = stretch_audio_preserve_pitch(&clip, 1.0);

        // Should be approximately the same length
        assert_eq!(stretched.frame_count(), clip.frame_count());
    }

    #[test]
    fn test_stretch_faster() {
        // stretch_factor = 2.0 means project is 2x faster, clip should be HALF as long
        let clip = create_test_clip(4800, 2);
        let stretched = stretch_audio_preserve_pitch(&clip, 2.0);

        // Should be approximately half as long (4800 / 2.0 = 2400)
        let expected_frames = (clip.frame_count() as f64 / 2.0).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }

    #[test]
    fn test_stretch_slower() {
        // stretch_factor = 0.5 means project is 0.5x speed, clip should be TWICE as long
        let clip = create_test_clip(4800, 2);
        let stretched = stretch_audio_preserve_pitch(&clip, 0.5);

        // Should be approximately twice as long (4800 / 0.5 = 9600)
        let expected_frames = (clip.frame_count() as f64 / 0.5).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }

    #[test]
    fn test_mono_stretch() {
        // stretch_factor = 1.5 means project is 1.5x faster, clip should be 2/3 as long
        let clip = create_test_clip(4800, 1);
        let stretched = stretch_audio_preserve_pitch(&clip, 1.5);

        assert_eq!(stretched.channels, 1);
        // Should be approximately 2/3 as long (4800 / 1.5 = 3200)
        let expected_frames = (clip.frame_count() as f64 / 1.5).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }
}
