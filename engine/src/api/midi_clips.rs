//! MIDI clips API functions
//!
//! Functions for MIDI clip management, editing, and manipulation.
//! Includes virtual keyboard input and Piano Roll editing operations.

use super::helpers::get_audio_graph;
use crate::track::{TrackId, TrackType};
use std::sync::Arc;

// ============================================================================
// MIDI CLIP INFO
// ============================================================================

/// Get number of MIDI clips on timeline
pub fn get_midi_clip_count() -> Result<usize, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.midi_clip_count())
}

/// Get all MIDI clips info
/// Returns semicolon-separated list of clip info strings
/// Each clip: "clip_id,track_id,start_time,duration,note_count"
pub fn get_all_midi_clips_info() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut clips_info = Vec::new();

    // Get clips from global MIDI clips storage
    let midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    for timeline_clip in midi_clips.iter() {
        let track_id = timeline_clip.track_id.unwrap_or(u64::MAX) as i64;
        let track_id_str = if track_id == u64::MAX as i64 { -1 } else { track_id };
        let duration = timeline_clip.clip.duration_seconds();
        let note_count = timeline_clip.clip.events.len() / 2; // NoteOn/NoteOff pairs
        clips_info.push(format!("{},{},{},{},{}",
            timeline_clip.id, track_id_str, timeline_clip.start_time, duration, note_count));
    }
    drop(midi_clips);

    // Also get clips from tracks (they might have different IDs)
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    for track in track_manager.get_all_tracks() {
        if let Ok(track_lock) = track.lock() {
            for timeline_clip in &track_lock.midi_clips {
                // Check if we already have this clip
                let already_added = clips_info.iter().any(|info| {
                    info.split(',').next().unwrap_or("") == timeline_clip.id.to_string()
                });
                if !already_added {
                    let track_id = timeline_clip.track_id.unwrap_or(track_lock.id) as i64;
                    let duration = timeline_clip.clip.duration_seconds();
                    let note_count = timeline_clip.clip.events.len() / 2;
                    clips_info.push(format!("{},{},{},{},{}",
                        timeline_clip.id, track_id, timeline_clip.start_time, duration, note_count));
                }
            }
        }
    }

    Ok(clips_info.join(";"))
}

/// Get info about a MIDI clip
/// Returns: "clip_id,track_id,start_time,duration,note_count"
/// track_id is -1 if not assigned to a track
pub fn get_midi_clip_info(clip_id: u64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // First check global MIDI clips
    let midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    if let Some(timeline_clip) = midi_clips.iter().find(|c| c.id == clip_id) {
        let track_id = timeline_clip.track_id.unwrap_or(u64::MAX) as i64;
        let track_id_str = if track_id == u64::MAX as i64 { -1 } else { track_id };
        let duration = timeline_clip.clip.duration_seconds();
        let note_count = timeline_clip.clip.events.len() / 2; // NoteOn/NoteOff pairs
        return Ok(format!("{},{},{},{},{}",
            clip_id, track_id_str, timeline_clip.start_time, duration, note_count));
    }
    drop(midi_clips);

    // Also check track-specific MIDI clips
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    for track in track_manager.get_all_tracks() {
        if let Ok(track_lock) = track.lock() {
            for timeline_clip in &track_lock.midi_clips {
                if timeline_clip.id == clip_id {
                    let track_id = timeline_clip.track_id.unwrap_or(track_lock.id) as i64;
                    let duration = timeline_clip.clip.duration_seconds();
                    let note_count = timeline_clip.clip.events.len() / 2;
                    return Ok(format!("{},{},{},{},{}",
                        clip_id, track_id, timeline_clip.start_time, duration, note_count));
                }
            }
        }
    }

    Err(format!("MIDI clip {} not found", clip_id))
}

