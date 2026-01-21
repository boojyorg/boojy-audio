// Remaining API functions - Track utilities
//
// These functions are included via include!() in mod.rs.
// They could be moved to tracks.rs in the future.

use crate::track::TrackId;

/// Set the start time (position) of a clip on a track
/// Used for dragging clips to reposition them on the timeline
pub fn set_clip_start_time(track_id: u64, clip_id: u64, start_time: f64) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;

        // Try audio clips first
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.start_time = start_time.max(0.0); // Clamp to >= 0
                return Ok(format!("Clip {} moved to {:.3}s", clip_id, start_time));
            }
        }

        // Try MIDI clips
        for clip in &mut track.midi_clips {
            if clip.id == clip_id {
                clip.start_time = start_time.max(0.0); // Clamp to >= 0
                return Ok(format!("MIDI clip {} moved to {:.3}s", clip_id, start_time));
            }
        }

        Err(format!("Clip {} not found on track {}", clip_id, track_id))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Delete a track (cannot delete master)
pub fn delete_track(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Stop any playing notes on the per-track synth to prevent stuck notes
    if let Ok(mut synth_manager) = graph.track_synth_manager.lock() {
        synth_manager.all_notes_off(track_id);
        // Also remove the synth for this track
        synth_manager.remove_synth(track_id);
    }

    // Remove all MIDI clips belonging to this track from the global collection
    graph.remove_midi_clips_for_track(track_id);

    // Get the track's fx_chain before deleting so we can clean up effects
    let fx_chain: Vec<u64> = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let track = track_arc.lock().map_err(|e| e.to_string())?;
            track.fx_chain.clone()
        } else {
            Vec::new()
        }
    };

    // Remove all VST3 effects in the track's fx_chain
    if !fx_chain.is_empty() {
        if let Ok(mut effect_manager) = graph.effect_manager.lock() {
            for effect_id in &fx_chain {
                effect_manager.remove_effect(*effect_id);
                eprintln!("🧹 [API] Removed effect {} from deleted track {}", effect_id, track_id);
            }
        }
    }

    let mut track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if track_manager.remove_track(track_id) {
        Ok(format!("Track {} deleted", track_id))
    } else {
        Err(format!(
            "Cannot delete track {} (either not found or is master track)",
            track_id
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
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Stop playback if running
    let _ = graph.stop();

    // Get all track IDs except master
    let track_ids_to_remove: Vec<u64> = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        let all_tracks = track_manager.get_all_tracks();
        all_tracks
            .iter()
            .filter_map(|track_arc| {
                let track = track_arc.lock().expect("mutex poisoned");
                if track.id != 0 {
                    Some(track.id)
                } else {
                    None
                }
            })
            .collect()
    };

    // Collect all fx_chains from tracks being deleted
    let all_effect_ids: Vec<u64> = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        track_ids_to_remove.iter().flat_map(|track_id| {
            if let Some(track_arc) = track_manager.get_track(*track_id) {
                let track = track_arc.lock().expect("mutex poisoned");
                track.fx_chain.clone()
            } else {
                Vec::new()
            }
        }).collect()
    };

    // Delete all non-master tracks
    for track_id in &track_ids_to_remove {
        // Stop any playing notes on the per-track synth
        if let Ok(mut synth_manager) = graph.track_synth_manager.lock() {
            synth_manager.all_notes_off(*track_id);
            synth_manager.remove_synth(*track_id);
        }

        // Remove all MIDI clips belonging to this track
        graph.remove_midi_clips_for_track(*track_id);

        // Remove the track
        let mut track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        track_manager.remove_track(*track_id);
    }

    // Remove all VST3 effects that were on deleted tracks
    if !all_effect_ids.is_empty() {
        if let Ok(mut effect_manager) = graph.effect_manager.lock() {
            for effect_id in &all_effect_ids {
                effect_manager.remove_effect(*effect_id);
            }
            eprintln!("🧹 [API] Removed {} effects from deleted tracks", all_effect_ids.len());
        }
    }

    // Clear all audio clips from global storage
    let clips_mutex = clips()?;
    let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;
    clips_map.clear();

    // Reset master track to defaults (volume = 0dB, pan = 0, unmuted)
    {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        if let Some(master_arc) = track_manager.get_track(0) {
            let mut master = master_arc.lock().expect("mutex poisoned");
            master.volume_db = 0.0;
            master.pan = 0.0;
            master.mute = false;
            master.solo = false;
        }
    }

    eprintln!(
        "🧹 [API] Cleared {} tracks (master track preserved)",
        track_ids_to_remove.len()
    );
    Ok(format!("Cleared {} tracks", track_ids_to_remove.len()))
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
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Cannot duplicate master track
    if track_id == 0 {
        return Err("Cannot duplicate master track".to_string());
    }

    // First, collect the data we need from the source track
    let (track_type, name, volume_db, pan, mute, audio_clips, midi_clips, fx_chain, sends) = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        let source_track_arc = track_manager
            .get_track(track_id)
            .ok_or(format!("Track {} not found", track_id))?;

        let source_track = source_track_arc.lock().map_err(|e| e.to_string())?;

        // Collect all data we need to copy
        (
            source_track.track_type,
            format!("{} Copy", source_track.name),
            source_track.volume_db,
            source_track.pan,
            source_track.mute,
            source_track.audio_clips.clone(),
            source_track.midi_clips.clone(),
            source_track.fx_chain.clone(),
            source_track.sends.clone(),
        )
        // source_track lock is released here
        // track_manager lock is released here
    };

    // Now create the new track and set its properties
    let new_track_id = {
        let mut track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        track_manager.create_track(track_type, name)
    };

    // Deep copy effects chain (create new effect instances)
    let new_fx_chain = {
        let mut effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;
        let mut new_chain = Vec::new();

        for effect_id in &fx_chain {
            if let Some(new_effect_id) = effect_manager.duplicate_effect(*effect_id) {
                new_chain.push(new_effect_id);
            } else {
                eprintln!("⚠️  [API] Failed to duplicate effect {}", effect_id);
            }
        }

        new_chain
    };

    // Copy properties to the new track
    {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        let new_track_arc = track_manager
            .get_track(new_track_id)
            .ok_or("Failed to get newly created track")?;

        let mut new_track = new_track_arc.lock().map_err(|e| e.to_string())?;

        // Copy mixer settings
        new_track.volume_db = volume_db;
        new_track.pan = pan;
        new_track.mute = mute;
        new_track.solo = false; // Don't copy solo state
        new_track.armed = false; // Don't copy armed state

        // Copy clips (Arc references, so this is cheap)
        new_track.audio_clips = audio_clips;
        new_track.midi_clips = midi_clips;

        // Use the deep-copied effects chain
        new_track.fx_chain = new_fx_chain;

        // Copy sends
        new_track.sends = sends;
        // new_track lock is released here
        // track_manager lock is released here
    };

    // Copy instrument assignment if exists (for MIDI tracks)
    {
        let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
        if synth_manager.has_synth(track_id) {
            synth_manager.copy_synth(track_id, new_track_id);
        }
    };

    eprintln!(
        "📋 [API] Duplicated track {} → new track {} created",
        track_id, new_track_id
    );

    Ok(new_track_id)
}

