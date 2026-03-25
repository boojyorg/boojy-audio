use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;
use super::{safe_cstring, ffi_catch};

// ============================================================================
// Latency Control FFI
// ============================================================================

/// Set buffer size preset
/// 0=Lowest (64), 1=Low (128), 2=Balanced (256), 3=Safe (512), 4=HighStability (1024)
#[no_mangle]
pub extern "C" fn set_buffer_size_ffi(preset: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_buffer_size(preset) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get current buffer size preset (0-4)
#[no_mangle]
pub extern "C" fn get_buffer_size_preset_ffi() -> i32 {
    ffi_catch(-1, || {
        api::get_buffer_size_preset().unwrap_or(2) // Default to Balanced
    })
}

/// Get actual buffer size in samples
#[no_mangle]
pub extern "C" fn get_actual_buffer_size_ffi() -> u32 {
    ffi_catch(0, || {
        api::get_actual_buffer_size().unwrap_or(256)
    })
}

/// Get audio latency info
/// Returns: `buffer_size`, `input_latency_ms`, `output_latency_ms`, `total_roundtrip_ms`
/// Output is written to the provided pointers
#[no_mangle]
pub extern "C" fn get_latency_info_ffi(
    out_buffer_size: *mut u32,
    out_input_latency_ms: *mut f32,
    out_output_latency_ms: *mut f32,
    out_roundtrip_ms: *mut f32,
) {
    ffi_catch((), AssertUnwindSafe(|| {
        if let Some((buffer_size, input_ms, output_ms, roundtrip_ms)) = api::get_latency_info() {
            unsafe {
                if !out_buffer_size.is_null() { *out_buffer_size = buffer_size; }
                if !out_input_latency_ms.is_null() { *out_input_latency_ms = input_ms; }
                if !out_output_latency_ms.is_null() { *out_output_latency_ms = output_ms; }
                if !out_roundtrip_ms.is_null() { *out_roundtrip_ms = roundtrip_ms; }
            }
        }
    }));
}

// ============================================================================
// LATENCY TEST FFI
// ============================================================================

/// Start latency test to measure real round-trip audio latency
#[no_mangle]
pub extern "C" fn start_latency_test_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::start_latency_test() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Stop/cancel latency test
#[no_mangle]
pub extern "C" fn stop_latency_test_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::stop_latency_test() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get latency test status
/// Returns packed i64: (state << 32) | (`result_ms` as bits)
/// State: 0=Idle, 1=WaitingForSilence, 2=Playing, 3=Listening, 4=Analyzing, 5=Done, 6=Error
#[no_mangle]
pub extern "C" fn get_latency_test_status_ffi(
    out_state: *mut i32,
    out_result_ms: *mut f32,
) {
    ffi_catch((), AssertUnwindSafe(|| {
        match api::get_latency_test_status() {
            Ok((state, result_ms)) => {
                unsafe {
                    if !out_state.is_null() { *out_state = state; }
                    if !out_result_ms.is_null() { *out_result_ms = result_ms; }
                }
            }
            Err(_) => {
                unsafe {
                    if !out_state.is_null() { *out_state = 0; }
                    if !out_result_ms.is_null() { *out_result_ms = -1.0; }
                }
            }
        }
    }));
}

/// Get latency test error message (if state is Error)
/// Returns null if no error
#[no_mangle]
pub extern "C" fn get_latency_test_error_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_latency_test_error() {
            Ok(Some(msg)) => safe_cstring(msg).into_raw(),
            Ok(None) | Err(_) => std::ptr::null_mut(),
        }
    })
}
