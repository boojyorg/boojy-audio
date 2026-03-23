use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M6: PER-TRACK SYNTHESIZER FFI
// ============================================================================

/// Set instrument for a track (returns instrument ID, or -1 on error)
#[no_mangle]
pub extern "C" fn set_track_instrument_ffi(
    track_id: u64,
    instrument_type: *const c_char,
) -> i64 {
    let instrument_type_str = unsafe {
        match CStr::from_ptr(instrument_type).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    match api::set_track_instrument(track_id, instrument_type_str) {
        Ok(id) => id,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to set instrument: {e}");
            -1
        }
    }
}

/// Set a synthesizer parameter for a track
#[no_mangle]
pub extern "C" fn set_synth_parameter_ffi(
    track_id: u64,
    param_name: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    let param_name_str = unsafe {
        match CStr::from_ptr(param_name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid parameter name".to_string()).into_raw(),
        }
    };

    let value_str = unsafe {
        match CStr::from_ptr(value).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid value".to_string()).into_raw(),
        }
    };

    match api::set_synth_parameter(track_id, param_name_str, value_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Get all synthesizer parameters for a track
#[no_mangle]
pub extern "C" fn get_synth_parameters_ffi(track_id: u64) -> *mut c_char {
    println!("🎹 [FFI] Get synth parameters for track {track_id}");

    match api::get_synth_parameters(track_id) {
        Ok(json) => safe_cstring(json).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Send MIDI note on event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_on_ffi(track_id: u64, note: u8, velocity: u8) -> *mut c_char {
    println!("🎹 [FFI] Track {track_id} Note On: note={note}, velocity={velocity}");

    match api::send_track_midi_note_on(track_id, note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Send MIDI note off event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_off_ffi(track_id: u64, note: u8, velocity: u8) -> *mut c_char {
    println!("🎹 [FFI] Track {track_id} Note Off: note={note}, velocity={velocity}");

    match api::send_track_midi_note_off(track_id, note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

// ============================================================================
// SAMPLER FFI
// ============================================================================

/// Create a sampler instrument for a track
/// Returns instrument ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn create_sampler_for_track_ffi(track_id: u64) -> i64 {
    println!("🎹 [FFI] Creating sampler for track {track_id}");

    match api::create_sampler_for_track(track_id) {
        Ok(id) => {
            println!("✅ [FFI] Sampler created with ID: {id}");
            id
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to create sampler: {e}");
            -1
        }
    }
}

/// Load a sample file into a sampler track
/// `root_note`: MIDI note that plays sample at original pitch (default 60 = C4)
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn load_sample_for_track_ffi(
    track_id: u64,
    path: *const c_char,
    root_note: u8,
) -> i32 {
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return 0,
        }
    };

    println!("🎹 [FFI] Loading sample for track {track_id}: {path_str} (root={root_note})");

    match api::load_sample_for_track(track_id, path_str, root_note) {
        Ok(msg) => {
            println!("✅ [FFI] {msg}");
            1
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to load sample: {e}");
            0
        }
    }
}

/// Set sampler parameter for a track
/// `param_name`: "`root_note`", "attack", "`attack_ms`", "release", "`release_ms`"
/// Returns success message or error
#[no_mangle]
pub extern "C" fn set_sampler_parameter_ffi(
    track_id: u64,
    param_name: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    let param_name_str = unsafe {
        match CStr::from_ptr(param_name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid parameter name".to_string()).into_raw(),
        }
    };

    let value_str = unsafe {
        match CStr::from_ptr(value).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid value".to_string()).into_raw(),
        }
    };

    println!("🎹 [FFI] Set sampler param for track {track_id}: {param_name_str}={value_str}");

    match api::set_sampler_parameter(track_id, param_name_str, value_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}

/// Check if a track has a sampler instrument
/// Returns 1 if sampler, 0 if not, -1 on error
#[no_mangle]
pub extern "C" fn is_sampler_track_ffi(track_id: u64) -> i32 {
    match api::is_sampler_track(track_id) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to check sampler track: {e}");
            -1
        }
    }
}

// ============================================================================
// SAMPLER INFO + WAVEFORM PEAKS FFI
// ============================================================================

/// Get sampler info for UI synchronization.
/// Returns 1 on success, 0 if track is not a sampler.
#[no_mangle]
pub extern "C" fn get_sampler_info_ffi(
    track_id: u64,
    out_duration_seconds: *mut f64,
    out_sample_rate: *mut f64,
    out_loop_enabled: *mut i32,
    out_loop_start_seconds: *mut f64,
    out_loop_end_seconds: *mut f64,
    out_root_note: *mut i32,
    out_attack_ms: *mut f64,
    out_release_ms: *mut f64,
    out_volume_db: *mut f64,
    out_transpose_semitones: *mut i32,
    out_fine_cents: *mut i32,
    out_reversed: *mut i32,
    out_original_bpm: *mut f64,
    out_warp_enabled: *mut i32,
    out_warp_mode: *mut i32,
    out_beats_per_bar: *mut i32,
    out_beat_unit: *mut i32,
) -> i32 {
    match api::get_sampler_info(track_id) {
        Ok(info) => {
            unsafe {
                if !out_duration_seconds.is_null() { *out_duration_seconds = info.duration_seconds; }
                if !out_sample_rate.is_null() { *out_sample_rate = info.sample_rate; }
                if !out_loop_enabled.is_null() { *out_loop_enabled = if info.loop_enabled { 1 } else { 0 }; }
                if !out_loop_start_seconds.is_null() { *out_loop_start_seconds = info.loop_start_seconds; }
                if !out_loop_end_seconds.is_null() { *out_loop_end_seconds = info.loop_end_seconds; }
                if !out_root_note.is_null() { *out_root_note = info.root_note; }
                if !out_attack_ms.is_null() { *out_attack_ms = info.attack_ms; }
                if !out_release_ms.is_null() { *out_release_ms = info.release_ms; }
                if !out_volume_db.is_null() { *out_volume_db = info.volume_db; }
                if !out_transpose_semitones.is_null() { *out_transpose_semitones = info.transpose_semitones; }
                if !out_fine_cents.is_null() { *out_fine_cents = info.fine_cents; }
                if !out_reversed.is_null() { *out_reversed = if info.reversed { 1 } else { 0 }; }
                if !out_original_bpm.is_null() { *out_original_bpm = info.original_bpm; }
                if !out_warp_enabled.is_null() { *out_warp_enabled = if info.warp_enabled { 1 } else { 0 }; }
                if !out_warp_mode.is_null() { *out_warp_mode = info.warp_mode; }
                if !out_beats_per_bar.is_null() { *out_beats_per_bar = info.beats_per_bar; }
                if !out_beat_unit.is_null() { *out_beat_unit = info.beat_unit; }
            }
            1
        }
        Err(e) => {
            eprintln!("❌ [FFI] get_sampler_info failed: {e}");
            0
        }
    }
}

/// Get waveform peaks from sampler's loaded sample.
/// Returns pointer to f32 array (caller must free with free_sampler_waveform_peaks_ffi).
#[no_mangle]
pub extern "C" fn get_sampler_waveform_peaks_ffi(
    track_id: u64,
    resolution: usize,
    out_length: *mut usize,
) -> *mut f32 {
    if let Ok(peaks) = api::get_sampler_waveform_peaks(track_id, resolution) {
        let len = peaks.len();
        let ptr = peaks.as_ptr().cast_mut();
        std::mem::forget(peaks);

        if !out_length.is_null() {
            unsafe { *out_length = len; }
        }

        ptr
    } else {
        if !out_length.is_null() {
            unsafe { *out_length = 0; }
        }
        std::ptr::null_mut()
    }
}

/// Free waveform peaks allocated by get_sampler_waveform_peaks_ffi.
#[no_mangle]
pub extern "C" fn free_sampler_waveform_peaks_ffi(ptr: *mut f32, length: usize) {
    if !ptr.is_null() {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, length, length);
        }
    }
}
