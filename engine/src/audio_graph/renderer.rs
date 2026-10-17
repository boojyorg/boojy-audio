/// Real-time audio render callback — runs on the audio thread
use super::{interpolate_automation_gain, AudioGraph, TransportState};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::audio_health::{
    lock_or_count, BufferTimer, GapDetector, EFFECT_LOCK_WAITS, RECORDER_LOCK_WAITS,
    SYNTH_LOCK_WAITS, TRACK_LOCK_WAITS,
};
use crate::audio_input::InputTap;
use crate::effects::{Effect, EffectManager, Limiter};
use crate::recorder::RecorderCallbackRefs;
use crate::synth::TrackSynthManager;
use crate::track::{
    AutomationPoint, TimelineClip, TimelineMidiClip, TrackId, TrackManager, TrackType,
};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;

use cpal::traits::DeviceTrait;

/// Maximum frames handed to a VST3 plugin per `process()` call. A plugin is
/// initialised with `maxSamplesPerBlock = 512` (`engine/src/api/vst3.rs`) and
/// sizes its internal buffers for that maximum, so it must never receive more.
/// The device callback size is only a hint (and a 1024 buffer preset exists),
/// so the realtime path renders in sub-blocks of at most this many frames.
/// Matches `OFFLINE_BLOCK` in `offline.rs`.
const MAX_VST3_BLOCK: usize = 512;

/// Clamp a sample to the device's valid range and replace any non-finite value
/// with silence. The device boundary is the last line of defence: a NaN/Inf
/// from a misbehaving plugin or a denormal-driven blow-up would otherwise reach
/// the DAC as full-scale noise — the master limiter passes NaN straight through
/// (`NaN > threshold` is `false`, so its gain stays 1.0).
#[inline]
fn sanitize_sample(x: f32) -> f32 {
    if x.is_finite() {
        x.clamp(-1.0, 1.0)
    } else {
        0.0
    }
}

/// Write one stereo frame into an interleaved device buffer with `channels`
/// channels, sanitizing every sample. Mono devices get the L/R average; devices
/// with more than two channels get L/R in the first two and silence elsewhere.
/// Centralizes the device-boundary write so the NaN/Inf guard and channel layout
/// live in exactly one place (was an un-guarded `data[i*2] = ..` at each site).
#[inline]
fn write_frame(data: &mut [f32], frame_idx: usize, channels: usize, left: f32, right: f32) {
    let base = frame_idx * channels;
    match channels {
        0 => {}
        1 => data[base] = sanitize_sample(left.midpoint(right)),
        _ => {
            data[base] = sanitize_sample(left);
            data[base + 1] = sanitize_sample(right);
            for ch in 2..channels {
                data[base + ch] = 0.0;
            }
        }
    }
}

/// Pure selection logic for [`select_stereo_48k_config`]: given candidate
/// `(channels, min_hz, max_hz)` ranges, return the index of the first stereo
/// range that covers `target_hz`. Extracted so it can be unit-tested without a
/// real audio device.
fn pick_stereo_config_index(ranges: &[(u16, u32, u32)], target_hz: u32) -> Option<usize> {
    ranges
        .iter()
        .position(|&(ch, min, max)| ch == 2 && min <= target_hz && target_hz <= max)
}

/// Find a device output config that is stereo and supports `target_rate`,
/// pinned to that rate. Returns `None` if the device exposes no stereo config
/// covering the target rate (caller falls back to the device default).
fn select_stereo_48k_config(
    device: &cpal::Device,
    target_rate: cpal::SampleRate,
) -> Option<cpal::SupportedStreamConfig> {
    let ranges: Vec<cpal::SupportedStreamConfigRange> =
        device.supported_output_configs().ok()?.collect();
    let triples: Vec<(u16, u32, u32)> = ranges
        .iter()
        .map(|r| (r.channels(), r.min_sample_rate().0, r.max_sample_rate().0))
        .collect();
    let idx = pick_stereo_config_index(&triples, target_rate.0)?;
    Some(ranges[idx].with_sample_rate(target_rate))
}

/// Track snapshot data extracted from locked tracks for lock-free audio processing.
/// Defined at module scope so helper functions can reference it.
struct TrackSnapshot {
    id: u64,
    audio_clips: Vec<TimelineClip>,
    midi_clips: Vec<TimelineMidiClip>,
    volume_gain: f32, // Static volume (used when no automation)
    pan_left: f32,
    pan_right: f32,
    muted: bool,
    soloed: bool,
    fx_chain: Vec<u64>,
    sends: Vec<(u64, f32)>,
    volume_automation: Vec<AutomationPoint>, // For per-frame interpolation
    armed: bool,
    input_monitoring: bool,
    input_channel: u32,
    is_audio_track: bool,
    monitoring_fade_gain: f64,
}

/// Slim per-track snapshot for the STOPPED path (no timeline clips play, so
/// cloning the clip/automation vectors would be pure allocator pressure).
/// Peaks accumulate here during the buffer and are written back to the track
/// under a brief end-of-buffer lock, exactly like the playing path.
struct StoppedTrackSnapshot {
    id: u64,
    volume_gain: f32,
    pan_left: f32,
    pan_right: f32,
    muted: bool,
    soloed: bool,
    fx_chain: Vec<u64>,
    armed: bool,
    input_monitoring: bool,
    input_channel: u32,
    is_audio_track: bool,
    monitoring_fade_gain: f64,
    peak_left: f32,
    peak_right: f32,
}

// ── Helper functions for the audio callback ─────────────────────────────
// These are called from the hot path — no allocations, no panics.

/// Update monitoring fade gain with a 20ms ramp to avoid clicks.
/// Modifies `fade_gain` in place toward 0.0 or 1.0.
/// `sample_rate` is the rate the stream actually runs at — the ramp is one
/// step per callback frame, so 20 ms is only 20 ms at the real rate (C4).
#[inline]
fn update_monitoring_fade(fade_gain: &mut f64, should_monitor: bool, sample_rate: f64) {
    let target = if should_monitor { 1.0_f64 } else { 0.0_f64 };
    #[allow(clippy::float_cmp)]
    if *fade_gain != target {
        let step = 1.0 / (0.020 * sample_rate);
        if target > *fade_gain {
            *fade_gain = (*fade_gain + step).min(1.0);
        } else {
            *fade_gain = (*fade_gain - step).max(0.0);
        }
    }
}

/// Source frame for a position already scaled to frames. Truncating
/// `x as usize` turned a float result like 52909.9999999 (meant: 52910) into
/// the previous frame on ~1 sample in 17, a repeated sample heard as grit.
/// The nudge is far below one frame, so real fractions still floor.
#[inline]
pub(crate) fn frame_at(frames: f64) -> usize {
    (frames + 1e-6) as usize
}

