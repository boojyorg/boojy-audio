//! Sample-rate conversion at the device boundary.
//!
//! The engine renders, records and runs its effects at `TARGET_SAMPLE_RATE`.
//! A device that runs at another rate (headphones that only offer 44.1 kHz,
//! a Bluetooth headset at 16 kHz) gets converted audio on the way out
//! ([`OutputConverter`]) and gives converted audio on the way in
//! ([`InputConverter`]). At the engine rate the output is not converted at
//! all, so a 48 kHz device hears exactly what it did before.
//!
//! Everything is allocated when the stream opens: the audio callbacks only
//! copy and filter.

use crate::audio_file::TARGET_SAMPLE_RATE;
use rubato::{
    calculate_cutoff, Resampler, SincFixedIn, SincFixedOut, SincInterpolationParameters,
    SincInterpolationType, WindowFunction,
};

/// Frames per conversion step: device frames out, device frames in. Small,
/// so a step adds about a millisecond of delay.
const CHUNK: usize = 64;

/// Filter length. 128 taps keep the passband flat to ~20 kHz at 44.1 kHz.
const SINC_LEN: usize = 128;

/// Engine frames the output converter can hold between conversion steps.
/// Larger device buffers are converted in several steps.
const PENDING_CAPACITY: usize = 4096;

/// The largest clock correction the input converter applies (±0.5%, about
/// 9 cents: far beyond real clock drift, small enough to stay inaudible).
const MAX_STEER: f64 = 1.005;

/// How hard the input converter corrects: ratio change per frame of error
/// in the input buffer's level. Gives a ~2 s correction time against the
/// level's ~1 s average, which settles without overshoot.
const STEER_GAIN: f64 = 1e-5;

fn engine_rate() -> f64 {
    f64::from(TARGET_SAMPLE_RATE)
}

/// Fold `value` into a running average over about a second of audio;
/// `frames` is how many engine frames passed since the last value.
fn smooth(average: f64, value: f64, frames: usize) -> f64 {
    if average.is_nan() {
        return value;
    }
    average + (frames as f64 / engine_rate()).min(1.0) * (value - average)
}

fn sinc_params() -> SincInterpolationParameters {
    let window = WindowFunction::BlackmanHarris2;
    SincInterpolationParameters {
        sinc_len: SINC_LEN,
        f_cutoff: calculate_cutoff(SINC_LEN, window),
        oversampling_factor: 256,
        interpolation: SincInterpolationType::Linear,
        window,
    }
}

/// Converts the engine's stereo output to the device's rate. One per output
/// stream, owned by its callback.
pub(crate) struct OutputConverter {
    resampler: SincFixedOut<f32>,
    /// Engine frames per device frame.
    engine_per_device: f64,
    /// Engine frames rendered but not yet converted.
    pending_l: Vec<f32>,
    pending_r: Vec<f32>,
    pending: usize,
    /// One render call's interleaved stereo output.
    render_buf: Vec<f32>,
    /// The last converted step, written out from `out_pos`.
    out_l: Vec<f32>,
    out_r: Vec<f32>,
    out_len: usize,
    out_pos: usize,
    /// Engine frames held between callbacks (rendered, not yet played),
    /// averaged.
    held: f64,
}

impl OutputConverter {
    /// A converter for a device at `device_rate`, or `None` when the device
    /// runs at the engine rate and needs none.
    pub(crate) fn new(device_rate: u32) -> Option<Self> {
        if device_rate == TARGET_SAMPLE_RATE || device_rate == 0 {
            return None;
        }
        let ratio = f64::from(device_rate) / engine_rate();
        let resampler = SincFixedOut::<f32>::new(ratio, 1.0, sinc_params(), CHUNK, 2).ok()?;
        debug_assert!(resampler.input_frames_max() < PENDING_CAPACITY);
        Some(Self {
            resampler,
            engine_per_device: 1.0 / ratio,
            pending_l: vec![0.0; PENDING_CAPACITY],
            pending_r: vec![0.0; PENDING_CAPACITY],
            pending: 0,
            render_buf: vec![0.0; PENDING_CAPACITY * 2],
            out_l: vec![0.0; CHUNK],
            out_r: vec![0.0; CHUNK],
            out_len: 0,
            out_pos: 0,
            held: f64::NAN,
        })
    }

