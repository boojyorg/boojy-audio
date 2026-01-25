//! Preview API - Functions for library audio preview
//!
//! Provides preview playback independent of the main timeline transport.

use crate::preview::PreviewPlayer;
use std::sync::{Arc, Mutex, OnceLock};

/// Global preview player instance
static PREVIEW_PLAYER: OnceLock<Arc<Mutex<PreviewPlayer>>> = OnceLock::new();

/// Get or create the preview player
pub fn get_preview_player() -> &'static Arc<Mutex<PreviewPlayer>> {
    PREVIEW_PLAYER.get_or_init(|| Arc::new(Mutex::new(PreviewPlayer::new())))
}

/// Load an audio file for preview
pub fn preview_load_audio(path: String) -> Result<(), String> {
    let player = get_preview_player();
    let mut guard = player.lock().map_err(|e| e.to_string())?;
    guard.load_file(&path)
}

/// Start preview playback
pub fn preview_play() -> Result<(), String> {
    let player = get_preview_player();
    let mut guard = player.lock().map_err(|e| e.to_string())?;
    guard.play();
    Ok(())
}

/// Stop preview playback (with fade out)
pub fn preview_stop() -> Result<(), String> {
    let player = get_preview_player();
    let mut guard = player.lock().map_err(|e| e.to_string())?;
    guard.stop();
    Ok(())
}

/// Seek to a position in seconds
pub fn preview_seek(position_seconds: f64) -> Result<(), String> {
    let player = get_preview_player();
    let mut guard = player.lock().map_err(|e| e.to_string())?;
    guard.seek(position_seconds);
    Ok(())
}

/// Get current playback position in seconds
pub fn preview_get_position() -> f64 {
    let player = get_preview_player();
    match player.lock() {
        Ok(guard) => guard.get_position(),
        Err(_) => 0.0,
    }
}

/// Get total duration in seconds
pub fn preview_get_duration() -> f64 {
    let player = get_preview_player();
    match player.lock() {
        Ok(guard) => guard.get_duration(),
        Err(_) => 0.0,
    }
}

/// Check if preview is currently playing
pub fn preview_is_playing() -> bool {
    let player = get_preview_player();
    match player.lock() {
        Ok(guard) => guard.is_playing(),
        Err(_) => false,
    }
}

/// Set looping mode
pub fn preview_set_looping(should_loop: bool) -> Result<(), String> {
    let player = get_preview_player();
    let mut guard = player.lock().map_err(|e| e.to_string())?;
    guard.set_looping(should_loop);
    Ok(())
}

/// Get looping mode
pub fn preview_is_looping() -> bool {
    let player = get_preview_player();
    match player.lock() {
        Ok(guard) => guard.is_looping(),
        Err(_) => false,
    }
}

/// Get waveform peaks for UI display
pub fn preview_get_waveform(resolution: i32) -> Vec<f32> {
    let player = get_preview_player();
    match player.lock() {
        Ok(guard) => guard.get_waveform_peaks(resolution.max(1) as usize),
        Err(_) => vec![0.0; resolution.max(1) as usize],
    }
}

/// Process a single sample frame (called from audio callback)
/// Returns stereo output (left, right)
pub fn preview_process_sample() -> (f32, f32) {
    let player = get_preview_player();
    match player.try_lock() {
        Ok(mut guard) => guard.process_sample(),
        Err(_) => (0.0, 0.0), // Skip frame if lock is held
    }
}
