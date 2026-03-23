use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M4: TRACK & MIXING FFI
// ============================================================================

/// Create a new track
///
/// # Arguments
/// * `track_type` - Track type: "audio", "midi", "return", "group"
/// * `name` - Display name for the track
///
/// # Returns
/// Track ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn create_track_ffi(
    track_type: *const c_char,
    name: *const c_char,
) -> i64 {
    let track_type_str = unsafe {
        match CStr::from_ptr(track_type).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };
    let name_str = unsafe {
        match CStr::from_ptr(name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    match api::create_track(track_type_str, name_str) {
        Ok(id) => id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] create_track error: {e}");
            -1
        }
    }
}

/// Set track volume
#[no_mangle]
pub extern "C" fn set_track_volume_ffi(track_id: u64, volume_db: f32) -> *mut c_char {
    match api::set_track_volume(track_id, volume_db) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track volume automation curve
/// `csv_data` format: "`time_seconds,db;time_seconds,db`;..." or empty to clear
#[no_mangle]
pub extern "C" fn set_track_volume_automation_ffi(track_id: u64, csv_data: *const c_char) -> *mut c_char {
    let csv = if csv_data.is_null() {
        String::new()
    } else {
        unsafe {
            match CStr::from_ptr(csv_data).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid UTF-8 in csv_data".to_string()).into_raw(),
            }
        }
    };

    match api::set_track_volume_automation(track_id, &csv) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track pan
#[no_mangle]
pub extern "C" fn set_track_pan_ffi(track_id: u64, pan: f32) -> *mut c_char {
    match api::set_track_pan(track_id, pan) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track mute
#[no_mangle]
pub extern "C" fn set_track_mute_ffi(track_id: u64, mute: bool) -> *mut c_char {
    match api::set_track_mute(track_id, mute) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track solo
#[no_mangle]
pub extern "C" fn set_track_solo_ffi(track_id: u64, solo: bool) -> *mut c_char {
    match api::set_track_solo(track_id, solo) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track armed (for recording)
#[no_mangle]
pub extern "C" fn set_track_armed_ffi(track_id: u64, armed: bool) -> *mut c_char {
    match api::set_track_armed(track_id, armed) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track input device and channel
#[no_mangle]
pub extern "C" fn set_track_input_ffi(track_id: u64, device_index: i32, channel: u32) -> *mut c_char {
    match api::set_track_input(track_id, device_index, channel) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get track input device and channel
/// Returns: "`device_index,channel`" (-1 if no input assigned)
#[no_mangle]
pub extern "C" fn get_track_input_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_input(track_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set track input monitoring
#[no_mangle]
pub extern "C" fn set_track_input_monitoring_ffi(track_id: u64, enabled: bool) -> *mut c_char {
    match api::set_track_input_monitoring(track_id, enabled) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get input channel peak level for metering
/// Returns peak amplitude as a float string (e.g., "0.42")
#[no_mangle]
pub extern "C" fn get_input_channel_level_ffi(channel: u32) -> *mut c_char {
    match api::get_input_channel_level(channel) {
        Ok(level) => safe_cstring(format!("{level:.4}")).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get number of input channels for the current device
#[no_mangle]
pub extern "C" fn get_input_channel_count_ffi() -> u32 {
    api::get_input_channel_count().unwrap_or(0)
}

/// Set track name
#[no_mangle]
pub extern "C" fn set_track_name_ffi(track_id: u64, name: *const c_char) -> *mut c_char {
    let name_str = unsafe {
        if name.is_null() {
            return safe_cstring("Error: name is null".to_string()).into_raw();
        }
        CStr::from_ptr(name).to_string_lossy().to_string()
    };
    match api::set_track_name(track_id, name_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get track count
#[no_mangle]
pub extern "C" fn get_track_count_ffi() -> usize {
    api::get_track_count().unwrap_or(0)
}

/// Get all track IDs (CSV format)
#[no_mangle]
pub extern "C" fn get_all_track_ids_ffi() -> *mut c_char {
    match api::get_all_track_ids() {
        Ok(ids) => safe_cstring(ids).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get track info (CSV format)
///
/// Returns: "`track_id,name,type,volume_db,pan,mute,solo`"
/// Caller must free the returned string
#[no_mangle]
pub extern "C" fn get_track_info_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_info(track_id) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get track peak levels (M5.5)
/// Returns: "`peak_left_db,peak_right_db`"
/// Caller must free the returned string
#[no_mangle]
pub extern "C" fn get_track_peak_levels_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_peak_levels(track_id) {
        Ok(levels) => safe_cstring(levels).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Delete a track
#[no_mangle]
pub extern "C" fn delete_track_ffi(track_id: u64) -> *mut c_char {
    match api::delete_track(track_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Clear all tracks except master - used for New Project / Close Project
#[no_mangle]
pub extern "C" fn clear_all_tracks_ffi() -> *mut c_char {
    match api::clear_all_tracks() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Duplicate a track
///
/// Returns the new track ID as a string on success, or "Error: <message>" on failure.
/// Returns "-1" if duplication fails.
#[no_mangle]
pub extern "C" fn duplicate_track_ffi(track_id: u64) -> i64 {
    match api::duplicate_track(track_id) {
        Ok(new_track_id) => new_track_id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to duplicate track {track_id}: {e}");
            -1
        }
    }
}