    /// Fill `frames` device frames. `render` fills an interleaved stereo
    /// buffer with the next engine frames (it advances the playhead);
    /// `write` receives each converted device frame by index.
    pub(crate) fn fill(
        &mut self,
        frames: usize,
        mut render: impl FnMut(&mut [f32]),
        mut write: impl FnMut(usize, f32, f32),
    ) {
        let mut written = 0;
        while written < frames {
            if self.out_pos == self.out_len && !self.convert_step(frames - written, &mut render) {
                // Can't happen with the buffers sized in `new`; play silence
                // rather than stall the device.
                for i in written..frames {
                    write(i, 0.0, 0.0);
                }
                return;
            }
            let n = (self.out_len - self.out_pos).min(frames - written);
            for i in 0..n {
                let j = self.out_pos + i;
                write(written + i, self.out_l[j], self.out_r[j]);
            }
            self.out_pos += n;
            written += n;
        }
        let held =
            self.pending as f64 + (self.out_len - self.out_pos) as f64 * self.engine_per_device;
        self.held = smooth(
            self.held,
            held,
            (frames as f64 * self.engine_per_device) as usize,
        );
    }

    /// Convert one step, rendering first if the pending engine frames don't
    /// cover it. `remaining` device frames are still owed this callback, so
    /// one render call can cover them all instead of many small ones.
    fn convert_step(&mut self, remaining: usize, render: &mut impl FnMut(&mut [f32])) -> bool {
        let need = self.resampler.input_frames_next();
        if self.pending < need {
            let steps = remaining.div_ceil(CHUNK);
            let estimate = ((steps * CHUNK) as f64 * self.engine_per_device).ceil() as usize + 2;
            let want = estimate
                .max(need)
                .min(PENDING_CAPACITY)
                .saturating_sub(self.pending);
            let buf = &mut self.render_buf[..want * 2];
            render(buf);
            for (i, frame) in buf.as_chunks::<2>().0.iter().enumerate() {
                self.pending_l[self.pending + i] = frame[0];
                self.pending_r[self.pending + i] = frame[1];
            }
            self.pending += want;
        }
        let input = [
            &self.pending_l[..self.pending],
            &self.pending_r[..self.pending],
        ];
        let mut output = [&mut self.out_l[..], &mut self.out_r[..]];
        let Ok((used, made)) = self
            .resampler
            .process_into_buffer(&input, &mut output, None)
        else {
            return false;
        };
        self.pending_l.copy_within(used..self.pending, 0);
        self.pending_r.copy_within(used..self.pending, 0);
        self.pending -= used;
        self.out_len = made;
        self.out_pos = 0;
        made > 0
    }

    /// Drop everything rendered but not yet heard (Stop, New Project), so
    /// the next sound starts clean.
    pub(crate) fn flush(&mut self) {
        self.resampler.reset();
        self.pending = 0;
        self.out_len = 0;
        self.out_pos = 0;
    }

    /// Average engine frames between rendering a frame and the device
    /// playing it, beyond what a 48 kHz device adds: what's held between
    /// callbacks, plus the filter's delay.
    pub(crate) fn delay_engine_frames(&self) -> f64 {
        let held = if self.held.is_nan() { 0.0 } else { self.held };
        held + self.resampler.output_delay() as f64 * self.engine_per_device
    }
}

/// Converts a microphone's frames to the engine rate, and steers the
/// conversion so a microphone on its own clock keeps pace with the output.
/// One per input stream, owned by its callback.
pub struct InputConverter {
    resampler: SincFixedIn<f32>,
    /// 1 (mono) or 2 (stereo).
    channels: usize,
    /// Engine frames per device frame at the nominal rates.
    engine_per_device: f64,
    in_l: Vec<f32>,
    in_r: Vec<f32>,
    filled: usize,
    out_l: Vec<f32>,
    out_r: Vec<f32>,
    /// The input buffer's level, averaged over about a second.
    level: f64,
    /// Engine frames held between callbacks (in, not yet converted),
    /// averaged.
    held: f64,
}

impl InputConverter {
    pub fn new(device_rate: u32, channels: usize) -> Option<Self> {
        if device_rate == 0 {
            return None;
        }
        let channels = channels.clamp(1, 2);
        let ratio = engine_rate() / f64::from(device_rate);
        let resampler =
            SincFixedIn::<f32>::new(ratio, MAX_STEER, sinc_params(), CHUNK, channels).ok()?;
        let out_max = resampler.output_frames_max();
        Some(Self {
            resampler,
            channels,
            engine_per_device: ratio,
            in_l: vec![0.0; CHUNK],
            in_r: vec![0.0; CHUNK],
            filled: 0,
            out_l: vec![0.0; out_max],
            out_r: vec![0.0; out_max],
            level: f64::NAN,
            held: f64::NAN,
        })
    }

