use std::os::raw::c_char;
use crate::api;
use super::{safe_cstring, ffi_catch};

// ============================================================================
// M3: MIDI FFI
// ============================================================================

/// Start MIDI input
#[no_mangle]
pub extern "C" fn start_midi_input_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::start_midi_input() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Stop MIDI input
#[no_mangle]
pub extern "C" fn stop_midi_input_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::stop_midi_input() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set synthesizer oscillator type (0=Sine, 1=Saw, 2=Square)
#[no_mangle]
pub extern "C" fn set_synth_oscillator_type_ffi(osc_type: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_synth_oscillator_type(osc_type) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Set synthesizer volume (0.0 to 1.0)
#[no_mangle]
pub extern "C" fn set_synth_volume_ffi(volume: f32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::set_synth_volume(volume) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Send MIDI note on event to synthesizer (for virtual piano)
#[no_mangle]
pub extern "C" fn send_midi_note_on_ffi(note: u8, velocity: u8) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::send_midi_note_on(note, velocity) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Send MIDI note off event to synthesizer (for virtual piano)
#[no_mangle]
pub extern "C" fn send_midi_note_off_ffi(note: u8, velocity: u8) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::send_midi_note_off(note, velocity) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

// ============================================================================
// MIDI Recording and Clip Manipulation FFI
// ============================================================================

/// Start MIDI recording
#[no_mangle]
pub extern "C" fn start_midi_recording_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::start_midi_recording() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Stop MIDI recording and return the clip ID (-1 if no events recorded)
#[no_mangle]
pub extern "C" fn stop_midi_recording_ffi() -> i64 {
    ffi_catch(-1, || {
        match api::stop_midi_recording() {
            Ok(Some(clip_id)) => clip_id as i64,
            Ok(None) | Err(_) => -1,
        }
    })
}

/// Get MIDI recording state (0 = Idle, 1 = Recording)
#[no_mangle]
pub extern "C" fn get_midi_recording_state_ffi() -> i32 {
    ffi_catch(-1, || {
        api::get_midi_recording_state().unwrap_or(-1)
    })
}

/// Get live MIDI recording events for real-time UI preview
/// Returns CSV: "`note,velocity,type,timestamp_samples`;..." or empty string
#[no_mangle]
pub extern "C" fn get_midi_recorder_live_events_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_midi_recorder_live_events() {
            Ok(events) => safe_cstring(events).into_raw(),
            Err(_) => safe_cstring(String::new()).into_raw(),
        }
    })
}

// ============================================================================
// MIDI Device Management FFI
// ============================================================================

/// Get available MIDI input devices
/// Returns a newline-separated list of "`id|name|is_default`"
#[no_mangle]
pub extern "C" fn get_midi_input_devices_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_midi_input_devices() {
            Ok(devices) => {
                let formatted: Vec<String> = devices
                    .into_iter()
                    .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                    .collect();
                safe_cstring(formatted.join("\n")).into_raw()
            }
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Select a MIDI input device by index
#[no_mangle]
pub extern "C" fn select_midi_input_device_ffi(device_index: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::select_midi_input_device(device_index) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Refresh MIDI devices (rescan)
#[no_mangle]
pub extern "C" fn refresh_midi_devices_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::refresh_midi_devices() {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

// ============================================================================
// MIDI Clip Operations FFI
// ============================================================================

/// Create a new empty MIDI clip
#[no_mangle]
pub extern "C" fn create_midi_clip_ffi() -> i64 {
    ffi_catch(-1, || {
        match api::create_midi_clip() {
            Ok(clip_id) => clip_id as i64,
            Err(_) => -1,
        }
    })
}

/// Add a MIDI clip to a track's timeline for playback
#[no_mangle]
pub extern "C" fn add_midi_clip_to_track_ffi(
    track_id: u64,
    clip_id: u64,
    start_time_seconds: f64,
) -> i64 {
    ffi_catch(-1, || {
        match api::add_midi_clip_to_track(track_id, clip_id, start_time_seconds) {
            Ok(()) => 0,
            Err(_) => -1,
        }
    })
}

/// Remove a MIDI clip from a track and global storage
#[no_mangle]
pub extern "C" fn remove_midi_clip_ffi(track_id: u64, clip_id: u64) -> i64 {
    ffi_catch(-1, || {
        match api::remove_midi_clip(track_id, clip_id) {
            Ok(removed) => i64::from(!removed),
            Err(_) => -1,
        }
    })
}

/// Add a MIDI note to a clip
#[no_mangle]
pub extern "C" fn add_midi_note_to_clip_ffi(
    clip_id: u64,
    note: u8,
    velocity: u8,
    start_time: f64,
    duration: f64,
) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::add_midi_note_to_clip(clip_id, note, velocity, start_time, duration) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Clear all notes from a MIDI clip
#[no_mangle]
pub extern "C" fn clear_midi_clip_ffi(clip_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::clear_midi_clip(clip_id) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Quantize a MIDI clip
#[no_mangle]
pub extern "C" fn quantize_midi_clip_ffi(clip_id: u64, grid_division: u32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::quantize_midi_clip(clip_id, grid_division) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get MIDI clip count
#[no_mangle]
pub extern "C" fn get_midi_clip_count_ffi() -> usize {
    ffi_catch(0, || {
        api::get_midi_clip_count().unwrap_or(0)
    })
}

/// Get MIDI clip info as CSV: "`clip_id,track_id,start_time,duration,note_count`"
/// `track_id` is -1 if not assigned to a track
#[no_mangle]
pub extern "C" fn get_midi_clip_info_ffi(clip_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_midi_clip_info(clip_id) {
            Ok(info) => safe_cstring(info).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

// ============================================================================
// MIDI Clip Info FFI (for restoring clips after project load)
// ============================================================================

/// Get all MIDI clips info
/// Returns semicolon-separated list: "`clip_id,track_id,start_time,duration,note_count`"
/// Each clip info is separated by semicolon
#[no_mangle]
pub extern "C" fn get_all_midi_clips_info_ffi() -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_all_midi_clips_info() {
            Ok(info) => safe_cstring(info).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}

/// Get MIDI notes from a clip
/// Returns semicolon-separated list: "`note,velocity,start_time,duration`"
#[no_mangle]
pub extern "C" fn get_midi_clip_notes_ffi(clip_id: u64) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::get_midi_clip_notes(clip_id) {
            Ok(notes) => safe_cstring(notes).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}