/// Get MIDI notes from a clip
/// Returns semicolon-separated list of notes: "note,velocity,start_time,duration"
pub fn get_midi_clip_notes(clip_id: u64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let sample_rate = crate::audio_graph::AudioGraph::get_sample_rate();

    // First check global MIDI clips
    let midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    if let Some(timeline_clip) = midi_clips.iter().find(|c| c.id == clip_id) {
        let notes = extract_notes_from_clip(&timeline_clip.clip, sample_rate);
        return Ok(notes);
    }
    drop(midi_clips);

    // Also check track-specific MIDI clips
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    for track in track_manager.get_all_tracks() {
        if let Ok(track_lock) = track.lock() {
            for timeline_clip in &track_lock.midi_clips {
                if timeline_clip.id == clip_id {
                    let notes = extract_notes_from_clip(&timeline_clip.clip, sample_rate);
                    return Ok(notes);
                }
            }
        }
    }

    Err(format!("MIDI clip {} not found", clip_id))
}

/// Helper function to extract notes from a MIDI clip
fn extract_notes_from_clip(clip: &crate::midi::MidiClip, sample_rate: u32) -> String {
    use crate::midi::MidiEventType;
    use std::collections::HashMap;

    let mut notes_info = Vec::new();
    let mut note_starts: HashMap<u8, (u64, u8)> = HashMap::new(); // note -> (start_samples, velocity)

    for event in &clip.events {
        match event.event_type {
            MidiEventType::NoteOn { note, velocity } => {
                note_starts.insert(note, (event.timestamp_samples, velocity));
            }
            MidiEventType::NoteOff { note, .. } => {
                if let Some((start_samples, velocity)) = note_starts.remove(&note) {
                    let start_time = start_samples as f64 / sample_rate as f64;
                    let end_time = event.timestamp_samples as f64 / sample_rate as f64;
                    let duration = end_time - start_time;

                    // Format: note,velocity,start_time,duration
                    notes_info.push(format!("{},{},{},{}", note, velocity, start_time, duration));
                }
            }
        }
    }

    notes_info.join(";")
}

// ============================================================================
// VIRTUAL KEYBOARD INPUT
// ============================================================================

/// Send MIDI note on event directly to synthesizer (for virtual piano)
/// Also records the event if MIDI recording is active
pub fn send_midi_note_on(note: u8, velocity: u8) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get current playhead position for timestamping
    let timestamp_samples = graph.get_playhead_samples();

    use crate::midi::{MidiEvent, MidiEventType};
    let event = MidiEvent {
        event_type: MidiEventType::NoteOn { note, velocity },
        timestamp_samples,
    };

    // Record to MIDI recorder if recording is active
    if let Ok(mut recorder) = graph.midi_recorder.lock() {
        if recorder.is_recording() {
            recorder.record_event(event);
        }
    }

    // Send to per-track synthesizer for live playback
    // Route to first armed MIDI track (or first MIDI track if none armed)
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let tracks = track_manager.get_all_tracks();

    let mut target_track_id: Option<TrackId> = None;
    let mut first_midi_track_id: Option<TrackId> = None;

    for track_arc in tracks {
        if let Ok(track) = track_arc.lock() {
            if track.track_type == TrackType::Midi {
                if first_midi_track_id.is_none() {
                    first_midi_track_id = Some(track.id);
                }
                if track.armed {
                    target_track_id = Some(track.id);
                    break;
                }
            }
        }
    }
    drop(track_manager);

    // Use armed track, or fallback to first MIDI track
    let target = target_track_id.or(first_midi_track_id);

    if let Some(track_id) = target {
        let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
        synth_manager.note_on(track_id, note, velocity);
    }

    Ok(format!("Note On: {} (velocity: {})", note, velocity))
}

/// Send MIDI note off event directly to synthesizer (for virtual piano)
/// Also records the event if MIDI recording is active
pub fn send_midi_note_off(note: u8, velocity: u8) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get current playhead position for timestamping
    let timestamp_samples = graph.get_playhead_samples();

    use crate::midi::{MidiEvent, MidiEventType};
    let event = MidiEvent {
        event_type: MidiEventType::NoteOff { note, velocity },
        timestamp_samples,
    };

    // Record to MIDI recorder if recording is active
    if let Ok(mut recorder) = graph.midi_recorder.lock() {
        if recorder.is_recording() {
            recorder.record_event(event);
        }
    }

    // Send to per-track synthesizer for live playback
    // Route to first armed MIDI track (or first MIDI track if none armed)
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let tracks = track_manager.get_all_tracks();

    let mut target_track_id: Option<TrackId> = None;
    let mut first_midi_track_id: Option<TrackId> = None;

    for track_arc in tracks {
        if let Ok(track) = track_arc.lock() {
            if track.track_type == TrackType::Midi {
                if first_midi_track_id.is_none() {
                    first_midi_track_id = Some(track.id);
                }
                if track.armed {
                    target_track_id = Some(track.id);
                    break;
                }
            }
        }
    }
    drop(track_manager);

    // Use armed track, or fallback to first MIDI track
    let target = target_track_id.or(first_midi_track_id);

    if let Some(track_id) = target {
        let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
        synth_manager.note_off(track_id, note);
    }

    Ok(format!("Note Off: {} (velocity: {})", note, velocity))
}

