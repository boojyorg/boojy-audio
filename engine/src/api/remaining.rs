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