    /// Convert one callback's input. `data` is interleaved with `stride`
    /// channels per frame, of which the first one or two are kept; each
    /// converted engine frame goes to `push` (left, right; right repeats
    /// left for mono).
    pub fn process(&mut self, data: &[f32], stride: usize, mut push: impl FnMut(f32, f32)) {
        let stride = stride.max(1);
        for frame in data.chunks_exact(stride) {
            self.in_l[self.filled] = frame[0];
            if self.channels == 2 {
                self.in_r[self.filled] = frame.get(1).copied().unwrap_or(frame[0]);
            }
            self.filled += 1;
            if self.filled == CHUNK {
                self.filled = 0;
                self.convert_chunk(&mut push);
            }
        }
        let frames = (data.len() / stride) as f64 * self.engine_per_device;
        let held = self.filled as f64 * self.engine_per_device;
        self.held = smooth(self.held, held, frames as usize);
    }

    fn convert_chunk(&mut self, push: &mut impl FnMut(f32, f32)) {
        let result = if self.channels == 2 {
            let input = [&self.in_l[..], &self.in_r[..]];
            let mut output = [&mut self.out_l[..], &mut self.out_r[..]];
            self.resampler
                .process_into_buffer(&input, &mut output, None)
        } else {
            let input = [&self.in_l[..]];
            let mut output = [&mut self.out_l[..]];
            self.resampler
                .process_into_buffer(&input, &mut output, None)
        };
        let Ok((_, made)) = result else { return };
        for i in 0..made {
            let left = self.out_l[i];
            let right = if self.channels == 2 {
                self.out_r[i]
            } else {
                left
            };
            push(left, right);
        }
    }

    /// Nudge the conversion so the input buffer holds `target` frames.
    /// `level` is its level now, just after this callback's frames went in,
    /// and `frames` how many engine frames they were. Two devices never run
    /// at exactly the same speed; without this the buffer slowly fills
    /// (growing delay, then a skip) or empties (a click).
    pub fn steer(&mut self, level: usize, target: usize, frames: usize) {
        let target = target as f64;
        if self.level.is_nan() {
            self.level = target;
        }
        self.level = smooth(self.level, level as f64, frames);
        let correction =
            (1.0 - STEER_GAIN * (self.level - target)).clamp(1.0 / MAX_STEER, MAX_STEER);
        let _ = self.resampler.set_resample_ratio_relative(correction, true);
    }

    /// Engine frames produced per device frame right now.
    pub fn engine_per_device(&self) -> f64 {
        self.engine_per_device
    }

