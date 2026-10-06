// Remaining API functions - Track utilities
//
// These functions are included via include!() in mod.rs.
// They could be moved to tracks.rs in the future.

use crate::track::TrackId;

/// Re-add an existing audio clip to a track from the clips map.
/// Used for undo/redo to restore a previously removed clip with its original ID.
/// The clip data must still exist in `AUDIO_CLIPS`.
///
/// Returns the clip ID (same as input) on success.
pub fn add_existing_clip_to_track(
    clip_id: u64,
    track_id: u64,
    start_time: f64,
    offset: f64,
    duration: Option<f64>,
) -> Result<u64, String> {
    let clips_mutex = clips()?;
    let clips_map = clips_mutex.lock();

    let clip_arc = clips_map
        .get(&clip_id)
        .ok_or(format!("Clip {clip_id} not found in clips map"))?
        .clone();

    drop(clips_map);

    let graph_mutex = graph()?;
    let graph_lock = graph_mutex.lock();

    let success = graph_lock.add_clip_to_track_with_id(
        track_id, clip_id, clip_arc, start_time, offset, duration,
    );

    if !success {
        return Err(format!("Failed to add clip to track {track_id}"));
    }

    eprintln!(
        "🔄 [API] Re-added clip {clip_id} on track {track_id} at {start_time:.3}s"
    );

    Ok(clip_id)
}

/// List every audio clip on every track, so the UI can rebuild its arrangement
/// from the engine's copy of the song (the way MIDI clips already work).
///
/// Returns a `;`-separated list, one entry per clip. Each entry is
/// `clip_id,track_id,start_time,offset,duration,file_duration,gain_db,`
/// `warp_enabled,stretch_factor,warp_mode,transpose_semitones,transpose_cents,`
/// `reversed,loop_length,loop_start,file_path`
///
/// `duration` is `-1` when the clip plays to the end of its file (no explicit
/// duration), `loop_length` `-1` when the clip doesn't repeat. Booleans are `0`/`1`. `file_path` is last and percent-encoded
/// (`encode_csv_field`; decode with `decodeCsvField` on the Dart side).
pub fn get_all_audio_clips_info() -> Result<String, String> {
    use super::helpers::encode_csv_field;

    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    let mut entries: Vec<String> = Vec::new();
    for track_arc in track_manager.get_all_tracks() {
        let track = track_arc.lock();
        for clip in &track.audio_clips {
            entries.push(format!(
                "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}",
                clip.id,
                track.id,
                clip.start_time,
                clip.offset,
                clip.duration.unwrap_or(-1.0),
                clip.clip.duration_seconds,
                clip.gain_db,
                u8::from(clip.warp_enabled),
                clip.stretch_factor,
                clip.warp_mode,
                clip.transpose_semitones,
                clip.transpose_cents,
                u8::from(clip.reversed),
                clip.loop_length.unwrap_or(-1.0),
                clip.loop_start,
                encode_csv_field(&clip.clip.file_path),
            ));
        }
    }

    Ok(entries.join(";"))
}

/// Join (bounce) a set of audio clips on one track into a single rendered WAV.
///
/// RENDER-ONLY: the engine writes a stereo 48 kHz WAV baking each clip's
/// gain/pitch/warp/reverse exactly as playback does, and does NOT mutate the
/// track — the UI's `JoinAudioClipsCommand` owns removing the originals and
/// adding the joined clip (so the whole thing is one undo step). The file is
/// written to the OS temp dir; on project save it is copied into the project
/// like any other audio file.
///
/// Returns the absolute path of the rendered WAV.
pub fn join_audio_clips(track_id: u64, clip_ids: Vec<u64>) -> Result<String, String> {
    if clip_ids.len() < 2 {
        return Err("need at least 2 clips to join".to_string());
    }

    // Deterministic temp filename — repeating the same join overwrites rather
    // than leaking a new file each time.
    let mut sorted = clip_ids.clone();
    sorted.sort_unstable();
    let first = sorted.first().copied().unwrap_or(0);
    let last = sorted.last().copied().unwrap_or(0);
    let out_path =
        std::env::temp_dir().join(format!("boojy_join_t{track_id}_{first}_{last}.wav"));

    let graph_mutex = graph()?;
    let graph_lock = graph_mutex.lock();
    graph_lock.render_audio_clips_to_wav(track_id, &clip_ids, &out_path)?;

    Ok(out_path.to_string_lossy().into_owned())
}