// ============================================================================
// MIDI CLIP MANIPULATION (Piano Roll)
// ============================================================================

/// Create a new empty MIDI clip
pub fn create_midi_clip() -> Result<u64, String> {
    use crate::midi::MidiClip;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Create empty MIDI clip
    let clip = MidiClip::new(crate::audio_file::TARGET_SAMPLE_RATE);
    let clip_arc = Arc::new(clip);

    // Add to timeline at position 0.0 (can be moved later)
    let clip_id = graph.add_midi_clip(clip_arc, 0.0);

    Ok(clip_id)
}

/// Add a MIDI note to a clip
///
/// # Arguments
/// * `clip_id` - The MIDI clip ID
/// * `note` - MIDI note number (0-127)
/// * `velocity` - Note velocity (0-127)
/// * `start_time` - Start time in seconds
/// * `duration` - Duration in seconds
pub fn add_midi_note_to_clip(
    clip_id: u64,
    note: u8,
    velocity: u8,
    start_time: f64,
    duration: f64,
) -> Result<String, String> {
    use crate::midi::MidiEvent;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip and modify it
    {
        let mut midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
        let timeline_clip = midi_clips
            .iter_mut()
            .find(|c| c.id == clip_id)
            .ok_or("MIDI clip not found")?;

        // Get mutable reference to the clip data
        // Note: Arc::make_mut may clone the data if there are multiple references
        let clip_data: &mut crate::midi::MidiClip = Arc::make_mut(&mut timeline_clip.clip);

        // Convert time to samples
        let start_samples = (start_time * crate::audio_file::TARGET_SAMPLE_RATE as f64) as u64;
        let duration_samples = (duration * crate::audio_file::TARGET_SAMPLE_RATE as f64) as u64;

        // Create note events
        let note_on = MidiEvent::note_on(note, velocity, start_samples);
        let note_off = MidiEvent::note_off(note, 64, start_samples + duration_samples);

        // Add events to clip
        clip_data.add_event(note_on);
        clip_data.add_event(note_off);
    }

    // Sync the updated clip to the track (needed because Arc::make_mut may have created a new copy)
    graph.sync_midi_clip_to_track(clip_id);

    Ok(format!("Added note {} at {:.3}s, duration {:.3}s", note, start_time, duration))
}

/// Get all MIDI events from a clip
/// Returns: Vec<(event_type, note, velocity, timestamp_seconds)>
/// event_type: 0 = NoteOn, 1 = NoteOff
pub fn get_midi_clip_events(clip_id: u64) -> Result<Vec<(i32, u8, u8, f64)>, String> {
    use crate::midi::MidiEventType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip
    let midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    let timeline_clip = midi_clips
        .iter()
        .find(|c| c.id == clip_id)
        .ok_or("MIDI clip not found")?;

    // Convert events to a format that can cross FFI
    let events: Vec<(i32, u8, u8, f64)> = timeline_clip
        .clip
        .events
        .iter()
        .map(|event| {
            let (event_type, note, velocity) = match event.event_type {
                MidiEventType::NoteOn { note, velocity } => (0, note, velocity),
                MidiEventType::NoteOff { note, velocity } => (1, note, velocity),
            };
            let timestamp_seconds = event.timestamp_samples as f64 / crate::audio_file::TARGET_SAMPLE_RATE as f64;
            (event_type, note, velocity, timestamp_seconds)
        })
        .collect();

    Ok(events)
}

