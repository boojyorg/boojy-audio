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
pub mod preview;
pub mod project;
pub mod recording;
pub mod sends;
pub mod synthesizer;
pub mod timing;
pub mod tracks;
pub mod transport;

#[cfg(all(feature = "vst3", not(target_os = "ios")))]
pub mod vst3;

#[cfg(test)]
mod tests;

// Re-export all public functions from submodules
pub use effects::{
    add_effect_to_track, add_eq_band, get_effect_info, get_effect_peak_levels, get_track_effects,
    insert_eq_band, remove_effect_from_track, remove_eq_band, reorder_track_effects,
    set_effect_bypass, set_effect_parameter,
};
pub use helpers::{get_audio_clips, get_audio_graph, AUDIO_CLIPS, AUDIO_GRAPH};
pub use init::{init_audio_engine, init_audio_graph};
pub use latency::{get_audio_health, get_clip_duration, get_waveform_peaks, set_buffer_size};
pub use midi_clips::{
    add_midi_clip_to_track_api, add_midi_clip_to_track_api as add_midi_clip_to_track,
    add_midi_note_to_clip, clear_midi_clip, create_midi_clip, get_all_midi_clips_info,
    get_midi_clip_info, get_midi_clip_notes, quantize_midi_clip, remove_midi_clip,
    send_midi_note_off, send_midi_note_on,
};
pub use midi_input::{
    get_midi_input_devices, get_midi_recorder_live_events, refresh_midi_devices,
    select_midi_input_device, start_midi_input, start_midi_recording, stop_midi_recording,
};
pub use preview::{
    preview_get_duration, preview_get_position, preview_get_waveform, preview_is_fully_decoded,
    preview_is_loaded, preview_is_playing, preview_load_audio_async, preview_play,
    preview_process_sample, preview_seek, preview_set_looping, preview_stop,
};
pub use project::{
    export_mp3_with_options, export_stems, export_to_wav, export_wav_with_options,
    get_tracks_for_stems, is_ffmpeg_available, load_project, save_project, write_mp3_metadata,
};
pub use recording::{
    get_audio_input_devices, get_audio_input_health, get_audio_input_status,
    get_audio_output_devices, get_audio_stream_error, get_count_in_beat, get_count_in_progress,
    get_input_channel_level, get_last_recorded_clip_ids, get_live_recording_peaks,
    get_recorded_duration, get_recording_state, set_audio_input_choice, set_audio_output_device,
    set_count_in_bars, start_recording, stop_recording,
};
pub use sends::{
    add_send, add_shared_send, count_sends_to_return, create_return_with_effect, db_to_linear,
    find_return_by_effect_type, get_all_returns, get_track_sends, linear_to_db, remove_return,
    remove_send, set_master_timeline_visible, set_send_amount, DEFAULT_SEND_DB,
};
pub use synthesizer::{
    add_drum_pad, create_drum_kit_for_track, create_sampler_for_track, drum_next_free_note,
    get_drum_kit_info, get_drum_pad_waveform_peaks, get_sampler_info, get_sampler_sample_path,
    get_sampler_waveform_peaks, is_drum_kit_track, is_sampler_track, load_drum_pad_sample,
    load_sample_for_track, send_track_midi_note_off, send_track_midi_note_on,
    set_drum_pad_parameter, set_sampler_parameter, set_synth_bypass, set_synth_parameter,
    set_track_instrument, unload_sample_for_track,
};
pub use timing::{get_tempo, set_metronome_enabled, set_tempo, set_time_signature};
pub use tracks::{
    create_track, create_track_with_id, get_all_track_ids, get_track_count, get_track_info,
    get_track_peak_levels, set_track_armed, set_track_input, set_track_input_monitoring,
    set_track_mute, set_track_name, set_track_pan, set_track_solo, set_track_volume,
    set_track_volume_automation,
};
pub use transport::{
    get_playhead_position, transport_pause, transport_play, transport_seek, transport_stop,
};

#[cfg(all(feature = "vst3", not(target_os = "ios")))]
pub use vst3::{
    add_vst3_effect_to_track, get_vst3_parameter_count, get_vst3_parameter_info,
    get_vst3_parameter_value, get_vst3_presets, get_vst3_state, scan_vst3_plugins,
    scan_vst3_plugins_standard, set_vst3_editor_max_size, set_vst3_parameter_value,
    set_vst3_program, set_vst3_state, vst3_attach_editor, vst3_close_editor, vst3_get_editor_size,
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

    // Lock GRAPH before CLIPS — the canonical order used everywhere else
    // (project.rs save/load, recording.rs). Taking CLIPS first here was an
    // AB/BA lock-order inversion that could deadlock against a concurrent
    // stop-recording. (C44)
    let graph_mutex = graph()?;
    let graph = graph_mutex.lock();

    let clips_mutex = clips()?;
    let mut clips_map = clips_mutex.lock();

    let clip_id = graph
        .add_clip_to_track(track_id, clip_arc.clone(), start_time)
        .ok_or(format!("Failed to add clip to track {track_id}"))?;

    clips_map.insert(clip_id, clip_arc);

    Ok(clip_id)
}

// Include remaining functions (track utilities like delete, clear, duplicate, set_clip_start_time)
include!("remaining.rs");
