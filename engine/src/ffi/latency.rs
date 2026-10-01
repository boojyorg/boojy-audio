use super::{ffi_catch, safe_cstring};
use crate::api;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;

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
    ffi_catch(0, || api::get_actual_buffer_size().unwrap_or(256))
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
    ffi_catch(
        (),
        AssertUnwindSafe(|| {
            if let Some((buffer_size, input_ms, output_ms, roundtrip_ms)) = api::get_latency_info()
            {
                unsafe {
                    if !out_buffer_size.is_null() {
                        *out_buffer_size = buffer_size;
                    }
                    if !out_input_latency_ms.is_null() {
                        *out_input_latency_ms = input_ms;
                    }
                    if !out_output_latency_ms.is_null() {
                        *out_output_latency_ms = output_ms;
                    }
                    if !out_roundtrip_ms.is_null() {
                        *out_roundtrip_ms = roundtrip_ms;
                    }
                }
            }
        }),
    );
}
