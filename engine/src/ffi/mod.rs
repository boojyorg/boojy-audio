/// Simple C-compatible FFI layer for M0
/// This will be replaced with `flutter_rust_bridge` in M1
use std::ffi::CString;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;

mod transport;
mod latency;
mod clips;
mod recording;
mod midi;
mod tracks;
mod effects;
mod project;
mod export;
mod synth;
mod preview;
mod devices;

#[cfg(all(feature = "vst3", not(target_os = "ios")))]
mod vst3;

/// Safely create a `CString`, replacing null bytes with spaces
pub(crate) fn safe_cstring(s: String) -> CString {
    // Replace any null bytes to prevent panic
    let safe_string = s.replace('\0', " ");
    CString::new(safe_string).unwrap_or_else(|_| CString::new("Error creating string").unwrap())
}

/// Catch panics at the FFI boundary to prevent undefined behavior.
/// Returns the closure result on success, or `default` if a panic occurred.
pub(crate) fn ffi_catch<T>(default: T, f: impl FnOnce() -> T + std::panic::UnwindSafe) -> T {
    if let Ok(val) = std::panic::catch_unwind(f) { val } else {
        eprintln!("[FFI] Caught panic at FFI boundary");
        default
    }
}

/// Play a sine wave - C-compatible wrapper
/// Returns a success message as a C string
#[no_mangle]
pub extern "C" fn play_sine_wave_ffi(frequency: f32, duration_ms: u32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::play_sine_wave(frequency, duration_ms) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Initialize audio engine - C-compatible wrapper
#[no_mangle]
pub extern "C" fn init_audio_engine_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::init_audio_engine() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Free a string allocated by Rust
#[no_mangle]
pub extern "C" fn free_rust_string(ptr: *mut c_char) {
    ffi_catch((), AssertUnwindSafe(|| {
        if !ptr.is_null() {
            unsafe {
                let _ = CString::from_raw(ptr);
            }
        }
    }));
}

/// Initialize the audio graph
#[no_mangle]
pub extern "C" fn init_audio_graph_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::init_audio_graph() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}
