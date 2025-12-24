//! VST3 plugin API functions
//!
//! Functions for managing VST3 plugins on tracks.
//! Note: VST3 is only available on desktop platforms (not iOS).

use super::helpers::get_audio_graph;
use crate::track::TrackId;

// ============================================================================
// VST3 Plugin Functions (M7) - Desktop only (not available on iOS)
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Load a VST3 plugin and add it to a track's FX chain
pub fn add_vst3_effect_to_track(track_id: TrackId, plugin_path: &str) -> Result<u64, String> {
    use crate::effects::EffectType;
    use crate::vst3_host::VST3Effect;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let mut effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    // Get audio settings
    let sample_rate = crate::audio_file::TARGET_SAMPLE_RATE as f64;
    let block_size = 512; // TODO: Get from config

    // Load VST3 plugin
    let mut vst3_effect = VST3Effect::new(plugin_path, sample_rate, block_size as i32)
        .map_err(|e| format!("Failed to load VST3 plugin: {}", e))?;

    // Initialize and activate the plugin for audio processing
    vst3_effect
        .initialize()
        .map_err(|e| format!("Failed to initialize VST3 plugin: {}", e))?;

    let effect = EffectType::VST3(vst3_effect);

    // Add effect to effect manager
    let effect_id = effect_manager.create_effect(effect);

    // Add effect to track's FX chain
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.fx_chain.push(effect_id);
        eprintln!(
            "🎛️ [API] Added VST3 plugin from {} (ID: {}) to track {}",
            plugin_path, effect_id, track_id
        );
        Ok(effect_id)
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get the number of parameters in a VST3 plugin
pub fn get_vst3_parameter_count(effect_id: u64) -> Result<u32, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.get_parameter_count() as u32)
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get information about a VST3 parameter (returns "name,min,max,default")
pub fn get_vst3_parameter_info(effect_id: u64, param_index: u32) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            let info = vst3.get_parameter_info(param_index as i32)?;
            // VST3 parameters are normalized 0.0-1.0
            Ok(format!("{},0.0,1.0,0.5", info.title_str()))
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get a VST3 parameter value
pub fn get_vst3_parameter_value(effect_id: u64, param_index: u32) -> Result<f64, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.get_parameter_value(param_index))
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Set a VST3 parameter value (normalized 0.0-1.0)
pub fn set_vst3_parameter_value(
    effect_id: u64,
    param_index: u32,
    value: f64,
) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.set_parameter_value(param_index, value)?;
            Ok(format!("Set VST3 parameter {} = {}", param_index, value))
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

// ============================================================================
// M7: VST3 Editor Functions - Desktop only (not available on iOS)
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Check if a VST3 plugin has an editor GUI
pub fn vst3_has_editor(effect_id: u64) -> Result<bool, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.has_editor())
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Open a VST3 plugin editor (creates IPlugView)
pub fn vst3_open_editor(effect_id: u64) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            vst3.open_editor()?;
            Ok(String::new()) // Empty string indicates success
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Close a VST3 plugin editor
pub fn vst3_close_editor(effect_id: u64) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            vst3.close_editor();
            Ok(())
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get VST3 editor size (returns "width,height")
pub fn vst3_get_editor_size(effect_id: u64) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            let (width, height) = vst3.get_editor_size()?;
            Ok(format!("{},{}", width, height))
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Attach VST3 editor to a parent window
///
/// IMPORTANT: This function releases all locks before calling attach_editor
/// to avoid deadlocks - plugins may call back into our code during attached().
pub fn vst3_attach_editor(
    effect_id: u64,
    parent_ptr: *mut std::os::raw::c_void,
) -> Result<String, String> {
    use crate::effects::EffectType;
    use crate::vst3_host::VST3Effect;

    eprintln!("🔧 [API] vst3_attach_editor: effect_id={}, parent_ptr={:?}", effect_id, parent_ptr);

    // Get the VST3 plugin handle while holding locks, then release locks before attach
    let handle: *mut std::os::raw::c_void;

    {
        let graph_mutex = get_audio_graph()?;
        eprintln!("🔧 [API] Got audio graph mutex");

        let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
        eprintln!("🔧 [API] Locked audio graph");

        let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;
        eprintln!("🔧 [API] Locked effect manager, looking for effect {}", effect_id);

        if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
            eprintln!("🔧 [API] Found effect, acquiring lock");
            let effect = effect_arc.lock().map_err(|e| e.to_string())?;
            eprintln!("🔧 [API] Locked effect, checking type");

            if let EffectType::VST3(vst3) = &*effect {
                // Get the raw handle - we'll call attach_editor outside the lock
                handle = vst3.get_handle();
                eprintln!("🔧 [API] Got VST3 handle: {:?}", handle);
            } else {
                return Err(format!("Effect {} is not a VST3 plugin", effect_id));
            }
        } else {
            return Err(format!("Effect {} not found", effect_id));
        }
        // All locks are released here when scope ends
    }

    eprintln!("🔧 [API] Locks released, calling attach_editor without locks held");

    // Call attach_editor without holding any locks
    // This is safe because:
    // 1. The handle is valid as long as the plugin is loaded
    // 2. Plugins may call back during attached() and need to acquire locks
    VST3Effect::attach_editor_raw(handle, parent_ptr)?;

    eprintln!("🔧 [API] attach_editor returned successfully");
    Ok(String::new()) // Empty string indicates success
}