/// Render a single audio clip at the given playhead position.
/// Returns (left, right) sample values, or (0, 0) if the playhead is outside the clip.
#[inline]
pub(crate) fn render_audio_clip_sample(
    timeline_clip: &TimelineClip,
    playhead_seconds: f64,
) -> (f32, f32) {
    let clip_duration = timeline_clip
        .duration
        .unwrap_or(timeline_clip.clip.duration_seconds);
    let effective_duration = if timeline_clip.warp_enabled {
        clip_duration / f64::from(timeline_clip.stretch_factor)
    } else {
        clip_duration
    };
    let clip_end = timeline_clip.start_time + effective_duration;

    // Decide the edges on the frame grid (nearest frame): float error let a
    // clip play one frame past its end, and a split's two halves must agree
    // on which of them owns the frame where they meet.
    let half_frame = 0.5 / f64::from(TARGET_SAMPLE_RATE);
    if playhead_seconds < timeline_clip.start_time - half_frame
        || playhead_seconds >= clip_end - half_frame
    {
        return (0.0, 0.0);
    }

    let progress = timeline_clip.progress_in_clip(playhead_seconds, effective_duration);
    let clip_gain = timeline_clip.get_gain();

    // Processed audio (Warp stretch and/or transpose) already plays at
    // timeline speed. Re-Pitch, or Warp whose processed audio isn't there,
    // reads the source faster or slower instead. Transpose never changes
    // the read speed: it changes pitch only.
    let processed = timeline_clip.stretched_cache.as_deref();
    let warp_from_processed = timeline_clip.warp_mode == 0 && processed.is_some();
    let rate = if timeline_clip.warp_enabled && !warp_from_processed {
        f64::from(timeline_clip.stretch_factor)
    } else {
        1.0
    };
    let source_clip: &AudioClip = processed.unwrap_or(&timeline_clip.clip);
    // The trim offset is in seconds of the clip's own audio: processed audio
    // is that stretched (Warp), and only the time played since the trim
    // moves at `rate`. Stretching the offset as well made a trimmed warped
    // clip (the right half of a split) play the wrong part.
    let frame_in_clip = if let Some(loop_length) = timeline_clip.active_loop(clip_duration) {
        looped_frame(
            timeline_clip,
            playhead_seconds,
            loop_length,
            processed.is_some(),
        )
    } else {
        let offset = if processed.is_some() {
            timeline_clip.offset / f64::from(timeline_clip.processed_stretch())
        } else {
            timeline_clip.offset
        };
        frame_at((offset + progress * rate) * f64::from(TARGET_SAMPLE_RATE))
    };

    let left = source_clip.get_sample(frame_in_clip, 0).unwrap_or(0.0) * clip_gain;
    let right = if source_clip.channels > 1 {
        source_clip.get_sample(frame_in_clip, 1).unwrap_or(0.0) * clip_gain
    } else {
        left // mono clip — duplicate to right
    };

    (left, right)
}

/// Source frame of a repeating clip: the audio `loop_length` seconds long
/// from its trim offset plays again and again, starting `loop_start` into it,
/// each repeat backwards when the clip is reversed (as the timeline draws it).
/// Worked in frames of the clip's own audio, where the loop is defined, then
/// scaled to the audio being read (processed audio is stretched by Warp).
#[inline]
fn looped_frame(
    timeline_clip: &TimelineClip,
    playhead_seconds: f64,
    loop_length: f64,
    from_processed: bool,
) -> usize {
    let rate = f64::from(TARGET_SAMPLE_RATE);
    // Frames of the clip's own audio per frame of timeline.
    let own_per_frame = if timeline_clip.warp_enabled {
        f64::from(timeline_clip.stretch_factor)
    } else {
        1.0
    };
    let loop_frames = loop_length * rate;
    let played = (playhead_seconds - timeline_clip.start_time) * rate * own_per_frame;
    // Nudged like `frame_at` before wrapping, so a position float error left
    // a hair short of the loop's end wraps to its start, not its last frame.
    let x = timeline_clip.loop_start * rate + played + 1e-6;
    let mut in_loop = x - (x / loop_frames).floor() * loop_frames - 1e-6;
    if timeline_clip.reversed {
        // Reflect onto the loop's last frame (see `progress_in_clip`).
        in_loop = (loop_frames - own_per_frame - in_loop).max(0.0);
    }
    let scale = if from_processed {
        f64::from(timeline_clip.processed_stretch())
    } else {
        1.0
    };
    frame_at((timeline_clip.offset * rate + in_loop.max(0.0)) / scale)
}

/// Process an effect chain through a locked `EffectManager`.
/// When `silent` is true, feeds zeros to keep VST3 plugins alive (muted tracks).
///
/// `meter_gain` scales the values passed to `update_peaks` so that effect strip
/// meters reflect the post-fader level (pass `volume_gain` from the track
/// snapshot; pass `1.0` for silent or already-scaled buffers).
#[inline]
fn process_effect_chain(
    fx_chain: &[u64],
    effect_mgr: &mut EffectManager,
    left: f32,
    right: f32,
    silent: bool,
    meter_gain: f32,
) -> (f32, f32) {
    let mut out_l = if silent { 0.0 } else { left };
    let mut out_r = if silent { 0.0 } else { right };
    for effect_id in fx_chain {
        if !silent && effect_mgr.is_bypassed(*effect_id) {
            // Bypassed: signal passes through, update peaks with passthrough level
            effect_mgr.update_peaks(
                *effect_id,
                out_l.abs() * meter_gain,
                out_r.abs() * meter_gain,
            );
            continue;
        }
        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
            let mut effect = lock_or_count(&effect_arc, &EFFECT_LOCK_WAITS);
            let (fx_l, fx_r) = effect.process_frame(out_l, out_r);
            out_l = fx_l;
            out_r = fx_r;
            // Capture output peak after this effect, scaled to post-fader level
            effect_mgr.update_peaks(
                *effect_id,
                out_l.abs() * meter_gain,
                out_r.abs() * meter_gain,
            );
        }
    }
    (out_l, out_r)
}

/// Peak (max absolute value) of a sample buffer.
#[inline]
fn block_peak(buf: &[f32]) -> f32 {
    buf.iter().fold(0.0f32, |m, &x| m.max(x.abs()))
}

/// Per-buffer sibling of [`process_effect_chain`]: run an FX chain over a whole
/// block in-place, calling each effect's `process_block` once. Built-in effects
/// loop `process_frame` internally (identical output to the per-sample path);
/// VST3 plugins process the whole block in a single `process()` call — the win.
///
/// Bypass and per-effect peak metering match the per-sample path: a bypassed
/// effect passes through and meters the passthrough level, and `update_peaks`
/// is a running max, so one call per block with the block peak is equivalent to
/// calling it every sample. When `silent`, the buffers are zeroed first and the
/// whole chain still runs (keeps VST3 plugins ticking on muted/non-solo tracks).
/// `meter_gain` scales `update_peaks` values to post-fader level — see
/// [`process_effect_chain`] for the contract.
fn process_effect_chain_block(
    fx_chain: &[u64],
    effect_mgr: &mut EffectManager,
    left: &mut [f32],
    right: &mut [f32],
    silent: bool,
    meter_gain: f32,
) {
    if silent {
        left.fill(0.0);
        right.fill(0.0);
    }
    for effect_id in fx_chain {
        if !silent && effect_mgr.is_bypassed(*effect_id) {
            // Bypassed: signal passes through; meter the passthrough level.
            effect_mgr.update_peaks(
                *effect_id,
                block_peak(left) * meter_gain,
                block_peak(right) * meter_gain,
            );
            continue;
        }
        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
            {
                let mut effect = lock_or_count(&effect_arc, &EFFECT_LOCK_WAITS);
                effect.process_block(left, right);
            }
            // Capture output peak after this effect, scaled to post-fader level.
            effect_mgr.update_peaks(
                *effect_id,
                block_peak(left) * meter_gain,
                block_peak(right) * meter_gain,
            );
        }
    }
}

