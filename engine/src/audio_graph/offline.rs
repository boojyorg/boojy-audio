/// Offline rendering for export and bounce
use super::{AudioGraph, interpolate_automation_gain};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::track::{AutomationPoint, TimelineClip, TimelineMidiClip};
use crate::effects::Effect;

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
            volume_automation: Vec<AutomationPoint>, // For per-frame interpolation
        }

        let sample_rate = TARGET_SAMPLE_RATE;
        let total_frames = (duration_seconds * f64::from(sample_rate)) as usize;
        let mut output = Vec::with_capacity(total_frames * 2); // stereo interleaved

        eprintln!("🎵 [AudioGraph] Starting offline render: {duration_seconds:.2}s ({total_frames} frames)");

        // Get tempo for timeline positioning
        // Timeline positions are tempo-dependent: at 120 BPM, 1 timeline second = 1 real second
        let current_tempo = self.recorder.get_tempo();
        let tempo_ratio = current_tempo / 120.0;
        eprintln!("🎵 [AudioGraph] Using tempo {current_tempo} BPM (ratio: {tempo_ratio:.3})");

        let (track_snapshots, has_solo, master_snapshot) = {
            let tm = self.track_manager.lock();
            let has_solo_flag = tm.has_solo();
            let all_tracks = tm.get_all_tracks();
            let mut snapshots = Vec::new();
            let mut master_snap = None;

            for track_arc in all_tracks {
                { let track = track_arc.lock();
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
                        volume_automation: track.volume_automation.clone(),
                    };

                    if track.track_type == crate::track::TrackType::Master {
                        master_snap = Some(snap);
                    } else {
                        snapshots.push(snap);
                    }
                }
            }

            (snapshots, has_solo_flag, master_snap)
        };

        eprintln!("🎵 [AudioGraph] Rendering {} tracks", track_snapshots.len());

        // Process each frame
        for frame_idx in 0..total_frames {
            // Apply tempo ratio: at 120 BPM, playhead advances 1:1 with real time
            let real_seconds = frame_idx as f64 / f64::from(sample_rate);
            let playhead_seconds = real_seconds * tempo_ratio;

            let mut mix_left = 0.0f32;
            let mut mix_right = 0.0f32;

            // Mix all tracks
            for track_snap in &track_snapshots {
                // Handle mute/solo logic
                if track_snap.muted {
                    continue;
                }
                if has_solo && !track_snap.soloed {
                    continue;
                }

                let mut track_left = 0.0f32;
                let mut track_right = 0.0f32;

                // Mix all audio clips on this track
                for timeline_clip in &track_snap.audio_clips {
                    let clip_duration = timeline_clip.duration
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
                        let time_in_clip = playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                        let clip_gain = timeline_clip.get_gain();
                        let pitch_ratio = f64::from(timeline_clip.get_pitch_ratio());

                        // Determine which audio source to use and calculate frame index
                        let (frame_in_clip, source_clip): (usize, &AudioClip) = if timeline_clip.warp_enabled {
                            if timeline_clip.warp_mode == 0 {
                                // Warp mode: use pre-stretched cached audio (pitch preserved)
                                // Apply pitch ratio for transpose
                                if let Some(ref stretched) = timeline_clip.stretched_cache {
                                    let frame = (time_in_clip * pitch_ratio * f64::from(sample_rate)) as usize;
                                    (frame, stretched.as_ref())
                                } else {
                                    // Fallback to Re-Pitch if cache not ready
                                    let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                                    ((stretched_time * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
                                }
                            } else {
                                // Re-Pitch mode: sample-rate shift (pitch follows speed)
                                // Also apply any additional transpose
                                let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                                ((stretched_time * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
                            }
                        } else {
                            // No warp - apply pitch ratio for transpose
                            ((time_in_clip * pitch_ratio * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
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

                // Process MIDI clips - route to EITHER built-in synth OR VST3 (not both)
                let has_vst3 = !track_snap.fx_chain.is_empty();
                for timeline_midi_clip in &track_snap.midi_clips {
                    let clip_start_samples = (timeline_midi_clip.start_time * f64::from(sample_rate)) as u64;
                    let clip_end_samples = clip_start_samples + timeline_midi_clip.clip.duration_samples;

                    // Check if clip is active at this frame
                    // Use <= for end boundary to ensure note-offs at exact clip end are triggered
                    if frame_idx as u64 >= clip_start_samples && (frame_idx as u64) <= clip_end_samples {
                        let frame_in_clip = frame_idx as u64 - clip_start_samples;

                        // Check for MIDI events at this exact frame
                        for event in &timeline_midi_clip.clip.events {
                            if event.timestamp_samples == frame_in_clip {
                                match event.event_type {
                                    crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                        // Send to built-in synth ONLY if no VST3 plugins
                                        if !has_vst3 {
                                            { let mut synth_manager = self.track_synth_manager.lock();
                                                synth_manager.note_on(track_snap.id, note, velocity);
                                            }
                                        }
                                        // Send to VST3 instruments in FX chain
                                        if has_vst3 {
                                            { let effect_mgr = self.effect_manager.lock();
                                                for effect_id in &track_snap.fx_chain {
                                                    if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                        { let mut effect = effect_arc.lock();
                                                            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                            if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                let _ = vst3.process_midi_event(0, 0, i32::from(note), i32::from(velocity), 0);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                        // Send to built-in synth ONLY if no VST3 plugins
                                        if !has_vst3 {
                                            { let mut synth_manager = self.track_synth_manager.lock();
                                                synth_manager.note_off(track_snap.id, note);
                                            }
                                        }
                                        // Send to VST3 instruments in FX chain
                                        if has_vst3 {
                                            { let effect_mgr = self.effect_manager.lock();
                                                for effect_id in &track_snap.fx_chain {
                                                    if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                        { let mut effect = effect_arc.lock();
                                                            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                            if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                                let _ = vst3.process_midi_event(1, 0, i32::from(note), 0, 0);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Add synthesizer output
                { let mut synth_manager = self.track_synth_manager.lock();
                    let (synth_left, synth_right) = synth_manager.process_sample_stereo(track_snap.id);
                    track_left += synth_left;
                    track_right += synth_right;
                }

                // Apply track volume (use automation if available)
                let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                    track_snap.volume_gain
                } else {
                    interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
                };
                track_left *= frame_volume_gain;
                track_right *= frame_volume_gain;

                // Apply track pan
                track_left *= track_snap.pan_left;
                track_right *= track_snap.pan_right;

                // Process FX chain on this track
                let mut fx_left = track_left;
                let mut fx_right = track_right;

                { let effect_mgr = self.effect_manager.lock();
                    for effect_id in &track_snap.fx_chain {
                        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                            { let mut effect = effect_arc.lock();
                                let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                                fx_left = out_l;
                                fx_right = out_r;
                            }
                        }
                    }
                }

                // Accumulate to mix bus
                mix_left += fx_left;
                mix_right += fx_right;
            }

            // Apply master track processing
            let mut master_left = mix_left;
            let mut master_right = mix_right;

            if let Some(ref master_snap) = master_snapshot {
                // Apply master volume
                master_left *= master_snap.volume_gain;
                master_right *= master_snap.volume_gain;

                // Apply master pan
                let temp_l = master_left * master_snap.pan_left + master_right * master_snap.pan_left;
                let temp_r = master_left * master_snap.pan_right + master_right * master_snap.pan_right;
                master_left = temp_l;
                master_right = temp_r;

                // Process master FX chain
                { let effect_mgr = self.effect_manager.lock();
                    for effect_id in &master_snap.fx_chain {
                        if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                            { let mut effect = effect_arc.lock();
                                let (out_l, out_r) = effect.process_frame(master_left, master_right);
                                master_left = out_l;
                                master_right = out_r;
                            }
                        }
                    }
                }
            }

            // Apply master limiter
            let (limited_left, limited_right) = { let mut limiter = self.master_limiter.lock();
                limiter.process_frame(master_left, master_right)
            };

            // Write to output buffer (interleaved stereo)
            output.push(limited_left);
            output.push(limited_right);

            // Progress logging every 10%
            if frame_idx % (total_frames / 10).max(1) == 0 {
                let progress = (frame_idx as f64 / total_frames as f64 * 100.0) as i32;
                eprintln!("   {progress}% complete...");
            }
        }

        eprintln!("✅ [AudioGraph] Offline render complete: {} samples", output.len());
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

        eprintln!(
            "🎚️ [AudioGraph] Starting track {track_id} offline render: {duration_seconds:.2}s ({total_frames} frames)"
        );

        // Get tempo for timeline positioning
        let current_tempo = self.recorder.get_tempo();
        let tempo_ratio = current_tempo / 120.0;

        let track_snapshot = {
            let tm = self.track_manager.lock();
            let mut snapshot = None;

            for track_arc in tm.get_all_tracks() {
                { let track = track_arc.lock();
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

        // Process each frame
        for frame_idx in 0..total_frames {
            // Apply tempo ratio: at 120 BPM, playhead advances 1:1 with real time
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

                if playhead_seconds >= timeline_clip.start_time && playhead_seconds < clip_end {
                    let time_in_clip =
                        playhead_seconds - timeline_clip.start_time + timeline_clip.offset;
                    let clip_gain = timeline_clip.get_gain();
                    let pitch_ratio = f64::from(timeline_clip.get_pitch_ratio());

                    // Determine which audio source to use and calculate frame index
                    let (frame_in_clip, source_clip): (usize, &AudioClip) = if timeline_clip.warp_enabled {
                        if timeline_clip.warp_mode == 0 {
                            // Warp mode: use pre-stretched cached audio (pitch preserved)
                            // Apply pitch ratio for transpose
                            if let Some(ref stretched) = timeline_clip.stretched_cache {
                                let frame = (time_in_clip * pitch_ratio * f64::from(sample_rate)) as usize;
                                (frame, stretched.as_ref())
                            } else {
                                // Fallback to Re-Pitch if cache not ready
                                let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                                ((stretched_time * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
                            }
                        } else {
                            // Re-Pitch mode: sample-rate shift (pitch follows speed)
                            // Also apply any additional transpose
                            let stretched_time = time_in_clip * f64::from(timeline_clip.stretch_factor) * pitch_ratio;
                            ((stretched_time * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
                        }
                    } else {
                        // No warp - apply pitch ratio for transpose
                        ((time_in_clip * pitch_ratio * f64::from(sample_rate)) as usize, &*timeline_clip.clip)
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

            // Process MIDI clips - route to EITHER built-in synth OR VST3 (not both)
            let has_vst3 = !track_snap.fx_chain.is_empty();
            for timeline_midi_clip in &track_snap.midi_clips {
                let clip_start_samples = (timeline_midi_clip.start_time * f64::from(sample_rate)) as u64;
                let clip_end_samples =
                    clip_start_samples + timeline_midi_clip.clip.duration_samples;

                if frame_idx as u64 >= clip_start_samples && (frame_idx as u64) <= clip_end_samples
                {
                    let frame_in_clip = frame_idx as u64 - clip_start_samples;

                    for event in &timeline_midi_clip.clip.events {
                        if event.timestamp_samples == frame_in_clip {
                            match event.event_type {
                                crate::midi::MidiEventType::NoteOn { note, velocity } => {
                                    // Send to built-in synth ONLY if no VST3 plugins
                                    if !has_vst3 {
                                        { let mut synth_manager = self.track_synth_manager.lock();
                                            synth_manager.note_on(track_id, note, velocity);
                                        }
                                    }
                                    // Send to VST3 instruments in FX chain
                                    if has_vst3 {
                                        { let effect_mgr = self.effect_manager.lock();
                                            for effect_id in &track_snap.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    { let mut effect = effect_arc.lock();
                                                        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                        if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                            let _ = vst3.process_midi_event(0, 0, i32::from(note), i32::from(velocity), 0);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                crate::midi::MidiEventType::NoteOff { note, velocity: _ } => {
                                    // Send to built-in synth ONLY if no VST3 plugins
                                    if !has_vst3 {
                                        { let mut synth_manager = self.track_synth_manager.lock();
                                            synth_manager.note_off(track_id, note);
                                        }
                                    }
                                    // Send to VST3 instruments in FX chain
                                    if has_vst3 {
                                        { let effect_mgr = self.effect_manager.lock();
                                            for effect_id in &track_snap.fx_chain {
                                                if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                                                    { let mut effect = effect_arc.lock();
                                                        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                                                        if let crate::effects::EffectType::VST3(ref mut vst3) = *effect {
                                                            let _ = vst3.process_midi_event(1, 0, i32::from(note), 0, 0);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add synthesizer output
            { let mut synth_manager = self.track_synth_manager.lock();
                let (synth_left, synth_right) = synth_manager.process_sample_stereo(track_id);
                track_left += synth_left;
                track_right += synth_right;
            }

            // Apply track volume (use automation if available)
            let frame_volume_gain = if track_snap.volume_automation.is_empty() {
                track_snap.volume_gain
            } else {
                interpolate_automation_gain(&track_snap.volume_automation, playhead_seconds)
            };
            track_left *= frame_volume_gain;
            track_right *= frame_volume_gain;

            // Apply track pan
            track_left *= track_snap.pan_left;
            track_right *= track_snap.pan_right;

            // Process FX chain on this track
            let mut fx_left = track_left;
            let mut fx_right = track_right;

            { let effect_mgr = self.effect_manager.lock();
                for effect_id in &track_snap.fx_chain {
                    if let Some(effect_arc) = effect_mgr.get_effect(*effect_id) {
                        { let mut effect = effect_arc.lock();
                            let (out_l, out_r) = effect.process_frame(fx_left, fx_right);
                            fx_left = out_l;
                            fx_right = out_r;
                        }
                    }
                }
            }

            // Write to output buffer (interleaved stereo)
            output.push(fx_left);
            output.push(fx_right);

            // Progress logging every 25%
            if frame_idx % (total_frames / 4).max(1) == 0 && frame_idx > 0 {
                let progress = (frame_idx as f64 / total_frames as f64 * 100.0) as i32;
                eprintln!("   Track {track_id} - {progress}% complete...");
            }
        }

        eprintln!(
            "✅ [AudioGraph] Track {} offline render complete: {} samples",
            track_id,
            output.len()
        );
        output
    }

    /// Get track info for stem export (id, name, type)
    pub fn get_tracks_for_stem_export(&self) -> Vec<(u64, String, String)> {
        let mut tracks = Vec::new();

        { let tm = self.track_manager.lock();
            for track_arc in tm.get_all_tracks() {
                { let track = track_arc.lock();
                    // Skip master track
                    if track.track_type == crate::track::TrackType::Master {
                        continue;
                    }

                    let type_str = match track.track_type {
                        crate::track::TrackType::Audio => "audio",
                        crate::track::TrackType::Midi
                        | crate::track::TrackType::Sampler => "midi",
                        crate::track::TrackType::Return => "return",
                        crate::track::TrackType::Group => "group",
                        crate::track::TrackType::Master => "master",
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
        { let tm = self.track_manager.lock();
            for track_arc in tm.get_all_tracks() {
                { let track = track_arc.lock();
                    // Audio clips
                    for clip in &track.audio_clips {
                        let clip_end = clip.start_time + clip.duration.unwrap_or(clip.clip.duration_seconds);
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
