/// Offline rendering for export and bounce
use super::{interpolate_automation_gain, AudioGraph};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::dlog;
use crate::effects::{Effect, EffectManager};
use crate::track::{AutomationPoint, TimelineClip, TimelineMidiClip, TrackType};

/// Offline render block size, in frames.
///
/// Must not exceed the `maxSamplesPerBlock` that VST3 plugins are initialised
/// with (`engine/src/api/vst3.rs`, currently 512) — a plugin sizes its internal
/// buffers for that maximum, so handing `process_audio` a larger block violates
/// the VST3 contract. We render the timeline in chunks of this size and call
/// each effect's `process_block` once per chunk.
const OFFLINE_BLOCK: usize = 512;

/// Run an FX chain over a whole block in-place (offline path).
///
/// Mirrors offline's previous per-sample FX loop — no bypass handling and no
/// peak metering, because the offline renderer has neither — but calls
/// `process_block` once per effect so VST3 plugins process the chunk in a
/// single `process_audio` call. Built-in effects fall through to the `Effect`
/// trait's default `process_block` (a `process_frame` loop), so their output is
/// bit-identical to the previous path.
fn process_chain_block_offline(
    effect_mgr: &EffectManager,
    fx_chain: &[u64],
    left: &mut [f32],
    right: &mut [f32],
) {
    for effect_id in fx_chain {
        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
            let mut effect = effect_arc.lock();
            effect.process_block(left, right);
        }
    }
}

/// A queued MIDI event for a VST3 instrument: `(event_type, channel, data1,
/// data2, sample_offset)` where `sample_offset` is relative to the start of the
/// current render block. Collected during the per-sample fill pass and flushed
/// to the plugin just before its `process_block` call.
type QueuedVst3Event = (i32, i32, i32, i32, i32);

impl AudioGraph {
    // --- Offline Rendering (Export) ---