impl AudioGraph {
    /// Create the audio output stream - native only
    pub(crate) fn create_audio_stream(&self) -> anyhow::Result<cpal::Stream> {
        use cpal::traits::HostTrait;
        use cpal::SupportedBufferSize;

        // Helper to find device by name from a host
        fn find_device_in_host<H: HostTrait>(host: &H, name: &str) -> Option<H::Device> {
            host.output_devices()
                .ok()?
                .find(|d| d.name().ok().as_ref().is_some_and(|n| n == name))
        }

        // A fresh stream supersedes any earlier device failure (C99).
        self.stream_error.lock().take();

        // Check if a specific device is selected
        let selected_name = self.selected_output_device.lock().clone();

        // Determine if we should use ASIO host and get the device
        #[cfg(all(windows, feature = "asio"))]
        let device = if let Some(ref name) = selected_name {
            if name.starts_with("[ASIO] ") {
                let actual_name = name.strip_prefix("[ASIO] ").unwrap_or(name);
                dlog!(
                    "🔊 [AudioGraph] Attempting to use ASIO device: {}",
                    actual_name
                );

                match cpal::host_from_id(cpal::HostId::Asio) {
                    Ok(asio_host) => match find_device_in_host(&asio_host, actual_name) {
                        Some(d) => {
                            dlog!("🔊 [AudioGraph] Using ASIO device: {}", actual_name);
                            d
                        }
                        None => {
                            eprintln!("⚠️ [AudioGraph] ASIO device '{}' not found, falling back to default", actual_name);
                            cpal::default_host()
                                .default_output_device()
                                .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                        }
                    },
                    Err(e) => {
                        eprintln!("⚠️ [AudioGraph] Failed to initialize ASIO host: {}, falling back to default", e);
                        cpal::default_host()
                            .default_output_device()
                            .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                    }
                }
            } else {
                // Non-ASIO device, use default host
                let host = cpal::default_host();
                match find_device_in_host(&host, name) {
                    Some(d) => {
                        dlog!("🔊 [AudioGraph] Using selected output device: {}", name);
                        d
                    }
                    None => {
                        eprintln!(
                            "⚠️ [AudioGraph] Selected device '{}' not found, using default",
                            name
                        );
                        host.default_output_device()
                            .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                    }
                }
            }
        } else {
            cpal::default_host()
                .default_output_device()
                .ok_or_else(|| anyhow::anyhow!("No output device available"))?
        };

        #[cfg(not(all(windows, feature = "asio")))]
        let device = {
            let host = cpal::default_host();
            if let Some(ref name) = selected_name {
                if let Some(d) = find_device_in_host(&host, name) {
                    dlog!("🔊 [AudioGraph] Using selected output device: {name}");
                    d
                } else {
                    eprintln!("⚠️ [AudioGraph] Selected device '{name}' not found, using default");
                    host.default_output_device()
                        .ok_or_else(|| anyhow::anyhow!("No output device available"))?
                }
            } else {
                host.default_output_device()
                    .ok_or_else(|| anyhow::anyhow!("No output device available"))?
            }
        };

        // Log device info
        if let Ok(name) = device.name() {
            dlog!("🔊 [AudioGraph] Using device: {name}");
        }

        let default_config = device.default_output_config()?;
        dlog!("🔊 [AudioGraph] Device default config: {default_config:?}");

        // Prefer an explicit stereo 48 kHz config. Many devices *support* stereo
        // 48 kHz but report a different default (e.g. 44.1 kHz, or a mono/aggregate
        // layout) — inheriting that default makes playback run at the wrong pitch or
        // scrambles channels, because all engine time-math assumes TARGET_SAMPLE_RATE
        // and the callback assumes interleaved stereo. So request 48 kHz stereo
        // explicitly when the device can provide it, and fall back (with a loud
        // warning) to the device default otherwise. True sample-rate conversion for
        // 48k-incapable devices is deferred to a later cycle.
        let target_rate = cpal::SampleRate(TARGET_SAMPLE_RATE);
        let supported_config = if let Some(cfg) = select_stereo_48k_config(&device, target_rate) {
            dlog!("🔊 [AudioGraph] Using stereo {TARGET_SAMPLE_RATE} Hz config: {cfg:?}");
            cfg
        } else {
            eprintln!(
                "⚠️ [AudioGraph] Output device cannot provide stereo {} Hz (default is \
                 {:?}, {} ch). Playback may be pitched or use the wrong channel layout \
                 until sample-rate conversion is implemented.",
                TARGET_SAMPLE_RATE,
                default_config.sample_rate(),
                default_config.channels()
            );
            default_config
        };

        // Channel count of the stream we're actually opening. The callback uses this
        // (not a hard-coded 2) to lay out interleaved frames.
        let channels = (supported_config.channels() as usize).max(1);

        // Get preferred buffer size
        let preferred_samples = self.preferred_buffer_size.lock().samples();

        // Check if device supports our preferred buffer size
        let buffer_size = match supported_config.buffer_size() {
            SupportedBufferSize::Range { min, max } => {
                // Handle invalid range (e.g., iOS simulator reports [0-0])
                if *max == 0 {
                    dlog!("🔊 [AudioGraph] Buffer size: device reports invalid range [{min}-{max}], using default");
                    None
                } else {
                    let clamped = preferred_samples.clamp(*min, *max);
                    dlog!("🔊 [AudioGraph] Buffer size: requested={preferred_samples}, device range=[{min}-{max}], using={clamped}");
                    Some(cpal::BufferSize::Fixed(clamped))
                }
            }
            SupportedBufferSize::Unknown => {
                dlog!("🔊 [AudioGraph] Buffer size: device doesn't report range, using default");
                None
            }
        };

        // Build stream config with our buffer size preference
        let mut config: cpal::StreamConfig = supported_config.into();
        if let Some(buf_size) = buffer_size {
            config.buffer_size = buf_size;
        }

        // Clone for tracking actual buffer size in callback
        let actual_buffer_size = self.actual_buffer_size.clone();

        // C12: tell the filter-based effects (EQ/Compressor/Limiter) the real stream
        // rate so their coefficients are correct in the non-48k fallback path. Done
        // before the stream starts; new effects inherit it via create_effect. (The
        // wider engine time-math still assumes TARGET_SAMPLE_RATE — see the config
        // selection comment above.)
        let stream_sample_rate = config.sample_rate.0 as f32;
        self.effect_manager
            .lock()
            .set_sample_rate(stream_sample_rate);
        self.master_limiter
            .lock()
            .set_sample_rate(stream_sample_rate);

        // Publish the real stream rate so the rest of the engine (recording
        // duration math C22, offline-render pin/restore) can read it.
        self.stream_sample_rate
            .store(config.sample_rate.0, Ordering::Relaxed);
        // Audio health (dropout counters): the buffer budget and gap check
        // need the stream's real rate.
        let stream_rate = config.sample_rate.0;
        let mut gap_detector = GapDetector::new(stream_rate);

        // The callback's render state, with the monitoring fade ramp (C4) at the
        // stream's rate. Built here so the audio thread never allocates.
        let mut render = self.realtime_render(f64::from(config.sample_rate.0));

        let stream = device.build_output_stream(
            &config,
            move |data: &mut [f32], info: &cpal::OutputCallbackInfo| {
                // Flush denormals to zero for the duration of this callback. Denormalised
                // floats in the reverb/delay feedback paths are 10–100× slower to process on
                // x86, spiking CPU on quiet tails. Apple Silicon flushes by default; this is
                // the x86 fix and a no-op elsewhere.
                #[cfg(target_arch = "x86_64")]
                #[allow(deprecated)]
                // _mm_{get,set}csr is the standard denormal-flush mechanism
                unsafe {
                    use std::arch::x86_64::{_mm_getcsr, _mm_setcsr};
                    _mm_setcsr(_mm_getcsr() | 0x8040); // FTZ (bit 15) | DAZ (bit 6)
                }

                // Track actual buffer size. `channels` is the opened stream's channel count
                // (not a hard-coded 2), so non-stereo devices don't scramble the frame math.
                let frames = data.len() / channels;
                actual_buffer_size.store(frames as u32, Ordering::Relaxed);

                // Audio health: time this buffer (recorded when the timer drops at the
                // end of the callback) and check the device didn't skip one.
                let _buffer_timer = BufferTimer::start(frames, stream_rate);
                gap_detector.on_callback(info.timestamp().callback, frames);

                render.render(data, channels);
            },
            {
                // C99: publish stream failures (device disconnect) so the UI
                // can stop the transport and tell the user, instead of the
                // playhead advancing in silence.
                let stream_error = self.stream_error.clone();
                move |err| {
                    eprintln!("Audio stream error: {err}");
                    *stream_error.lock() = Some(err.to_string());
                }
            },
            None,
        )?;

        Ok(stream)
    }
}

