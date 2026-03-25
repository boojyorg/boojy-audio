use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;
use super::{safe_cstring, ffi_catch};

/// Load an audio file to a specific track and return clip ID
#[no_mangle]
pub extern "C" fn load_audio_file_to_track_ffi(path: *const c_char, track_id: u64, start_time: f64) -> i64 {
    ffi_catch(-1, AssertUnwindSafe(|| {
        if path.is_null() {
            return -1;
        }

        let c_str = unsafe { CStr::from_ptr(path) };
        let Ok(path_str) = c_str.to_str() else {
            return -1;
        };

        match api::load_audio_file_to_track_api(path_str.to_string(), track_id, start_time) {
            Ok(id) => id as i64,
            Err(e) => {
                eprintln!("[FFI] load_audio_file_to_track_ffi error: {e}");
                -1
            }
        }
    }))
}

/// Load an audio file and return clip ID (legacy - adds to first available track)
#[no_mangle]
pub extern "C" fn load_audio_file_ffi(path: *const c_char) -> i64 {
    ffi_catch(-1, AssertUnwindSafe(|| {
        if path.is_null() {
            return -1;
        }

        let c_str = unsafe { CStr::from_ptr(path) };
        let Ok(path_str) = c_str.to_str() else {
            return -1;
        };

        match api::load_audio_file_api(path_str.to_string()) {
            Ok(id) => id as i64,
            Err(_) => -1,
        }
    }))
}

/// Get clip duration in seconds
#[no_mangle]
pub extern "C" fn get_clip_duration_ffi(clip_id: u64) -> f64 {
    ffi_catch(0.0, || {
        api::get_clip_duration(clip_id).unwrap_or(0.0)
    })
}

/// Set clip start time (position) on timeline
/// Used for dragging clips to reposition them
#[no_mangle]
pub extern "C" fn set_clip_start_time_ffi(track_id: u64, clip_id: u64, start_time: f64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_clip_start_time(track_id, clip_id, start_time) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio clip offset (trim start)
/// Used for recording overlap trimming
#[no_mangle]
pub extern "C" fn set_clip_offset_ffi(track_id: u64, clip_id: u64, offset: f64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_clip_offset(track_id, clip_id, offset) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio clip duration
/// Used for recording overlap trimming
#[no_mangle]
pub extern "C" fn set_clip_duration_ffi(track_id: u64, clip_id: u64, duration: f64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_clip_duration(track_id, clip_id, duration) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio clip gain
/// Used to adjust per-clip volume in the Audio Editor
#[no_mangle]
pub extern "C" fn set_audio_clip_gain_ffi(track_id: u64, clip_id: u64, gain_db: f32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_audio_clip_gain(track_id, clip_id, gain_db) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio clip warp settings for tempo sync
/// Used to enable/disable time-stretching in the Audio Editor
/// `warp_mode`: 0 = warp (pitch preserved), 1 = repitch (pitch follows speed)
#[no_mangle]
pub extern "C" fn set_audio_clip_warp_ffi(
    track_id: u64,
    clip_id: u64,
    warp_enabled: bool,
    stretch_factor: f32,
    warp_mode: i32,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_audio_clip_warp(track_id, clip_id, warp_enabled, stretch_factor, warp_mode as u8) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set audio clip transpose (pitch shift)
/// semitones: -48 to +48
/// cents: -50 to +50
#[no_mangle]
pub extern "C" fn set_audio_clip_transpose_ffi(
    track_id: u64,
    clip_id: u64,
    semitones: i32,
    cents: i32,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_audio_clip_transpose(track_id, clip_id, semitones, cents) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get waveform peaks
/// Returns pointer to float array, and writes the length to `out_length`
/// Caller must free the returned array with `free_waveform_peaks_ffi`
#[no_mangle]
pub extern "C" fn get_waveform_peaks_ffi(
    clip_id: u64,
    resolution: usize,
    out_length: *mut usize,
) -> *mut f32 {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        if let Ok(peaks) = api::get_waveform_peaks(clip_id, resolution) {
            let len = peaks.len();
            // Convert to boxed slice to guarantee capacity == length,
            // avoiding UB when reconstructing in free_waveform_peaks_ffi
            let boxed = peaks.into_boxed_slice();
            let ptr = Box::into_raw(boxed).cast::<f32>();

            if !out_length.is_null() {
                unsafe {
                    *out_length = len;
                }
            }

            ptr
        } else {
            if !out_length.is_null() {
                unsafe {
                    *out_length = 0;
                }
            }
            std::ptr::null_mut()
        }
    }))
}

/// Free waveform peaks array allocated by get_waveform_peaks_ffi
#[no_mangle]
pub extern "C" fn free_waveform_peaks_ffi(ptr: *mut f32, length: usize) {
    ffi_catch((), AssertUnwindSafe(|| {
        if !ptr.is_null() {
            unsafe {
                // Reconstruct the Box<[f32]> that was created via into_boxed_slice()
                let slice = std::slice::from_raw_parts_mut(ptr, length);
                let _ = Box::from_raw(std::ptr::from_mut::<[f32]>(slice));
            }
        }
    }));
}

/// Move clip to track
#[no_mangle]
pub extern "C" fn move_clip_to_track_ffi(track_id: u64, clip_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::move_clip_to_track(track_id, clip_id) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Duplicate an audio clip on the same track at a new position
///
/// Returns the new clip ID on success, or -1 on failure.
#[no_mangle]
pub extern "C" fn duplicate_audio_clip_ffi(
    track_id: u64,
    source_clip_id: u64,
    new_start_time: f64,
) -> i64 {
    ffi_catch(-1, || {
        match api::duplicate_audio_clip(track_id, source_clip_id, new_start_time) {
            Ok(new_clip_id) => new_clip_id as i64,
            Err(e) => {
                eprintln!(
                    "[FFI] Failed to duplicate clip {source_clip_id} on track {track_id}: {e}"
                );
                -1
            }
        }
    })
}

/// Remove an audio clip from a track
///
/// Returns 1 if removed, 0 if not found, -1 on error.
#[no_mangle]
pub extern "C" fn remove_audio_clip_ffi(track_id: u64, clip_id: u64) -> i32 {
    ffi_catch(-1, || {
        match api::remove_audio_clip(track_id, clip_id) {
            Ok(true) => 1,
            Ok(false) => 0,
            Err(e) => {
                eprintln!(
                    "[FFI] Failed to remove clip {clip_id} from track {track_id}: {e}"
                );
                -1
            }
        }
    })
}

/// Re-add an existing audio clip to a track (for undo/redo support).
/// The clip data must still exist in the clips map.
/// Returns new clip ID, or -1 on error.
#[no_mangle]
pub extern "C" fn add_existing_clip_to_track_ffi(
    clip_id: u64,
    track_id: u64,
    start_time: f64,
    offset: f64,
    has_duration: i32,
    duration: f64,
) -> i64 {
    ffi_catch(-1, || {
        let dur = if has_duration != 0 {
            Some(duration)
        } else {
            None
        };

        match api::add_existing_clip_to_track(clip_id, track_id, start_time, offset, dur) {
            Ok(new_id) => new_id as i64,
            Err(e) => {
                eprintln!(
                    "[FFI] add_existing_clip_to_track_ffi error: {e}"
                );
                -1
            }
        }
    })
}
