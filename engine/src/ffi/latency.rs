use super::{ffi_catch, safe_cstring};
use crate::api;
use std::os::raw::c_char;

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