/// Everything the realtime callback renders with: the graph's shared state
/// plus scratch buffers allocated up front, so the audio thread never
/// allocates in steady state. [`RealtimeRender::render`] is the callback body;
/// the device callback adds only the device-specific parts (denormal flush,
/// buffer timing and gap detection).
pub(crate) struct RealtimeRender {
    playhead_samples: Arc<AtomicU64>,
    state: Arc<AtomicU8>,
    /// The audio thread's own end of the input: never waits on the input
    /// manager, which the UI locks for meters.
    input_tap: Arc<InputTap>,
    recorder_refs: RecorderCallbackRefs,
    track_manager: Arc<Mutex<TrackManager>>,
    effect_manager: Arc<Mutex<EffectManager>>,
    master_limiter: Arc<Mutex<Limiter>>,
    track_synth_manager: Arc<Mutex<TrackSynthManager>>,
    /// Rate of the monitoring fade ramp (C4).
    monitoring_ramp_rate: f64,
    snapshot_buf: Vec<TrackSnapshot>,
    return_snapshot_buf: Vec<TrackSnapshot>,
    peak_buf: HashMap<TrackId, (f32, f32)>,
    stopped_snapshot_buf: Vec<StoppedTrackSnapshot>,
    // Per-buffer (sub-block) scratch buffers for the playing path. The FX chain
    // runs once per sub-block via `process_block` (so VST3 plugins process a whole
    // buffer per call instead of one sample at a time).
    scratch_l: Vec<f32>,
    scratch_r: Vec<f32>,
    mix_l: Vec<f32>,
    mix_r: Vec<f32>,
    master_l: Vec<f32>,
    master_r: Vec<f32>,
    input_l: Vec<f32>,
    input_r: Vec<f32>,
    /// Per-return block accumulators (num_returns × block_len).
    return_bus_l: Vec<Vec<f32>>,
    return_bus_r: Vec<Vec<f32>>,
    /// Reusable VST3 MIDI event queue: (event_type, channel, data1, data2, sample_offset).
    vst3_events: Vec<(i32, i32, i32, i32, i32)>,
}

impl AudioGraph {
    /// The realtime callback's render state for this graph, with the
    /// monitoring fade ramp at `monitoring_ramp_rate`.
    pub(crate) fn realtime_render(&self, monitoring_ramp_rate: f64) -> RealtimeRender {
        RealtimeRender {
            playhead_samples: self.playhead_samples.clone(),
            state: self.state.clone(),
            input_tap: self.input_manager.lock().tap(),
            recorder_refs: self.recorder.get_callback_refs(),
            track_manager: self.track_manager.clone(),
            effect_manager: self.effect_manager.clone(),
            master_limiter: self.master_limiter.clone(),
            track_synth_manager: self.track_synth_manager.clone(),
            monitoring_ramp_rate,
            snapshot_buf: Vec::with_capacity(16),
            return_snapshot_buf: Vec::with_capacity(4),
            peak_buf: HashMap::with_capacity(16),
            stopped_snapshot_buf: Vec::with_capacity(16),
            scratch_l: Vec::with_capacity(2048),
            scratch_r: Vec::with_capacity(2048),
            mix_l: Vec::with_capacity(2048),
            mix_r: Vec::with_capacity(2048),
            master_l: Vec::with_capacity(2048),
            master_r: Vec::with_capacity(2048),
            input_l: Vec::with_capacity(2048),
            input_r: Vec::with_capacity(2048),
            return_bus_l: Vec::with_capacity(4),
            return_bus_r: Vec::with_capacity(4),
            vst3_events: Vec::with_capacity(128),
        }
    }
}

