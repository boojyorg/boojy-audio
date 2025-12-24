//! API module - Functions exposed to Flutter via FFI
//!
//! This module is organized into domain-focused submodules:
//! - `helpers` - Shared state and helper functions
//! - `init` - Engine initialization
//! - `transport` - Playback control (play, pause, stop, seek)
//! - `latency` - Buffer size and latency configuration
//! - `recording` - Audio recording and input
//! - `timing` - Tempo and metronome
//! - `midi_input` - MIDI device management and recording
//! - `midi_clips` - MIDI clip editing and virtual keyboard
//! - `tracks` - Track management
//! - `effects` - Effect chains
//! - `vst3` - VST3 plugins
//! - `project` - Save/load/export
//! - `synthesizer` - Per-track synth

// Submodules
pub mod effects;
pub mod helpers;
pub mod init;
pub mod latency;
pub mod midi_clips;
pub mod midi_input;
pub mod project;
pub mod recording;
pub mod synthesizer;
pub mod timing;
pub mod tracks;
pub mod transport;
pub mod vst3;

// Re-export all public functions from submodules
pub use effects::{
    add_effect_to_track, get_effect_info, get_track_effects, remove_effect_from_track,
    set_effect_parameter,
};
pub use helpers::{get_audio_clips, get_audio_graph, AUDIO_CLIPS, AUDIO_GRAPH};
pub use init::{init_audio_engine, init_audio_graph, play_sine_wave};
pub use latency::{
    get_actual_buffer_size, get_buffer_size_preset, get_clip_duration, get_latency_info,
    get_waveform_peaks, set_buffer_size,
};
pub use midi_clips::{
    add_midi_clip_to_track_api, add_midi_clip_to_track_api as add_midi_clip_to_track,
    add_midi_note_to_clip, clear_midi_clip, create_midi_clip, get_all_midi_clips_info,
    get_midi_clip_count, get_midi_clip_events, get_midi_clip_info, get_midi_clip_notes,
    quantize_midi_clip, remove_midi_clip, remove_midi_event, send_midi_note_off, send_midi_note_on,
};
pub use midi_input::{
    get_midi_input_devices, get_midi_recording_state, refresh_midi_devices,
    select_midi_input_device, set_synth_oscillator_type, set_synth_volume, start_midi_input,
    start_midi_recording, stop_midi_input, stop_midi_recording,
};
pub use project::{export_to_wav, load_project, save_project};
pub use recording::{
    get_audio_input_devices, get_audio_output_devices, get_count_in_bars, get_recorded_duration,
    get_recording_state, get_recording_waveform, get_sample_rate, set_audio_input_device,
    set_count_in_bars, start_audio_input, start_recording, stop_audio_input, stop_recording,
};
pub use synthesizer::{
    get_synth_parameters, send_track_midi_note_off, send_track_midi_note_on, set_synth_parameter,
    set_track_instrument,
};
pub use timing::{get_tempo, is_metronome_enabled, set_metronome_enabled, set_tempo};
pub use tracks::{
    create_track, get_all_track_ids, get_track_count, get_track_info, get_track_peak_levels,
    move_clip_to_track, set_track_armed, set_track_mute, set_track_name, set_track_pan,
    set_track_solo, set_track_volume,
};
pub use transport::{
    get_playhead_position, get_transport_state, transport_pause, transport_play, transport_seek,
    transport_stop,
};
pub use vst3::{
    add_vst3_effect_to_track, get_vst3_parameter_count, get_vst3_parameter_info,
    get_vst3_parameter_value, scan_vst3_plugins, scan_vst3_plugins_standard,
    set_vst3_parameter_value, vst3_attach_editor, vst3_close_editor, vst3_get_editor_size,
    vst3_has_editor, vst3_open_editor, vst3_send_midi_note,
};

// ============================================================================
// REMAINING FUNCTIONS (audio file loading and track utilities)
// ============================================================================

use crate::audio_file::load_audio_file;
use std::sync::Arc;

// Re-use helpers for global state access
use helpers::{get_audio_clips as clips, get_audio_graph as graph};

/// Load an audio file to a specific track and return a clip ID
pub fn load_audio_file_to_track_api(
    path: String,
    track_id: u64,
    start_time: f64,
) -> Result<u64, String> {
    let clip = load_audio_file(&path).map_err(|e| e.to_string())?;
    let clip_arc = Arc::new(clip);

    let clips_mutex = clips()?;
    let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;

    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let clip_id = graph
        .add_clip_to_track(track_id, clip_arc.clone(), start_time)
        .ok_or(format!("Failed to add clip to track {}", track_id))?;

    clips_map.insert(clip_id, clip_arc);

    Ok(clip_id)
}

/// Load an audio file and return a clip ID (legacy - adds to first available track)
pub fn load_audio_file_api(path: String) -> Result<u64, String> {
    let clip = load_audio_file(&path).map_err(|e| e.to_string())?;
    let clip_arc = Arc::new(clip);

    let clips_mutex = clips()?;
    let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;

    let graph_mutex = graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Find armed audio track first, then any audio track
    let target_track_id = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        let all_tracks = track_manager.get_all_tracks();

        let mut armed_track_id = None;
        let mut any_audio_track_id = None;

        for track_arc in all_tracks {
            let track = track_arc.lock().map_err(|e| e.to_string())?;
            if track.track_type == crate::track::TrackType::Audio {
                if any_audio_track_id.is_none() {
                    any_audio_track_id = Some(track.id);
                }
                if track.armed {
                    armed_track_id = Some(track.id);
                    break;
                }
            }
        }

        if let Some(id) = armed_track_id {
            id
        } else if let Some(id) = any_audio_track_id {
            id
        } else {
            drop(track_manager);
            let mut tm = graph.track_manager.lock().map_err(|e| e.to_string())?;
            tm.create_track(crate::track::TrackType::Audio, "Audio 1".to_string())
        }
    };

    let clip_id = graph
        .add_clip_to_track(target_track_id, clip_arc.clone(), 0.0)
        .ok_or(format!("Failed to add clip to track {}", target_track_id))?;

    clips_map.insert(clip_id, clip_arc);

    Ok(clip_id)
}

// Include remaining functions (track utilities like delete, clear, duplicate, set_clip_start_time)
include!("remaining.rs");