/// Remove a MIDI event at the specified index
pub fn remove_midi_event(clip_id: u64, event_index: usize) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip
    let mut midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    let timeline_clip = midi_clips
        .iter_mut()
        .find(|c| c.id == clip_id)
        .ok_or("MIDI clip not found")?;

    // Get mutable reference to the clip data
    let clip_data: &mut crate::midi::MidiClip = Arc::make_mut(&mut timeline_clip.clip);

    // Remove the event
    clip_data.remove_event(event_index)
        .ok_or("Event index out of bounds")?;

    Ok(format!("Removed event at index {}", event_index))
}

/// Clear all MIDI events from a clip
pub fn clear_midi_clip(clip_id: u64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip and clear it
    {
        let mut midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
        let timeline_clip = midi_clips
            .iter_mut()
            .find(|c| c.id == clip_id)
            .ok_or("MIDI clip not found")?;

        // Get mutable reference to the clip data
        let clip_data: &mut crate::midi::MidiClip = Arc::make_mut(&mut timeline_clip.clip);

        // Clear all events
        clip_data.clear();
    }

    // Sync the updated clip to the track (needed because Arc::make_mut may have created a new copy)
    graph.sync_midi_clip_to_track(clip_id);

    Ok("Cleared all events".to_string())
}

/// Quantize a MIDI clip to the specified grid
///
/// # Arguments
/// * `clip_id` - The MIDI clip ID
/// * `grid_division` - Grid division (4 = quarter note, 8 = eighth note, 16 = sixteenth note, etc.)
pub fn quantize_midi_clip(clip_id: u64, grid_division: u32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip
    let mut midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
    let timeline_clip = midi_clips
        .iter_mut()
        .find(|c| c.id == clip_id)
        .ok_or("MIDI clip not found")?;

    // Calculate grid size in samples based on tempo (assume 120 BPM for now)
    let tempo = 120.0;
    let seconds_per_beat = 60.0 / tempo;
    let samples_per_beat = (seconds_per_beat * crate::audio_file::TARGET_SAMPLE_RATE as f64) as u64;
    let grid_samples = samples_per_beat / grid_division as u64;

    // Get mutable reference to the clip data
    let clip_data: &mut crate::midi::MidiClip = Arc::make_mut(&mut timeline_clip.clip);

    // Quantize the clip
    clip_data.quantize(grid_samples);

    Ok(format!("Quantized to 1/{} note grid", grid_division))
}

// ============================================================================
// MIDI CLIP TRACK MANAGEMENT
// ============================================================================

/// Add a MIDI clip to a track's timeline for playback
///
/// # Arguments
/// * `track_id` - The track to add the clip to
/// * `clip_id` - The MIDI clip ID (must exist)
/// * `start_time_seconds` - Start time on the timeline in seconds
pub fn add_midi_clip_to_track_api(track_id: u64, clip_id: u64, start_time_seconds: f64) -> Result<(), String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get the MIDI clip from global storage and update its track_id
    let clip_arc = {
        let mut midi_clips = graph.get_midi_clips().lock().map_err(|e| e.to_string())?;
        let timeline_clip = midi_clips
            .iter_mut()
            .find(|c| c.id == clip_id)
            .ok_or(format!("MIDI clip {} not found", clip_id))?;

        // Update the track_id in the global collection
        timeline_clip.track_id = Some(track_id);

        // Clone the clip Arc for adding to the track
        timeline_clip.clip.clone()
    };

    // Add the clip to the track's timeline (use the same clip_id for consistency)
    graph.add_midi_clip_to_track(track_id, clip_arc, start_time_seconds, clip_id)
        .ok_or(format!("Failed to add MIDI clip to track {}", track_id))?;

    Ok(())
}

/// Remove a MIDI clip from a track and global storage
///
/// # Arguments
/// * `track_id` - The track containing the clip
/// * `clip_id` - The MIDI clip ID to remove
pub fn remove_midi_clip(track_id: u64, clip_id: u64) -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Remove from track's timeline
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.midi_clips.retain(|c| c.id != clip_id);
    }
    drop(track_manager);

    // Remove from global collection
    let removed = graph.remove_clip(clip_id);
    Ok(removed)
}
