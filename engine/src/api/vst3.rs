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
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let mut effect_manager = graph.effect_manager.lock();

    // Get audio settings.
    //
    // C21/C62: maxSamplesPerBlock honours the session's buffer preset (same
    // rule as project reload in `audio_graph/project.rs`). The host never
    // hands a plugin more than 512 frames per call (live MAX_VST3_BLOCK and
    // offline OFFLINE_BLOCK both sub-block), so the floor stays 512.
    let sample_rate = f64::from(crate::audio_file::TARGET_SAMPLE_RATE);
    let block_size = graph.preferred_buffer_size.lock().samples().max(512) as i32;

    // Load VST3 plugin
    let mut vst3_effect = VST3Effect::new(plugin_path, sample_rate, block_size)
        .map_err(|e| format!("Failed to load VST3 plugin: {e}"))?;

    // Initialize and activate the plugin for audio processing
    vst3_effect
        .initialize()
        .map_err(|e| format!("Failed to initialize VST3 plugin: {e}"))?;

    let effect = EffectType::VST3(vst3_effect);

    // Add effect to effect manager
    let effect_id = effect_manager.create_effect(effect);

    // Add effect to track's FX chain
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock();
        track.fx_chain.push(effect_id);
        eprintln!(
            "🎛️ [API] Added VST3 plugin from {plugin_path} (ID: {effect_id}) to track {track_id}"
        );
        Ok(effect_id)
    } else {
        Err(format!("Track {track_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get the number of parameters in a VST3 plugin
pub fn get_vst3_parameter_count(effect_id: u64) -> Result<u32, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.get_parameter_count() as u32)
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get information about a VST3 parameter (returns "name,min,max,default")
pub fn get_vst3_parameter_info(effect_id: u64, param_index: u32) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            let info = vst3.get_parameter_info(param_index as i32)?;
            // VST3 parameters are normalized 0.0-1.0
            Ok(format!("{},0.0,1.0,0.5", info.title_str()))
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get a VST3 parameter value
pub fn get_vst3_parameter_value(effect_id: u64, param_index: u32) -> Result<f64, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.get_parameter_value(param_index))
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
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
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.set_parameter_value(param_index, value)?;
            Ok(format!("Set VST3 parameter {param_index} = {value}"))
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
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
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            Ok(vst3.has_editor())
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Open a VST3 plugin editor (creates `IPlugView`)
pub fn vst3_open_editor(effect_id: u64) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            vst3.open_editor()?;
            Ok(String::new()) // Empty string indicates success
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Close a VST3 plugin editor
pub fn vst3_close_editor(effect_id: u64) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            vst3.close_editor();
            Ok(())
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Get VST3 editor size (returns "width,height")
pub fn vst3_get_editor_size(effect_id: u64) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            let (width, height) = vst3.get_editor_size()?;
            Ok(format!("{width},{height}"))
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Attach VST3 editor to a parent window.
///
/// Thread-safety: we take a cheap `Clone` of the `VST3Effect` (which shares the
/// same underlying per-plugin `Arc<Mutex<VST3Plugin>>`), then **drop the graph
/// and effect-manager locks** before attaching — the plugin may call back into
/// our host during `attached()`, and those callbacks must be free to take the
/// graph locks. The attach itself goes through the *locked* `attach_editor`,
/// which acquires the same per-plugin mutex the audio thread's `process_block`
/// holds. That serialization is the fix for the prior data race: the old path
/// extracted a raw handle and attached lock-free, so editor-open could mutate
/// `editor_view`/`plug_frame`/`parent_window` while the audio thread was calling
/// `process()` on the same instance (crash on editor-open during playback).
pub fn vst3_attach_editor(
    effect_id: u64,
    parent_ptr: *mut std::os::raw::c_void,
) -> Result<String, String> {
    use crate::effects::EffectType;
    use crate::vst3_host::VST3Effect;

    eprintln!("🔧 [API] vst3_attach_editor: effect_id={effect_id}, parent_ptr={parent_ptr:?}");

    // Snapshot a shared-Arc clone of the effect, then release all manager locks.
    let vst3_effect: VST3Effect = {
        let graph_mutex = get_audio_graph()?;
        let graph = graph_mutex.lock();
        let effect_manager = graph.effect_manager.lock();

        if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
            let effect = effect_arc.lock();
            if let EffectType::VST3(vst3) = &*effect {
                vst3.clone()
            } else {
                return Err(format!("Effect {effect_id} is not a VST3 plugin"));
            }
        } else {
            return Err(format!("Effect {effect_id} not found"));
        }
        // graph / effect_manager / effect locks all released here.
    };

    eprintln!("🔧 [API] Manager locks released; attaching via locked per-plugin path");

    // Locks only the shared per-plugin mutex (same one process_block holds), so
    // the attach can no longer race concurrent audio processing of this plugin.
    vst3_effect.attach_editor(parent_ptr)?;

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
        Err(e) => Err(format!("Failed to scan VST3 plugins: {e}")),
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
            eprintln!("❌ [Rust API] Scan failed: {e}");
            Err(format!("Failed to scan VST3 plugins: {e}"))
        }
    }
}

