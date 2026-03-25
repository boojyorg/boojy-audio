use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;
use crate::api;
use super::{safe_cstring, ffi_catch};

// ============================================================================
// M8: EXPORT FFI
// ============================================================================

/// Export to WAV file
#[no_mangle]
pub extern "C" fn export_to_wav_ffi(
    output_path: *const c_char,
    normalize: bool,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let output_path_str = unsafe {
            match CStr::from_ptr(output_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
            }
        };

        match api::export_to_wav(output_path_str, normalize) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Check if ffmpeg is available for MP3 encoding
/// Returns 1 if available, 0 if not
#[no_mangle]
pub extern "C" fn is_ffmpeg_available_ffi() -> i32 {
    ffi_catch(-1, || {
        i32::from(api::is_ffmpeg_available())
    })
}

/// Export audio with configurable options (generic, accepts JSON options)
/// `options_json`: JSON string of `ExportOptions`
/// Returns JSON string with `ExportResult` on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_audio_ffi(
    output_path: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let output_path_str = unsafe {
            match CStr::from_ptr(output_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
            }
        };

        let options_json_str = unsafe {
            match CStr::from_ptr(options_json).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid options JSON".to_string()).into_raw(),
            }
        };

        match api::export_audio(output_path_str, options_json_str) {
            Ok(result_json) => safe_cstring(result_json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Export WAV with configurable options
/// `bit_depth`: 16, 24, or 32
/// `sample_rate`: 44100 or 48000
/// Returns JSON string with `ExportResult` on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_wav_with_options_ffi(
    output_path: *const c_char,
    bit_depth: i32,
    sample_rate: u32,
    normalize: bool,
    dither: bool,
    mono: bool,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let output_path_str = unsafe {
            match CStr::from_ptr(output_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
            }
        };

        match api::export_wav_with_options(output_path_str, bit_depth, sample_rate, normalize, dither, mono) {
            Ok(result_json) => safe_cstring(result_json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Export MP3 with configurable options
/// bitrate: 128, 192, or 320
/// `sample_rate`: 44100 or 48000
/// Returns JSON string with `ExportResult` on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_mp3_with_options_ffi(
    output_path: *const c_char,
    bitrate: i32,
    sample_rate: u32,
    normalize: bool,
    mono: bool,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let output_path_str = unsafe {
            match CStr::from_ptr(output_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
            }
        };

        match api::export_mp3_with_options(output_path_str, bitrate, sample_rate, normalize, mono) {
            Ok(result_json) => safe_cstring(result_json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

/// Write ID3 metadata to an MP3 file
/// `metadata_json`: JSON string of `ExportMetadata`
/// Returns success message or "Error: <message>"
#[no_mangle]
pub extern "C" fn write_mp3_metadata_ffi(
    file_path: *const c_char,
    metadata_json: *const c_char,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let file_path_str = unsafe {
            match CStr::from_ptr(file_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid file path".to_string()).into_raw(),
            }
        };

        let metadata_json_str = unsafe {
            match CStr::from_ptr(metadata_json).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid metadata JSON".to_string()).into_raw(),
            }
        };

        match api::write_mp3_metadata(file_path_str, metadata_json_str) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

// ============================================================================
// STEM EXPORT FFI
// ============================================================================

/// Get tracks available for stem export
/// Returns JSON array of {id, name, type} objects
#[no_mangle]
pub extern "C" fn get_tracks_for_stems_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_tracks_for_stems() {
            Ok(json) => safe_cstring(json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Export stems (individual tracks) to a directory
/// `output_dir`: Directory to export stems to
/// `base_name`: Base filename for stems
/// `track_ids_json`: JSON array of track IDs, or empty/null for all tracks
/// `options_json`: JSON string of `ExportOptions`
/// Returns JSON string with `StemExportResult` on success
#[no_mangle]
pub extern "C" fn export_stems_ffi(
    output_dir: *const c_char,
    base_name: *const c_char,
    track_ids_json: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let output_dir_str = unsafe {
            match CStr::from_ptr(output_dir).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid output directory".to_string()).into_raw(),
            }
        };

        let base_name_str = unsafe {
            match CStr::from_ptr(base_name).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid base name".to_string()).into_raw(),
            }
        };

        let track_ids_str = unsafe {
            match CStr::from_ptr(track_ids_json).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid track IDs".to_string()).into_raw(),
            }
        };

        let options_str = unsafe {
            match CStr::from_ptr(options_json).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid options JSON".to_string()).into_raw(),
            }
        };

        match api::export_stems(output_dir_str, base_name_str, track_ids_str, options_str) {
            Ok(result_json) => safe_cstring(result_json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}

// ============================================================================
// EXPORT PROGRESS FFI
// ============================================================================

/// Get current export progress info
/// Returns JSON string with progress, `is_running`, `is_cancelled`, status, error
#[no_mangle]
pub extern "C" fn get_export_progress_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        use crate::export::ExportProgressInfo;
        let info = ExportProgressInfo::current();
        safe_cstring(info.to_json()).into_raw()
    })
}

/// Cancel the current export operation
#[no_mangle]
pub extern "C" fn cancel_export_ffi() {
    ffi_catch((), || {
        crate::export::export_progress().cancel();
    });
}

/// Reset export progress state (call before starting a new export)
#[no_mangle]
pub extern "C" fn reset_export_progress_ffi() {
    ffi_catch((), || {
        crate::export::export_progress().reset();
    });
}
