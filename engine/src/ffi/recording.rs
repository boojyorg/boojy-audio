use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M2: Recording & Input FFI
// ============================================================================

/// Start recording audio
#[no_mangle]
pub extern "C" fn start_recording_ffi() -> *mut c_char {
    match api::start_recording() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Stop recording and return clip ID (-1 if no recording)
#[no_mangle]
pub extern "C" fn stop_recording_ffi() -> i64 {
    match api::stop_recording() {
        Ok(Some(clip_id)) => clip_id as i64,
        Ok(None) => -1,  // No recording to stop
        Err(e) => {
            eprintln!("❌ [FFI] Stop recording failed: {e}");
            -1
        }
    }
}

/// Get recording state (0=Idle, 1=CountingIn, 2=Recording)
#[no_mangle]
pub extern "C" fn get_recording_state_ffi() -> i32 {
    api::get_recording_state().unwrap_or_else(|e| {
        eprintln!("❌ [FFI] Get recording state failed: {e}");
        0  // Return Idle state on error
    })
}

/// Get recorded duration in seconds
#[no_mangle]
pub extern "C" fn get_recorded_duration_ffi() -> f64 {
    api::get_recorded_duration().unwrap_or_else(|e| {
        eprintln!("❌ [FFI] Get recorded duration failed: {e}");
        0.0
    })
}

/// Get recording waveform preview as CSV of peak values
/// `num_peaks`: number of downsampled peaks to return
/// Returns CSV string of 0.0-1.0 peak values, or empty string on error
#[no_mangle]
pub extern "C" fn get_recording_waveform_ffi(num_peaks: u32) -> *mut c_char {
    match api::get_recording_waveform(num_peaks as usize) {
        Ok(csv) => safe_cstring(csv).into_raw(),
        Err(_) => safe_cstring(String::new()).into_raw(),
    }
}

/// Set count-in duration in bars
#[no_mangle]
pub extern "C" fn set_count_in_bars_ffi(bars: u32) -> *mut c_char {
    match api::set_count_in_bars(bars) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get count-in duration in bars
#[no_mangle]
pub extern "C" fn get_count_in_bars_ffi() -> u32 {
    api::get_count_in_bars().unwrap_or(2)
}

/// Get current count-in beat number (1-indexed, 0 when not counting in)
#[no_mangle]
pub extern "C" fn get_count_in_beat_ffi() -> u32 {
    api::get_count_in_beat().unwrap_or(0)
}

/// Get count-in progress (0.0-1.0)
#[no_mangle]
pub extern "C" fn get_count_in_progress_ffi() -> f32 {
    api::get_count_in_progress().unwrap_or(0.0)
}

// ── Punch In/Out ──────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn set_punch_in_enabled_ffi(enabled: i32) -> *mut c_char {
    match api::set_punch_in_enabled(enabled != 0) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

#[no_mangle]
pub extern "C" fn is_punch_in_enabled_ffi() -> i32 {
    i32::from(api::is_punch_in_enabled().unwrap_or(false))
}

#[no_mangle]
pub extern "C" fn set_punch_out_enabled_ffi(enabled: i32) -> *mut c_char {
    match api::set_punch_out_enabled(enabled != 0) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

#[no_mangle]
pub extern "C" fn is_punch_out_enabled_ffi() -> i32 {
    i32::from(api::is_punch_out_enabled().unwrap_or(false))
}

#[no_mangle]
pub extern "C" fn set_punch_region_ffi(in_seconds: f64, out_seconds: f64) -> *mut c_char {
    match api::set_punch_region(in_seconds, out_seconds) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

#[no_mangle]
pub extern "C" fn get_punch_in_seconds_ffi() -> f64 {
    api::get_punch_in_seconds().unwrap_or(0.0)
}

#[no_mangle]
pub extern "C" fn get_punch_out_seconds_ffi() -> f64 {
    api::get_punch_out_seconds().unwrap_or(0.0)
}

#[no_mangle]
pub extern "C" fn is_punch_complete_ffi() -> i32 {
    i32::from(api::is_punch_complete().unwrap_or(false))
}