/// Set the start time (position) of a clip on a track
/// Used for dragging clips to reposition them on the timeline
pub fn set_clip_start_time(track_id: u64, clip_id: u64, start_time: f64) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();

        // Try audio clips first
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.start_time = start_time.max(0.0); // Clamp to >= 0
                return Ok(format!("Clip {clip_id} moved to {start_time:.3}s"));
            }
        }

        // Try MIDI clips
        for clip in &mut track.midi_clips {
            if clip.id == clip_id {
                let clamped = start_time.max(0.0);
                clip.start_time = clamped;
                drop(track);
                drop(track_manager);
                {
                    let mut midi_clips = graph.get_midi_clips().lock();
                    if let Some(global) = midi_clips.iter_mut().find(|c| c.id == clip_id) {
                        global.start_time = clamped;
                    }
                }
                return Ok(format!("MIDI clip {clip_id} moved to {clamped:.3}s"));
            }
        }

        Err(format!("Clip {clip_id} not found on track {track_id}"))
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

/// Set the offset (trim start) of an audio clip on a track
///
/// Offset is in seconds — how far into the audio data to start playback.
/// Used for recording overlap trimming.
pub fn set_clip_offset(track_id: u64, clip_id: u64, offset: f64) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();

        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.offset = offset.max(0.0);
                return Ok(format!("Clip {clip_id} offset set to {offset:.3}s"));
            }
        }

        Err(format!("Audio clip {clip_id} not found on track {track_id}"))
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

/// Set the playback duration of an audio clip on a track
///
/// Duration is in seconds. Sets `clip.duration = Some(duration)` which limits
/// how much of the audio data is played. Used for recording overlap trimming.
pub fn set_clip_duration(track_id: u64, clip_id: u64, duration: f64) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();

        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.duration = Some(duration.max(0.0));
                return Ok(format!("Clip {clip_id} duration set to {duration:.3}s"));
            }
        }

        Err(format!("Audio clip {clip_id} not found on track {track_id}"))
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

/// Delete a track (cannot delete master)
pub fn delete_track(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();

    // Stop any playing notes on the per-track synth to prevent stuck notes
    { let mut synth_manager = graph.track_synth_manager.lock();
        synth_manager.all_notes_off(track_id);
        // Also remove the synth for this track
        synth_manager.remove_synth(track_id);
    }

    // Remove all MIDI clips belonging to this track from the global collection
    graph.remove_midi_clips_for_track(track_id);

    // Get the track's fx_chain before deleting so we can clean up effects
    let fx_chain: Vec<u64> = {
        let track_manager = graph.track_manager.lock();
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let track = track_arc.lock();
            track.fx_chain.clone()
        } else {
            Vec::new()
        }
    };

    // Remove all VST3 effects in the track's fx_chain
    if !fx_chain.is_empty() {
        { let mut effect_manager = graph.effect_manager.lock();
            for effect_id in &fx_chain {
                effect_manager.remove_effect(*effect_id);
                eprintln!("🧹 [API] Removed effect {effect_id} from deleted track {track_id}");
            }
        }
    }

    let removed = graph.track_manager.lock().remove_track(track_id);
    // Deleting the last armed audio track closes the input.
    graph.sync_input_to_armed_tracks();

    if removed {
        Ok(format!("Track {track_id} deleted"))
    } else {
        Err(format!(
            "Cannot delete track {track_id} (either not found or is master track)"
        ))
    }
}

/// Clear all tracks except master - used for New Project / Close Project
///
/// This removes all tracks, clips, and effects, leaving only the master track.
/// The master track is reset to default settings.
///
/// # Returns
/// Success message
pub fn clear_all_tracks() -> Result<String, String> {
    let graph_mutex = graph()?;
    let mut graph = graph_mutex.lock();

    // Tear down tracks, instruments, effects, MIDI clips and restart track and
    // clip numbering, so the first track in every new project gets id 1.
    let cleared_tracks = {
        let track_manager = graph.track_manager.lock();
        track_manager.get_all_tracks().len().saturating_sub(1)
    };
    graph.teardown_project_state();
    graph.sync_input_to_armed_tracks();

    // Clear all audio clips from global storage
    let clips_mutex = clips()?;
    let mut clips_map = clips_mutex.lock();
    clips_map.clear();

    // Reset master track to defaults (volume = 0dB, pan = 0, unmuted)
    {
        let track_manager = graph.track_manager.lock();
        if let Some(master_arc) = track_manager.get_track(0) {
            let mut master = master_arc.lock();
            master.volume_db = 0.0;
            master.pan = 0.0;
            master.mute = false;
            master.solo = false;
        }
    }

    eprintln!("🧹 [API] Cleared {cleared_tracks} tracks (master track preserved)");
    Ok(format!("Cleared {cleared_tracks} tracks"))
}

