use std::ffi::CStr;
use std::os::raw::c_char;
use crate::api;
use super::safe_cstring;

// ============================================================================
// M7: VST3 Plugin Hosting FFI
// ============================================================================

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
            eprintln!("❌ [FFI] VST3 scan failed: {e}");
            safe_cstring(String::new()).into_raw()
        }
    }
}

/// Add a VST3 effect to a track
/// Returns the effect ID, or -1 on failure
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

    println!("🔌 [FFI] Adding VST3 plugin to track {track_id}: {plugin_path_str}");

    match api::add_vst3_effect_to_track(track_id, &plugin_path_str) {
        Ok(effect_id) => {
            println!("✅ [FFI] VST3 plugin added with effect ID: {effect_id}");
            effect_id as i64
        }
        Err(e) => {
            eprintln!("❌ [FFI] Failed to add VST3 plugin: {e}");
            -1
        }
    }
}

/// Get the number of parameters for a VST3 effect
#[no_mangle]
pub extern "C" fn get_vst3_parameter_count_ffi(effect_id: i64) -> i32 {
    match api::get_vst3_parameter_count(effect_id as u64) {
        Ok(count) => count as i32,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter count: {e}");
            0
        }
    }
}

/// Get information about a VST3 parameter
/// Returns a CSV string: "name,min,max,default"
#[no_mangle]
pub extern "C" fn get_vst3_parameter_info_ffi(
    effect_id: i64,
    param_index: i32,
) -> *mut c_char {
    match api::get_vst3_parameter_info(effect_id as u64, param_index as u32) {
        Ok(info) => safe_cstring(info).into_raw(),
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter info: {e}");
            safe_cstring(String::new()).into_raw()
        }
    }
}

/// Get the current value of a VST3 parameter (0.0-1.0)
#[no_mangle]
pub extern "C" fn get_vst3_parameter_value_ffi(
    effect_id: i64,
    param_index: i32,
) -> f64 {
    match api::get_vst3_parameter_value(effect_id as u64, param_index as u32) {
        Ok(value) => value,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 parameter value: {e}");
            0.0
        }
    }
}

/// Set the value of a VST3 parameter (0.0-1.0)
/// Returns 1 on success, 0 on failure
#[no_mangle]
pub extern "C" fn set_vst3_parameter_value_ffi(
    effect_id: i64,
    param_index: i32,
    value: f64,
) -> i32 {
    match api::set_vst3_parameter_value(effect_id as u64, param_index as u32, value) {
        Ok(_) => 1,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to set VST3 parameter value: {e}");
            0
        }
    }
}

// ============================================================================
// M7: VST3 Editor FFI Functions
// ============================================================================

/// Check if a VST3 plugin has an editor GUI
/// Returns true if the plugin has an editor
#[no_mangle]
pub extern "C" fn vst3_has_editor_ffi(effect_id: i64) -> bool {
    match api::vst3_has_editor(effect_id as u64) {
        Ok(has_editor) => has_editor,
        Err(e) => {
            eprintln!("❌ [FFI] Failed to check VST3 editor: {e}");
            false
        }
    }
}

/// Open a VST3 plugin editor (creates `IPlugView`)
/// Returns empty string on success, error message on failure
#[no_mangle]
pub extern "C" fn vst3_open_editor_ffi(effect_id: i64) -> *mut c_char {
    println!("🎨 [FFI] Opening VST3 editor for effect {effect_id}");

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
            eprintln!("❌ [FFI] Failed to open VST3 editor: {e}");
            safe_cstring(format!("Error: {e}")).into_raw()
        }
    }
}

/// Close a VST3 plugin editor
#[no_mangle]
pub extern "C" fn vst3_close_editor_ffi(effect_id: i64) {
    println!("🎨 [FFI] Closing VST3 editor for effect {effect_id}");

    match api::vst3_close_editor(effect_id as u64) {
        Ok(()) => println!("✅ [FFI] VST3 editor closed"),
        Err(e) => eprintln!("❌ [FFI] Failed to close VST3 editor: {e}"),
    }
}

/// Get VST3 editor size
/// Returns "width,height" or error message
#[no_mangle]
pub extern "C" fn vst3_get_editor_size_ffi(effect_id: i64) -> *mut c_char {
    match api::vst3_get_editor_size(effect_id as u64) {
        Ok(size) => safe_cstring(size).into_raw(),
        Err(e) => {
            eprintln!("❌ [FFI] Failed to get VST3 editor size: {e}");
            safe_cstring(format!("Error: {e}")).into_raw()
        }
    }
}

/// Attach VST3 editor to a parent window
/// `parent_ptr`: Pointer to `NSView` (on macOS)
/// Returns empty string on success, error message on failure
#[no_mangle]
pub extern "C" fn vst3_attach_editor_ffi(
    effect_id: i64,
    parent_ptr: *mut std::os::raw::c_void,
) -> *mut c_char {
    println!("🎨 [FFI] Attaching VST3 editor for effect {effect_id} to parent {parent_ptr:?}");

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
            eprintln!("❌ [FFI] Failed to attach VST3 editor: {e}");
            safe_cstring(format!("Error: {e}")).into_raw()
        }
    }
}

/// Send a MIDI note event to a VST3 plugin
/// `event_type`: 0 = note on, 1 = note off
/// Returns empty string on success, error message on failure
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
        Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
    }
}