#[cfg(not(target_os = "ios"))]
/// Scan a directory for VST3 plugins (returns list of plugin paths)
pub fn scan_vst3_plugins(directory_path: &str) -> Result<String, String> {
    use crate::vst3_host;

    match vst3_host::scan_directory(directory_path) {
        Ok(plugins) => {
            let plugin_list: Vec<String> = plugins
                .iter()
                .map(|info| format!("{}|{}", info.name_str(), info.file_path_str()))
                .collect();
            Ok(plugin_list.join("\n"))
        }
        Err(e) => Err(format!("Failed to scan VST3 plugins: {}", e)),
    }
}

#[cfg(not(target_os = "ios"))]
/// Scan standard system locations for VST3 plugins
pub fn scan_vst3_plugins_standard() -> Result<String, String> {
    use crate::vst3_host;

    eprintln!("🔍 [Rust API] Starting VST3 standard location scan...");

    match vst3_host::scan_standard_locations() {
        Ok(plugins) => {
            eprintln!("✅ [Rust API] Scan returned {} plugins", plugins.len());

            for (i, info) in plugins.iter().enumerate() {
                let plugin_type = if info.is_instrument {
                    "instrument"
                } else if info.is_effect {
                    "effect"
                } else {
                    "unknown"
                };
                eprintln!(
                    "  Plugin {}: {} at {} [{}]",
                    i + 1,
                    info.name_str(),
                    info.file_path_str(),
                    plugin_type
                );
            }

            // Serialize with type information: name|path|vendor|is_instrument|is_effect
            let plugin_list: Vec<String> = plugins
                .iter()
                .map(|info| {
                    format!(
                        "{}|{}|{}|{}|{}",
                        info.name_str(),
                        info.file_path_str(),
                        info.vendor_str(),
                        if info.is_instrument { "1" } else { "0" },
                        if info.is_effect { "1" } else { "0" }
                    )
                })
                .collect();

            let result = plugin_list.join("\n");
            eprintln!("📦 [Rust API] Returning string: {} bytes", result.len());
            Ok(result)
        }
        Err(e) => {
            eprintln!("❌ [Rust API] Scan failed: {}", e);
            Err(format!("Failed to scan VST3 plugins: {}", e))
        }
    }
}

// ============================================================================
// VST3 MIDI Functions
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Send a MIDI note on event to a VST3 plugin
///
/// event_type: 0 = note on, 1 = note off
/// channel: MIDI channel (0-15)
/// note: MIDI note number (0-127)
/// velocity: MIDI velocity (0-127)
pub fn vst3_send_midi_note(
    effect_id: u64,
    event_type: i32,
    channel: i32,
    note: i32,
    velocity: i32,
) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.process_midi_event(event_type, channel, note, velocity, 0)?;
            eprintln!("🎹 [API] Sent MIDI event to VST3 {}: type={} ch={} note={} vel={}",
                     effect_id, event_type, channel, note, velocity);
            Ok(())
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(target_os = "ios")]
pub fn vst3_send_midi_note(
    _effect_id: u64,
    _event_type: i32,
    _channel: i32,
    _note: i32,
    _velocity: i32,
) -> Result<(), String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

// ============================================================================
// VST3 State Functions (for project save/load)
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Get a VST3 plugin's state as a binary blob
/// Returns base64-encoded state data
pub fn get_vst3_state(effect_id: u64) -> Result<Vec<u8>, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &*effect {
            vst3.get_state()
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(not(target_os = "ios"))]
/// Set a VST3 plugin's state from a binary blob
pub fn set_vst3_state(effect_id: u64, data: &[u8]) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock().map_err(|e| e.to_string())?;

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.set_state(data)
        } else {
            Err(format!("Effect {} is not a VST3 plugin", effect_id))
        }
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

#[cfg(target_os = "ios")]
pub fn get_vst3_state(_effect_id: u64) -> Result<Vec<u8>, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn set_vst3_state(_effect_id: u64, _data: &[u8]) -> Result<(), String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

// ============================================================================
// iOS stub functions for VST3 (return "not supported" errors)
// ============================================================================

#[cfg(target_os = "ios")]
pub fn add_vst3_effect_to_track(_track_id: u64, _plugin_path: &str) -> Result<u64, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn get_vst3_parameter_count(_effect_id: u64) -> Result<u32, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn get_vst3_parameter_info(_effect_id: u64, _param_index: u32) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn get_vst3_parameter_value(_effect_id: u64, _param_index: u32) -> Result<f64, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn set_vst3_parameter_value(
    _effect_id: u64,
    _param_index: u32,
    _value: f64,
) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn vst3_has_editor(_effect_id: u64) -> Result<bool, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn vst3_open_editor(_effect_id: u64) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn vst3_close_editor(_effect_id: u64) -> Result<(), String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn vst3_get_editor_size(_effect_id: u64) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn vst3_attach_editor(
    _effect_id: u64,
    _parent_ptr: *mut std::os::raw::c_void,
) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn scan_vst3_plugins(_directory_path: &str) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn scan_vst3_plugins_standard() -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}