/// Duplicate a track (cannot duplicate master)
///
/// Creates a copy of the track with the same settings, clips, and effects.
/// The new track will be named "<original name> Copy".
///
/// # Arguments
/// * `track_id` - Track ID to duplicate
///
/// # Returns
/// New track ID on success, error if track not found or is master
pub fn duplicate_track(track_id: TrackId) -> Result<TrackId, String> {
    duplicate_track_as(track_id, None)
}

/// [`duplicate_track`] under a chosen id for the copy (redo recreates the
/// copy under the id it had), or a fresh one with `None`.
pub fn duplicate_track_as(track_id: TrackId, new_id: Option<TrackId>) -> Result<TrackId, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();

    // Cannot duplicate master track
    if track_id == 0 {
        return Err("Cannot duplicate master track".to_string());
    }

    // First, collect the data we need from the source track
    let (track_type, name, volume_db, pan, mute, fx_chain, sends) = {
        let track_manager = graph.track_manager.lock();
        let source_track_arc = track_manager
            .get_track(track_id)
            .ok_or(format!("Track {track_id} not found"))?;

        let source_track = source_track_arc.lock();

        // Collect all data we need to copy
        (
            source_track.track_type,
            format!("{} Copy", source_track.name),
            source_track.volume_db,
            source_track.pan,
            source_track.mute,
            source_track.fx_chain.clone(),
            source_track.sends.clone(),
        )
        // source_track lock is released here
        // track_manager lock is released here
    };

    // Now create the new track and set its properties
    let new_track_id = {
        let mut track_manager = graph.track_manager.lock();
        match new_id {
            Some(id) => track_manager.insert_track_with_id(id, track_type, name)?,
            None => track_manager.create_track(track_type, name),
        }
    };

    // Deep copy effects chain (create new effect instances)
    let new_fx_chain = {
        let mut effect_manager = graph.effect_manager.lock();
        let mut new_chain = Vec::new();

        for effect_id in &fx_chain {
            if let Some(new_effect_id) = effect_manager.duplicate_effect(*effect_id) {
                new_chain.push(new_effect_id);
            } else {
                eprintln!("⚠️  [API] Failed to duplicate effect {effect_id}");
            }
        }

        new_chain
    };

    // Copy properties to the new track
    {
        let track_manager = graph.track_manager.lock();
        let new_track_arc = track_manager
            .get_track(new_track_id)
            .ok_or("Failed to get newly created track")?;

        let mut new_track = new_track_arc.lock();

        // Copy mixer settings
        new_track.volume_db = volume_db;
        new_track.pan = pan;
        new_track.mute = mute;
        new_track.solo = false; // Don't copy solo state
        new_track.armed = false; // Don't copy armed state

        // Clips are not copied here: the app copies each one through
        // duplicate_audio_clip_to_track (and its MIDI path) so every copy
        // gets its own ID and appears on the timeline. Copying them here
        // shared IDs with the originals and left them playing unseen.

        // Use the deep-copied effects chain
        new_track.fx_chain = new_fx_chain;

        // Copy sends
        new_track.sends = sends;
        // new_track lock is released here
        // track_manager lock is released here
    };

    // Copy instrument assignment if exists (for MIDI tracks)
    {
        let mut synth_manager = graph.track_synth_manager.lock();
        if synth_manager.has_synth(track_id) {
            synth_manager.copy_synth(track_id, new_track_id);
        }
    };

    eprintln!(
        "📋 [API] Duplicated track {track_id} → new track {new_track_id} created"
    );
    graph.sync_input_to_armed_tracks();

    Ok(new_track_id)
}

