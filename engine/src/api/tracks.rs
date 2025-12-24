//! Track management API functions
//!
//! Functions for creating and managing tracks, including volume, pan, mute, solo,
//! armed state, and clip management.

use super::helpers::get_audio_graph;
use crate::track::{ClipId, TrackId, TrackType};

// ============================================================================
// TRACK CREATION
// ============================================================================

/// Create a new track
///
/// # Arguments
/// * `track_type_str` - Track type: "audio", "midi", "return", "group", "master"
/// * `name` - Display name for the track
///
/// # Returns
/// Track ID on success
pub fn create_track(track_type_str: &str, name: String) -> Result<TrackId, String> {
    let track_type = match track_type_str.to_lowercase().as_str() {
        "audio" => TrackType::Audio,
        "midi" => TrackType::Midi,
        "return" => TrackType::Return,
        "group" => TrackType::Group,
        "master" => return Err("Cannot create additional master tracks".to_string()),
        _ => return Err(format!("Unknown track type: {}", track_type_str)),
    };

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let track_id = {
        let mut track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        track_manager.create_track(track_type, name)
    };

    // Auto-create synthesizer for MIDI tracks so they can produce sound immediately
    if track_type == TrackType::Midi {
        let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
        synth_manager.create_synth(track_id);
        println!("✅ Auto-created synth for MIDI track {}", track_id);
    }

    Ok(track_id)
}

// ============================================================================
// TRACK PROPERTIES
// ============================================================================

/// Set track volume
///
/// # Arguments
/// * `track_id` - Track ID
/// * `volume_db` - Volume in dB (-96.0 to +6.0)
pub fn set_track_volume(track_id: TrackId, volume_db: f32) -> Result<String, String> {
    eprintln!("🎚️ set_track_volume called: track={}, volume_db={:.2}", track_id, volume_db);
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.volume_db = volume_db.clamp(-96.0, 6.0);
        eprintln!("🎚️ Track {} volume now = {:.2} dB, gain = {:.4}", track_id, track.volume_db, track.get_gain());
        Ok(format!("Track {} volume set to {:.2} dB", track_id, track.volume_db))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set track pan
///
/// # Arguments
/// * `track_id` - Track ID
/// * `pan` - Pan position (-1.0 = left, 0.0 = center, +1.0 = right)
pub fn set_track_pan(track_id: TrackId, pan: f32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.pan = pan.clamp(-1.0, 1.0);
        Ok(format!("Track {} pan set to {:.2}", track_id, track.pan))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set track mute state
pub fn set_track_mute(track_id: TrackId, mute: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.mute = mute;
        Ok(format!("Track {} mute: {}", track_id, mute))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set track armed state (for recording)
pub fn set_track_armed(track_id: TrackId, armed: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.armed = armed;
        Ok(format!("Track {} armed: {}", track_id, armed))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set track solo state
pub fn set_track_solo(track_id: TrackId, solo: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.solo = solo;
        Ok(format!("Track {} solo: {}", track_id, solo))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set track name
pub fn set_track_name(track_id: TrackId, name: String) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.name = name.clone();
        Ok(format!("Track {} renamed to '{}'", track_id, name))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

// ============================================================================
// TRACK QUERIES
// ============================================================================

/// Get total number of tracks (including master)
pub fn get_track_count() -> Result<usize, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    let count = track_manager.get_all_tracks().len();
    Ok(count)
}

/// Get all track IDs as comma-separated string
pub fn get_all_track_ids() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    let all_tracks = track_manager.get_all_tracks();
    let ids: Vec<String> = all_tracks.iter().filter_map(|track_arc| {
        track_arc.lock().ok().map(|track| track.id.to_string())
    }).collect();

    Ok(ids.join(","))
}

/// Get track info (for UI display)
///
/// Returns: "track_id,name,type,volume_db,pan,mute,solo,armed"
pub fn get_track_info(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let track = track_arc.lock().map_err(|e| e.to_string())?;
        let type_str = match track.track_type {
            TrackType::Audio => "Audio",
            TrackType::Midi => "MIDI",
            TrackType::Return => "Return",
            TrackType::Group => "Group",
            TrackType::Master => "Master",
        };
        Ok(format!(
            "{},{},{},{:.2},{:.2},{},{},{}",
            track.id,
            track.name,
            type_str,
            track.volume_db,
            track.pan,
            track.mute as u8,
            track.solo as u8,
            track.armed as u8
        ))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Get track peak levels (M5.5)
/// Returns CSV: "peak_left_db,peak_right_db"
pub fn get_track_peak_levels(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let track = track_arc.lock().map_err(|e| e.to_string())?;
        let (peak_left_db, peak_right_db) = track.get_peak_db();
        Ok(format!("{:.2},{:.2}", peak_left_db, peak_right_db))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

// ============================================================================
// CLIP MANAGEMENT
// ============================================================================

/// Move an existing clip to a track
///
/// This migrates clips from the legacy global timeline to track-based system
pub fn move_clip_to_track(track_id: TrackId, clip_id: ClipId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    // Find the clip in the global timeline
    let mut clips = graph.get_clips().lock().map_err(|e| e.to_string())?;
    let clip_idx = clips.iter().position(|c| c.id == clip_id)
        .ok_or(format!("Clip {} not found in global timeline", clip_id))?;

    // Remove from global timeline
    let timeline_clip = clips.remove(clip_idx);

    // Add to track
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;

        // Verify track type matches clip type
        if track.track_type != TrackType::Audio && track.track_type != TrackType::Group {
            clips.insert(clip_idx, timeline_clip); // Put it back
            return Err(format!("Track {} is not an audio track", track_id));
        }

        track.audio_clips.push(timeline_clip);
        Ok(format!("Moved clip {} to track {}", clip_id, track_id))
    } else {
        clips.insert(clip_idx, timeline_clip); // Put it back
        Err(format!("Track {} not found", track_id))
    }
}
