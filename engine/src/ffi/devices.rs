use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;
use super::{safe_cstring, ffi_catch};

// ============================================================================
// Audio Device Management FFI
// ============================================================================

/// Get available audio input devices
/// Returns a newline-separated list of "`id|name|is_default`"
#[no_mangle]
pub extern "C" fn get_audio_input_devices_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_audio_input_devices() {
            Ok(devices) => {
                let formatted: Vec<String> = devices
                    .into_iter()
                    .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                    .collect();
                safe_cstring(formatted.join("\n")).into_raw()
            }
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get available audio output devices
/// Returns a newline-separated list of "`id|name|is_default`"
#[no_mangle]
pub extern "C" fn get_audio_output_devices_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_audio_output_devices() {
            Ok(devices) => {
                let formatted: Vec<String> = devices
                    .into_iter()
                    .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                    .collect();
                safe_cstring(formatted.join("\n")).into_raw()
            }
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio input device by index
#[no_mangle]
pub extern "C" fn set_audio_input_device_ffi(device_index: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_audio_input_device(device_index) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get current sample rate
#[no_mangle]
pub extern "C" fn get_sample_rate_ffi() -> u32 {
    ffi_catch(0, || {
        api::get_sample_rate()
    })
}

/// Set audio output device by name
/// Pass empty string to use system default
#[no_mangle]
pub extern "C" fn set_audio_output_device_ffi(device_name: *const c_char) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let name = unsafe {
            if device_name.is_null() {
                ""
            } else {
                match CStr::from_ptr(device_name).to_str() {
                    Ok(s) => s,
                    Err(_) => return safe_cstring("Error: Invalid UTF-8".to_string()).into_raw(),
                }
            }
        };

        match api::set_audio_output_device(name) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Get currently selected audio output device name
/// Returns empty string for system default
#[no_mangle]
pub extern "C" fn get_selected_audio_output_device_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_selected_audio_output_device() {
            Ok(name) => safe_cstring(name).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}