impl RealtimeRender {
    /// Render one device buffer into `data` (interleaved, `channels` per
    /// frame) and advance the playhead while playing.
    pub(crate) fn render(&mut self, data: &mut [f32], channels: usize) {
        let frames = data.len() / channels;
        let monitoring_ramp_rate = self.monitoring_ramp_rate;
        let Self {
            playhead_samples,
            state,
            input_tap,
            recorder_refs,
            track_manager,
            effect_manager,
            master_limiter,
            track_synth_manager,
            monitoring_ramp_rate: _,
            snapshot_buf,
            return_snapshot_buf,
            peak_buf,
            stopped_snapshot_buf,
            scratch_l,
            scratch_r,
            mix_l,
            mix_r,
            master_l,
            master_r,
            input_l,
            input_r,
            return_bus_l,
            return_bus_r,
            vst3_events,
        } = self;

        // Check if we should be playing (lock-free atomic read)
        let is_playing = state.load(Ordering::SeqCst) == TransportState::Playing as u8;

        if !is_playing {
            // Even when not playing, we might be recording or using virtual piano
            // Process metronome, recording, AND synths (for real-time MIDI input)
            // but DON'T advance playhead or trigger MIDI clips from timeline

            // Lock the synth, effect, and track managers ONCE for the
            // whole buffer, counting any wait (`lock_or_count`), like
            // the playing path. The stopped path used to
            // re-acquire effect_manager and track_manager *per sample*
            // with blocking locks (C1) — the exact realtime stall the
            // playing path was deliberately hardened against.
            //
            // LOCK ORDER: track_manager BEFORE effect_manager — the API
            // layer (api/effects.rs add/remove_effect_to_track) takes
            // track→effect; acquiring effect→track here is an AB/BA
            // deadlock that silently froze the UI on add/remove-effect
            // while stopped (C32).
            let mut synth_guard = Some(lock_or_count(track_synth_manager, &SYNTH_LOCK_WAITS));
            // Snapshot per-track state under a SHORT track_manager
            // lock instead of holding it across the whole buffer. The
            // stopped path used to keep track_manager locked for every
            // frame of the callback, so any UI FFI call that walks the
            // track list (mute/solo/arm writes, meter polling) stalled
            // behind the audio thread — the suspected root cause of
            // the 100–400 ms M/S/R/I button lag while stopped (#19).
            // Peaks and monitoring fade gains accumulate in the
            // snapshot and are written back under a brief lock after
            // the buffer, mirroring the playing path.
            stopped_snapshot_buf.clear();
            let has_solo = {
                let tm = lock_or_count(track_manager, &TRACK_LOCK_WAITS);
                for track_arc in tm.get_all_tracks() {
                    let track = lock_or_count(&track_arc, &TRACK_LOCK_WAITS);
                    // Skip master track in per-track processing
                    if track.track_type == TrackType::Master {
                        continue;
                    }
                    stopped_snapshot_buf.push(StoppedTrackSnapshot {
                        id: track.id,
                        volume_gain: track.get_gain(),
                        pan_left: track.get_pan_gains().0,
                        pan_right: track.get_pan_gains().1,
                        muted: track.mute,
                        soloed: track.solo,
                        fx_chain: track.fx_chain.clone(),
                        armed: track.armed,
                        input_monitoring: track.input_monitoring,
                        input_channel: track.input_channel,
                        is_audio_track: track.track_type == TrackType::Audio,
                        monitoring_fade_gain: track.monitoring_fade_gain,
                        peak_left: 0.0,
                        peak_right: 0.0,
                    });
                }
                tm.has_solo()
            }; // track_manager released — UI calls proceed while we render

            let mut effect_guard = lock_or_count(effect_manager, &EFFECT_LOCK_WAITS);

            let mut master_peak_left = 0.0f32;
            let mut master_peak_right = 0.0f32;

            for frame_idx in 0..frames {
                let (input_left, input_right) = input_tap.read_frame();

                // Process recording and get metronome output
                let (met_left, met_right) =
                    recorder_refs.process_frame(input_left, input_right, false);

                // Start with metronome output
                let mut out_left = met_left;
                let mut out_right = met_right;

                // Process each track (synth + VST3 instruments + volume/pan + metering)
                // This is necessary for:
                // 1. Per-track synthesizer output from MIDI input
                // 2. VST3 instruments that need continuous process() calls
                // 3. Track-level metering for level meters in UI
                for snap in stopped_snapshot_buf.iter_mut() {
                    // Get per-track synth output FIRST
                    let mut track_left = 0.0f32;
                    let mut track_right = 0.0f32;

                    if let Some(ref mut synth_manager) = synth_guard {
                        let (synth_left, synth_right) =
                            synth_manager.process_sample_stereo(snap.id);
                        track_left += synth_left;
                        track_right += synth_right;
                    }

                    // Input monitoring: mix live input for armed audio tracks
                    {
                        let should_monitor =
                            snap.armed && snap.input_monitoring && snap.is_audio_track;
                        update_monitoring_fade(
                            &mut snap.monitoring_fade_gain,
                            should_monitor,
                            monitoring_ramp_rate,
                        );

                        if snap.monitoring_fade_gain > 0.0 {
                            // Only a stereo pair is captured: even
                            // channels map to left, odd to right (C9 —
                            // previously every channel >= 1 monitored right).
                            let ch = snap.input_channel as usize;
                            let input_sample = if ch.is_multiple_of(2) {
                                input_left
                            } else {
                                input_right
                            };
                            track_left += input_sample * snap.monitoring_fade_gain as f32;
                            track_right += input_sample * snap.monitoring_fade_gain as f32;
                        }
                    }

                    // Handle mute/solo (FX still run on silence to keep
                    // VST3 alive; peaks stay at 0)
                    if snap.muted || (has_solo && !snap.soloed) {
                        process_effect_chain(
                            &snap.fx_chain,
                            &mut effect_guard,
                            0.0,
                            0.0,
                            true,
                            1.0,
                        );
                        continue;
                    }

                    // Process FX chain for this track
                    let (fx_l, fx_r) = process_effect_chain(
                        &snap.fx_chain,
                        &mut effect_guard,
                        track_left,
                        track_right,
                        false,
                        snap.volume_gain,
                    );

                    // Apply track volume and pan AFTER FX chain
                    track_left = fx_l * snap.volume_gain * snap.pan_left;
                    track_right = fx_r * snap.volume_gain * snap.pan_right;

                    // Accumulate peak levels for metering (written back
                    // to the track after the buffer)
                    snap.peak_left = snap.peak_left.max(track_left.abs());
                    snap.peak_right = snap.peak_right.max(track_right.abs());

                    // Mix into output
                    out_left += track_left;
                    out_right += track_right;
                }

                // Master peak over the WHOLE buffer (the old per-frame
                // variable only ever recorded the final frame's level)
                master_peak_left = master_peak_left.max(out_left.abs());
                master_peak_right = master_peak_right.max(out_right.abs());

                // Mix library preview audio (independent of transport)
                let (preview_left, preview_right) = crate::api::preview::preview_process_sample();
                out_left += preview_left;
                out_right += preview_right;

                // Output metronome + synths + VST3 + preview when not playing
                write_frame(data, frame_idx, channels, out_left, out_right);
            }

            // Release effect manager BEFORE re-acquiring track_manager
            // (the C32 track→effect lock order).
            drop(effect_guard);

            // Brief end-of-buffer lock: write back peaks + monitoring
            // fade gains (update_peaks is a running max, so muted
            // tracks' 0.0 entries leave their meters untouched —
            // matching the old per-frame behaviour).
            {
                let tm = lock_or_count(track_manager, &TRACK_LOCK_WAITS);
                for snap in stopped_snapshot_buf.iter() {
                    if let Some(track_arc) = tm.get_track(snap.id) {
                        let mut track = lock_or_count(&track_arc, &TRACK_LOCK_WAITS);
                        track.monitoring_fade_gain = snap.monitoring_fade_gain;
                        track.update_peaks(snap.peak_left, snap.peak_right);
                    }
                }
                let master_arc = tm.get_master_track();
                lock_or_count(&master_arc, &TRACK_LOCK_WAITS)
                    .update_peaks(master_peak_left, master_peak_right);
            }
            return;
        }

        // frames already calculated at top of callback
        let current_playhead = playhead_samples.load(Ordering::SeqCst);

        // Timeline positions live in REAL seconds — the same domain the
        // playhead, MIDI clips, automation points and the UI all use.
        // Tempo only changes where the UI *places* things (beats →
        // seconds), never how fast the engine advances through them.
        // (A legacy tempo/120 "playhead scaling" here made audio clips
        // start early/late AND play at the wrong speed at any tempo
        // other than 120 BPM, while MIDI clips played correctly.)

        // NOTE: Legacy MIDI clip processing removed - all MIDI now handled per-track

        // M5.5: Track-based mixing (replaces legacy clip mixing)

        // Reuse pre-allocated buffers (clear without deallocating)
        snapshot_buf.clear();
        return_snapshot_buf.clear();
        peak_buf.clear();

        let (has_solo, master_snapshot, return_index) = {
            let tm = lock_or_count(track_manager, &TRACK_LOCK_WAITS);
            let has_solo_flag = tm.has_solo();
            let all_tracks = tm.get_all_tracks();
            let mut master_snap = None;

            for track_arc in all_tracks {
                {
                    let track = lock_or_count(&track_arc, &TRACK_LOCK_WAITS);
                    let snap = TrackSnapshot {
                        id: track.id,
                        audio_clips: track.audio_clips.clone(),
                        midi_clips: track.midi_clips.clone(),
                        volume_gain: track.get_gain(),
                        pan_left: track.get_pan_gains().0,
                        pan_right: track.get_pan_gains().1,
                        muted: track.mute,
                        soloed: track.solo,
                        fx_chain: track.fx_chain.clone(),
                        sends: track
                            .sends
                            .iter()
                            .map(|send| (send.target_track_id, send.amount))
                            .collect(),
                        volume_automation: track.volume_automation.clone(),
                        armed: track.armed,
                        input_monitoring: track.input_monitoring,
                        input_channel: track.input_channel,
                        is_audio_track: track.track_type == TrackType::Audio,
                        monitoring_fade_gain: track.monitoring_fade_gain,
                    };

                    match track.track_type {
                        TrackType::Master => master_snap = Some(snap),
                        TrackType::Return => return_snapshot_buf.push(snap),
                        _ => snapshot_buf.push(snap),
                    }
                }
            }

            let return_index: HashMap<u64, usize> = return_snapshot_buf
                .iter()
                .enumerate()
                .map(|(idx, snap)| (snap.id, idx))
                .collect();

            (has_solo_flag, master_snap, return_index)
        }; // All locks released here!
        let mut master_peak_left = 0.0f32;
        let mut master_peak_right = 0.0f32;

        // OPTIMIZATION: Lock synth manager ONCE before the frame loop
        let mut synth_guard = Some(lock_or_count(track_synth_manager, &SYNTH_LOCK_WAITS));

        // OPTIMIZATION: Lock effect manager ONCE before the frame loop
        let mut effect_guard = lock_or_count(effect_manager, &EFFECT_LOCK_WAITS);

        // Check if recording is active (skip clip playback on armed tracks)
        let is_recording = *lock_or_count(&recorder_refs.state, &RECORDER_LOCK_WAITS)
            == crate::recorder::RecordingState::Recording;

        // Process the callback in sub-blocks of at most MAX_VST3_BLOCK frames
        // (see the const's doc comment for why). Within each sub-block the FX chain
        // runs once per effect via `process_block` — VST3 plugins process the whole
        // chunk in a single call (the fix), while built-in effects loop
        // `process_frame` internally (output unchanged).
        //
        // Size the hoisted per-buffer scratch (capacity 2048, so resize never
        // allocates on the audio thread).
        scratch_l.resize(MAX_VST3_BLOCK, 0.0);
        scratch_r.resize(MAX_VST3_BLOCK, 0.0);
        mix_l.resize(MAX_VST3_BLOCK, 0.0);
        mix_r.resize(MAX_VST3_BLOCK, 0.0);
        master_l.resize(MAX_VST3_BLOCK, 0.0);
        master_r.resize(MAX_VST3_BLOCK, 0.0);
        input_l.resize(MAX_VST3_BLOCK, 0.0);
        input_r.resize(MAX_VST3_BLOCK, 0.0);
        let num_returns = return_snapshot_buf.len();
        return_bus_l.resize_with(num_returns, || Vec::with_capacity(MAX_VST3_BLOCK));
        return_bus_r.resize_with(num_returns, || Vec::with_capacity(MAX_VST3_BLOCK));
        for buf in return_bus_l.iter_mut() {
            buf.resize(MAX_VST3_BLOCK, 0.0);
        }
        for buf in return_bus_r.iter_mut() {
            buf.resize(MAX_VST3_BLOCK, 0.0);
        }

        let mut sb_start = 0usize;
        while sb_start < frames {
            let sb_len = MAX_VST3_BLOCK.min(frames - sb_start);

            // Reset per-sub-block mix + return accumulators.
            for i in 0..sb_len {
                mix_l[i] = 0.0;
                mix_r[i] = 0.0;
            }
            for ret in 0..num_returns {
                for i in 0..sb_len {
                    return_bus_l[ret][i] = 0.0;
                    return_bus_r[ret][i] = 0.0;
                }
            }

            // Read input once per frame up front (a single consumer of the input
            // ring, exactly as before) so monitoring, recording and the latency
            // test all see the same per-frame samples.
            for i in 0..sb_len {
                let (il, ir) = input_tap.read_frame();
                input_l[i] = il;
                input_r[i] = ir;
            }

            // --- Tracks ---
            for track_snap in snapshot_buf.iter_mut() {
                let audible = !track_snap.muted && (!has_solo || track_snap.soloed);
                // Skip existing clip playback on armed tracks during recording
                // (user should only hear new input, not old overlapping clips).
                let skip_clips = track_snap.armed && is_recording;

                // Does this track host a VST3 instrument (vs VST3 or built-in FX)?
                #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                let has_vst3_instrument = track_snap.fx_chain.iter().any(|effect_id| {
                    effect_guard
                        .get_effect(*effect_id)
                        .is_some_and(|effect_arc| {
                            lock_or_count(&effect_arc, &EFFECT_LOCK_WAITS).is_vst3_instrument()
                        })
                });
                #[cfg(not(all(feature = "vst3", not(target_os = "ios"))))]
                let has_vst3_instrument = false;

                vst3_events.clear();

                // Pass 1: fill scratch with the pre-FX signal (clips + built-in
                // synth + input monitoring), dispatching built-in-synth MIDI
                // per-sample and queuing VST3 MIDI with a sample offset.
                if let Some(ref mut synth_manager) = synth_guard {
                    for i in 0..sb_len {
                        let playhead_frame = current_playhead + (sb_start + i) as u64;
                        let playhead_seconds =
                            playhead_frame as f64 / f64::from(TARGET_SAMPLE_RATE);

                        let mut track_left = 0.0;
                        let mut track_right = 0.0;

                        if !skip_clips {
                            for timeline_clip in &track_snap.audio_clips {
                                let (cl, cr) =
                                    render_audio_clip_sample(timeline_clip, playhead_seconds);
                                track_left += cl;
                                track_right += cr;
                            }
                        }

                        if !skip_clips {
                            for timeline_midi_clip in &track_snap.midi_clips {
                                let clip_start_samples = frame_at(
                                    timeline_midi_clip.start_time * f64::from(TARGET_SAMPLE_RATE),
                                ) as u64;
                                let clip_end_samples =
                                    clip_start_samples + timeline_midi_clip.clip.duration_samples;

                                // Use <= for end boundary so note-offs at exact clip end fire.
                                if playhead_frame >= clip_start_samples
                                    && playhead_frame <= clip_end_samples
                                {
                                    let frame_in_clip = playhead_frame - clip_start_samples;
                                    for event in &timeline_midi_clip.clip.events {
                                        if event.timestamp_samples == frame_in_clip {
                                            match event.event_type {
                                                crate::midi::MidiEventType::NoteOn {
                                                    note,
                                                    velocity,
                                                } => {
                                                    if has_vst3_instrument {
                                                        vst3_events.push((
                                                            0,
                                                            0,
                                                            i32::from(note),
                                                            i32::from(velocity),
                                                            i as i32,
                                                        ));
                                                    } else {
                                                        synth_manager.note_on(
                                                            track_snap.id,
                                                            note,
                                                            velocity,
                                                        );
                                                    }
                                                }
                                                crate::midi::MidiEventType::NoteOff {
                                                    note,
                                                    velocity: _,
                                                } => {
                                                    if has_vst3_instrument {
                                                        vst3_events.push((
                                                            1,
                                                            0,
                                                            i32::from(note),
                                                            0,
                                                            i as i32,
                                                        ));
                                                    } else {
                                                        synth_manager.note_off(track_snap.id, note);
                                                    }
                                                }
                                                crate::midi::MidiEventType::ControlChange {
                                                    controller,
                                                    value,
                                                } => {
                                                    if has_vst3_instrument {
                                                        vst3_events.push((
                                                            2,
                                                            0,
                                                            i32::from(controller),
                                                            i32::from(value),
                                                            i as i32,
                                                        ));
                                                    } else {
                                                        synth_manager.control_change(
                                                            track_snap.id,
                                                            controller,
                                                            value,
                                                        );
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Per-track built-in synthesizer output (lock already held)
                        let (synth_left, synth_right) =
                            synth_manager.process_sample_stereo(track_snap.id);
                        track_left += synth_left;
                        track_right += synth_right;

                        // Input monitoring: mix live input for armed audio tracks
                        let should_monitor = track_snap.armed
                            && track_snap.input_monitoring
                            && track_snap.is_audio_track;
                        update_monitoring_fade(
                            &mut track_snap.monitoring_fade_gain,
                            should_monitor,
                            monitoring_ramp_rate,
                        );
                        if track_snap.monitoring_fade_gain > 0.0 {
                            // Stereo pair only: even channels → left, odd → right (C9).
                            let ch = track_snap.input_channel as usize;
                            let input_sample = if ch.is_multiple_of(2) {
                                input_l[i]
                            } else {
                                input_r[i]
                            };
                            track_left += input_sample * track_snap.monitoring_fade_gain as f32;
                            track_right += input_sample * track_snap.monitoring_fade_gain as f32;
                        }

                        scratch_l[i] = track_left;
                        scratch_r[i] = track_right;
                    }
                }

                // Pass 2: flush queued VST3 MIDI at their offsets, then run the FX
                // chain once over the whole sub-block.
                #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                if has_vst3_instrument && !vst3_events.is_empty() {
                    for effect_id in &track_snap.fx_chain {
                        if let Some(effect_arc) = effect_guard.get_effect(*effect_id) {
                            let mut effect = lock_or_count(&effect_arc, &EFFECT_LOCK_WAITS);
                            if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                for &(et, ch, d1, d2, off) in vst3_events.iter() {
                                    let _ = vst3.process_midi_event(et, ch, d1, d2, off);
                                }
                            }
                        }
                    }
                }
                process_effect_chain_block(
                    &track_snap.fx_chain,
                    &mut effect_guard,
                    &mut scratch_l[..sb_len],
                    &mut scratch_r[..sb_len],
                    false,
                    track_snap.volume_gain,
                );

                // Pass 3: per-sample fader/pan (post-FX), metering, sends, mix.
                // Multiply/accumulate order preserved → bit-identical to the
                // previous path for built-in chains.
                for i in 0..sb_len {
                    let playhead_frame = current_playhead + (sb_start + i) as u64;
                    let playhead_seconds = playhead_frame as f64 / f64::from(TARGET_SAMPLE_RATE);

                    let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                        track_snap.volume_gain
                    } else {
                        interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
                    };

                    let mut fx_left = scratch_l[i];
                    let mut fx_right = scratch_r[i];
                    fx_left *= frame_volume_gain;
                    fx_right *= frame_volume_gain;
                    fx_left *= track_snap.pan_left;
                    fx_right *= track_snap.pan_right;

                    if audible {
                        let entry = peak_buf.entry(track_snap.id).or_insert((0.0, 0.0));
                        entry.0 = entry.0.max(fx_left.abs());
                        entry.1 = entry.1.max(fx_right.abs());

                        for (return_id, amount) in &track_snap.sends {
                            if let Some(&idx) = return_index.get(return_id) {
                                return_bus_l[idx][i] += fx_left * amount;
                                return_bus_r[idx][i] += fx_right * amount;
                            }
                        }
                        mix_l[i] += fx_left;
                        mix_r[i] += fx_right;
                    }
                }
            }

            // --- Return tracks: FX over the accumulated send buffer, then sum to master ---
            for (idx, return_snap) in return_snapshot_buf.iter().enumerate() {
                let return_audible = !return_snap.muted && (!has_solo || return_snap.soloed);
                if !return_audible {
                    continue;
                }

                scratch_l[..sb_len].copy_from_slice(&return_bus_l[idx][..sb_len]);
                scratch_r[..sb_len].copy_from_slice(&return_bus_r[idx][..sb_len]);
                process_effect_chain_block(
                    &return_snap.fx_chain,
                    &mut effect_guard,
                    &mut scratch_l[..sb_len],
                    &mut scratch_r[..sb_len],
                    false,
                    return_snap.volume_gain,
                );

                for i in 0..sb_len {
                    let playhead_frame = current_playhead + (sb_start + i) as u64;
                    let playhead_seconds = playhead_frame as f64 / f64::from(TARGET_SAMPLE_RATE);
                    let frame_volume_gain = if return_snap.volume_automation.is_empty() {
                        return_snap.volume_gain
                    } else {
                        interpolate_automation_gain(
                            &return_snap.volume_automation,
                            playhead_seconds,
                        )
                    };
                    let mut fx_left = scratch_l[i];
                    let mut fx_right = scratch_r[i];
                    fx_left *= frame_volume_gain;
                    fx_right *= frame_volume_gain;
                    fx_left *= return_snap.pan_left;
                    fx_right *= return_snap.pan_right;

                    let entry = peak_buf.entry(return_snap.id).or_insert((0.0, 0.0));
                    entry.0 = entry.0.max(fx_left.abs());
                    entry.1 = entry.1.max(fx_right.abs());

                    mix_l[i] += fx_left;
                    mix_r[i] += fx_right;
                }
            }

            // --- Master: volume/pan per-sample, then master FX over the block ---
            master_l[..sb_len].copy_from_slice(&mix_l[..sb_len]);
            master_r[..sb_len].copy_from_slice(&mix_r[..sb_len]);
            if let Some(ref master_snap) = master_snapshot {
                for i in 0..sb_len {
                    master_l[i] *= master_snap.volume_gain;
                    master_r[i] *= master_snap.volume_gain;
                    master_l[i] *= master_snap.pan_left;
                    master_r[i] *= master_snap.pan_right;
                }
                process_effect_chain_block(
                    &master_snap.fx_chain,
                    &mut effect_guard,
                    &mut master_l[..sb_len],
                    &mut master_r[..sb_len],
                    false,
                    1.0, // volume already applied to master buffer above
                );
            }

            // In-place count-in (recording at/near bar 1, no room for
            // a full pre-roll): mute track playback so the count-in
            // isn't accompanied by the very bars being recorded over.
            // The metronome is mixed in after the limiter, so it stays.
            if recorder_refs.count_in_in_place.load(Ordering::Relaxed)
                && *lock_or_count(&recorder_refs.state, &RECORDER_LOCK_WAITS)
                    == crate::recorder::RecordingState::CountingIn
            {
                master_l[..sb_len].fill(0.0);
                master_r[..sb_len].fill(0.0);
            }

            // --- Per-sample tail: recording/metronome, limiter, metering,
            // preview, output write. These stay strictly per-frame
            // and in order (recorder + preview advance per sample). ---
            {
                let mut limiter = lock_or_count(master_limiter, &EFFECT_LOCK_WAITS);
                for i in 0..sb_len {
                    let frame_idx = sb_start + i;

                    // Process recording (metronome handled separately below)
                    let (met_left, met_right) =
                        recorder_refs.process_frame(input_l[i], input_r[i], true);

                    // Apply master limiter to prevent clipping
                    let (limited_left, limited_right) =
                        limiter.process_frame(master_l[i], master_r[i]);

                    // Update master peak levels for metering (before metronome is added)
                    master_peak_left = master_peak_left.max(limited_left.abs());
                    master_peak_right = master_peak_right.max(limited_right.abs());

                    // Add metronome AFTER metering so it doesn't affect the master meter
                    let mut output_left = limited_left + met_left;
                    let mut output_right = limited_right + met_right;

                    // Mix library preview audio (independent of transport)
                    let (preview_left, preview_right) =
                        crate::api::preview::preview_process_sample();
                    output_left += preview_left;
                    output_right += preview_right;

                    // Write to output buffer (interleaved, channel-count aware + sanitized)
                    write_frame(data, frame_idx, channels, output_left, output_right);
                }
            }

            sb_start += sb_len;
        }

        // Release effect manager lock before acquiring track_manager lock for peak updates
        drop(effect_guard);

        // Update track peak levels and monitoring fade gains (brief lock after buffer processing)
        {
            let tm = lock_or_count(track_manager, &TRACK_LOCK_WAITS);
            for track_snap in snapshot_buf.iter() {
                if let Some(track_arc) = tm.get_track(track_snap.id) {
                    {
                        let mut track = lock_or_count(&track_arc, &TRACK_LOCK_WAITS);
                        track.monitoring_fade_gain = track_snap.monitoring_fade_gain;
                    }
                }
            }
            for (track_id, (peak_l, peak_r)) in peak_buf.iter() {
                if let Some(track_arc) = tm.get_track(*track_id) {
                    {
                        let mut track = lock_or_count(&track_arc, &TRACK_LOCK_WAITS);
                        track.update_peaks(*peak_l, *peak_r);
                    }
                }
            }
            // Update master track peaks
            {
                let master_arc = tm.get_master_track();
                {
                    let mut master = lock_or_count(&master_arc, &TRACK_LOCK_WAITS);
                    master.update_peaks(master_peak_left, master_peak_right);
                };
            }
        }

        // Advance playhead
        playhead_samples.fetch_add(frames as u64, Ordering::SeqCst);
    }
}
#[cfg(test)]
mod tests {
    // Exact float comparisons are intentional here: the values under test are
    // deterministic sentinels produced by clamping/sanitizing (exactly 0.0 / ±1.0).
    #![allow(clippy::float_cmp)]
    use super::{pick_stereo_config_index, sanitize_sample, update_monitoring_fade, write_frame};

    /// A mono clip whose sample values are their own index, placed at
    /// `start_frame`, so the played value says which sample was picked.
    fn ramp_clip(frames: usize, start_frame: u32) -> crate::track::TimelineClip {
        use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
        let clip = AudioClip {
            samples: (0..frames).map(|i| i as f32).collect(),
            channels: 1,
            sample_rate: TARGET_SAMPLE_RATE,
            duration_seconds: frames as f64 / f64::from(TARGET_SAMPLE_RATE),
            file_path: "ramp.wav".into(),
        };
        crate::track::TimelineClip {
            id: 0,
            clip: std::sync::Arc::new(clip),
            start_time: f64::from(start_frame) / f64::from(TARGET_SAMPLE_RATE),
            offset: 0.0,
            duration: None,
            gain_db: 0.0,
            warp_enabled: false,
            stretch_factor: 1.0,
            warp_mode: 0,
            stretched_cache: None,
            cached_stretch_factor: 1.0,
            cached_transpose_cents: 0,
            transpose_semitones: 0,
            transpose_cents: 0,
            reversed: false,
            loop_length: None,
            loop_start: 0.0,
        }
    }

    #[test]
    fn clip_playback_plays_every_sample_in_order() {
        // Truncating (playhead - start) * rate picked the previous sample
        // whenever float error left the index at k - 0.0000001: ~0.6% of
        // samples repeated, heard as grit/crackle on playback.
        use crate::audio_file::TARGET_SAMPLE_RATE;
        let frames = 8 * TARGET_SAMPLE_RATE as usize;
        for start_frame in [0u32, 96_000, 59_253] {
            let clip = ramp_clip(frames, start_frame);
            let wrong = (0..frames)
                .filter(|&i| {
                    let playhead =
                        f64::from(start_frame + i as u32) / f64::from(TARGET_SAMPLE_RATE);
                    super::render_audio_clip_sample(&clip, playhead).0 != i as f32
                })
                .count();
            assert_eq!(
                wrong, 0,
                "clip at frame {start_frame}: {wrong} samples out of order"
            );
        }
    }

    #[test]
    fn sanitize_replaces_non_finite_with_silence() {
        assert_eq!(sanitize_sample(f32::NAN), 0.0);
        assert_eq!(sanitize_sample(f32::INFINITY), 0.0);
        assert_eq!(sanitize_sample(f32::NEG_INFINITY), 0.0);
    }

    #[test]
    fn sanitize_clamps_to_device_range_but_passes_normal_values() {
        assert_eq!(sanitize_sample(2.5), 1.0);
        assert_eq!(sanitize_sample(-2.5), -1.0);
        assert!((sanitize_sample(0.5) - 0.5).abs() < f32::EPSILON);
        assert!((sanitize_sample(-0.5) + 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn write_frame_stereo_lays_out_lr_and_sanitizes() {
        let mut buf = [0.0f32; 4];
        write_frame(&mut buf, 0, 2, 0.5, -0.5);
        write_frame(&mut buf, 1, 2, f32::NAN, 9.0); // NaN -> 0, 9.0 -> clamped 1.0
        assert_eq!(buf, [0.5, -0.5, 0.0, 1.0]);
    }

    #[test]
    fn write_frame_mono_averages_channels() {
        let mut buf = [0.0f32; 1];
        write_frame(&mut buf, 0, 1, 1.0, 0.0);
        assert!((buf[0] - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn monitoring_fade_takes_20ms_at_the_stream_rate() {
        // C4: the ramp steps once per callback frame, so 20 ms is only 20 ms
        // when the step is derived from the rate the stream actually runs at.
        for rate in [44_100.0_f64, 48_000.0, 96_000.0] {
            let mut gain = 0.0_f64;
            let mut steps = 0u32;
            while gain < 1.0 {
                update_monitoring_fade(&mut gain, true, rate);
                steps += 1;
                assert!(steps < 100_000, "ramp never completed at {rate} Hz");
            }
            let expected = (0.020 * rate) as u32;
            assert!(
                steps.abs_diff(expected) <= 1,
                "20 ms ramp at {rate} Hz should take ~{expected} frames, took {steps}"
            );
        }
    }

    #[test]
    fn write_frame_multichannel_fills_extra_channels_with_silence() {
        let mut buf = [7.0f32; 4]; // pre-fill to prove extra channels are zeroed
        write_frame(&mut buf, 0, 4, 0.25, -0.25);
        assert_eq!(buf, [0.25, -0.25, 0.0, 0.0]);
    }

    #[test]
    fn picks_first_stereo_range_covering_target() {
        // mono-only, then stereo 44.1–48k: should pick index 1.
        let ranges = [(1u16, 48_000u32, 48_000u32), (2, 44_100, 48_000)];
        assert_eq!(pick_stereo_config_index(&ranges, 48_000), Some(1));
    }

    #[test]
    fn rejects_when_no_stereo_range_covers_target() {
        // stereo exists but only up to 44.1k; mono covers 48k. No stereo @ 48k.
        let ranges = [(2u16, 44_100u32, 44_100u32), (1, 48_000, 48_000)];
        assert_eq!(pick_stereo_config_index(&ranges, 48_000), None);
    }
}
