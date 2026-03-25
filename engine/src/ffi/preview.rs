use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;
use super::{safe_cstring, ffi_catch};

// ============================================================================
// LIBRARY PREVIEW FFI
// ============================================================================

/// Load an audio file asynchronously (returns immediately, poll preview_is_loaded_ffi)
#[no_mangle]
pub extern "C" fn preview_load_audio_async_ffi(path: *const c_char) {
    ffi_catch((), AssertUnwindSafe(|| {
        if path.is_null() {
            return;
        }
        let c_str = unsafe { CStr::from_ptr(path) };
        if let Ok(path_str) = c_str.to_str() {
            api::preview_load_audio_async(path_str.to_string());
        }
    }));
}

/// Check if async load completed and clip is ready
#[no_mangle]
pub extern "C" fn preview_is_loaded_ffi() -> bool {
    ffi_catch(false, || {
        api::preview_is_loaded()
    })
}

/// Load an audio file for library preview (synchronous, blocks until complete)
#[no_mangle]
pub extern "C" fn preview_load_audio_ffi(path: *const c_char) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        if path.is_null() {
            return safe_cstring("Error: null path".to_string()).into_raw();
        }

        let c_str = unsafe { CStr::from_ptr(path) };
        let Ok(path_str) = c_str.to_str() else {
            return safe_cstring("Error: invalid UTF-8".to_string()).into_raw();
        };

        match api::preview_load_audio(path_str.to_string()) {
            Ok(()) => safe_cstring("OK".to_string()).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Check if full clip is ready to hot-swap after partial decode
#[no_mangle]
pub extern "C" fn preview_check_full_clip_ffi() -> bool {
    ffi_catch(false, || {
        api::preview_check_full_clip()
    })
}

/// Start preview playback
#[no_mangle]
pub extern "C" fn preview_play_ffi() {
    ffi_catch((), || {
        let _ = api::preview_play();
    });
}

/// Stop preview playback (with fade out)
#[no_mangle]
pub extern "C" fn preview_stop_ffi() {
    ffi_catch((), || {
        let _ = api::preview_stop();
    });
}

/// Seek to position in seconds
#[no_mangle]
pub extern "C" fn preview_seek_ffi(position_seconds: f64) {
    ffi_catch((), || {
        let _ = api::preview_seek(position_seconds);
    });
}

/// Get current playback position in seconds
#[no_mangle]
pub extern "C" fn preview_get_position_ffi() -> f64 {
    ffi_catch(0.0, || {
        api::preview_get_position()
    })
}

/// Get total duration in seconds
#[no_mangle]
pub extern "C" fn preview_get_duration_ffi() -> f64 {
    ffi_catch(0.0, || {
        api::preview_get_duration()
    })
}

/// Check if preview is currently playing
#[no_mangle]
pub extern "C" fn preview_is_playing_ffi() -> bool {
    ffi_catch(false, || {
        api::preview_is_playing()
    })
}

/// Set looping mode
#[no_mangle]
pub extern "C" fn preview_set_looping_ffi(should_loop: bool) {
    ffi_catch((), || {
        let _ = api::preview_set_looping(should_loop);
    });
}

/// Get looping mode
#[no_mangle]
pub extern "C" fn preview_is_looping_ffi() -> bool {
    ffi_catch(false, || {
        api::preview_is_looping()
    })
}

/// Get waveform peaks for UI display
/// Returns JSON array of floats (e.g., "[0.5, 0.8, 0.3, ...]")
#[no_mangle]
pub extern "C" fn preview_get_waveform_ffi(resolution: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        let peaks = api::preview_get_waveform(resolution);
        let json = format!(
            "[{}]",
            peaks
                .iter()
                .map(|p| format!("{p:.4}"))
                .collect::<Vec<_>>()
                .join(",")
        );
        safe_cstring(json).into_raw()
    })
}
