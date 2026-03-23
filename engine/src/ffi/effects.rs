use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M4: Effect Management FFI
// ============================================================================

/// Add an effect to a track's FX chain
/// Returns effect ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn add_effect_to_track_ffi(
    track_id: u64,
    effect_type: *const c_char,
) -> i64 {
    let effect_type_str = unsafe {
        match CStr::from_ptr(effect_type).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    match api::add_effect_to_track(track_id, effect_type_str) {
        Ok(effect_id) => effect_id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] add_effect_to_track error: {e}");
            -1
        }
    }
}

/// Remove an effect from a track
#[no_mangle]
pub extern "C" fn remove_effect_from_track_ffi(track_id: u64, effect_id: u64) -> *mut c_char {
    match api::remove_effect_from_track(track_id, effect_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get all effects on a track (CSV format)
#[no_mangle]
pub extern "C" fn get_track_effects_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_effects(track_id) {
        Ok(effects) => safe_cstring(effects).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get effect info (type and parameters)
#[no_mangle]
pub extern "C" fn get_effect_info_ffi(effect_id: u64) -> *mut c_char {
    match api::get_effect_info(effect_id) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set an effect parameter
#[no_mangle]
pub extern "C" fn set_effect_parameter_ffi(
    effect_id: u64,
    param_name: *const c_char,
    value: f32,
) -> *mut c_char {
    let param_name_str = unsafe {
        match CStr::from_ptr(param_name).to_str() {
            Ok(s) => s,
            Err(_) => return safe_cstring("Error: Invalid parameter name".to_string()).into_raw(),
        }
    };

    match api::set_effect_parameter(effect_id, param_name_str, value) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Set effect bypass state
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn set_effect_bypass_ffi(effect_id: u64, bypassed: i32) -> i32 {
    match api::set_effect_bypass(effect_id, bypassed != 0) {
        Ok(_) => 1,
        Err(e) => {
            eprintln!("❌ [FFI] set_effect_bypass error: {e}");
            0
        }
    }
}

/// Get effect bypass state
/// Returns 1 if bypassed, 0 if not bypassed, -1 on error
#[no_mangle]
pub extern "C" fn get_effect_bypass_ffi(effect_id: u64) -> i32 {
    match api::get_effect_bypass(effect_id) {
        Ok(bypassed) => i32::from(bypassed),
        Err(e) => {
            eprintln!("❌ [FFI] get_effect_bypass error: {e}");
            -1
        }
    }
}

/// Reorder effects in a track's FX chain
/// `effect_ids_csv`: comma-separated list of effect IDs in the desired order
#[no_mangle]
pub extern "C" fn reorder_track_effects_ffi(track_id: u64, effect_ids_csv: *const c_char) -> *mut c_char {
    let ids_str = unsafe {
        match CStr::from_ptr(effect_ids_csv).to_str() {
            Ok(s) => s,
            Err(_) => return safe_cstring("Error: Invalid effect IDs string".to_string()).into_raw(),
        }
    };

    match api::reorder_track_effects(track_id, ids_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}
