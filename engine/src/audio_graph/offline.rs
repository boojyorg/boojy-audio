/// Offline rendering for export and bounce
use super::{interpolate_automation_gain, AudioGraph};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
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

/// Reset every built-in effect in a chain before an offline render, so the
/// export starts from silence — not from whatever compressor envelopes, delay
/// lines and reverb tails live playback (or a previous offline render) left
/// behind. Effect instances are shared with realtime playback, so without
/// this a stem rendered after the full mix starts with the mix render's FX
/// state and audibly diverges from it.
///
/// VST3 plugins are deliberately skipped: their `reset()` is a full
/// deactivate/reinitialize/activate cycle (`vst3_host.rs`), too heavy and
/// risky to fire on every export. VST3 export fidelity is its own later
/// cycle (C27–C30).
fn reset_builtin_fx_offline(effect_mgr: &EffectManager, fx_chain: &[u64]) {
    for effect_id in fx_chain {
        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
            let mut effect = effect_arc.lock();
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            if matches!(*effect, crate::effects::EffectType::VST3(_)) {
                continue;
            }
            effect.reset();
        }
    }
}

/// True if the chain hosts a VST3 plugin, which receives the track's MIDI as an
/// instrument. Built-in effects (reverb, EQ, …) do not — for those the track's
/// MIDI must reach the built-in synth instead. This mirrors the realtime
/// renderer's routing decision (`renderer.rs`): without it, offline export used
/// `!fx_chain.is_empty()`, so any MIDI track carrying a built-in effect routed
/// its notes to the (absent) VST3 queue and exported silent. (Bug C6)
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
fn fx_chain_hosts_vst3(effect_mgr: &EffectManager, fx_chain: &[u64]) -> bool {
    fx_chain.iter().any(|effect_id| {
        effect_mgr.get_effect(*effect_id).is_some_and(|effect_arc| {
            matches!(*effect_arc.lock(), crate::effects::EffectType::VST3(_))
        })
    })
}