    /// Render the entire project offline to a buffer of stereo f32 samples
    /// Returns interleaved stereo audio (L, R, L, R, ...)
    pub fn render_offline(&self, duration_seconds: f64) -> Vec<f32> {
        // Create track snapshots (same as real-time rendering)
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
        }

        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * f64::from(sample_rate)) as usize;
        let mut output = Vec::with_capacity(total_frames * 2); // stereo interleaved

        dlog!("🎵 [AudioGraph] Starting offline render: {duration_seconds:.2}s ({total_frames} frames)");

        // Get tempo for timeline positioning
        // Timeline positions are tempo-dependent: at 120 BPM, 1 timeline second = 1 real second
        let current_tempo = self.recorder.get_tempo();
        let tempo_ratio = current_tempo / 120.0;
        dlog!("🎵 [AudioGraph] Using tempo {current_tempo} BPM (ratio: {tempo_ratio:.3})");

        let (track_snapshots, return_snapshots, has_solo, master_snapshot, return_index) = {
            let tm = self.track_manager.lock();
            let has_solo_flag = tm.has_solo();
            let all_tracks = tm.get_all_tracks();
            let mut snapshots = Vec::new();
            let mut return_snaps = Vec::new();
            let mut master_snap = None;

            for track_arc in all_tracks {
                {
                    let track = track_arc.lock();
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
                    };

                    match track.track_type {
                        TrackType::Master => master_snap = Some(snap),
                        TrackType::Return => return_snaps.push(snap),
                        _ => snapshots.push(snap),
                    }
                }
            }

            let return_index: std::collections::HashMap<u64, usize> = return_snaps
                .iter()
                .enumerate()
                .map(|(idx, snap)| (snap.id, idx))
                .collect();

            (
                snapshots,
                return_snaps,
                has_solo_flag,
                master_snap,
                return_index,
            )
        };

        dlog!(
            "🎵 [AudioGraph] Rendering {} tracks (+ {} returns)",
            track_snapshots.len(),
            return_snapshots.len()
        );

        // Render the timeline in sub-blocks of OFFLINE_BLOCK frames. For each
        // block: (1) fill a per-track scratch buffer with the pre-FX signal
        // sample-by-sample (clips + built-in synth, MIDI dispatched at its exact
        // frame; VST3 events queued with a sample offset), then (2) run the FX
        // chain once over the whole block via `process_block`. Built-in effects
        // loop `process_frame` internally, so their output is bit-identical to
        // the previous per-sample path; VST3 plugins process the chunk in one
        // call with sample-accurate MIDI offsets.
        let num_returns = return_snapshots.len();
        let mut scratch_l = vec![0.0f32; OFFLINE_BLOCK];
        let mut scratch_r = vec![0.0f32; OFFLINE_BLOCK];
        let mut mix_l = vec![0.0f32; OFFLINE_BLOCK];
        let mut mix_r = vec![0.0f32; OFFLINE_BLOCK];
        let mut return_l: Vec<Vec<f32>> = vec![vec![0.0f32; OFFLINE_BLOCK]; num_returns];
        let mut return_r: Vec<Vec<f32>> = vec![vec![0.0f32; OFFLINE_BLOCK]; num_returns];
        let mut master_l = vec![0.0f32; OFFLINE_BLOCK];
        let mut master_r = vec![0.0f32; OFFLINE_BLOCK];
        let mut vst3_events: Vec<QueuedVst3Event> = Vec::with_capacity(128);

        let mut block_start = 0usize;
        while block_start < total_frames {
            let block_len = OFFLINE_BLOCK.min(total_frames - block_start);

            // Reset per-block mix + return accumulators.
            for i in 0..block_len {
                mix_l[i] = 0.0;
                mix_r[i] = 0.0;
            }
            for ret in 0..num_returns {
                for i in 0..block_len {
                    return_l[ret][i] = 0.0;
                    return_r[ret][i] = 0.0;
                }
            }

            // --- Tracks ---
            for track_snap in &track_snapshots {
                let audible = !track_snap.muted && (!has_solo || track_snap.soloed);
                // Route MIDI to EITHER built-in synth OR VST3 (not both).
                let has_vst3 = !track_snap.fx_chain.is_empty();
                vst3_events.clear();

                // Pass 1: fill scratch with the pre-FX signal (clips + synth),
                // dispatching built-in-synth MIDI per-sample and queuing VST3
                // MIDI with an offset relative to the block start.
                {
                    let mut synth_manager = self.track_synth_manager.lock();
                    for i in 0..block_len {
                        let frame_idx = block_start + i;
                        let real_seconds = frame_idx as f64 / f64::from(sample_rate);
                        let playhead_seconds = real_seconds * tempo_ratio;

                        let mut track_left = 0.0f32;
                        let mut track_right = 0.0f32;

                        // Mix all audio clips on this track
                        for timeline_clip in &track_snap.audio_clips {
                            let clip_duration = timeline_clip
                                .duration
                                .unwrap_or(timeline_clip.clip.duration_seconds);
                            // When warp is enabled, the clip's timeline duration changes:
                            // stretch > 1 = faster playback = clip ends sooner
                            // stretch < 1 = slower playback = clip ends later
                            let effective_duration = if timeline_clip.warp_enabled {
                                clip_duration / f64::from(timeline_clip.stretch_factor)
                            } else {
                                clip_duration
                            };
                            let clip_end = timeline_clip.start_time + effective_duration;

                            if playhead_seconds >= timeline_clip.start_time
                                && playhead_seconds < clip_end
                            {
                                let time_in_clip = playhead_seconds - timeline_clip.start_time
                                    + timeline_clip.offset;
                                let clip_gain = timeline_clip.get_gain();
                                let pitch_ratio = f64::from(timeline_clip.get_pitch_ratio());

                                // Determine which audio source to use and calculate frame index
                                let (frame_in_clip, source_clip): (usize, &AudioClip) =
                                    if timeline_clip.warp_enabled {
                                        if timeline_clip.warp_mode == 0 {
                                            // Warp mode: use pre-stretched cached audio (pitch preserved)
                                            // Apply pitch ratio for transpose
                                            if let Some(ref stretched) =
                                                timeline_clip.stretched_cache
                                            {
                                                let frame = (time_in_clip
                                                    * pitch_ratio
                                                    * f64::from(sample_rate))
                                                    as usize;
                                                (frame, stretched.as_ref())
                                            } else {
                                                // Fallback to Re-Pitch if cache not ready
                                                let stretched_time = time_in_clip
                                                    * f64::from(timeline_clip.stretch_factor)
                                                    * pitch_ratio;
                                                (
                                                    (stretched_time * f64::from(sample_rate))
                                                        as usize,
                                                    &*timeline_clip.clip,
                                                )
                                            }
                                        } else {
                                            // Re-Pitch mode: sample-rate shift (pitch follows speed)
                                            // Also apply any additional transpose
                                            let stretched_time = time_in_clip
                                                * f64::from(timeline_clip.stretch_factor)
                                                * pitch_ratio;
                                            (
                                                (stretched_time * f64::from(sample_rate)) as usize,
                                                &*timeline_clip.clip,
                                            )
                                        }
                                    } else {
                                        // No warp - apply pitch ratio for transpose
                                        (
                                            (time_in_clip * pitch_ratio * f64::from(sample_rate))
                                                as usize,
                                            &*timeline_clip.clip,
                                        )
                                    };

                                if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                    track_left += l * clip_gain;
                                }
                                if source_clip.channels > 1 {
                                    if let Some(r) = source_clip.get_sample(frame_in_clip, 1) {
                                        track_right += r * clip_gain;
                                    }
                                } else {
                                    // Mono clip - duplicate to right
                                    if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                        track_right += l * clip_gain;
                                    }
                                }
                            }
                        }

                        // MIDI events landing at this exact frame
                        for timeline_midi_clip in &track_snap.midi_clips {
                            let clip_start_samples =
                                (timeline_midi_clip.start_time * f64::from(sample_rate)) as u64;
                            let clip_end_samples =
                                clip_start_samples + timeline_midi_clip.clip.duration_samples;

                            // Use <= for end boundary so note-offs at exact clip end fire.
                            if frame_idx as u64 >= clip_start_samples
                                && (frame_idx as u64) <= clip_end_samples
                            {
                                let frame_in_clip = frame_idx as u64 - clip_start_samples;
                                for event in &timeline_midi_clip.clip.events {
                                    if event.timestamp_samples == frame_in_clip {
                                        match event.event_type {
                                            crate::midi::MidiEventType::NoteOn {
                                                note,
                                                velocity,
                                            } => {
                                                if has_vst3 {
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
                                                if has_vst3 {
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
                                                ..
                                            } => {}
                                        }
                                    }
                                }
                            }
                        }

                        // Built-in synth output (per sample)
                        let (synth_left, synth_right) =
                            synth_manager.process_sample_stereo(track_snap.id);
                        track_left += synth_left;
                        track_right += synth_right;

                        scratch_l[i] = track_left;
                        scratch_r[i] = track_right;
                    }
                }

                // Pass 2: flush queued VST3 MIDI at their offsets, then run the FX
                // chain once over the whole block.
                {
                    let effect_mgr = self.effect_manager.lock();
                    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                    if has_vst3 && !vst3_events.is_empty() {
                        for effect_id in &track_snap.fx_chain {
                            if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                let mut effect = effect_arc.lock();
                                if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                    for &(et, ch, d1, d2, off) in &vst3_events {
                                        let _ = vst3.process_midi_event(et, ch, d1, d2, off);
                                    }
                                }
                            }
                        }
                    }
                    process_chain_block_offline(
                        &effect_mgr,
                        &track_snap.fx_chain,
                        &mut scratch_l[..block_len],
                        &mut scratch_r[..block_len],
                    );
                }

                // Pass 3: per-sample fader/pan, post-fader sends, sum into the mix.
                // Multiply order preserved (signal *= volume; *= pan) so the result
                // is bit-identical to the previous path.
                for i in 0..block_len {
                    let frame_idx = block_start + i;
                    let playhead_seconds =
                        (frame_idx as f64 / f64::from(sample_rate)) * tempo_ratio;

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
                        for (return_id, amount) in &track_snap.sends {
                            if let Some(&idx) = return_index.get(return_id) {
                                return_l[idx][i] += fx_left * amount;
                                return_r[idx][i] += fx_right * amount;
                            }
                        }
                        mix_l[i] += fx_left;
                        mix_r[i] += fx_right;
                    }
                }
            }

            // --- Return tracks: FX over the accumulated send buffer, then sum to master ---
            for (idx, return_snap) in return_snapshots.iter().enumerate() {
                let return_audible = !return_snap.muted && (!has_solo || return_snap.soloed);
                if !return_audible {
                    continue;
                }

                scratch_l[..block_len].copy_from_slice(&return_l[idx][..block_len]);
                scratch_r[..block_len].copy_from_slice(&return_r[idx][..block_len]);
                {
                    let effect_mgr = self.effect_manager.lock();
                    process_chain_block_offline(
                        &effect_mgr,
                        &return_snap.fx_chain,
                        &mut scratch_l[..block_len],
                        &mut scratch_r[..block_len],
                    );
                }
                for i in 0..block_len {
                    let frame_idx = block_start + i;
                    let playhead_seconds =
                        (frame_idx as f64 / f64::from(sample_rate)) * tempo_ratio;
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
                    mix_l[i] += fx_left;
                    mix_r[i] += fx_right;
                }
            }

            // --- Master: volume/pan per-sample, then master FX over the block ---
            master_l[..block_len].copy_from_slice(&mix_l[..block_len]);
            master_r[..block_len].copy_from_slice(&mix_r[..block_len]);
            if let Some(ref master_snap) = master_snapshot {
                for i in 0..block_len {
                    // Apply master volume
                    master_l[i] *= master_snap.volume_gain;
                    master_r[i] *= master_snap.volume_gain;
                    // Apply master pan — independent per-channel gain, matching the
                    // realtime renderer and the return-bus pan above. The previous
                    // matrix summed both channels into each output, folding every
                    // bounce to dual-mono (~3 dB hot).
                    master_l[i] *= master_snap.pan_left;
                    master_r[i] *= master_snap.pan_right;
                }
                let effect_mgr = self.effect_manager.lock();
                process_chain_block_offline(
                    &effect_mgr,
                    &master_snap.fx_chain,
                    &mut master_l[..block_len],
                    &mut master_r[..block_len],
                );
            }

            // Master limiter (per-sample, in order) + write interleaved output.
            {
                let mut limiter = self.master_limiter.lock();
                for i in 0..block_len {
                    let (limited_left, limited_right) =
                        limiter.process_frame(master_l[i], master_r[i]);
                    output.push(limited_left);
                    output.push(limited_right);
                }
            }

            // Progress logging (~once per block)
            let progress = (block_start as f64 / total_frames as f64 * 100.0) as i32;
            dlog!("   {progress}% complete...");

            block_start += block_len;
        }

        dlog!(
            "✅ [AudioGraph] Offline render complete: {} samples",
            output.len()
        );
        output
    }

    /// Render a single track offline to a buffer of stereo f32 samples
    /// Returns interleaved stereo audio (L, R, L, R, ...)
    /// This renders the track in isolation without master bus processing
    pub fn render_track_offline(&self, track_id: u64, duration_seconds: f64) -> Vec<f32> {
        // Get track snapshot
        struct TrackSnapshot {
            audio_clips: Vec<TimelineClip>,
            midi_clips: Vec<TimelineMidiClip>,
            volume_gain: f32,
            pan_left: f32,
            pan_right: f32,
            fx_chain: Vec<u64>,
            volume_automation: Vec<AutomationPoint>,
        }

        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * f64::from(sample_rate)) as usize;
        let mut output = Vec::with_capacity(total_frames * 2);

        dlog!(
            "🎚️ [AudioGraph] Starting track {track_id} offline render: {duration_seconds:.2}s ({total_frames} frames)"
        );

        // Get tempo for timeline positioning
        let current_tempo = self.recorder.get_tempo();
        let tempo_ratio = current_tempo / 120.0;

        let track_snapshot = {
            let tm = self.track_manager.lock();
            let mut snapshot = None;

            for track_arc in tm.get_all_tracks() {
                {
                    let track = track_arc.lock();
                    if track.id == track_id {
                        snapshot = Some(TrackSnapshot {
                            audio_clips: track.audio_clips.clone(),
                            midi_clips: track.midi_clips.clone(),
                            volume_gain: track.get_gain(),
                            pan_left: track.get_pan_gains().0,
                            pan_right: track.get_pan_gains().1,
                            fx_chain: track.fx_chain.clone(),
                            volume_automation: track.volume_automation.clone(),
                        });
                        break;
                    }
                }
            }

            snapshot
        };

        let Some(track_snap) = track_snapshot else {
            eprintln!("❌ [AudioGraph] Track {track_id} not found for stem export");
            return output;
        };

        // Render the stem in sub-blocks of OFFLINE_BLOCK frames. Order matches
        // the previous per-sample path: clips + synth, then fader/pan, then the
        // FX chain (so the FX run on the post-fader signal). Built-in effects'
        // `process_block` is a `process_frame` loop, so output is bit-identical;
        // VST3 plugins process each chunk in one call with MIDI offsets.
        let mut scratch_l = vec![0.0f32; OFFLINE_BLOCK];
        let mut scratch_r = vec![0.0f32; OFFLINE_BLOCK];
        let mut vst3_events: Vec<QueuedVst3Event> = Vec::with_capacity(128);
        // Route MIDI to EITHER built-in synth OR VST3 (not both).
        let has_vst3 = !track_snap.fx_chain.is_empty();

        let mut block_start = 0usize;
        while block_start < total_frames {
            let block_len = OFFLINE_BLOCK.min(total_frames - block_start);
            vst3_events.clear();

            // Pass 1: clips + synth + MIDI, then fader/pan, into scratch.
            {
                let mut synth_manager = self.track_synth_manager.lock();
                for i in 0..block_len {
                    let frame_idx = block_start + i;
                    let real_seconds = frame_idx as f64 / f64::from(sample_rate);
                    let playhead_seconds = real_seconds * tempo_ratio;

                    let mut track_left = 0.0f32;
                    let mut track_right = 0.0f32;

                    // Mix all audio clips on this track
                    for timeline_clip in &track_snap.audio_clips {
                        let clip_duration = timeline_clip
                            .duration
                            .unwrap_or(timeline_clip.clip.duration_seconds);
                        // When warp is enabled, the clip's timeline duration changes:
                        // stretch > 1 = faster playback = clip ends sooner
                        // stretch < 1 = slower playback = clip ends later
                        let effective_duration = if timeline_clip.warp_enabled {
                            clip_duration / f64::from(timeline_clip.stretch_factor)
                        } else {
                            clip_duration
                        };
                        let clip_end = timeline_clip.start_time + effective_duration;

                        if playhead_seconds >= timeline_clip.start_time
                            && playhead_seconds < clip_end
                        {
                            let time_in_clip =
                                playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                            let clip_gain = timeline_clip.get_gain();
                            let pitch_ratio = f64::from(timeline_clip.get_pitch_ratio());

                            // Determine which audio source to use and calculate frame index
                            let (frame_in_clip, source_clip): (usize, &AudioClip) = if timeline_clip
                                .warp_enabled
                            {
                                if timeline_clip.warp_mode == 0 {
                                    // Warp mode: use pre-stretched cached audio (pitch preserved)
                                    // Apply pitch ratio for transpose
                                    if let Some(ref stretched) = timeline_clip.stretched_cache {
                                        let frame =
                                            (time_in_clip * pitch_ratio * f64::from(sample_rate))
                                                as usize;
                                        (frame, stretched.as_ref())
                                    } else {
                                        // Fallback to Re-Pitch if cache not ready
                                        let stretched_time = time_in_clip
                                            * f64::from(timeline_clip.stretch_factor)
                                            * pitch_ratio;
                                        (
                                            (stretched_time * f64::from(sample_rate)) as usize,
                                            &*timeline_clip.clip,
                                        )
                                    }
                                } else {
                                    // Re-Pitch mode: sample-rate shift (pitch follows speed)
                                    // Also apply any additional transpose
                                    let stretched_time = time_in_clip
                                        * f64::from(timeline_clip.stretch_factor)
                                        * pitch_ratio;
                                    (
                                        (stretched_time * f64::from(sample_rate)) as usize,
                                        &*timeline_clip.clip,
                                    )
                                }
                            } else {
                                // No warp - apply pitch ratio for transpose
                                (
                                    (time_in_clip * pitch_ratio * f64::from(sample_rate)) as usize,
                                    &*timeline_clip.clip,
                                )
                            };

                            if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                track_left += l * clip_gain;
                            }
                            if source_clip.channels > 1 {
                                if let Some(r) = source_clip.get_sample(frame_in_clip, 1) {
                                    track_right += r * clip_gain;
                                }
                            } else {
                                // Mono clip - duplicate to right
                                if let Some(l) = source_clip.get_sample(frame_in_clip, 0) {
                                    track_right += l * clip_gain;
                                }
                            }
                        }
                    }

                    // MIDI events landing at this exact frame
                    for timeline_midi_clip in &track_snap.midi_clips {
                        let clip_start_samples =
                            (timeline_midi_clip.start_time * f64::from(sample_rate)) as u64;
                        let clip_end_samples =
                            clip_start_samples + timeline_midi_clip.clip.duration_samples;

                        if frame_idx as u64 >= clip_start_samples
                            && (frame_idx as u64) <= clip_end_samples
                        {
                            let frame_in_clip = frame_idx as u64 - clip_start_samples;
                            for event in &timeline_midi_clip.clip.events {
                                if event.timestamp_samples == frame_in_clip {
                                    match event.event_type {
                                        crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                            if has_vst3 {
                                                vst3_events.push((
                                                    0,
                                                    0,
                                                    i32::from(note),
                                                    i32::from(velocity),
                                                    i as i32,
                                                ));
                                            } else {
                                                synth_manager.note_on(track_id, note, velocity);
                                            }
                                        }
                                        crate::midi::MidiEventType::NoteOff {
                                            note,
                                            velocity: _,
                                        } => {
                                            if has_vst3 {
                                                vst3_events.push((
                                                    1,
                                                    0,
                                                    i32::from(note),
                                                    0,
                                                    i as i32,
                                                ));
                                            } else {
                                                synth_manager.note_off(track_id, note);
                                            }
                                        }
                                        crate::midi::MidiEventType::ControlChange { .. } => {}
                                    }
                                }
                            }
                        }
                    }

                    // Built-in synth output
                    let (synth_left, synth_right) = synth_manager.process_sample_stereo(track_id);
                    track_left += synth_left;
                    track_right += synth_right;

                    // Apply track volume (use automation if available) then pan,
                    // BEFORE the FX chain — preserving the stem's existing order.
                    let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                        track_snap.volume_gain
                    } else {
                        interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
                    };
                    track_left *= frame_volume_gain;
                    track_right *= frame_volume_gain;
                    track_left *= track_snap.pan_left;
                    track_right *= track_snap.pan_right;

                    scratch_l[i] = track_left;
                    scratch_r[i] = track_right;
                }
            }

            // Pass 2: flush queued VST3 MIDI at their offsets, then FX once over the block.
            {
                let effect_mgr = self.effect_manager.lock();
                #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                if has_vst3 && !vst3_events.is_empty() {
                    for effect_id in &track_snap.fx_chain {
                        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                            let mut effect = effect_arc.lock();
                            if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                for &(et, ch, d1, d2, off) in &vst3_events {
                                    let _ = vst3.process_midi_event(et, ch, d1, d2, off);
                                }
                            }
                        }
                    }
                }
                process_chain_block_offline(
                    &effect_mgr,
                    &track_snap.fx_chain,
                    &mut scratch_l[..block_len],
                    &mut scratch_r[..block_len],
                );
            }

            // Write interleaved stereo output.
            for i in 0..block_len {
                output.push(scratch_l[i]);
                output.push(scratch_r[i]);
            }

            // Progress logging (~once per block)
            let progress = (block_start as f64 / total_frames as f64 * 100.0) as i32;
            dlog!("   Track {track_id} - {progress}% complete...");

            block_start += block_len;
        }

        dlog!(
            "✅ [AudioGraph] Track {} offline render complete: {} samples",
            track_id,
            output.len()
        );
        output
    }

    /// Get track info for stem export (id, name, type)
    pub fn get_tracks_for_stem_export(&self) -> Vec<(u64, String, String)> {
        let mut tracks = Vec::new();

        {
            let tm = self.track_manager.lock();
            for track_arc in tm.get_all_tracks() {
                {
                    let track = track_arc.lock();
                    // Skip master track
                    if track.track_type == TrackType::Master {
                        continue;
                    }

                    let type_str = match track.track_type {
                        TrackType::Audio => "audio",
                        TrackType::Midi | TrackType::Sampler => "midi",
                        TrackType::Return => "return",
                        TrackType::Group => "group",
                        TrackType::Master => "master",
                    };

                    tracks.push((track.id, track.name.clone(), type_str.to_string()));
                }
            }
        }

        tracks
    }

    /// Calculate the total duration of the project based on clips
    pub fn calculate_project_duration(&self) -> f64 {
        let mut max_end_time = 0.0f64;

        // Check all tracks for clips
        {
            let tm = self.track_manager.lock();
            for track_arc in tm.get_all_tracks() {
                {
                    let track = track_arc.lock();
                    // Audio clips
                    for clip in &track.audio_clips {
                        let clip_end =
                            clip.start_time + clip.duration.unwrap_or(clip.clip.duration_seconds);
                        if clip_end > max_end_time {
                            max_end_time = clip_end;
                        }
                    }
                    // MIDI clips
                    for clip in &track.midi_clips {
                        let clip_end = clip.start_time + clip.clip.duration_seconds();
                        if clip_end > max_end_time {
                            max_end_time = clip_end;
                        }
                    }
                }
            }
        }

        // Add a small tail for reverb/delay to decay (1 second)
        max_end_time + 1.0
    }
}