    /// Average engine frames between a sound reaching the converter and
    /// leaving it: what's held between callbacks, plus the filter's delay.
    pub fn delay_engine_frames(&self) -> f64 {
        let held = if self.held.is_nan() { 0.0 } else { self.held };
        held + self.resampler.output_delay() as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::TAU;

    const RATES: [u32; 5] = [16_000, 22_050, 44_100, 88_200, 96_000];

    /// A sine at `hz`, as engine frames from `start`, written to an
    /// interleaved stereo buffer: left = sine, right = -sine / 2.
    fn sine_source(hz: f32) -> impl FnMut(&mut [f32]) {
        let mut n: u64 = 0;
        move |buf: &mut [f32]| {
            for frame in buf.as_chunks_mut::<2>().0 {
                let s = (TAU * hz * n as f32 / TARGET_SAMPLE_RATE as f32).sin() * 0.5;
                frame[0] = s;
                frame[1] = -s / 2.0;
                n += 1;
            }
        }
    }

    /// Convert `seconds` of a source at the engine rate for a device at
    /// `rate`, in callbacks of `sizes` frames (cycled).
    fn convert_out(
        rate: u32,
        seconds: f64,
        sizes: &[usize],
        source: impl FnMut(&mut [f32]),
    ) -> (Vec<f32>, Vec<f32>, usize) {
        let mut conv = OutputConverter::new(rate).expect("converter");
        let total = (seconds * f64::from(rate)) as usize;
        let (mut left, mut right) = (vec![0.0; total], vec![0.0; total]);
        let mut rendered = 0usize;
        let mut source = source;
        let mut render = |buf: &mut [f32]| {
            rendered += buf.len() / 2;
            source(buf);
        };
        let mut at = 0;
        let mut i = 0;
        while at < total {
            let n = sizes[i % sizes.len()].min(total - at);
            conv.fill(n, &mut render, |j, l, r| {
                left[at + j] = l;
                right[at + j] = r;
            });
            at += n;
            i += 1;
        }
        (left, right, rendered)
    }

    /// Frequency of a sine from its rising zero crossings, skipping the
    /// converter's start-up.
    fn frequency(samples: &[f32], rate: u32) -> f64 {
        let skip = rate as usize / 10;
        let crossings: Vec<usize> = (skip + 1..samples.len())
            .filter(|&i| samples[i - 1] < 0.0 && samples[i] >= 0.0)
            .collect();
        let (first, last) = (crossings[0], crossings[crossings.len() - 1]);
        (crossings.len() - 1) as f64 * f64::from(rate) / (last - first) as f64
    }

    #[test]
    fn the_engine_rate_needs_no_converter() {
        assert!(OutputConverter::new(TARGET_SAMPLE_RATE).is_none());
    }

    #[test]
    fn a_tone_keeps_its_pitch_and_length_at_every_device_rate() {
        for rate in RATES {
            let (left, _, rendered) = convert_out(rate, 2.0, &[512], sine_source(1000.0));
            let hz = frequency(&left, rate);
            assert!((hz - 1000.0).abs() < 0.5, "{rate} Hz device heard {hz} Hz");
            // Two device seconds used two engine seconds (plus the filter's
            // look-ahead and one step).
            let extra = rendered as i64 - 2 * i64::from(TARGET_SAMPLE_RATE);
            assert!(
                (0..400).contains(&extra),
                "{rate} Hz rendered {extra} extra"
            );
        }
    }

    #[test]
    fn left_and_right_stay_separate() {
        let (left, right, _) = convert_out(44_100, 0.5, &[512], sine_source(440.0));
        for i in 4410..left.len() {
            assert!((right[i] + left[i] / 2.0).abs() < 1e-3, "frame {i}");
        }
    }

    #[test]
    fn callback_sizes_change_nothing() {
        let sizes = [1, 7, 512, 33, 2500, 64, 300, 1024, 2, 129];
        for rate in [16_000, 44_100, 96_000] {
            let (fixed, _, _) = convert_out(rate, 1.0, &[512], sine_source(440.0));
            let (ragged, _, _) = convert_out(rate, 1.0, &sizes, sine_source(440.0));
            assert_eq!(fixed, ragged, "{rate} Hz");
        }
    }

    #[test]
    fn flush_drops_what_was_rendered_but_not_heard() {
        let mut conv = OutputConverter::new(44_100).unwrap();
        let mut loud = |buf: &mut [f32]| buf.fill(0.5);
        conv.fill(500, &mut loud, |_, _, _| {});
        conv.flush();
        let mut peak = 0.0f32;
        let mut silent = |buf: &mut [f32]| buf.fill(0.0);
        conv.fill(500, &mut silent, |_, l, r| {
            peak = peak.max(l.abs()).max(r.abs());
        });
        assert!(peak < 1e-6, "old audio after flush: {peak}");
    }

    #[test]
    fn input_tone_keeps_its_pitch_mono_on_both_sides() {
        for rate in RATES {
            let mut conv = InputConverter::new(rate, 1).unwrap();
            let device: Vec<f32> = (0..rate * 2)
                .map(|n| (TAU * 1000.0 * n as f32 / rate as f32).sin() * 0.5)
                .collect();
            let (mut left, mut right) = (Vec::new(), Vec::new());
            for block in device.chunks(441) {
                conv.process(block, 1, |l, r| {
                    left.push(l);
                    right.push(r);
                });
            }
            assert_eq!(left, right, "mono duplicates");
            let hz = frequency(&left, TARGET_SAMPLE_RATE);
            assert!((hz - 1000.0).abs() < 0.5, "{rate} Hz mic recorded {hz} Hz");
            let expected = 2 * TARGET_SAMPLE_RATE as usize;
            assert!(
                left.len().abs_diff(expected) < 200,
                "{rate} Hz: {}",
                left.len()
            );
        }
    }

    #[test]
    fn input_keeps_the_first_two_channels_of_an_interface() {
        let mut conv = InputConverter::new(44_100, 2).unwrap();
        // Four channels: L = 0.25, R = -0.25, then two others that must be ignored.
        let device: Vec<f32> = (0..44_100).flat_map(|_| [0.25, -0.25, 0.9, 0.9]).collect();
        let mut last = (0.0, 0.0);
        conv.process(&device, 4, |l, r| last = (l, r));
        assert!(
            (last.0 - 0.25).abs() < 1e-3 && (last.1 + 0.25).abs() < 1e-3,
            "{last:?}"
        );
    }
}
