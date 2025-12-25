//! Effect management API functions
//!
//! Functions for managing audio effects (EQ, compressor, reverb, etc.) on tracks.

use super::helpers::get_audio_graph;
use crate::track::TrackId;

// ============================================================================
// EFFECT MANAGEMENT
// ============================================================================

/// Add an effect to a track's FX chain
pub fn add_effect_to_track(track_id: TrackId, effect_type_str: &str) -> Result<u64, String> {
    use crate::effects::*;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let mut effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    // Create the effect
    let effect = match effect_type_str.to_lowercase().as_str() {
        "eq" => EffectType::EQ(ParametricEQ::new()),
        "compressor" => EffectType::Compressor(Compressor::new()),
        "reverb" => EffectType::Reverb(Reverb::new()),
        "delay" => EffectType::Delay(Delay::new()),
        "chorus" => EffectType::Chorus(Chorus::new()),
        "limiter" => EffectType::Limiter(Limiter::new()),
        _ => return Err(format!("Unknown effect type: {}", effect_type_str)),
    };

    // Add effect to effect manager
    let effect_id = effect_manager.create_effect(effect);

    // Add effect to track's FX chain
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        track.fx_chain.push(effect_id);
        eprintln!(
            "🎛️ [API] Added {} effect (ID: {}) to track {}",
            effect_type_str, effect_id, track_id
        );
        Ok(effect_id)
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Remove an effect from a track's FX chain
pub fn remove_effect_from_track(track_id: TrackId, effect_id: u64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
    let mut effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    // Remove from track's FX chain
    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;
        if let Some(pos) = track.fx_chain.iter().position(|&id| id == effect_id) {
            track.fx_chain.remove(pos);
            // Remove from effect manager
            effect_manager.remove_effect(effect_id);
            eprintln!(
                "🗑️ [API] Removed effect {} from track {}",
                effect_id, track_id
            );
            Ok(format!("Effect {} removed from track {}", effect_id, track_id))
        } else {
            Err(format!(
                "Effect {} not found in track {}'s FX chain",
                effect_id, track_id
            ))
        }
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Get all effects on a track (returns CSV: "effect_id,effect_id,...")
pub fn get_track_effects(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let track = track_arc.lock().map_err(|e| e.to_string())?;
        let ids: Vec<String> = track.fx_chain.iter().map(|id| id.to_string()).collect();
        Ok(ids.join(","))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Get effect info (returns JSON-like string with type and parameters)
pub fn get_effect_info(effect_id: u64) -> Result<String, String> {
    use crate::effects::*;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    // Get bypass state
    let bypassed = effect_manager.is_bypassed(effect_id);
    let bypass_str = if bypassed { "1" } else { "0" };

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let effect = effect_arc.lock().map_err(|e| e.to_string())?;

        let info = match &*effect {
            EffectType::EQ(eq) => format!(
                "type:eq,bypassed:{},low_freq:{},low_gain:{},mid1_freq:{},mid1_gain:{},mid1_q:{},mid2_freq:{},mid2_gain:{},mid2_q:{},high_freq:{},high_gain:{}",
                bypass_str, eq.low_freq, eq.low_gain_db, eq.mid1_freq, eq.mid1_gain_db, eq.mid1_q,
                eq.mid2_freq, eq.mid2_gain_db, eq.mid2_q, eq.high_freq, eq.high_gain_db
            ),
            EffectType::Compressor(comp) => format!(
                "type:compressor,bypassed:{},threshold:{},ratio:{},attack:{},release:{},makeup:{}",
                bypass_str, comp.threshold_db, comp.ratio, comp.attack_ms, comp.release_ms, comp.makeup_gain_db
            ),
            EffectType::Reverb(rev) => format!(
                "type:reverb,bypassed:{},room_size:{},damping:{},wet_dry:{}",
                bypass_str, rev.room_size, rev.damping, rev.wet_dry_mix
            ),
            EffectType::Delay(delay) => format!(
                "type:delay,bypassed:{},time:{},feedback:{},wet_dry:{}",
                bypass_str, delay.delay_time_ms, delay.feedback, delay.wet_dry_mix
            ),
            EffectType::Chorus(chorus) => format!(
                "type:chorus,bypassed:{},rate:{},depth:{},wet_dry:{}",
                bypass_str, chorus.rate_hz, chorus.depth, chorus.wet_dry_mix
            ),
            EffectType::Limiter(lim) => format!(
                "type:limiter,bypassed:{},threshold:{},release:{}",
                bypass_str, lim.threshold_db, lim.release_ms
            ),
            #[cfg(not(target_os = "ios"))]
            EffectType::VST3(vst3) => {
                // Return basic VST3 info
                format!("type:vst3,bypassed:{},name:{}", bypass_str, vst3.name())
            }
        };
        Ok(info)
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

/// Set effect bypass state
pub fn set_effect_bypass(effect_id: u64, bypassed: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if effect_manager.set_bypass(effect_id, bypassed) {
        Ok(format!(
            "Effect {} bypass set to {}",
            effect_id,
            if bypassed { "on" } else { "off" }
        ))
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}

/// Get effect bypass state
pub fn get_effect_bypass(effect_id: u64) -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    effect_manager
        .get_bypass(effect_id)
        .ok_or_else(|| format!("Effect {} not found", effect_id))
}

/// Reorder effects in a track's FX chain
/// Takes a comma-separated list of effect IDs in the desired order
pub fn reorder_track_effects(track_id: u64, effect_ids_csv: &str) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;

    // Parse the effect IDs
    let new_order: Vec<u64> = effect_ids_csv
        .split(',')
        .filter(|s| !s.is_empty())
        .filter_map(|s| s.trim().parse::<u64>().ok())
        .collect();

    if let Some(track_arc) = track_manager.get_track(track_id) {
        let mut track = track_arc.lock().map_err(|e| e.to_string())?;

        // Validate that all IDs in new_order are in the current fx_chain
        for id in &new_order {
            if !track.fx_chain.contains(id) {
                return Err(format!("Effect {} not found in track {}'s FX chain", id, track_id));
            }
        }

        // Validate that all current effects are in the new order
        if new_order.len() != track.fx_chain.len() {
            return Err(format!(
                "Effect count mismatch: expected {} effects, got {}",
                track.fx_chain.len(),
                new_order.len()
            ));
        }

        // Apply the new order
        track.fx_chain = new_order;

        eprintln!(
            "🔄 [API] Reordered effects on track {}: {:?}",
            track_id, track.fx_chain
        );

        Ok(format!("Effects reordered on track {}", track_id))
    } else {
        Err(format!("Track {} not found", track_id))
    }
}

/// Set an effect parameter
pub fn set_effect_parameter(effect_id: u64, param_name: &str, value: f32) -> Result<String, String> {
    use crate::effects::*;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;

    if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
        let mut effect = effect_arc.lock().map_err(|e| e.to_string())?;

        match &mut *effect {
            EffectType::EQ(eq) => match param_name {
                "low_freq" => {
                    eq.low_freq = value;
                    eq.update_coefficients();
                }
                "low_gain" => {
                    eq.low_gain_db = value;
                    eq.update_coefficients();
                }
                "mid1_freq" => {
                    eq.mid1_freq = value;
                    eq.update_coefficients();
                }
                "mid1_gain" => {
                    eq.mid1_gain_db = value;
                    eq.update_coefficients();
                }
                "mid1_q" => {
                    eq.mid1_q = value;
                    eq.update_coefficients();
                }
                "mid2_freq" => {
                    eq.mid2_freq = value;
                    eq.update_coefficients();
                }
                "mid2_gain" => {
                    eq.mid2_gain_db = value;
                    eq.update_coefficients();
                }
                "mid2_q" => {
                    eq.mid2_q = value;
                    eq.update_coefficients();
                }
                "high_freq" => {
                    eq.high_freq = value;
                    eq.update_coefficients();
                }
                "high_gain" => {
                    eq.high_gain_db = value;
                    eq.update_coefficients();
                }
                _ => return Err(format!("Unknown EQ parameter: {}", param_name)),
            },
            EffectType::Compressor(comp) => match param_name {
                "threshold" => {
                    comp.threshold_db = value;
                }
                "ratio" => {
                    comp.ratio = value;
                }
                "attack" => {
                    comp.attack_ms = value;
                    comp.update_coefficients();
                }
                "release" => {
                    comp.release_ms = value;
                    comp.update_coefficients();
                }
                "makeup" => {
                    comp.makeup_gain_db = value;
                }
                _ => return Err(format!("Unknown Compressor parameter: {}", param_name)),
            },
            EffectType::Reverb(rev) => match param_name {
                "room_size" => {
                    rev.room_size = value;
                }
                "damping" => {
                    rev.damping = value;
                }
                "wet_dry" => {
                    rev.wet_dry_mix = value;
                }
                _ => return Err(format!("Unknown Reverb parameter: {}", param_name)),
            },
            EffectType::Delay(delay) => match param_name {
                "time" => {
                    delay.delay_time_ms = value;
                }
                "feedback" => {
                    delay.feedback = value;
                }
                "wet_dry" => {
                    delay.wet_dry_mix = value;
                }
                _ => return Err(format!("Unknown Delay parameter: {}", param_name)),
            },
            EffectType::Chorus(chorus) => match param_name {
                "rate" => {
                    chorus.rate_hz = value;
                }
                "depth" => {
                    chorus.depth = value;
                }
                "wet_dry" => {
                    chorus.wet_dry_mix = value;
                }
                _ => return Err(format!("Unknown Chorus parameter: {}", param_name)),
            },
            EffectType::Limiter(lim) => match param_name {
                "threshold" => {
                    lim.threshold_db = value;
                }
                "release" => {
                    lim.release_ms = value;
                    lim.update_coefficients();
                }
                _ => return Err(format!("Unknown Limiter parameter: {}", param_name)),
            },
            #[cfg(not(target_os = "ios"))]
            EffectType::VST3(vst3) => {
                // VST3 parameters are accessed by index (e.g., "param_0", "param_1")
                if let Some(index_str) = param_name.strip_prefix("param_") {
                    if let Ok(param_index) = index_str.parse::<u32>() {
                        vst3.set_parameter_value(param_index, value as f64)
                            .map_err(|e| format!("Failed to set VST3 parameter: {}", e))?;
                    } else {
                        return Err(format!("Invalid VST3 parameter index: {}", param_name));
                    }
                } else {
                    return Err(format!(
                        "VST3 parameter must be in format 'param_N': {}",
                        param_name
                    ));
                }
            }
        }
        Ok(format!(
            "Set {} = {} on effect {}",
            param_name, value, effect_id
        ))
    } else {
        Err(format!("Effect {} not found", effect_id))
    }
}