/// Duplicate an audio clip on the same track at a new position.
///
/// Returns the new clip's ID. See [`duplicate_audio_clip_to_track`].
pub fn duplicate_audio_clip(
    track_id: TrackId,
    source_clip_id: u64,
    new_start_time: f64,
    new_clip_id: Option<u64>,
) -> Result<u64, String> {
    duplicate_audio_clip_to_track(
        track_id,
        source_clip_id,
        track_id,
        new_start_time,
        new_clip_id,
    )
}

/// Copy an audio clip onto `target_track_id` at `new_start_time` under a new
/// clip ID: same audio (shared, not copied), trim, gain, warp, pitch, reverse
/// and processed audio. Duplicate Track uses it to give every copied clip its
/// own ID.
///
/// `new_clip_id` keeps the id the copy had before (redo); `None` picks a
/// fresh one. Returns the new clip's ID.
pub fn duplicate_audio_clip_to_track(
    source_track_id: TrackId,
    source_clip_id: u64,
    target_track_id: TrackId,
    new_start_time: f64,
    new_clip_id: Option<u64>,
) -> Result<u64, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();

    // The whole clip is cloned so every setting comes along, including ones
    // added later (field-by-field copying once dropped Reverse).
    let mut copy = {
        let track_manager = graph.track_manager.lock();
        let track_arc = track_manager
            .get_track(source_track_id)
            .ok_or(format!("Track {source_track_id} not found"))?;
        let track = track_arc.lock();
        track
            .audio_clips
            .iter()
            .find(|c| c.id == source_clip_id)
            .ok_or(format!(
                "Clip {source_clip_id} not found on track {source_track_id}"
            ))?
            .clone()
    };
    copy.id = match new_clip_id {
        Some(id) => {
            graph.ensure_next_clip_id_above(id);
            id
        }
        None => graph.allocate_clip_id(),
    };
    copy.start_time = new_start_time;
    let new_clip_id = copy.id;
    let audio = copy.clip.clone();

    {
        let track_manager = graph.track_manager.lock();
        let track_arc = track_manager
            .get_track(target_track_id)
            .ok_or(format!("Track {target_track_id} not found"))?;
        track_arc.lock().audio_clips.push(copy);
    }

    // The global clips map is what a save writes out.
    clips()?.lock().insert(new_clip_id, audio);

    eprintln!(
        "📋 [API] Duplicated clip {source_clip_id} (track {source_track_id}) → clip {new_clip_id} on track {target_track_id} at {new_start_time:.3}s"
    );

    Ok(new_clip_id)
}

/// Set the gain of an audio clip
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to modify
/// * `gain_db` - Gain in dB (-70.0 to +24.0)
///
/// # Returns
/// Success message
pub fn set_audio_clip_gain(track_id: TrackId, clip_id: u64, gain_db: f32) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();

        // Find and update the clip
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.gain_db = gain_db.clamp(-70.0, 24.0);
                return Ok(format!("Clip {} gain set to {:.2} dB", clip_id, clip.gain_db));
            }
        }

        Err(format!("Clip {clip_id} not found on track {track_id}"))
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

/// Set the warp (time-stretch) settings of an audio clip
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to modify
/// * `warp_enabled` - Whether warp/tempo sync is enabled
/// * `stretch_factor` - Stretch factor (`project_bpm` / `clip_bpm`), 1.0 = no stretch
/// * `warp_mode` - Warp algorithm: 0 = warp (pitch preserved), 1 = repitch (pitch follows speed)
///
/// # Returns
/// Success message
pub fn set_audio_clip_warp(
    track_id: TrackId,
    clip_id: u64,
    warp_enabled: bool,
    stretch_factor: f32,
    warp_mode: u8,
) -> Result<String, String> {
    let stretch_factor = stretch_factor.clamp(0.25, 4.0);
    edit_clip_processing(track_id, clip_id, |clip| {
        clip.warp_enabled = warp_enabled;
        clip.stretch_factor = stretch_factor;
        clip.warp_mode = warp_mode;
    })?;
    let mode_str = if warp_mode == 0 { "warp" } else { "repitch" };
    Ok(format!(
        "Clip {clip_id} warp: {warp_enabled}, stretch: {stretch_factor:.2}x, mode: {mode_str}"
    ))
}

