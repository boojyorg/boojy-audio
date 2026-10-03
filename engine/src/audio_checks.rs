//! Test-only checks that listen to rendered audio.
//!
//! Renders used to be checked only for "finite and not silent", which let a
//! repeated sample on ~1 frame in 17 (heard as grit) ship for months. These
//! helpers check the content itself: ramp clips whose sample values encode
//! their own position (so a skipped, repeated or doubled sample is exact to
//! spot), plus click, gap and level checks for ordinary signals.

use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use std::sync::Arc;

/// Value step of a ramp clip. A power of two, so every ramp value is exact
/// in f32 (up to 2^24 frames) and stays well under the master limiter.
pub(crate) const RAMP_STEP: f32 = 1.0 / 1_048_576.0;

pub(crate) fn seconds(frames: usize) -> f64 {
    frames as f64 / f64::from(TARGET_SAMPLE_RATE)
}

/// A clip whose frame `i` holds `(i + 1) * RAMP_STEP` on the left and the
/// negative on the right, so position and channel both show in the output
/// and frame 0 is distinguishable from silence.
pub(crate) fn ramp_clip(frames: usize, channels: usize) -> Arc<AudioClip> {
    let mut samples = Vec::with_capacity(frames * channels);
    for i in 0..frames {
        let v = (i + 1) as f32 * RAMP_STEP;
        samples.push(v);
        if channels == 2 {
            samples.push(-v);
        }
    }
    Arc::new(AudioClip {
        samples,
        channels,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds: seconds(frames),
        file_path: "ramp.wav".into(),
    })
}

/// A stereo sine clip (same signal on both channels).
pub(crate) fn sine_clip(frames: usize, hz: f64, amplitude: f32) -> Arc<AudioClip> {
    let sr = f64::from(TARGET_SAMPLE_RATE);
    let samples = (0..frames)
        .flat_map(|i| {
            let v = amplitude * (std::f64::consts::TAU * hz * i as f64 / sr).sin() as f32;
            [v, v]
        })
        .collect();
    Arc::new(AudioClip {
        samples,
        channels: 2,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds: seconds(frames),
        file_path: "sine.wav".into(),
    })
}

/// One channel of an interleaved stereo buffer.
pub(crate) fn channel(buf: &[f32], ch: usize) -> Vec<f32> {
    buf.iter().skip(ch).step_by(2).copied().collect()
}

/// Read a rendered ramp back into source frame numbers: `None` for silence,
/// `Some(i)` for ramp frame `i`. `gain` is everything applied after the clip
/// (fader × pan × master). A value between two frames (a doubled sample or a
/// wrong gain) decodes to `Some(usize::MAX)`, so it never matches.
pub(crate) fn decode_ramp(samples: &[f32], gain: f32) -> Vec<Option<usize>> {
    samples
        .iter()
        .map(|&s| {
            if s == 0.0 {
                return None;
            }
            let pos = f64::from(s) / f64::from(gain * RAMP_STEP);
            let whole = pos.round();
            if (pos - whole).abs() > 0.01 || whole < 1.0 {
                Some(usize::MAX)
            } else {
                Some(whole as usize - 1)
            }
        })
        .collect()
}

/// One wrong output frame: `(frame, expected, got)`.
pub(crate) type Mismatch = (usize, Option<usize>, Option<usize>);

/// How many output frames' decoded values differ from `expected`, and the
/// first few of them for a readable failure.
pub(crate) fn ramp_mismatches(
    got: &[Option<usize>],
    expected: &[Option<usize>],
) -> (usize, Vec<Mismatch>) {
    assert_eq!(got.len(), expected.len(), "render length");
    let wrong: Vec<_> = got
        .iter()
        .zip(expected)
        .enumerate()
        .filter(|(_, (g, e))| g != e)
        .map(|(i, (g, e))| (i, *e, *g))
        .collect();
    let count = wrong.len();
    (count, wrong.into_iter().take(5).collect())
}

/// Every sample is a real number inside the device range.
pub(crate) fn assert_valid(buf: &[f32], what: &str) {
    if let Some(i) = buf.iter().position(|s| !s.is_finite() || s.abs() > 1.0) {
        panic!("{what}: invalid sample {} at index {i}", buf[i]);
    }
}

/// Frames where the signal jumps further than `max_step` from the previous
/// frame. For a sine of amplitude `a` at `hz`, the steepest honest step is
/// `TAU * hz * a / sample_rate`; anything well above that is a click.
pub(crate) fn clicks(samples: &[f32], max_step: f32) -> Vec<usize> {
    samples
        .windows(2)
        .enumerate()
        .filter(|(_, w)| (w[1] - w[0]).abs() > max_step)
        .map(|(i, _)| i + 1)
        .collect()
}

/// Longest run of exact zeros in `samples` (a dropout inside a signal that
/// should be continuous).
pub(crate) fn longest_silence(samples: &[f32]) -> usize {
    let mut longest = 0;
    let mut run = 0;
    for &s in samples {
        run = if s == 0.0 { run + 1 } else { 0 };
        longest = longest.max(run);
    }
    longest
}

/// Rising zero crossings per second: the pitch of a clean tone.
pub(crate) fn frequency(samples: &[f32], sample_rate: u32) -> f64 {
    let rising = samples
        .windows(2)
        .filter(|w| w[0] < 0.0 && w[1] >= 0.0)
        .count();
    rising as f64 * f64::from(sample_rate) / samples.len() as f64
}
