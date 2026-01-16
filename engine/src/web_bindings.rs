//! WebAssembly bindings for Boojy Audio engine
//!
//! This module provides wasm-bindgen exports that mirror the native FFI functions,
//! allowing the Rust audio engine to be called from JavaScript in browser environments.

use wasm_bindgen::prelude::*;
use crate::web_audio::{console_log, console_error};
use std::cell::RefCell;

// Thread-local storage for web audio backend (WASM is single-threaded)
thread_local! {
    static WEB_AUDIO_CONTEXT: RefCell<Option<web_sys::AudioContext>> = RefCell::new(None);
    static WEB_AUDIO_GAIN: RefCell<Option<web_sys::GainNode>> = RefCell::new(None);
    static IS_PLAYING: RefCell<bool> = RefCell::new(false);
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the audio engine for web
/// Must be called from a user gesture (click/keypress) due to browser autoplay policies
#[wasm_bindgen]
pub fn init_audio_graph() -> Result<String, JsValue> {
    use web_sys::{AudioContext, AudioContextOptions};

    console_log("Initializing Boojy Audio Web Engine...");

    // Create AudioContext with desired sample rate
    let mut options = AudioContextOptions::new();
    options.sample_rate(48000.0);

    let context = AudioContext::new_with_context_options(&options)?;
    let sample_rate = context.sample_rate();

    // Create master gain node
    let gain_node = context.create_gain()?;
    gain_node.gain().set_value(1.0);
    gain_node.connect_with_audio_node(&context.destination())?;

    // Store in thread-local
    WEB_AUDIO_CONTEXT.with(|ctx| {
        *ctx.borrow_mut() = Some(context);
    });
    WEB_AUDIO_GAIN.with(|gain| {
        *gain.borrow_mut() = Some(gain_node);
    });

    let msg = format!("Audio engine initialized (Web Audio API, {}Hz)", sample_rate);
    console_log(&msg);
    Ok(msg)
}

/// Resume audio context after user interaction
#[wasm_bindgen]
pub async fn resume_audio_context() -> Result<(), JsValue> {
    use web_sys::AudioContextState;

    WEB_AUDIO_CONTEXT.with(|ctx| {
        if let Some(ref context) = *ctx.borrow() {
            if context.state() == AudioContextState::Suspended {
                let _ = context.resume();
                console_log("Audio context resumed");
            }
        }
    });
    Ok(())
}

// ============================================================================
// Transport Controls
// ============================================================================

/// Start playback
#[wasm_bindgen]
pub fn transport_play() -> Result<String, JsValue> {
    console_log("Transport: Play");
    IS_PLAYING.with(|p| *p.borrow_mut() = true);
    // TODO: Integrate with AudioGraph for actual playback
    Ok("Playing".to_string())
}

/// Pause playback
#[wasm_bindgen]
pub fn transport_pause() -> Result<String, JsValue> {
    console_log("Transport: Pause");
    IS_PLAYING.with(|p| *p.borrow_mut() = false);
    Ok("Paused".to_string())
}

/// Stop playback
#[wasm_bindgen]
pub fn transport_stop() -> Result<String, JsValue> {
    console_log("Transport: Stop");
    IS_PLAYING.with(|p| *p.borrow_mut() = false);
    Ok("Stopped".to_string())
}

/// Seek to position in seconds
#[wasm_bindgen]
pub fn transport_seek(position_seconds: f64) -> Result<String, JsValue> {
    console_log(&format!("Transport: Seek to {}s", position_seconds));
    // TODO: Integrate with AudioGraph
    Ok(format!("Seeked to {}s", position_seconds))
}

/// Get current playhead position in seconds
#[wasm_bindgen]
pub fn get_playhead_position() -> f64 {
    // TODO: Get actual position from AudioGraph
    WEB_AUDIO_CONTEXT.with(|ctx| {
        if let Some(ref context) = *ctx.borrow() {
            return context.current_time();
        }
        0.0
    })
}

/// Get transport state (0=Stopped, 1=Playing, 2=Paused)
#[wasm_bindgen]
pub fn get_transport_state() -> i32 {
    IS_PLAYING.with(|p| {
        if *p.borrow() { 1 } else { 0 }
    })
}

// ============================================================================
// Audio File Loading
// ============================================================================

/// Load audio data from a byte array (for files uploaded via browser)
/// Returns clip ID or -1 on error
#[wasm_bindgen]
pub fn load_audio_data(data: &[u8], name: &str) -> i64 {
    console_log(&format!("Loading audio data: {} ({} bytes)", name, data.len()));

    // TODO: Decode audio using symphonia and add to AudioGraph
    // For now, return a placeholder ID
    console_log(&format!("Audio loaded: {}", name));
    1 // Placeholder clip ID
}

/// Load audio data to a specific track
/// Returns clip ID or -1 on error
#[wasm_bindgen]
pub fn load_audio_data_to_track(data: &[u8], name: &str, track_id: u64, start_time: f64) -> i64 {
    console_log(&format!(
        "Loading audio to track {}: {} ({} bytes) at {}s",
        track_id, name, data.len(), start_time
    ));

    // TODO: Decode and add to specific track
    1 // Placeholder clip ID
}

// ============================================================================
// Track Management
// ============================================================================

/// Create a new track
/// Returns track ID or -1 on error
#[wasm_bindgen]
pub fn create_track(name: &str) -> i64 {
    console_log(&format!("Creating track: {}", name));
    // TODO: Create track in AudioGraph
    1 // Placeholder track ID
}

/// Delete a track
#[wasm_bindgen]
pub fn delete_track(track_id: u64) -> Result<String, JsValue> {
    console_log(&format!("Deleting track: {}", track_id));
    // TODO: Delete track from AudioGraph
    Ok("Track deleted".to_string())
}

/// Set track volume (0.0 to 1.0)
#[wasm_bindgen]
pub fn set_track_volume(track_id: u64, volume: f32) -> Result<(), JsValue> {
    console_log(&format!("Track {} volume: {}", track_id, volume));
    // TODO: Set volume in AudioGraph
    Ok(())
}

/// Set track pan (-1.0 left to 1.0 right)
#[wasm_bindgen]
pub fn set_track_pan(track_id: u64, pan: f32) -> Result<(), JsValue> {
    console_log(&format!("Track {} pan: {}", track_id, pan));
    // TODO: Set pan in AudioGraph
    Ok(())
}

/// Set track mute state
#[wasm_bindgen]
pub fn set_track_mute(track_id: u64, muted: bool) -> Result<(), JsValue> {
    console_log(&format!("Track {} muted: {}", track_id, muted));
    // TODO: Set mute in AudioGraph
    Ok(())
}

/// Set track solo state
#[wasm_bindgen]
pub fn set_track_solo(track_id: u64, solo: bool) -> Result<(), JsValue> {
    console_log(&format!("Track {} solo: {}", track_id, solo));
    // TODO: Set solo in AudioGraph
    Ok(())
}

// ============================================================================
// MIDI
// ============================================================================

/// Send MIDI note on event
#[wasm_bindgen]
pub fn send_midi_note_on(track_id: u64, note: u32, velocity: u32) {
    console_log(&format!("MIDI note on: track={}, note={}, vel={}", track_id, note, velocity));
    // TODO: Route to synth
}

/// Send MIDI note off event
#[wasm_bindgen]
pub fn send_midi_note_off(track_id: u64, note: u32) {
    console_log(&format!("MIDI note off: track={}, note={}", track_id, note));
    // TODO: Route to synth
}

/// Create a MIDI clip
/// Returns clip ID or -1 on error
#[wasm_bindgen]
pub fn create_midi_clip(track_id: u64, start_beat: f64, duration_beats: f64) -> i64 {
    console_log(&format!(
        "Creating MIDI clip: track={}, start={}, duration={}",
        track_id, start_beat, duration_beats
    ));
    // TODO: Create MIDI clip in AudioGraph
    1 // Placeholder clip ID
}

// ============================================================================
// Project
// ============================================================================

/// Save project to JSON string
#[wasm_bindgen]
pub fn save_project_to_json() -> Result<String, JsValue> {
    console_log("Saving project to JSON");
    // TODO: Serialize AudioGraph state
    Ok("{}".to_string()) // Placeholder empty project
}

/// Load project from JSON string
#[wasm_bindgen]
pub fn load_project_from_json(json: &str) -> Result<String, JsValue> {
    console_log(&format!("Loading project from JSON ({} bytes)", json.len()));
    // TODO: Deserialize and restore AudioGraph state
    Ok("Project loaded".to_string())
}

// ============================================================================
// Tempo & Time Signature
// ============================================================================

/// Set tempo in BPM
#[wasm_bindgen]
pub fn set_tempo(bpm: f32) -> Result<(), JsValue> {
    console_log(&format!("Setting tempo: {} BPM", bpm));
    // TODO: Set tempo in AudioGraph
    Ok(())
}

/// Get current tempo
#[wasm_bindgen]
pub fn get_tempo() -> f32 {
    // TODO: Get from AudioGraph
    120.0 // Default
}

// ============================================================================
// Export
// ============================================================================

/// Export project to WAV and return as byte array
#[wasm_bindgen]
pub fn export_to_wav() -> Result<Vec<u8>, JsValue> {
    console_log("Exporting to WAV");
    // TODO: Offline render and encode to WAV
    Ok(Vec::new()) // Placeholder
}

// ============================================================================
// Utility
// ============================================================================

/// Get engine version
#[wasm_bindgen]
pub fn get_engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Check if audio context is initialized
#[wasm_bindgen]
pub fn is_audio_initialized() -> bool {
    WEB_AUDIO_CONTEXT.with(|ctx| ctx.borrow().is_some())
}

/// Get sample rate
#[wasm_bindgen]
pub fn get_sample_rate() -> f32 {
    WEB_AUDIO_CONTEXT.with(|ctx| {
        if let Some(ref context) = *ctx.borrow() {
            return context.sample_rate();
        }
        48000.0 // Default
    })
}

/// Set master volume (0.0 to 1.0)
#[wasm_bindgen]
pub fn set_master_volume(volume: f32) -> Result<(), JsValue> {
    WEB_AUDIO_GAIN.with(|gain| {
        if let Some(ref gain_node) = *gain.borrow() {
            gain_node.gain().set_value(volume.clamp(0.0, 1.0));
        }
    });
    Ok(())
}