/// Apply `edit` to a clip's playback settings and rebuild its processed
/// audio (warp stretch, transpose) to match. The rebuild renders the whole
/// clip, so it runs on a copy with no locks held: the audio thread takes the
/// track lock every buffer, and rendering under it stalled playback.
fn edit_clip_processing(
    track_id: TrackId,
    clip_id: u64,
    edit: impl Fn(&mut crate::track::TimelineClip),
) -> Result<(), String> {
    let graph_mutex = graph()?;
    let with_clip = |apply: &mut dyn FnMut(&mut crate::track::TimelineClip)| {
        let graph = graph_mutex.lock();
        let track_manager = graph.track_manager.lock();
        let track_arc = track_manager
            .get_track(track_id)
            .ok_or(format!("Track {track_id} not found"))?;
        let mut track = track_arc.lock();
        let clip = track
            .audio_clips
            .iter_mut()
            .find(|c| c.id == clip_id)
            .ok_or(format!("Clip {clip_id} not found on track {track_id}"))?;
        apply(clip);
        Ok::<(), String>(())
    };

    let mut snapshot = None;
    with_clip(&mut |clip| snapshot = Some(clip.clone()))?;
    let mut snapshot = snapshot.expect("clip was found");
    edit(&mut snapshot);
    let processed = snapshot.processed_audio();

    with_clip(&mut |clip| {
        edit(clip);
        clip.set_processed_audio(processed.clone());
    })
}

/// Set the transpose/pitch shift of an audio clip
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to modify
/// * `semitones` - Transpose in semitones (-48 to +48)
/// * `cents` - Fine pitch adjustment in cents (-50 to +50)
///
/// # Returns
/// Success message
pub fn set_audio_clip_transpose(
    track_id: TrackId,
    clip_id: u64,
    semitones: i32,
    cents: i32,
) -> Result<String, String> {
    let semitones = semitones.clamp(-48, 48);
    let cents = cents.clamp(-50, 50);
    edit_clip_processing(track_id, clip_id, |clip| {
        clip.transpose_semitones = semitones;
        clip.transpose_cents = cents;
    })?;
    Ok(format!("Clip {clip_id} transpose: {semitones} st, {cents} ct"))
}

/// Set whether an audio clip plays its audible window backwards
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to modify
/// * `reversed` - true to play the clip backwards
///
/// # Returns
/// Success message
pub fn set_audio_clip_reverse(
    track_id: TrackId,
    clip_id: u64,
    reversed: bool,
) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();

        // Find and update the clip
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.reversed = reversed;
                return Ok(format!("Clip {clip_id} reversed: {reversed}"));
            }
        }

        Err(format!("Clip {clip_id} not found on track {track_id}"))
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

/// Set how an audio clip repeats when it is longer than its loop:
/// `loop_length` seconds of its own audio from its trim offset (`<= 0` = no
/// repeats), starting `loop_start` seconds into the loop.
pub fn set_audio_clip_loop(
    track_id: TrackId,
    clip_id: u64,
    loop_length: f64,
    loop_start: f64,
) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    let Some(track_arc) = track_manager.get_track(track_id) else {
        return Err(format!("Track {track_id} not found"));
    };
    let mut track = track_arc.lock();
    let Some(clip) = track.audio_clips.iter_mut().find(|c| c.id == clip_id) else {
        return Err(format!("Clip {clip_id} not found on track {track_id}"));
    };
    clip.loop_length = (loop_length > 0.0).then_some(loop_length);
    clip.loop_start = loop_start.max(0.0);
    Ok(format!("Clip {clip_id} loop: {loop_length:.3}s from {loop_start:.3}s"))
}

/// Remove an audio clip from a track
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to remove
///
/// # Returns
/// true if clip was removed, false if not found
pub fn remove_audio_clip(track_id: TrackId, clip_id: u64) -> Result<bool, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();

    let track_manager = graph.track_manager.lock();
    let track_arc = track_manager
        .get_track(track_id)
        .ok_or(format!("Track {track_id} not found"))?;

    let mut track = track_arc.lock();

    // Find and remove the clip
    let initial_len = track.audio_clips.len();
    track.audio_clips.retain(|c| c.id != clip_id);
    let removed = track.audio_clips.len() < initial_len;

    if removed {
        eprintln!("🗑️  [API] Removed audio clip {clip_id} from track {track_id}");
    }

    Ok(removed)
}