/// Duplicate an audio clip on the same track at a new position
///
/// Creates a new timeline clip that references the same audio data
/// but at a different start time. This is efficient as no audio data is copied.
///
/// # Arguments
/// * `track_id` - Track containing the original clip
/// * `source_clip_id` - ID of the clip to duplicate
/// * `new_start_time` - Position (in seconds) for the duplicated clip
///
/// # Returns
/// New clip ID on success
pub fn duplicate_audio_clip(
    track_id: TrackId,
    source_clip_id: u64,
    new_start_time: f64,
) -> Result<u64, String> {
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Find the source clip and get its Arc<AudioClip>
    let (clip_arc, offset, duration) = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        let track_arc = track_manager
            .get_track(track_id)
            .ok_or(format!("Track {} not found", track_id))?;

        let track = track_arc.lock().map_err(|e| e.to_string())?;

        // Find the source clip
        let source_clip = track
            .audio_clips
            .iter()
            .find(|c| c.id == source_clip_id)
            .ok_or(format!("Clip {} not found on track {}", source_clip_id, track_id))?;

        // Clone the Arc (cheap - just increments reference count)
        (source_clip.clip.clone(), source_clip.offset, source_clip.duration)
    };

    // Add a new timeline clip with the same audio data at new position
    let new_clip_id = graph
        .add_clip_to_track(track_id, clip_arc.clone(), new_start_time)
        .ok_or("Failed to add duplicated clip to track")?;

    // Also add to global clips map so it can be saved to project
    {
        let clips_mutex = clips()?;
        let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;
        clips_map.insert(new_clip_id, clip_arc);
    }

    // Copy offset and duration settings to the new clip
    {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let mut track = track_arc.lock().map_err(|e| e.to_string())?;
            if let Some(new_clip) = track.audio_clips.iter_mut().find(|c| c.id == new_clip_id) {
                new_clip.offset = offset;
                new_clip.duration = duration;
            }
        }
    }

    eprintln!(
        "📋 [API] Duplicated clip {} → new clip {} at {:.3}s",
        source_clip_id, new_clip_id, new_start_time
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
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;

        // Find and update the clip
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.gain_db = gain_db.clamp(-70.0, 24.0);
                return Ok(format!("Clip {} gain set to {:.2} dB", clip_id, clip.gain_db));
            }
        }

        Err(format!("Clip {} not found on track {}", clip_id, track_id))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set the warp (time-stretch) settings of an audio clip
///
/// # Arguments
/// * `track_id` - Track containing the clip
/// * `clip_id` - ID of the clip to modify
/// * `warp_enabled` - Whether warp/tempo sync is enabled
/// * `stretch_factor` - Stretch factor (project_bpm / clip_bpm), 1.0 = no stretch
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
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;

        // Find and update the clip
        for clip in &mut track.audio_clips {
            if clip.id == clip_id {
                clip.warp_enabled = warp_enabled;
                clip.stretch_factor = stretch_factor.clamp(0.25, 4.0);
                clip.warp_mode = warp_mode;
                let mode_str = if warp_mode == 0 { "warp" } else { "repitch" };
                return Ok(format!(
                    "Clip {} warp: {}, stretch: {:.2}x, mode: {}",
                    clip_id, warp_enabled, clip.stretch_factor, mode_str
                ));
            }
        }

        Err(format!("Clip {} not found on track {}", clip_id, track_id))
    } else {
        Err(format!("Track {} not found", track_id))
    }
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
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let track_arc = track_manager
        .get_track(track_id)
        .ok_or(format!("Track {} not found", track_id))?;

    let mut track = track_arc.lock().map_err(|e| e.to_string())?;

    // Find and remove the clip
    let initial_len = track.audio_clips.len();
    track.audio_clips.retain(|c| c.id != clip_id);
    let removed = track.audio_clips.len() < initial_len;

    if removed {
        eprintln!("🗑️  [API] Removed audio clip {} from track {}", clip_id, track_id);
    }

    Ok(removed)
}
