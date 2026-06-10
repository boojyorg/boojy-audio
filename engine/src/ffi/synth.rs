use super::{cstr_arg, ffi_catch, safe_cstring};
use crate::api;
use std::os::raw::c_char;
use std::panic::AssertUnwindSafe;

// ============================================================================
// M6: PER-TRACK SYNTHESIZER FFI
// ============================================================================

/// Set bypass state for a track's built-in instrument
#[no_mangle]
pub extern "C" fn set_synth_bypass_ffi(track_id: u64, bypassed: i32) -> *mut c_char {
    ffi_catch(
        safe_cstring("Error: panic".to_string()).into_raw(),
        AssertUnwindSafe(|| match api::set_synth_bypass(track_id, bypassed != 0) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }),
    )
}

/// Set instrument for a track (returns instrument ID, or -1 on error)
#[no_mangle]
pub extern "C" fn set_track_instrument_ffi(track_id: u64, instrument_type: *const c_char) -> i64 {
    ffi_catch(
        -1,
        AssertUnwindSafe(|| {
            let Some(instrument_type_str) = (unsafe { cstr_arg(instrument_type) }) else {
                return -1;
            };

            match api::set_track_instrument(track_id, instrument_type_str.to_string()) {
                Ok(id) => id,
                Err(e) => {
                    eprintln!("[FFI] Failed to set instrument: {e}");
                    -1
                }
            }
        }),
    )
}

/// Set a synthesizer parameter for a track
#[no_mangle]
pub extern "C" fn set_synth_parameter_ffi(
    track_id: u64,
    param_name: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let Some(param_name_str) = (unsafe { cstr_arg(param_name) }) else {
                return safe_cstring("Error: Invalid parameter name".to_string()).into_raw();
            };

            let Some(value_str) = (unsafe { cstr_arg(value) }) else {
                return safe_cstring("Error: Invalid value".to_string()).into_raw();
            };

            match api::set_synth_parameter(track_id, param_name_str.to_string(), value_str.to_string()) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}

