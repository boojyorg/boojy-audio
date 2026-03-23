use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// LIBRARY PREVIEW FFI
// ============================================================================

/// Load an audio file for library preview
#[no_mangle]
pub extern "C" fn preview_load_audio_ffi(path: *const c_char) -> *mut c_char {
    if path.is_null() {
        return safe_cstring("Error: null path".to_string()).into_raw();
    }

    let c_str = unsafe { CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return safe_cstring("Error: invalid UTF-8".to_string()).into_raw(),
    };

    match api::preview_load_audio(path_str.to_string()) {
        Ok(()) => safe_cstring("OK".to_string()).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Start preview playback
#[no_mangle]
pub extern "C" fn preview_play_ffi() {
    let _ = api::preview_play();
}

/// Stop preview playback (with fade out)
#[no_mangle]
pub extern "C" fn preview_stop_ffi() {
    let _ = api::preview_stop();
}

/// Seek to position in seconds
#[no_mangle]
pub extern "C" fn preview_seek_ffi(position_seconds: f64) {
    let _ = api::preview_seek(position_seconds);
}

/// Get current playback position in seconds
#[no_mangle]
pub extern "C" fn preview_get_position_ffi() -> f64 {
    api::preview_get_position()
}

/// Get total duration in seconds
#[no_mangle]
pub extern "C" fn preview_get_duration_ffi() -> f64 {
    api::preview_get_duration()
}

/// Check if preview is currently playing
#[no_mangle]
pub extern "C" fn preview_is_playing_ffi() -> bool {
    api::preview_is_playing()
}

/// Set looping mode
#[no_mangle]
pub extern "C" fn preview_set_looping_ffi(should_loop: bool) {
    let _ = api::preview_set_looping(should_loop);
}

/// Get looping mode
#[no_mangle]
pub extern "C" fn preview_is_looping_ffi() -> bool {
    api::preview_is_looping()
}

/// Get waveform peaks for UI display
/// Returns JSON array of floats (e.g., "[0.5, 0.8, 0.3, ...]")
#[no_mangle]
pub extern "C" fn preview_get_waveform_ffi(resolution: i32) -> *mut c_char {
    let peaks = api::preview_get_waveform(resolution);
    let json = format!(
        "[{}]",
        peaks
            .iter()
            .map(|p| format!("{p:.4}"))
            .collect::<Vec<_>>()
            .join(",")
    );
    safe_cstring(json).into_raw()
}
