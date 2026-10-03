use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
/// Pitch-preserved time-stretching using signalsmith-stretch
///
/// This module provides functionality to time-stretch audio while preserving pitch,
/// used when `warp_mode` = 0 (Warp). When `warp_mode` = 1 (Re-Pitch), simple sample-rate
/// shifting is used instead (handled in `audio_graph.rs`).
use signalsmith_stretch::Stretch;
use std::sync::Arc;

/// Apply pitch-preserved time-stretching to an audio clip.
///
/// # Arguments
/// * `clip` - The source audio clip to stretch
/// * `stretch_factor` - Speed multiplier from BPM ratio (project_bpm / clip_bpm)
///   - >1.0 = clip should play FASTER (shorter output) to match higher project tempo
///   - <1.0 = clip should play SLOWER (longer output) to match lower project tempo
///
/// # Returns
/// A new `AudioClip` with the stretched audio, wrapped in Arc
///
/// # Notes
/// - `stretch_factor` = `project_bpm` / `clip_original_bpm`
/// - `stretch_factor` of 1.2 means project is 20% faster, so clip needs to be 20% shorter
/// - `stretch_factor` of 0.8 means project is 20% slower, so clip needs to be 20% longer
///
/// `transpose_semitones` shifts the pitch in the same pass. It never changes
/// the length: transposing a clip changes its pitch only.
pub fn process_audio(
    clip: &AudioClip,
    stretch_factor: f32,
    transpose_semitones: f32,
) -> Arc<AudioClip> {
    if (stretch_factor - 1.0).abs() < 0.001 && transpose_semitones.abs() < 0.001 {
        return Arc::new(clip.clone());
    }

    let channels = clip.channels as u32;
    let sample_rate = clip.sample_rate;
    let input_frames = clip.frame_count();

    // Calculate output length
    // stretch_factor > 1.0 means clip should play FASTER = SHORTER output
    // stretch_factor < 1.0 means clip should play SLOWER = LONGER output
    // So output_frames = input_frames / stretch_factor
    let output_frames = (input_frames as f64 / f64::from(stretch_factor)).ceil() as usize;

    // Create stretcher instance
    let mut stretcher = Stretch::preset_default(channels, sample_rate);
    if transpose_semitones.abs() >= 0.001 {
        stretcher.set_transpose_factor_semitones(transpose_semitones, None);
    }

    // Prepare output buffer (interleaved, same format as input)
    let mut output_samples = vec![0.0f32; output_frames * clip.channels];

    // Try exact() first for complete offline batch processing
    // The stretch ratio is determined by input/output buffer size ratio
    let success = stretcher.exact(&clip.samples, &mut output_samples);

    if !success {
        // exact() can fail for certain stretch ratios (especially compression)
        // Fall back to process() which always works but may need flushing
        stretcher.reset();
        stretcher.process(&clip.samples, &mut output_samples);

        // Flush any remaining buffered output
        let latency = stretcher.output_latency();
        if latency > 0 {
            let mut flush_buffer = vec![0.0f32; latency * clip.channels];
            stretcher.flush(&mut flush_buffer);
        }
    }

    // Calculate new duration
    let duration_seconds = output_frames as f64 / f64::from(sample_rate);

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

    /// Rising zero crossings per second (the pitch of a clean tone), measured
    /// away from the edges.
    fn frequency(clip: &AudioClip) -> f64 {
        let left: Vec<f32> = clip
            .samples
            .iter()
            .step_by(clip.channels)
            .copied()
            .collect();
        let middle = &left[left.len() / 4..left.len() * 3 / 4];
        let rising = middle
            .windows(2)
            .filter(|w| w[0] < 0.0 && w[1] >= 0.0)
            .count();
        rising as f64 * 48_000.0 / middle.len() as f64
    }

    #[test]
    fn transpose_changes_pitch_not_length() {
        let clip = create_test_clip(48_000, 2); // 1 s of 440 Hz
        for (semitones, stretch) in [(12.0, 1.0), (-12.0, 1.0), (7.0, 1.25)] {
            let out = process_audio(&clip, stretch, semitones);
            let expected_frames = (48_000.0 / f64::from(stretch)).ceil() as usize;
            assert_eq!(out.frame_count(), expected_frames, "{semitones} st: length");
            let want = 440.0 * 2f64.powf(f64::from(semitones) / 12.0);
            let got = frequency(&out);
            assert!(
                (got - want).abs() < want * 0.02,
                "{semitones} st at {stretch}x: expected {want:.0} Hz, got {got:.0} Hz"
            );
        }
    }

    #[test]
    fn test_no_stretch() {
        let clip = create_test_clip(4800, 2); // 0.1 seconds of stereo audio
        let stretched = process_audio(&clip, 1.0, 0.0);

        // Should be approximately the same length
        assert_eq!(stretched.frame_count(), clip.frame_count());
    }

    #[test]
    fn test_stretch_faster() {
        // stretch_factor = 2.0 means project is 2x faster, clip should be HALF as long
        let clip = create_test_clip(4800, 2);
        let stretched = process_audio(&clip, 2.0, 0.0);

        // Should be approximately half as long (4800 / 2.0 = 2400)
        let expected_frames = (clip.frame_count() as f64 / 2.0).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }

    #[test]
    fn test_stretch_slower() {
        // stretch_factor = 0.5 means project is 0.5x speed, clip should be TWICE as long
        let clip = create_test_clip(4800, 2);
        let stretched = process_audio(&clip, 0.5, 0.0);

        // Should be approximately twice as long (4800 / 0.5 = 9600)
        let expected_frames = (clip.frame_count() as f64 / 0.5).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }

    #[test]
    fn test_mono_stretch() {
        // stretch_factor = 1.5 means project is 1.5x faster, clip should be 2/3 as long
        let clip = create_test_clip(4800, 1);
        let stretched = process_audio(&clip, 1.5, 0.0);

        assert_eq!(stretched.channels, 1);
        // Should be approximately 2/3 as long (4800 / 1.5 = 3200)
        let expected_frames = (clip.frame_count() as f64 / 1.5).ceil() as usize;
        assert!((stretched.frame_count() as i64 - expected_frames as i64).abs() < 100);
    }
}