/// Get all synthesizer parameters for a track
#[no_mangle]
pub extern "C" fn get_synth_parameters_ffi(track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        println!("[FFI] Get synth parameters for track {track_id}");

        match api::get_synth_parameters(track_id) {
            Ok(json) => safe_cstring(json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Send MIDI note on event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_on_ffi(
    track_id: u64,
    note: u8,
    velocity: u8,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        println!("[FFI] Track {track_id} Note On: note={note}, velocity={velocity}");

        match api::send_track_midi_note_on(track_id, note, velocity) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Send MIDI note off event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_off_ffi(
    track_id: u64,
    note: u8,
    velocity: u8,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        println!("[FFI] Track {track_id} Note Off: note={note}, velocity={velocity}");

        match api::send_track_midi_note_off(track_id, note, velocity) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

// ============================================================================
// SAMPLER FFI
// ============================================================================

/// Create a sampler instrument for a track
/// Returns instrument ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn create_sampler_for_track_ffi(track_id: u64) -> i64 {
    ffi_catch(-1, || {
        println!("[FFI] Creating sampler for track {track_id}");

        match api::create_sampler_for_track(track_id) {
            Ok(id) => {
                println!("[FFI] Sampler created with ID: {id}");
                id
            }
            Err(e) => {
                eprintln!("[FFI] Failed to create sampler: {e}");
                -1
            }
        }
    })
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
    ffi_catch(
        -1,
        AssertUnwindSafe(|| {
            let Some(path_str) = (unsafe { cstr_arg(path) }) else {
                return 0;
            };

            println!("[FFI] Loading sample for track {track_id}: {path_str} (root={root_note})");

            match api::load_sample_for_track(track_id, path_str.to_string(), root_note) {
                Ok(msg) => {
                    println!("[FFI] {msg}");
                    1
                }
                Err(e) => {
                    eprintln!("[FFI] Failed to load sample: {e}");
                    0
                }
            }
        }),
    )
}

/// Unload the sample from a sampler track (undo of a first sample load)
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn unload_sample_for_track_ffi(track_id: u64) -> i32 {
    ffi_catch(-1, || match api::unload_sample_for_track(track_id) {
        Ok(msg) => {
            println!("[FFI] {msg}");
            1
        }
        Err(e) => {
            eprintln!("[FFI] Failed to unload sample: {e}");
            0
        }
    })
}

/// Path of the sample currently loaded on a sampler track
/// Returns an empty string when the track has no sample (or isn't a sampler)
#[no_mangle]
pub extern "C" fn get_sampler_sample_path_ffi(track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_sampler_sample_path(track_id) {
            Ok(path) => safe_cstring(path).into_raw(),
            Err(e) => {
                eprintln!("[FFI] Failed to get sampler sample path: {e}");
                safe_cstring(String::new()).into_raw()
            }
        }
    })
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
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let Some(param_name_str) = (unsafe { cstr_arg(param_name) }) else {
                return safe_cstring("Error: Invalid parameter name".to_string()).into_raw();
            };

            let Some(value_str) = (unsafe { cstr_arg(value) }) else {
                return safe_cstring("Error: Invalid value".to_string()).into_raw();
            };

            println!("[FFI] Set sampler param for track {track_id}: {param_name_str}={value_str}");

            match api::set_sampler_parameter(track_id, param_name_str.to_string(), value_str.to_string()) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}

/// Check if a track has a sampler instrument
/// Returns 1 if sampler, 0 if not, -1 on error
#[no_mangle]
pub extern "C" fn is_sampler_track_ffi(track_id: u64) -> i32 {
    ffi_catch(-1, || match api::is_sampler_track(track_id) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(e) => {
            eprintln!("[FFI] Failed to check sampler track: {e}");
            -1
        }
    })
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
    ffi_catch(
        -1,
        AssertUnwindSafe(|| match api::get_sampler_info(track_id) {
            Ok(info) => {
                unsafe {
                    if !out_duration_seconds.is_null() {
                        *out_duration_seconds = info.duration_seconds;
                    }
                    if !out_sample_rate.is_null() {
                        *out_sample_rate = info.sample_rate;
                    }
                    if !out_loop_enabled.is_null() {
                        *out_loop_enabled = i32::from(info.loop_enabled);
                    }
                    if !out_loop_start_seconds.is_null() {
                        *out_loop_start_seconds = info.loop_start_seconds;
                    }
                    if !out_loop_end_seconds.is_null() {
                        *out_loop_end_seconds = info.loop_end_seconds;
                    }
                    if !out_root_note.is_null() {
                        *out_root_note = info.root_note;
                    }
                    if !out_attack_ms.is_null() {
                        *out_attack_ms = info.attack_ms;
                    }
                    if !out_release_ms.is_null() {
                        *out_release_ms = info.release_ms;
                    }
                    if !out_volume_db.is_null() {
                        *out_volume_db = info.volume_db;
                    }
                    if !out_transpose_semitones.is_null() {
                        *out_transpose_semitones = info.transpose_semitones;
                    }
                    if !out_fine_cents.is_null() {
                        *out_fine_cents = info.fine_cents;
                    }
                    if !out_reversed.is_null() {
                        *out_reversed = i32::from(info.reversed);
                    }
                    if !out_original_bpm.is_null() {
                        *out_original_bpm = info.original_bpm;
                    }
                    if !out_warp_enabled.is_null() {
                        *out_warp_enabled = i32::from(info.warp_enabled);
                    }
                    if !out_warp_mode.is_null() {
                        *out_warp_mode = info.warp_mode;
                    }
                    if !out_beats_per_bar.is_null() {
                        *out_beats_per_bar = info.beats_per_bar;
                    }
                    if !out_beat_unit.is_null() {
                        *out_beat_unit = info.beat_unit;
                    }
                }
                1
            }
            Err(e) => {
                eprintln!("[FFI] get_sampler_info failed: {e}");
                0
            }
        }),
    )
}

/// Get waveform peaks from sampler's loaded sample.
/// Returns pointer to f32 array (caller must free with free_sampler_waveform_peaks_ffi).
#[no_mangle]
pub extern "C" fn get_sampler_waveform_peaks_ffi(
    track_id: u64,
    resolution: usize,
    out_length: *mut usize,
) -> *mut f32 {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            if let Ok(peaks) = api::get_sampler_waveform_peaks(track_id, resolution) {
                let len = peaks.len();
                // Convert to boxed slice to guarantee capacity == length,
                // avoiding UB when reconstructing in free_sampler_waveform_peaks_ffi
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
        }),
    )
}

/// Free waveform peaks allocated by get_sampler_waveform_peaks_ffi
#[no_mangle]
pub extern "C" fn free_sampler_waveform_peaks_ffi(ptr: *mut f32, length: usize) {
    ffi_catch(
        (),
        AssertUnwindSafe(|| {
            if !ptr.is_null() {
                unsafe {
                    // Reconstruct the Box<[f32]> that was created via into_boxed_slice()
                    let slice = std::slice::from_raw_parts_mut(ptr, length);
                    let _ = Box::from_raw(std::ptr::from_mut::<[f32]>(slice));
                }
            }
        }),
    );
}

