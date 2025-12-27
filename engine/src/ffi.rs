/// Simple C-compatible FFI layer for M0
/// This will be replaced with flutter_rust_bridge in M1
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use crate::api;

/// Safely create a CString, replacing null bytes with spaces
fn safe_cstring(s: String) -> CString {
    // Replace any null bytes to prevent panic
    let safe_string = s.replace('\0', " ");
    CString::new(safe_string).unwrap_or_else(|_| CString::new("Error creating string").unwrap())
}

/// Play a sine wave - C-compatible wrapper
/// Returns a success message as a C string
#[no_mangle]
pub extern "C" fn play_sine_wave_ffi(frequency: f32, duration_ms: u32) -> *mut c_char {
    match api::play_sine_wave(frequency, duration_ms) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Initialize audio engine - C-compatible wrapper
#[no_mangle]
pub extern "C" fn init_audio_engine_ffi() -> *mut c_char {
    match api::init_audio_engine() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Free a string allocated by Rust
#[no_mangle]
pub extern "C" fn free_rust_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// ============================================================================
// M1: Audio Playback FFI
// ============================================================================

/// Initialize the audio graph
#[no_mangle]
pub extern "C" fn init_audio_graph_ffi() -> *mut c_char {
    match api::init_audio_graph() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Load an audio file to a specific track and return clip ID
#[no_mangle]
pub extern "C" fn load_audio_file_to_track_ffi(path: *const c_char, track_id: u64, start_time: f64) -> i64 {
    if path.is_null() {
        return -1;
    }

    let c_str = unsafe { std::ffi::CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    match api::load_audio_file_to_track_api(path_str.to_string(), track_id, start_time) {
        Ok(id) => id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] load_audio_file_to_track_ffi error: {}", e);
            -1
        }
    }
}

/// Load an audio file and return clip ID (legacy - adds to first available track)
#[no_mangle]
pub extern "C" fn load_audio_file_ffi(path: *const c_char) -> i64 {
    if path.is_null() {
        return -1;
    }

    let c_str = unsafe { std::ffi::CStr::from_ptr(path) };
    let path_str = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    match api::load_audio_file_api(path_str.to_string()) {
        Ok(id) => id as i64,
        Err(_) => -1,
    }
}

/// Start playback
#[no_mangle]
pub extern "C" fn transport_play_ffi() -> *mut c_char {
    match api::transport_play() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Pause playback
#[no_mangle]
pub extern "C" fn transport_pause_ffi() -> *mut c_char {
    match api::transport_pause() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Stop playback
#[no_mangle]
pub extern "C" fn transport_stop_ffi() -> *mut c_char {
    eprintln!("🔴 [FFI] transport_stop_ffi() called from Flutter");
    match api::transport_stop() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Seek to position in seconds
#[no_mangle]
pub extern "C" fn transport_seek_ffi(position_seconds: f64) -> *mut c_char {
    match api::transport_seek(position_seconds) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get playhead position in seconds
#[no_mangle]
pub extern "C" fn get_playhead_position_ffi() -> f64 {
    api::get_playhead_position().unwrap_or(0.0)
}

/// Get transport state (0=Stopped, 1=Playing, 2=Paused)
#[no_mangle]
pub extern "C" fn get_transport_state_ffi() -> i32 {
    api::get_transport_state().unwrap_or(0)
}

// ============================================================================
// Latency Control FFI
// ============================================================================

/// Set buffer size preset
/// 0=Lowest (64), 1=Low (128), 2=Balanced (256), 3=Safe (512), 4=HighStability (1024)
#[no_mangle]
pub extern "C" fn set_buffer_size_ffi(preset: i32) -> *mut c_char {
    match api::set_buffer_size(preset) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get current buffer size preset (0-4)
#[no_mangle]
pub extern "C" fn get_buffer_size_preset_ffi() -> i32 {
    api::get_buffer_size_preset().unwrap_or(2) // Default to Balanced
}

/// Get actual buffer size in samples
#[no_mangle]
pub extern "C" fn get_actual_buffer_size_ffi() -> u32 {
    api::get_actual_buffer_size().unwrap_or(256)
}

/// Get audio latency info
/// Returns: buffer_size, input_latency_ms, output_latency_ms, total_roundtrip_ms
/// Output is written to the provided pointers
#[no_mangle]
pub extern "C" fn get_latency_info_ffi(
    out_buffer_size: *mut u32,
    out_input_latency_ms: *mut f32,
    out_output_latency_ms: *mut f32,
    out_roundtrip_ms: *mut f32,
) {
    if let Some((buffer_size, input_ms, output_ms, roundtrip_ms)) = api::get_latency_info() {
        unsafe {
            if !out_buffer_size.is_null() { *out_buffer_size = buffer_size; }
            if !out_input_latency_ms.is_null() { *out_input_latency_ms = input_ms; }
            if !out_output_latency_ms.is_null() { *out_output_latency_ms = output_ms; }
            if !out_roundtrip_ms.is_null() { *out_roundtrip_ms = roundtrip_ms; }
        }
    }
}

/// Get clip duration in seconds
#[no_mangle]
pub extern "C" fn get_clip_duration_ffi(clip_id: u64) -> f64 {
    api::get_clip_duration(clip_id).unwrap_or(0.0)
}

/// Set clip start time (position) on timeline
/// Used for dragging clips to reposition them
#[no_mangle]
pub extern "C" fn set_clip_start_time_ffi(track_id: u64, clip_id: u64, start_time: f64) -> *mut c_char {
    match api::set_clip_start_time(track_id, clip_id, start_time) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get waveform peaks
/// Returns pointer to float array, and writes the length to out_length
/// Caller must free the returned array with free_waveform_peaks_ffi
#[no_mangle]
pub extern "C" fn get_waveform_peaks_ffi(
    clip_id: u64,
    resolution: usize,
    out_length: *mut usize,
) -> *mut f32 {
    match api::get_waveform_peaks(clip_id, resolution) {
        Ok(peaks) => {
            let len = peaks.len();
            let ptr = peaks.as_ptr() as *mut f32;
            std::mem::forget(peaks); // Don't drop the Vec
            
            if !out_length.is_null() {
                unsafe {
                    *out_length = len;
                }
            }
            
            ptr
        }
        Err(_) => {
            if !out_length.is_null() {
                unsafe {
                    *out_length = 0;
                }
            }
            std::ptr::null_mut()
        }
    }
}

/// Free waveform peaks array
#[no_mangle]
pub extern "C" fn free_waveform_peaks_ffi(ptr: *mut f32, length: usize) {
    if !ptr.is_null() {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, length, length);
        }
    }
}

// ============================================================================
// M2: Recording & Input FFI
// ============================================================================

/// Start recording audio
#[no_mangle]
pub extern "C" fn start_recording_ffi() -> *mut c_char {
    match api::start_recording() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Stop recording and return clip ID (-1 if no recording)
#[no_mangle]
pub extern "C" fn stop_recording_ffi() -> i64 {
    match api::stop_recording() {
        Ok(Some(clip_id)) => clip_id as i64,
        Ok(None) => -1,  // No recording to stop
        Err(e) => {
            eprintln!("❌ [FFI] Stop recording failed: {}", e);
            -1
        }
    }
}

/// Get recording state (0=Idle, 1=CountingIn, 2=Recording)
#[no_mangle]
pub extern "C" fn get_recording_state_ffi() -> i32 {
    api::get_recording_state().unwrap_or_else(|e| {
        eprintln!("❌ [FFI] Get recording state failed: {}", e);
        0  // Return Idle state on error
    })
}

/// Get recorded duration in seconds
#[no_mangle]
pub extern "C" fn get_recorded_duration_ffi() -> f64 {
    api::get_recorded_duration().unwrap_or_else(|e| {
        eprintln!("❌ [FFI] Get recorded duration failed: {}", e);
        0.0
    })
}

/// Get recording waveform preview as CSV of peak values
/// num_peaks: number of downsampled peaks to return
/// Returns CSV string of 0.0-1.0 peak values, or empty string on error
#[no_mangle]
pub extern "C" fn get_recording_waveform_ffi(num_peaks: u32) -> *mut c_char {
    match api::get_recording_waveform(num_peaks as usize) {
        Ok(csv) => safe_cstring(csv).into_raw(),
        Err(_) => safe_cstring(String::new()).into_raw(),
    }
}

/// Set count-in duration in bars
#[no_mangle]
pub extern "C" fn set_count_in_bars_ffi(bars: u32) -> *mut c_char {
    match api::set_count_in_bars(bars) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get count-in duration in bars
#[no_mangle]
pub extern "C" fn get_count_in_bars_ffi() -> u32 {
    api::get_count_in_bars().unwrap_or(2)
}

/// Set tempo in BPM
#[no_mangle]
pub extern "C" fn set_tempo_ffi(bpm: f64) -> *mut c_char {
    match api::set_tempo(bpm) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get tempo in BPM
#[no_mangle]
pub extern "C" fn get_tempo_ffi() -> f64 {
    api::get_tempo().unwrap_or(120.0)
}

/// Enable or disable metronome
#[no_mangle]
pub extern "C" fn set_metronome_enabled_ffi(enabled: i32) -> *mut c_char {
    match api::set_metronome_enabled(enabled != 0) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Check if metronome is enabled
#[no_mangle]
pub extern "C" fn is_metronome_enabled_ffi() -> i32 {
    if api::is_metronome_enabled().unwrap_or(true) { 1 } else { 0 }
}

// ============================================================================
// M3: MIDI FFI
// ============================================================================

/// Start MIDI input
#[no_mangle]
pub extern "C" fn start_midi_input_ffi() -> *mut c_char {
    match api::start_midi_input() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Stop MIDI input
#[no_mangle]
pub extern "C" fn stop_midi_input_ffi() -> *mut c_char {
    match api::stop_midi_input() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set synthesizer oscillator type (0=Sine, 1=Saw, 2=Square)
#[no_mangle]
pub extern "C" fn set_synth_oscillator_type_ffi(osc_type: i32) -> *mut c_char {
    match api::set_synth_oscillator_type(osc_type) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set synthesizer volume (0.0 to 1.0)
#[no_mangle]
pub extern "C" fn set_synth_volume_ffi(volume: f32) -> *mut c_char {
    match api::set_synth_volume(volume) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Send MIDI note on event to synthesizer (for virtual piano)
#[no_mangle]
pub extern "C" fn send_midi_note_on_ffi(note: u8, velocity: u8) -> *mut c_char {
    match api::send_midi_note_on(note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Send MIDI note off event to synthesizer (for virtual piano)
#[no_mangle]
pub extern "C" fn send_midi_note_off_ffi(note: u8, velocity: u8) -> *mut c_char {
    match api::send_midi_note_off(note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// MIDI Recording and Clip Manipulation FFI
// ============================================================================

/// Start MIDI recording
#[no_mangle]
pub extern "C" fn start_midi_recording_ffi() -> *mut c_char {
    match api::start_midi_recording() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Stop MIDI recording and return the clip ID (-1 if no events recorded)
#[no_mangle]
pub extern "C" fn stop_midi_recording_ffi() -> i64 {
    match api::stop_midi_recording() {
        Ok(Some(clip_id)) => clip_id as i64,
        Ok(None) => -1,
        Err(_) => -1,
    }
}

/// Get MIDI recording state (0 = Idle, 1 = Recording)
#[no_mangle]
pub extern "C" fn get_midi_recording_state_ffi() -> i32 {
    match api::get_midi_recording_state() {
        Ok(state) => state,
        Err(_) => -1,
    }
}

// ============================================================================
// MIDI Device Management FFI
// ============================================================================

/// Get available MIDI input devices
/// Returns a newline-separated list of "id|name|is_default"
#[no_mangle]
pub extern "C" fn get_midi_input_devices_ffi() -> *mut c_char {
    match api::get_midi_input_devices() {
        Ok(devices) => {
            let formatted: Vec<String> = devices
                .into_iter()
                .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                .collect();
            safe_cstring(formatted.join("\n")).into_raw()
        }
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Select a MIDI input device by index
#[no_mangle]
pub extern "C" fn select_midi_input_device_ffi(device_index: i32) -> *mut c_char {
    match api::select_midi_input_device(device_index) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Refresh MIDI devices (rescan)
#[no_mangle]
pub extern "C" fn refresh_midi_devices_ffi() -> *mut c_char {
    match api::refresh_midi_devices() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// Audio Device Management FFI
// ============================================================================

/// Get available audio input devices
/// Returns a newline-separated list of "id|name|is_default"
#[no_mangle]
pub extern "C" fn get_audio_input_devices_ffi() -> *mut c_char {
    match api::get_audio_input_devices() {
        Ok(devices) => {
            let formatted: Vec<String> = devices
                .into_iter()
                .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                .collect();
            safe_cstring(formatted.join("\n")).into_raw()
        }
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get available audio output devices
/// Returns a newline-separated list of "id|name|is_default"
#[no_mangle]
pub extern "C" fn get_audio_output_devices_ffi() -> *mut c_char {
    match api::get_audio_output_devices() {
        Ok(devices) => {
            let formatted: Vec<String> = devices
                .into_iter()
                .map(|(id, name, is_default)| format!("{}|{}|{}", id, name, if is_default { "1" } else { "0" }))
                .collect();
            safe_cstring(formatted.join("\n")).into_raw()
        }
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set audio input device by index
#[no_mangle]
pub extern "C" fn set_audio_input_device_ffi(device_index: i32) -> *mut c_char {
    match api::set_audio_input_device(device_index) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get current sample rate
#[no_mangle]
pub extern "C" fn get_sample_rate_ffi() -> u32 {
    api::get_sample_rate()
}

/// Create a new empty MIDI clip
#[no_mangle]
pub extern "C" fn create_midi_clip_ffi() -> i64 {
    match api::create_midi_clip() {
        Ok(clip_id) => clip_id as i64,
        Err(_) => -1,
    }
}

/// Add a MIDI clip to a track's timeline for playback
#[no_mangle]
pub extern "C" fn add_midi_clip_to_track_ffi(
    track_id: u64,
    clip_id: u64,
    start_time_seconds: f64,
) -> i64 {
    match api::add_midi_clip_to_track(track_id, clip_id, start_time_seconds) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Remove a MIDI clip from a track and global storage
#[no_mangle]
pub extern "C" fn remove_midi_clip_ffi(track_id: u64, clip_id: u64) -> i64 {
    match api::remove_midi_clip(track_id, clip_id) {
        Ok(removed) => if removed { 0 } else { 1 },
        Err(_) => -1,
    }
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
    match api::add_midi_note_to_clip(clip_id, note, velocity, start_time, duration) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Clear all notes from a MIDI clip
#[no_mangle]
pub extern "C" fn clear_midi_clip_ffi(clip_id: u64) -> *mut c_char {
    match api::clear_midi_clip(clip_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Quantize a MIDI clip
#[no_mangle]
pub extern "C" fn quantize_midi_clip_ffi(clip_id: u64, grid_division: u32) -> *mut c_char {
    match api::quantize_midi_clip(clip_id, grid_division) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get MIDI clip count
#[no_mangle]
pub extern "C" fn get_midi_clip_count_ffi() -> usize {
    api::get_midi_clip_count().unwrap_or(0)
}

/// Get MIDI clip info as CSV: "clip_id,track_id,start_time,duration,note_count"
/// track_id is -1 if not assigned to a track
#[no_mangle]
pub extern "C" fn get_midi_clip_info_ffi(clip_id: u64) -> *mut c_char {
    match api::get_midi_clip_info(clip_id) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// M4: TRACK & MIXING FFI
// ============================================================================

/// Create a new track
///
/// # Arguments
/// * `track_type` - Track type: "audio", "midi", "return", "group"
/// * `name` - Display name for the track
///
/// # Returns
/// Track ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn create_track_ffi(
    track_type: *const c_char,
    name: *const c_char,
) -> i64 {
    let track_type_str = unsafe {
        match CStr::from_ptr(track_type).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };
    let name_str = unsafe {
        match CStr::from_ptr(name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    match api::create_track(track_type_str, name_str) {
        Ok(id) => id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] create_track error: {}", e);
            -1
        }
    }
}

/// Set track volume
#[no_mangle]
pub extern "C" fn set_track_volume_ffi(track_id: u64, volume_db: f32) -> *mut c_char {
    match api::set_track_volume(track_id, volume_db) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set track pan
#[no_mangle]
pub extern "C" fn set_track_pan_ffi(track_id: u64, pan: f32) -> *mut c_char {
    match api::set_track_pan(track_id, pan) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set track mute
#[no_mangle]
pub extern "C" fn set_track_mute_ffi(track_id: u64, mute: bool) -> *mut c_char {
    match api::set_track_mute(track_id, mute) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set track solo
#[no_mangle]
pub extern "C" fn set_track_solo_ffi(track_id: u64, solo: bool) -> *mut c_char {
    match api::set_track_solo(track_id, solo) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set track armed (for recording)
#[no_mangle]
pub extern "C" fn set_track_armed_ffi(track_id: u64, armed: bool) -> *mut c_char {
    match api::set_track_armed(track_id, armed) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set track name
#[no_mangle]
pub extern "C" fn set_track_name_ffi(track_id: u64, name: *const c_char) -> *mut c_char {
    let name_str = unsafe {
        if name.is_null() {
            return safe_cstring("Error: name is null".to_string()).into_raw();
        }
        CStr::from_ptr(name).to_string_lossy().to_string()
    };
    match api::set_track_name(track_id, name_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get track count
#[no_mangle]
pub extern "C" fn get_track_count_ffi() -> usize {
    api::get_track_count().unwrap_or(0)
}

/// Get all track IDs (CSV format)
#[no_mangle]
pub extern "C" fn get_all_track_ids_ffi() -> *mut c_char {
    match api::get_all_track_ids() {
        Ok(ids) => safe_cstring(ids).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get track info (CSV format)
///
/// Returns: "track_id,name,type,volume_db,pan,mute,solo"
/// Caller must free the returned string
#[no_mangle]
pub extern "C" fn get_track_info_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_info(track_id) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get track peak levels (M5.5)
/// Returns: "peak_left_db,peak_right_db"
/// Caller must free the returned string
#[no_mangle]
pub extern "C" fn get_track_peak_levels_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_peak_levels(track_id) {
        Ok(levels) => safe_cstring(levels).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Move clip to track
#[no_mangle]
pub extern "C" fn move_clip_to_track_ffi(track_id: u64, clip_id: u64) -> *mut c_char {
    match api::move_clip_to_track(track_id, clip_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// M4: Effect Management FFI
// ============================================================================

/// Add an effect to a track's FX chain
/// Returns effect ID on success, or -1 on error
#[no_mangle]
pub extern "C" fn add_effect_to_track_ffi(
    track_id: u64,
    effect_type: *const c_char,
) -> i64 {
    let effect_type_str = unsafe {
        match CStr::from_ptr(effect_type).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    match api::add_effect_to_track(track_id, effect_type_str) {
        Ok(effect_id) => effect_id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] add_effect_to_track error: {}", e);
            -1
        }
    }
}

/// Remove an effect from a track
#[no_mangle]
pub extern "C" fn remove_effect_from_track_ffi(track_id: u64, effect_id: u64) -> *mut c_char {
    match api::remove_effect_from_track(track_id, effect_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get all effects on a track (CSV format)
#[no_mangle]
pub extern "C" fn get_track_effects_ffi(track_id: u64) -> *mut c_char {
    match api::get_track_effects(track_id) {
        Ok(effects) => safe_cstring(effects).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get effect info (type and parameters)
#[no_mangle]
pub extern "C" fn get_effect_info_ffi(effect_id: u64) -> *mut c_char {
    match api::get_effect_info(effect_id) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set an effect parameter
#[no_mangle]
pub extern "C" fn set_effect_parameter_ffi(
    effect_id: u64,
    param_name: *const c_char,
    value: f32,
) -> *mut c_char {
    let param_name_str = unsafe {
        match CStr::from_ptr(param_name).to_str() {
            Ok(s) => s,
            Err(_) => return safe_cstring("Error: Invalid parameter name".to_string()).into_raw(),
        }
    };

    match api::set_effect_parameter(effect_id, param_name_str, value) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Set effect bypass state
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn set_effect_bypass_ffi(effect_id: u64, bypassed: i32) -> i32 {
    match api::set_effect_bypass(effect_id, bypassed != 0) {
        Ok(_) => 1,
        Err(e) => {
            eprintln!("❌ [FFI] set_effect_bypass error: {}", e);
            0
        }
    }
}

/// Get effect bypass state
/// Returns 1 if bypassed, 0 if not bypassed, -1 on error
#[no_mangle]
pub extern "C" fn get_effect_bypass_ffi(effect_id: u64) -> i32 {
    match api::get_effect_bypass(effect_id) {
        Ok(bypassed) => if bypassed { 1 } else { 0 },
        Err(e) => {
            eprintln!("❌ [FFI] get_effect_bypass error: {}", e);
            -1
        }
    }
}

/// Reorder effects in a track's FX chain
/// effect_ids_csv: comma-separated list of effect IDs in the desired order
#[no_mangle]
pub extern "C" fn reorder_track_effects_ffi(track_id: u64, effect_ids_csv: *const c_char) -> *mut c_char {
    let ids_str = unsafe {
        match CStr::from_ptr(effect_ids_csv).to_str() {
            Ok(s) => s,
            Err(_) => return safe_cstring("Error: Invalid effect IDs string".to_string()).into_raw(),
        }
    };

    match api::reorder_track_effects(track_id, ids_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Delete a track
#[no_mangle]
pub extern "C" fn delete_track_ffi(track_id: u64) -> *mut c_char {
    match api::delete_track(track_id) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Clear all tracks except master - used for New Project / Close Project
#[no_mangle]
pub extern "C" fn clear_all_tracks_ffi() -> *mut c_char {
    match api::clear_all_tracks() {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Duplicate a track
///
/// Returns the new track ID as a string on success, or "Error: <message>" on failure.
/// Returns "-1" if duplication fails.
#[no_mangle]
pub extern "C" fn duplicate_track_ffi(track_id: u64) -> i64 {
    match api::duplicate_track(track_id) {
        Ok(new_track_id) => new_track_id as i64,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to duplicate track {}: {}", track_id, e);
            -1
        }
    }
}

// ============================================================================
// M5: SAVE/LOAD PROJECT FFI
// ============================================================================

/// Save project to .audio folder
#[no_mangle]
pub extern "C" fn save_project_ffi(
    project_name: *const c_char,
    project_path: *const c_char,
) -> *mut c_char {
    let project_name_str = unsafe {
        match CStr::from_ptr(project_name).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project name".to_string()).into_raw(),
        }
    };

    let project_path_str = unsafe {
        match CStr::from_ptr(project_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project path".to_string()).into_raw(),
        }
    };

    match api::save_project(project_name_str, project_path_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Load project from .audio folder
#[no_mangle]
pub extern "C" fn load_project_ffi(project_path: *const c_char) -> *mut c_char {
    let project_path_str = unsafe {
        match CStr::from_ptr(project_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid project path".to_string()).into_raw(),
        }
    };

    match api::load_project(project_path_str) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Export to WAV file
#[no_mangle]
pub extern "C" fn export_to_wav_ffi(
    output_path: *const c_char,
    normalize: bool,
) -> *mut c_char {
    let output_path_str = unsafe {
        match CStr::from_ptr(output_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
        }
    };

    match api::export_to_wav(output_path_str, normalize) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

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
            eprintln!("❌ [FFI] Failed to set instrument: {}", e);
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
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get all synthesizer parameters for a track
#[no_mangle]
pub extern "C" fn get_synth_parameters_ffi(track_id: u64) -> *mut c_char {
    println!("🎹 [FFI] Get synth parameters for track {}", track_id);

    match api::get_synth_parameters(track_id) {
        Ok(json) => safe_cstring(json).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Send MIDI note on event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_on_ffi(track_id: u64, note: u8, velocity: u8) -> *mut c_char {
    println!("🎹 [FFI] Track {} Note On: note={}, velocity={}", track_id, note, velocity);

    match api::send_track_midi_note_on(track_id, note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Send MIDI note off event to track synthesizer
#[no_mangle]
pub extern "C" fn send_track_midi_note_off_ffi(track_id: u64, note: u8, velocity: u8) -> *mut c_char {
    println!("🎹 [FFI] Track {} Note Off: note={}, velocity={}", track_id, note, velocity);

    match api::send_track_midi_note_off(track_id, note, velocity) {
        Ok(msg) => safe_cstring(msg).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// M7: VST3 Plugin Hosting FFI
// ============================================================================

// VST3 FFI functions - only available when vst3 feature is enabled
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
/// Scan standard system locations for VST3 plugins
/// Returns a newline-separated list of "name|path"
#[no_mangle]
pub extern "C" fn scan_vst3_plugins_standard_ffi() -> *mut c_char {
    println!("🔍 [FFI] Scanning VST3 plugins in standard locations...");

    match api::scan_vst3_plugins_standard() {
        Ok(plugin_list) => {
            println!("✅ [FFI] VST3 scan completed");
            safe_cstring(plugin_list).into_raw()
        }
        Err(e) => {
            eprintln!("❌ [FFI] VST3 scan failed: {}", e);
            safe_cstring(String::new()).into_raw()
        }
    }
}

/// Add a VST3 effect to a track
/// Returns the effect ID, or -1 on failure
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn add_vst3_effect_to_track_ffi(
    track_id: u64,
    plugin_path: *const c_char,
) -> i64 {
    let plugin_path_str = unsafe {
        match CStr::from_ptr(plugin_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    println!("🔌 [FFI] Adding VST3 plugin to track {}: {}", track_id, plugin_path_str);

    match api::add_vst3_effect_to_track(track_id, &plugin_path_str) {
        Ok(effect_id) => {
            println!("✅ [FFI] VST3 plugin added with effect ID: {}", effect_id);
            effect_id as i64
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to add VST3 plugin: {}", e);
            -1
        }
    }
}

/// Get the number of parameters for a VST3 effect
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn get_vst3_parameter_count_ffi(effect_id: i64) -> i32 {
    match api::get_vst3_parameter_count(effect_id as u64) {
        Ok(count) => count as i32,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter count: {}", e);
            0
        }
    }
}

/// Get information about a VST3 parameter
/// Returns a CSV string: "name,min,max,default"
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn get_vst3_parameter_info_ffi(
    effect_id: i64,
    param_index: i32,
) -> *mut c_char {
    match api::get_vst3_parameter_info(effect_id as u64, param_index as u32) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter info: {}", e);
            safe_cstring(String::new()).into_raw()
        }
    }
}

/// Get the current value of a VST3 parameter (0.0-1.0)
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn get_vst3_parameter_value_ffi(
    effect_id: i64,
    param_index: i32,
) -> f64 {
    match api::get_vst3_parameter_value(effect_id as u64, param_index as u32) {
        Ok(value) => value,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter value: {}", e);
            0.0
        }
    }
}

/// Set the value of a VST3 parameter (0.0-1.0)
/// Returns 1 on success, 0 on failure
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn set_vst3_parameter_value_ffi(
    effect_id: i64,
    param_index: i32,
    value: f64,
) -> i32 {
    match api::set_vst3_parameter_value(effect_id as u64, param_index as u32, value) {
        Ok(_) => 1,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to set VST3 parameter value: {}", e);
            0
        }
    }
}

// ============================================================================
// M7: VST3 Editor FFI Functions
// ============================================================================

/// Check if a VST3 plugin has an editor GUI
/// Returns true if the plugin has an editor
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_has_editor_ffi(effect_id: i64) -> bool {
    match api::vst3_has_editor(effect_id as u64) {
        Ok(has_editor) => has_editor,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to check VST3 editor: {}", e);
            false
        }
    }
}

/// Open a VST3 plugin editor (creates IPlugView)
/// Returns empty string on success, error message on failure
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_open_editor_ffi(effect_id: i64) -> *mut c_char {
    println!("🎨 [FFI] Opening VST3 editor for effect {}", effect_id);

    match api::vst3_open_editor(effect_id as u64) {
        Ok(msg) => {
            if msg.is_empty() {
                println!("✅ [FFI] VST3 editor opened successfully");
                safe_cstring(String::new()).into_raw()
            } else {
                safe_cstring(msg).into_raw()
            }
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to open VST3 editor: {}", e);
            safe_cstring(format!("Error: {}", e)).into_raw()
        }
    }
}

/// Close a VST3 plugin editor
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_close_editor_ffi(effect_id: i64) {
    println!("🎨 [FFI] Closing VST3 editor for effect {}", effect_id);

    match api::vst3_close_editor(effect_id as u64) {
        Ok(_) => println!("✅ [FFI] VST3 editor closed"),
        Err(e) => eprintln!("❌ [FFI] Failed to close VST3 editor: {}", e),
    }
}

/// Get VST3 editor size
/// Returns "width,height" or error message
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_get_editor_size_ffi(effect_id: i64) -> *mut c_char {
    match api::vst3_get_editor_size(effect_id as u64) {
        Ok(size) => safe_cstring(size).into_raw(),
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 editor size: {}", e);
            safe_cstring(format!("Error: {}", e)).into_raw()
        }
    }
}

/// Attach VST3 editor to a parent window
/// parent_ptr: Pointer to NSView (on macOS)
/// Returns empty string on success, error message on failure
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_attach_editor_ffi(
    effect_id: i64,
    parent_ptr: *mut std::os::raw::c_void,
) -> *mut c_char {
    println!("🎨 [FFI] Attaching VST3 editor for effect {} to parent {:?}", effect_id, parent_ptr);

    // Flush stdout to ensure logs appear before potential crash
    use std::io::Write;
    let _ = std::io::stdout().flush();

    println!("🔍 [FFI] About to call api::vst3_attach_editor...");
    let _ = std::io::stdout().flush();

    match api::vst3_attach_editor(effect_id as u64, parent_ptr) {
        Ok(msg) => {
            if msg.is_empty() {
                println!("✅ [FFI] VST3 editor attached successfully");
                safe_cstring(String::new()).into_raw()
            } else {
                safe_cstring(msg).into_raw()
            }
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to attach VST3 editor: {}", e);
            safe_cstring(format!("Error: {}", e)).into_raw()
        }
    }
}

/// Send a MIDI note event to a VST3 plugin
/// event_type: 0 = note on, 1 = note off
/// Returns empty string on success, error message on failure
#[cfg(all(feature = "vst3", not(target_os = "ios")))]
#[no_mangle]
pub extern "C" fn vst3_send_midi_note_ffi(
    effect_id: i64,
    event_type: i32,
    channel: i32,
    note: i32,
    velocity: i32,
) -> *mut c_char {
    match api::vst3_send_midi_note(effect_id as u64, event_type, channel, note, velocity) {
        Ok(()) => safe_cstring(String::new()).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// MIDI Clip Info FFI (for restoring clips after project load)
// ============================================================================

/// Get all MIDI clips info
/// Returns semicolon-separated list: "clip_id,track_id,start_time,duration,note_count"
/// Each clip info is separated by semicolon
#[no_mangle]
pub extern "C" fn get_all_midi_clips_info_ffi() -> *mut c_char {
    match api::get_all_midi_clips_info() {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Get MIDI notes from a clip
/// Returns semicolon-separated list: "note,velocity,start_time,duration"
#[no_mangle]
pub extern "C" fn get_midi_clip_notes_ffi(clip_id: u64) -> *mut c_char {
    match api::get_midi_clip_notes(clip_id) {
        Ok(notes) => safe_cstring(notes).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// M8: EXPORT FFI
// ============================================================================

/// Check if ffmpeg is available for MP3 encoding
/// Returns 1 if available, 0 if not
#[no_mangle]
pub extern "C" fn is_ffmpeg_available_ffi() -> i32 {
    if api::is_ffmpeg_available() { 1 } else { 0 }
}

/// Export audio with configurable options (generic, accepts JSON options)
/// options_json: JSON string of ExportOptions
/// Returns JSON string with ExportResult on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_audio_ffi(
    output_path: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
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
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Export WAV with configurable options
/// bit_depth: 16, 24, or 32
/// sample_rate: 44100 or 48000
/// Returns JSON string with ExportResult on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_wav_with_options_ffi(
    output_path: *const c_char,
    bit_depth: i32,
    sample_rate: u32,
    normalize: bool,
    dither: bool,
    mono: bool,
) -> *mut c_char {
    let output_path_str = unsafe {
        match CStr::from_ptr(output_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
        }
    };

    match api::export_wav_with_options(output_path_str, bit_depth, sample_rate, normalize, dither, mono) {
        Ok(result_json) => safe_cstring(result_json).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Export MP3 with configurable options
/// bitrate: 128, 192, or 320
/// sample_rate: 44100 or 48000
/// Returns JSON string with ExportResult on success, or "Error: <message>" on failure
#[no_mangle]
pub extern "C" fn export_mp3_with_options_ffi(
    output_path: *const c_char,
    bitrate: i32,
    sample_rate: u32,
    normalize: bool,
    mono: bool,
) -> *mut c_char {
    let output_path_str = unsafe {
        match CStr::from_ptr(output_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return safe_cstring("Error: Invalid output path".to_string()).into_raw(),
        }
    };

    match api::export_mp3_with_options(output_path_str, bitrate, sample_rate, normalize, mono) {
        Ok(result_json) => safe_cstring(result_json).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Write ID3 metadata to an MP3 file
/// metadata_json: JSON string of ExportMetadata
/// Returns success message or "Error: <message>"
#[no_mangle]
pub extern "C" fn write_mp3_metadata_ffi(
    file_path: *const c_char,
    metadata_json: *const c_char,
) -> *mut c_char {
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
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// STEM EXPORT FFI
// ============================================================================

/// Get tracks available for stem export
/// Returns JSON array of {id, name, type} objects
#[no_mangle]
pub extern "C" fn get_tracks_for_stems_ffi() -> *mut c_char {
    match api::get_tracks_for_stems() {
        Ok(json) => safe_cstring(json).into_raw(),
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

/// Export stems (individual tracks) to a directory
/// output_dir: Directory to export stems to
/// base_name: Base filename for stems
/// track_ids_json: JSON array of track IDs, or empty/null for all tracks
/// options_json: JSON string of ExportOptions
/// Returns JSON string with StemExportResult on success
#[no_mangle]
pub extern "C" fn export_stems_ffi(
    output_dir: *const c_char,
    base_name: *const c_char,
    track_ids_json: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
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
        Err(e) => safe_cstring(format!("Error: {}", e)).into_raw(),
    }
}

// ============================================================================
// EXPORT PROGRESS FFI
// ============================================================================

/// Get current export progress info
/// Returns JSON string with progress, is_running, is_cancelled, status, error
#[no_mangle]
pub extern "C" fn get_export_progress_ffi() -> *mut c_char {
    use crate::export::ExportProgressInfo;
    let info = ExportProgressInfo::current();
    safe_cstring(info.to_json()).into_raw()
}

/// Cancel the current export operation
#[no_mangle]
pub extern "C" fn cancel_export_ffi() {
    crate::export::export_progress().cancel();
}

/// Reset export progress state (call before starting a new export)
#[no_mangle]
pub extern "C" fn reset_export_progress_ffi() {
    crate::export::export_progress().reset();
}

