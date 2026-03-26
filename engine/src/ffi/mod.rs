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

// ── Structured FFI error types ──────────────────────────────────────────
//
// New FFI functions should use `ffi_ok` / `ffi_err` to return JSON results:
//   {"ok": <data>}                              — success
//   {"error": {"code": "<code>", "msg": "..."}} — failure
//
// The Dart side uses `parseEngineResult()` to handle both old ("Error: ...")
// and new (JSON) formats, so migration can happen incrementally.

/// Error categories for FFI results.
/// Each maps to a string code the Dart side can match on.
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)] // Incrementally adopted — not all FFI functions use this yet
pub(crate) enum FfiErrorCode {
    /// Resource not found (track, clip, effect, device)
    NotFound,
    /// Invalid argument (out of range, wrong type)
    InvalidArg,
    /// Engine not initialized or in wrong state
    EngineState,
    /// Audio I/O or device error
    AudioDevice,
    /// File I/O or format error
    FileError,
    /// Internal/unexpected error
    Internal,
}

impl FfiErrorCode {
    fn as_str(self) -> &'static str {
        match self {
            Self::NotFound => "not_found",
            Self::InvalidArg => "invalid_arg",
            Self::EngineState => "engine_state",
            Self::AudioDevice => "audio_device",
            Self::FileError => "file_error",
            Self::Internal => "internal",
        }
    }
}

/// Return a structured JSON success: `{"ok": "<data>"}`
#[allow(dead_code)] // Incrementally adopted
pub(crate) fn ffi_ok(data: &str) -> *mut c_char {
    let json = format!(r#"{{"ok":{}}}"#, serde_json::Value::String(data.to_string()));
    safe_cstring(json).into_raw()
}

/// Return a structured JSON error: `{"error": {"code": "<code>", "msg": "<message>"}}`
#[allow(dead_code)] // Incrementally adopted
pub(crate) fn ffi_err(code: FfiErrorCode, msg: &str) -> *mut c_char {
    let json = format!(
        r#"{{"error":{{"code":"{}","msg":{}}}}}"#,
        code.as_str(),
        serde_json::Value::String(msg.to_string()),
    );
    safe_cstring(json).into_raw()
}

/// Convenience: convert a `Result<String, String>` to a structured JSON FFI result.
/// Maps all errors to `FfiErrorCode::Internal` — use `ffi_ok`/`ffi_err` directly
/// when you need a specific error code.
#[allow(dead_code)] // Incrementally adopted
pub(crate) fn ffi_result(result: Result<String, String>) -> *mut c_char {
    match result {
        Ok(data) => ffi_ok(&data),
        Err(e) => ffi_err(FfiErrorCode::Internal, &e),
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