#[cfg(not(all(feature = "vst3", not(target_os = "ios"))))]
fn fx_chain_hosts_vst3(_effect_mgr: &EffectManager, _fx_chain: &[u64]) -> bool {
    false
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
            has_vst3_instrument: bool, // fx_chain hosts a VST3 plugin → MIDI routes to it, not the synth (C6)
            sends: Vec<(u64, f32)>,
            volume_automation: Vec<AutomationPoint>, // For per-frame interpolation
        }

        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * f64::from(sample_rate)) as usize;
        let mut output = Vec::with_capacity(total_frames * 2); // stereo interleaved

        dlog!("🎵 [AudioGraph] Starting offline render: {duration_seconds:.2}s ({total_frames} frames)");

        // Timeline positions live in REAL seconds — same domain as live
        // playback (renderer.rs); tempo only affects where the UI places
        // things, never how fast the render advances through them.

        let (mut track_snapshots, return_snapshots, has_solo, master_snapshot, return_index) = {
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
                        // Set in a second pass below, after the track-manager
                        // lock is released, to avoid nesting the effect-manager
                        // lock inside it.
                        has_vst3_instrument: false,
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

        // Decide MIDI routing per track now that the track-manager lock is
        // released: a track hosting a VST3 plugin sends its MIDI to that plugin;
        // every other track (including ones with only built-in effects) feeds
        // the built-in synth. One effect-manager lock for the whole pass. (C6)
        let live_fx_sample_rate = {
            let mut effect_mgr = self.effect_manager.lock();
            for snap in &mut track_snapshots {
                snap.has_vst3_instrument = fx_chain_hosts_vst3(&effect_mgr, &snap.fx_chain);
            }

            // Pin built-in FX to the export rate: the live stream may run at
            // a different device rate (their coefficients follow it), but the
            // offline render is written as a TARGET_SAMPLE_RATE file.
            // Restored after the render.
            let live_rate = effect_mgr.sample_rate();
            if (live_rate - TARGET_SAMPLE_RATE as f32).abs() > f32::EPSILON {
                effect_mgr.set_builtin_sample_rate(TARGET_SAMPLE_RATE as f32);
                self.master_limiter
                    .lock()
                    .set_sample_rate(TARGET_SAMPLE_RATE as f32);
            }

            // Start the export from silence: clear built-in FX state left by
            // live playback or a previous offline render (see
            // `reset_builtin_fx_offline`).
            for snap in &track_snapshots {
                reset_builtin_fx_offline(&effect_mgr, &snap.fx_chain);
            }
            for snap in &return_snapshots {
                reset_builtin_fx_offline(&effect_mgr, &snap.fx_chain);
            }
            if let Some(snap) = &master_snapshot {
                reset_builtin_fx_offline(&effect_mgr, &snap.fx_chain);
            }

            live_rate
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
                // Route MIDI to EITHER built-in synth OR VST3 (not both) —
                // precomputed from the actual effect types, not chain emptiness. (C6)
                let has_vst3 = track_snap.has_vst3_instrument;
                vst3_events.clear();

                // Pass 1: fill scratch with the pre-FX signal (clips + synth),
                // dispatching built-in-synth MIDI per-sample and queuing VST3
                // MIDI with an offset relative to the block start.
                {
                    let mut synth_manager = self.track_synth_manager.lock();
                    for i in 0..block_len {
                        let frame_idx = block_start + i;
                        let playhead_seconds = frame_idx as f64 / f64::from(sample_rate);

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
                                let time_in_clip = timeline_clip
                                    .time_in_clip(playhead_seconds, effective_duration);
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
                                                controller,
                                                value,
                                            } => {
                                                // Mirror realtime: route CC (mod
                                                // wheel, sustain, etc.) to the VST3
                                                // queue or the built-in synth so
                                                // exports keep MIDI automation. (C23)
                                                if has_vst3 {
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
                    let playhead_seconds = frame_idx as f64 / f64::from(sample_rate);

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
                    let playhead_seconds = frame_idx as f64 / f64::from(sample_rate);
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

        // Restore the live stream rate on the built-in FX (no-op when the
        // stream already runs at TARGET_SAMPLE_RATE).
        if (live_fx_sample_rate - TARGET_SAMPLE_RATE as f32).abs() > f32::EPSILON {
            self.effect_manager
                .lock()
                .set_builtin_sample_rate(live_fx_sample_rate);
            self.master_limiter
                .lock()
                .set_sample_rate(live_fx_sample_rate);
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
    /// Render a subset of a track's audio clips to a stereo 48 kHz WAV file,
    /// baking each clip's gain / pitch / warp / reverse exactly as playback does
    /// (it reuses the same per-sample math, [`render_audio_clip_sample`]).
    ///
    /// RENDER-ONLY: it never mutates the track or its clips, and applies no track
    /// fader / pan / FX — the join feature prints clip edits, not the channel
    /// strip. The output begins at the earliest selected clip's start, so the
    /// caller places the joined clip at that same start time. Gaps between the
    /// selected clips render as silence.
    ///
    /// Returns the joined clip's `(start_time, duration)` in seconds.
    pub fn render_audio_clips_to_wav(
        &self,
        track_id: u64,
        clip_ids: &[u64],
        output_path: &std::path::Path,
    ) -> Result<(f64, f64), String> {
        use super::renderer::render_audio_clip_sample;

        // Snapshot the selected clips under the track lock, then drop the guard
        // before doing any heavy work (lock-safety: see sends.rs pattern).
        let clips: Vec<TimelineClip> = {
            let tm = self.track_manager.lock();
            let mut found = Vec::new();
            for track_arc in tm.get_all_tracks() {
                let track = track_arc.lock();
                if track.id == track_id {
                    for tc in &track.audio_clips {
                        if clip_ids.contains(&tc.id) {
                            found.push(tc.clone());
                        }
                    }
                    break;
                }
            }
            found
        };

        if clips.is_empty() {
            return Err(format!(
                "no matching audio clips on track {track_id} to join"
            ));
        }

        // Audio clip start_time/duration are in real seconds — the same
        // domain playback renders in (renderer.rs).
        let sr = TARGET_SAMPLE_RATE;

        let clip_end = |c: &TimelineClip| -> f64 {
            let dur = c.duration.unwrap_or(c.clip.duration_seconds);
            let eff = if c.warp_enabled {
                dur / f64::from(c.stretch_factor)
            } else {
                dur
            };
            c.start_time + eff
        };

        let start = clips
            .iter()
            .map(|c| c.start_time)
            .fold(f64::INFINITY, f64::min);
        let end = clips.iter().map(clip_end).fold(f64::NEG_INFINITY, f64::max);
        let duration_real = (end - start).max(0.0);
        let total_frames = (duration_real * f64::from(sr)).ceil() as usize;

        let mut samples = Vec::with_capacity(total_frames * 2);
        for i in 0..total_frames {
            let playhead = start + i as f64 / f64::from(sr);
            let mut left = 0.0f32;
            let mut right = 0.0f32;
            for clip in &clips {
                let (l, r) = render_audio_clip_sample(clip, playhead);
                left += l;
                right += r;
            }
            samples.push(left);
            samples.push(right);
        }

        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: sr,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let mut writer = hound::WavWriter::create(output_path, spec)
            .map_err(|e| format!("Failed to create joined WAV: {e}"))?;
        for s in &samples {
            writer
                .write_sample(*s)
                .map_err(|e| format!("Failed to write joined sample: {e}"))?;
        }
        writer
            .finalize()
            .map_err(|e| format!("Failed to finalize joined WAV: {e}"))?;

        Ok((start, duration_real))
    }

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

        // Render the stem in sub-blocks of OFFLINE_BLOCK frames: clips + synth
        // into scratch, FX chain over the block, THEN fader/pan — the same
        // gain-stage order as `render_offline`, so a stem's compressor/EQ sees
        // the identical pre-fader signal it sees in the mix. (C68: stems used
        // to apply fader/pan before the FX chain, making them sound different
        // from the full mix.)
        let mut scratch_l = vec![0.0f32; OFFLINE_BLOCK];
        let mut scratch_r = vec![0.0f32; OFFLINE_BLOCK];
        let mut vst3_events: Vec<QueuedVst3Event> = Vec::with_capacity(128);
        // Route MIDI to EITHER built-in synth OR VST3 (not both) — based on the
        // actual effect types in the chain, not chain emptiness. (C6)
        let (has_vst3, live_fx_sample_rate) = {
            let mut effect_mgr = self.effect_manager.lock();

            // Same pin-to-export-rate rule as `render_offline` (restored below).
            let live_rate = effect_mgr.sample_rate();
            if (live_rate - TARGET_SAMPLE_RATE as f32).abs() > f32::EPSILON {
                effect_mgr.set_builtin_sample_rate(TARGET_SAMPLE_RATE as f32);
            }

            // Same clean-slate rule as `render_offline`: the stem must see the
            // FX state the mix render saw at t=0, not the state it left behind.
            reset_builtin_fx_offline(&effect_mgr, &track_snap.fx_chain);
            (
                fx_chain_hosts_vst3(&effect_mgr, &track_snap.fx_chain),
                live_rate,
            )
        };

        let mut block_start = 0usize;
        while block_start < total_frames {
            let block_len = OFFLINE_BLOCK.min(total_frames - block_start);
            vst3_events.clear();

            // Pass 1: clips + synth + MIDI, then fader/pan, into scratch.
            {
                let mut synth_manager = self.track_synth_manager.lock();
                for i in 0..block_len {
                    let frame_idx = block_start + i;
                    let playhead_seconds = frame_idx as f64 / f64::from(sample_rate);

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
                            let time_in_clip = timeline_clip
                                .time_in_clip(playhead_seconds, effective_duration);
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
                                        crate::midi::MidiEventType::ControlChange {
                                            controller,
                                            value,
                                        } => {
                                            // Mirror realtime so stem/track
                                            // exports keep MIDI CC automation. (C23)
                                            if has_vst3 {
                                                vst3_events.push((
                                                    2,
                                                    0,
                                                    i32::from(controller),
                                                    i32::from(value),
                                                    i as i32,
                                                ));
                                            } else {
                                                synth_manager.control_change(
                                                    track_id, controller, value,
                                                );
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Built-in synth output
                    let (synth_left, synth_right) = synth_manager.process_sample_stereo(track_id);
                    track_left += synth_left;
                    track_right += synth_right;

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

            // Pass 3: per-sample fader/pan AFTER the FX chain — matching
            // `render_offline` — then write interleaved stereo output. (C68)
            for i in 0..block_len {
                let frame_idx = block_start + i;
                let playhead_seconds = frame_idx as f64 / f64::from(sample_rate);
                let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                    track_snap.volume_gain
                } else {
                    interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
                };
                output.push(scratch_l[i] * frame_volume_gain * track_snap.pan_left);
                output.push(scratch_r[i] * frame_volume_gain * track_snap.pan_right);
            }

            // Progress logging (~once per block)
            let progress = (block_start as f64 / total_frames as f64 * 100.0) as i32;
            dlog!("   Track {track_id} - {progress}% complete...");

            block_start += block_len;
        }

        // Restore the live stream rate on the built-in FX (no-op when the
        // stream already runs at TARGET_SAMPLE_RATE).
        if (live_fx_sample_rate - TARGET_SAMPLE_RATE as f32).abs() > f32::EPSILON {
            self.effect_manager
                .lock()
                .set_builtin_sample_rate(live_fx_sample_rate);
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
