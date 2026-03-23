use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

/// Start playback
#[no_mangle]
pub extern "C" fn transport_play_ffi() -> *mut c_char {
    match api::transport_play() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Pause playback
#[no_mangle]
pub extern "C" fn transport_pause_ffi() -> *mut c_char {
    match api::transport_pause() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Stop playback
#[no_mangle]
pub extern "C" fn transport_stop_ffi() -> *mut c_char {
    match api::transport_stop() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Seek to position in seconds
#[no_mangle]
pub extern "C" fn transport_seek_ffi(position_seconds: f64) -> *mut c_char {
    match api::transport_seek(position_seconds) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get playhead position in seconds
#[no_mangle]
pub extern "C" fn get_playhead_position_ffi() -> f64 {
    api::get_playhead_position().unwrap_or(0.0)
}

/// Get position when Play was pressed (in seconds)
#[no_mangle]
pub extern "C" fn get_play_start_position_ffi() -> f64 {
    api::get_play_start_position().unwrap_or(0.0)
}

/// Set position when Play was pressed (in seconds)
#[no_mangle]
pub extern "C" fn set_play_start_position_ffi(position_seconds: f64) -> *mut c_char {
    match api::set_play_start_position(position_seconds) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get position when recording started (after count-in, in seconds)
#[no_mangle]
pub extern "C" fn get_record_start_position_ffi() -> f64 {
    api::get_record_start_position().unwrap_or(0.0)
}

/// Set position when recording started (after count-in, in seconds)
#[no_mangle]
pub extern "C" fn set_record_start_position_ffi(position_seconds: f64) -> *mut c_char {
    match api::set_record_start_position(position_seconds) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get transport state (0=Stopped, 1=Playing, 2=Paused)
#[no_mangle]
pub extern "C" fn get_transport_state_ffi() -> i32 {
    api::get_transport_state().unwrap_or(0)
}

/// Set tempo in BPM
#[no_mangle]
pub extern "C" fn set_tempo_ffi(bpm: f64) -> *mut c_char {
    match api::set_tempo(bpm) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get tempo in BPM
#[no_mangle]
pub extern "C" fn get_tempo_ffi() -> f64 {
    api::get_tempo().unwrap_or(120.0)
}

/// Enable or disable metronome
#[no_mangle]
pub extern "C" fn set_metronome_enabled_ffi(enabled: i32) -> *mut c_char {
    match api::set_metronome_enabled(enabled != 0) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Check if metronome is enabled
#[no_mangle]
pub extern "C" fn is_metronome_enabled_ffi() -> i32 {
    i32::from(api::is_metronome_enabled().unwrap_or(true))
}

/// Set time signature (beats per bar)
#[no_mangle]
pub extern "C" fn set_time_signature_ffi(beats_per_bar: u32) -> *mut c_char {
    match api::set_time_signature(beats_per_bar) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get time signature (beats per bar)
#[no_mangle]
pub extern "C" fn get_time_signature_ffi() -> u32 {
    api::get_time_signature().unwrap_or(4)
}
