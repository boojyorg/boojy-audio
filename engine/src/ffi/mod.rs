use crate::api;
/// Hand-written C-compatible FFI layer (raw `dart:ffi` on the Dart side).
/// This is the deliberate engine boundary — `flutter_rust_bridge` was considered
/// and dropped. See `.claude/rules/ffi.md`. Don't reintroduce FRB casually.
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;

mod clips;
mod devices;
mod effects;
mod export;
mod latency;
mod midi;
mod preview;
mod project;
mod recording;
mod sends;
mod synth;
mod tracks;
mod transport;

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
    if let Ok(val) = std::panic::catch_unwind(f) {
        val
    } else {
        eprintln!("[FFI] Caught panic at FFI boundary");
        default
    }
}

/// Borrow a C-string argument passed across the FFI boundary (C33).
///
/// Returns `None` when the pointer is null or the bytes are not valid UTF-8,
/// so callers map it onto their error return instead of hitting UB inside
/// `CStr::from_ptr`.
///
/// # Safety
/// If non-null, `ptr` must point to a valid NUL-terminated string that stays
/// alive for the duration of the call.
pub(crate) unsafe fn cstr_arg<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

/// Initialize audio engine - C-compatible wrapper
#[no_mangle]
pub extern "C" fn init_audio_engine_ffi() -> *mut c_char {
    // Install panic hook once — logs panics to stderr (visible in flutter run console)
    use std::sync::Once;
    static PANIC_HOOK: Once = Once::new();
    PANIC_HOOK.call_once(|| {
        std::panic::set_hook(Box::new(|info| {
            let location = info
                .location()
                .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
                .unwrap_or_default();
            let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
                (*s).to_string()
            } else if let Some(s) = info.payload().downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown".to_string()
            };
            eprintln!("💥 [RUST PANIC] {payload}");
            eprintln!("💥 [RUST PANIC] at {location}");
            eprintln!(
                "💥 [RUST PANIC] backtrace:\n{}",
                std::backtrace::Backtrace::force_capture()
            );
        }));
    });

    ffi_catch(std::ptr::null_mut(), || match api::init_audio_engine() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    })
}

/// Free a string allocated by Rust
#[no_mangle]
pub extern "C" fn free_rust_string(ptr: *mut c_char) {
    ffi_catch(
        (),
        AssertUnwindSafe(|| {
            if !ptr.is_null() {
                unsafe {
                    let _ = CString::from_raw(ptr);
                }
            }
        }),
    );
}

/// Initialize the audio graph
#[no_mangle]
pub extern "C" fn init_audio_graph_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || match api::init_audio_graph() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    })
}
