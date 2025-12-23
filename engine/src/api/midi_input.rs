//! MIDI input and recording API functions
//!
//! Functions for MIDI device management, input capture, and MIDI recording.

use super::helpers::get_audio_graph;
use crate::track::{TrackType, TrackId};
use std::sync::Arc;

// ============================================================================
// MIDI DEVICE MANAGEMENT
// ============================================================================

/// Get list of available MIDI input devices
pub fn get_midi_input_devices() -> Result<Vec<(String, String, bool)>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    let devices = midi_manager.get_devices();

    // Convert to tuple format: (id, name, is_default)
    let device_list: Vec<(String, String, bool)> = devices
        .into_iter()
        .map(|d| (d.id, d.name, d.is_default))
        .collect();

    Ok(device_list)
}

/// Refresh MIDI devices (rescan)
/// Returns success message - devices are fetched fresh each time get_midi_input_devices is called
pub fn refresh_midi_devices() -> Result<String, String> {
    // The device list is fetched fresh each time get_midi_input_devices is called,
    // so this just returns success to satisfy the API contract
    Ok("MIDI devices refreshed".to_string())
}

/// Select a MIDI input device by index
pub fn select_midi_input_device(device_index: i32) -> Result<String, String> {
    if device_index < 0 {
        return Err("Invalid device index".to_string());
    }

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    midi_manager.select_device(device_index as usize).map_err(|e| e.to_string())?;

    Ok(format!("Selected MIDI input device {}", device_index))
}

// ============================================================================
// MIDI INPUT CAPTURE
// ============================================================================

/// Start capturing MIDI input
pub fn start_midi_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;

    // Set up event callback to forward to MIDI recorder
    // Note: Live synth playback happens via per-track synths during audio callback
    let midi_recorder = graph.midi_recorder.clone();

    midi_manager.set_event_callback(move |event| {
        // Send to recorder if recording
        if let Ok(mut recorder) = midi_recorder.lock() {
            if recorder.is_recording() {
                recorder.record_event(event);
            }
        }
        // Note: Per-track synth is triggered from audio_graph audio callback
    });

    midi_manager.start_capture().map_err(|e| e.to_string())?;

    Ok("MIDI input started".to_string())
}

/// Stop capturing MIDI input
pub fn stop_midi_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    midi_manager.stop_capture().map_err(|e| e.to_string())?;

    Ok("MIDI input stopped".to_string())
}

// ============================================================================
// MIDI RECORDING
// ============================================================================

/// Start recording MIDI
pub fn start_midi_recording() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;
    midi_recorder.start_recording()?;

    Ok("MIDI recording started".to_string())
}

/// Stop recording MIDI and return the clip ID
/// Adds the clip to all armed MIDI tracks at the current playhead position
pub fn stop_midi_recording() -> Result<Option<u64>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;
    let clip_option = midi_recorder.stop_recording()?;

    if let Some(clip) = clip_option {
        let clip_arc = Arc::new(clip);

        // Get playhead position for clip placement
        let playhead_seconds = graph.get_playhead_position();

        // Find all armed MIDI tracks
        let armed_midi_track_ids: Vec<TrackId> = {
            let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
            track_manager.get_all_tracks()
                .iter()
                .filter_map(|track_arc| {
                    if let Ok(track) = track_arc.lock() {
                        if track.track_type == TrackType::Midi && track.armed {
                            Some(track.id)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect()
        };

        // If no MIDI tracks are armed, add clip to global storage
        // First add clip to global storage to get an ID
        let clip_id = graph.add_midi_clip(clip_arc.clone(), playhead_seconds);

        if armed_midi_track_ids.is_empty() {
            eprintln!("✅ [API] MIDI clip recorded with ID: {} (no armed tracks, added globally)", clip_id);
            return Ok(Some(clip_id));
        }

        // Add clip to each armed MIDI track using the same clip_id
        for track_id in armed_midi_track_ids {
            if let Some(_) = graph.add_midi_clip_to_track(track_id, clip_arc.clone(), playhead_seconds, clip_id) {
                eprintln!("✅ [API] MIDI clip {} added to armed track {}", clip_id, track_id);
            }
        }

        Ok(Some(clip_id))
    } else {
        Ok(None)
    }
}

/// Get current MIDI recording state (0=Idle, 1=Recording)
pub fn get_midi_recording_state() -> Result<i32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;

    use crate::midi_recorder::MidiRecordingState;
    let state = match midi_recorder.get_state() {
        MidiRecordingState::Idle => 0,
        MidiRecordingState::Recording => 1,
    };

    Ok(state)
}

// ============================================================================
// LEGACY SYNTH API (deprecated)
// ============================================================================

/// Set synthesizer oscillator type (LEGACY - use set_synth_parameter instead)
pub fn set_synth_oscillator_type(_osc_type: i32) -> Result<String, String> {
    // Legacy API - no-op, use set_synth_parameter for per-track synths
    Ok("Legacy API deprecated - use set_synth_parameter".to_string())
}

/// Set synthesizer master volume (LEGACY - use track volume instead)
pub fn set_synth_volume(_volume: f32) -> Result<String, String> {
    // Legacy API - no-op, use track volume for per-track synths
    Ok("Legacy API deprecated - use track volume".to_string())
}