// ============================================================================
// VST3 MIDI Functions
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Send a MIDI note on event to a VST3 plugin
///
/// `event_type`: 0 = note on, 1 = note off
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
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.process_midi_event(event_type, channel, note, velocity, 0)?;
            eprintln!("🎹 [API] Sent MIDI event to VST3 {effect_id}: type={event_type} ch={channel} note={note} vel={velocity}");
            Ok(())
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
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
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            vst3.get_state()
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Set a VST3 plugin's state from a binary blob
pub fn set_vst3_state(effect_id: u64, data: &[u8]) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.set_state(data)
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
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
// VST3 Preset Enumeration (via IUnitInfo)
// ============================================================================

#[cfg(not(target_os = "ios"))]
/// Get presets for a VST3 plugin as JSON
/// Returns JSON array: [{"listId":0,"name":"Factory","presets":["Init","Warm Pad",...]}, ...]
pub fn get_vst3_presets(effect_id: u64) -> Result<String, String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            let list_count = vst3.get_program_list_count();
            if list_count <= 0 {
                return Ok("[]".to_string());
            }

            let mut lists = Vec::new();
            for i in 0..list_count {
                if let Ok((list_id, list_name, program_count)) = vst3.get_program_list_info(i) {
                    let mut presets = Vec::new();
                    for p in 0..program_count {
                        if let Ok(name) = vst3.get_program_name(list_id, p) {
                            presets.push(format!("\"{}\"", name.replace('"', "\\\"")));
                        }
                    }
                    lists.push(format!(
                        "{{\"listId\":{},\"name\":\"{}\",\"programCount\":{},\"presets\":[{}]}}",
                        list_id,
                        list_name.replace('"', "\\\""),
                        program_count,
                        presets.join(",")
                    ));
                }
            }

            Ok(format!("[{}]", lists.join(",")))
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Set the active program (preset) for a VST3 plugin
pub fn set_vst3_program(effect_id: u64, list_id: i32, program_index: i32) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &mut *effect {
            vst3.set_program(list_id, program_index)
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(not(target_os = "ios"))]
/// Set max editor size constraint for a VST3 plugin (for embedded scale-to-fit)
/// Pass 0,0 to unconstrain (floating window mode)
pub fn set_vst3_editor_max_size(effect_id: u64, max_w: i32, max_h: i32) -> Result<(), String> {
    use crate::effects::EffectType;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let effect_manager = graph.effect_manager.lock();

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock();

        if let EffectType::VST3(vst3) = &*effect {
            vst3.set_editor_max_size(max_w, max_h);
            Ok(())
        } else {
            Err(format!("Effect {effect_id} is not a VST3 plugin"))
        }
    } else {
        Err(format!("Effect {effect_id} not found"))
    }
}

#[cfg(target_os = "ios")]
pub fn set_vst3_editor_max_size(_effect_id: u64, _max_w: i32, _max_h: i32) -> Result<(), String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn get_vst3_presets(_effect_id: u64) -> Result<String, String> {
    Err("VST3 plugins are not supported on iOS".to_string())
}

#[cfg(target_os = "ios")]
pub fn set_vst3_program(_effect_id: u64, _list_id: i32, _program_index: i32) -> Result<(), String> {
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