// ============================================================================
// DRUM KIT FFI
// ============================================================================

/// Create a drum-kit instrument for a track. Returns the instrument id, or -1 on error.
#[no_mangle]
pub extern "C" fn create_drum_kit_for_track_ffi(track_id: u64) -> i64 {
    ffi_catch(-1, || match api::create_drum_kit_for_track(track_id) {
        Ok(id) => id,
        Err(e) => {
            eprintln!("[FFI] Failed to create drum kit: {e}");
            -1
        }
    })
}

/// Add an empty pad pinned to `pinned_note`. Returns the new pad index, or -1 on error.
#[no_mangle]
pub extern "C" fn add_drum_pad_ffi(track_id: u64, pinned_note: u8) -> i64 {
    ffi_catch(-1, || match api::add_drum_pad(track_id, pinned_note) {
        Ok(idx) => idx,
        Err(e) => {
            eprintln!("[FFI] Failed to add drum pad: {e}");
            -1
        }
    })
}

/// Remove a pad by index. Returns a status/error message.
#[no_mangle]
pub extern "C" fn remove_drum_pad_ffi(track_id: u64, pad_index: u8) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::remove_drum_pad(track_id, pad_index) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Load a sample file into a drum pad. Returns 1 on success, 0 on failure, -1 on panic.
#[no_mangle]
pub extern "C" fn load_drum_pad_sample_ffi(
    track_id: u64,
    pad_index: u8,
    path: *const c_char,
) -> i32 {
    ffi_catch(
        -1,
        AssertUnwindSafe(|| {
            let Some(path_str) = (unsafe { cstr_arg(path) }) else {
                return 0;
            };
            match api::load_drum_pad_sample(track_id, pad_index, path_str.to_string()) {
                Ok(msg) => {
                    println!("[FFI] {msg}");
                    1
                }
                Err(e) => {
                    eprintln!("[FFI] Failed to load drum pad sample: {e}");
                    0
                }
            }
        }),
    )
}

/// Set a per-pad parameter. Returns a status/error message.
#[no_mangle]
pub extern "C" fn set_drum_pad_parameter_ffi(
    track_id: u64,
    pad_index: u8,
    param_name: *const c_char,
    value: *const c_char,
) -> *mut c_char {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            let Some(param_name_str) = (unsafe { cstr_arg(param_name) }) else {
                return safe_cstring("Error: Invalid parameter name".to_string()).into_raw();
            };
            let Some(value_str) = (unsafe { cstr_arg(value) }) else {
                return safe_cstring("Error: Invalid value".to_string()).into_raw();
            };
            match api::set_drum_pad_parameter(track_id, pad_index, param_name_str.to_string(), value_str.to_string()) {
                Ok(msg) => safe_cstring(msg).into_raw(),
                Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
            }
        }),
    )
}

/// Check if a track has a drum kit. Returns 1 if yes, 0 if no, -1 on error.
#[no_mangle]
pub extern "C" fn is_drum_kit_track_ffi(track_id: u64) -> i32 {
    ffi_catch(-1, || match api::is_drum_kit_track(track_id) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(e) => {
            eprintln!("[FFI] Failed to check drum-kit track: {e}");
            -1
        }
    })
}

/// The next free MIDI note for a new pad, from `start` upward. Returns -1 if none / on error.
#[no_mangle]
pub extern "C" fn drum_next_free_note_ffi(track_id: u64, start: u8) -> i64 {
    ffi_catch(-1, || match api::drum_next_free_note(track_id, start) {
        Ok(note) => note,
        Err(e) => {
            eprintln!("[FFI] drum_next_free_note failed: {e}");
            -1
        }
    })
}

/// Get drum-kit state as a JSON string (caller frees via the shared string-free FFI).
#[no_mangle]
pub extern "C" fn get_drum_kit_info_ffi(track_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_drum_kit_info(track_id) {
            Ok(json) => safe_cstring(json).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Waveform peaks for a single pad's sample. Returns an f32 array; free with
/// `free_sampler_waveform_peaks_ffi` (same allocation scheme).
#[no_mangle]
pub extern "C" fn get_drum_pad_waveform_peaks_ffi(
    track_id: u64,
    pad_index: u8,
    resolution: usize,
    out_length: *mut usize,
) -> *mut f32 {
    ffi_catch(
        std::ptr::null_mut(),
        AssertUnwindSafe(|| {
            if let Ok(peaks) = api::get_drum_pad_waveform_peaks(track_id, pad_index, resolution) {
                let len = peaks.len();
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
        }),
    )
}
