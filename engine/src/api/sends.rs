//! Send/return bus management API functions

use super::helpers::{encode_csv_field, get_audio_graph};
use crate::effects::{Chorus, Compressor, Delay, EffectType, Limiter, ParametricEQ, Reverb};
use crate::track::{Send, TrackId, TrackType};

/// Default send level in dB when creating a new send (-20 dB ≈ 10% linear)
pub const DEFAULT_SEND_DB: f32 = -20.0;

/// Convert dB to linear gain
pub fn db_to_linear(db: f32) -> f32 {
    if db <= -96.0 {
        0.0
    } else {
        10_f32.powf(db / 20.0)
    }
}

/// Convert linear gain to dB
pub fn linear_to_db(linear: f32) -> f32 {
    if linear <= 0.0 {
        -96.0
    } else {
        20.0 * linear.log10()
    }
}

fn effect_type_name(effect: &EffectType) -> Option<&'static str> {
    match effect {
        EffectType::EQ(_) => Some("eq"),
        EffectType::Compressor(_) => Some("compressor"),
        EffectType::Reverb(_) => Some("reverb"),
        EffectType::Delay(_) => Some("delay"),
        EffectType::Chorus(_) => Some("chorus"),
        EffectType::Limiter(_) => Some("limiter"),
        #[cfg(all(feature = "vst3", not(target_os = "ios")))]
        EffectType::VST3(_) => None,
    }
}

fn create_effect_with_full_wet(effect_type: &str) -> Result<EffectType, String> {
    let effect = match effect_type.to_lowercase().as_str() {
        // EQ has no wet/dry — it processes in series and is inherently "full wet".
        "eq" => EffectType::EQ(ParametricEQ::new()),
        "compressor" => {
            let mut comp = Compressor::new();
            comp.wet_dry_mix = 1.0;
            comp.update_coefficients();
            EffectType::Compressor(comp)
        }
        "reverb" => {
            let mut rev = Reverb::new();
            rev.wet_dry_mix = 1.0;
            EffectType::Reverb(rev)
        }
        "delay" => {
            let mut dly = Delay::new();
            dly.wet_dry_mix = 1.0;
            EffectType::Delay(dly)
        }
        "chorus" => {
            let mut chr = Chorus::new();
            chr.wet_dry_mix = 1.0;
            EffectType::Chorus(chr)
        }
        "limiter" => {
            let mut lim = Limiter::new();
            lim.wet_dry_mix = 1.0;
            lim.update_coefficients();
            EffectType::Limiter(lim)
        }
        _ => return Err(format!("Unknown effect type: {effect_type}")),
    };
    Ok(effect)
}

fn default_return_name(effect_type: &str) -> String {
    match effect_type.to_lowercase().as_str() {
        "eq" => "EQ".to_string(),
        "compressor" => "Compressor".to_string(),
        "reverb" => "Reverb".to_string(),
        "delay" => "Delay".to_string(),
        "chorus" => "Chorus".to_string(),
        "limiter" => "Limiter".to_string(),
        other => {
            let mut chars = other.chars();
            match chars.next() {
                None => "Return".to_string(),
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
            }
        }
    }
}

fn primary_effect_type_for_return(
    effect_manager: &crate::effects::EffectManager,
    fx_chain: &[u64],
) -> Option<String> {
    fx_chain.first().and_then(|effect_id| {
        effect_manager
            .get_effect(*effect_id)
            .and_then(|effect_arc| {
                let effect = effect_arc.lock();
                effect_type_name(&effect).map(str::to_string)
            })
    })
}

/// Find an existing return track that hosts the given built-in effect type.
pub fn find_return_by_effect_type(effect_type: &str) -> Result<Option<TrackId>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let effect_manager = graph.effect_manager.lock();
    let normalized = effect_type.to_lowercase();

    // Snapshot the (id, type, fx_chain) of every track in a short scope so we
    // can inspect each candidate Return without holding any Track lock. Looking
    // up the effect via primary_effect_type_for_return only touches the effect
    // manager, never re-enters TrackManager, so it stays deadlock-free.
    let snapshots: Vec<(TrackId, TrackType, Vec<u64>)> = track_manager
        .get_all_tracks()
        .iter()
        .map(|track_arc| {
            let track = track_arc.lock();
            (track.id, track.track_type, track.fx_chain.clone())
        })
        .collect();

    for (id, track_type, fx_chain) in snapshots {
        if track_type != TrackType::Return {
            continue;
        }
        if primary_effect_type_for_return(&effect_manager, &fx_chain)
            .is_some_and(|name| name == normalized)
        {
            return Ok(Some(id));
        }
    }

    Ok(None)
}

/// Create a return track with a built-in effect at 100% wet.
pub fn create_return_with_effect(
    effect_type: &str,
    name: Option<String>,
) -> Result<TrackId, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let mut track_manager = graph.track_manager.lock();
    let mut effect_manager = graph.effect_manager.lock();

    let display_name = name.unwrap_or_else(|| default_return_name(effect_type));
    let return_id = track_manager.create_track(TrackType::Return, display_name);

    let effect = create_effect_with_full_wet(effect_type)?;
    let effect_id = effect_manager.create_effect(effect);

    if let Some(track_arc) = track_manager.get_track(return_id) {
        let mut track = track_arc.lock();
        track.fx_chain.push(effect_id);
        track.timeline_visible = false;
        eprintln!("🔊 [API] Created return track {return_id} with {effect_type} effect (100% wet)");
        Ok(return_id)
    } else {
        Err(format!("Failed to create return track for {effect_type}"))
    }
}

fn upsert_send(track: &mut crate::track::Track, return_id: TrackId, amount_linear: f32) {
    if let Some(send) = track
        .sends
        .iter_mut()
        .find(|s| s.target_track_id == return_id)
    {
        send.amount = amount_linear;
    } else {
        track.sends.push(Send {
            target_track_id: return_id,
            amount: amount_linear,
            pre_fader: false,
        });
    }
}

/// Add a send from a source track to a return track.
pub fn add_send(
    source_track_id: TrackId,
    return_track_id: TrackId,
    amount_db: f32,
) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if track_manager
        .get_track(return_track_id)
        .is_none_or(|t| t.lock().track_type != TrackType::Return)
    {
        return Err(format!("Return track {return_track_id} not found"));
    }

    if let Some(track_arc) = track_manager.get_track(source_track_id) {
        let mut track = track_arc.lock();
        if matches!(track.track_type, TrackType::Master | TrackType::Return) {
            return Err(format!("Track {source_track_id} cannot send to a return"));
        }

        let amount_linear = db_to_linear(amount_db);
        upsert_send(&mut track, return_track_id, amount_linear);
        Ok(format!(
            "Added send from track {source_track_id} to return {return_track_id} at {amount_db:.2} dB"
        ))
    } else {
        Err(format!("Track {source_track_id} not found"))
    }
}

/// Create or reuse a shared return for an effect type and add a send at the default level.
pub fn add_shared_send(source_track_id: TrackId, effect_type: &str) -> Result<String, String> {
    let return_id = match find_return_by_effect_type(effect_type)? {
        Some(id) => id,
        None => create_return_with_effect(effect_type, None)?,
    };
    add_send(source_track_id, return_id, DEFAULT_SEND_DB)?;
    Ok(format!("{return_id},{DEFAULT_SEND_DB:.2}"))
}

/// Set the send amount from a source track to a return track (dB).
pub fn set_send_amount(
    source_track_id: TrackId,
    return_track_id: TrackId,
    amount_db: f32,
) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(source_track_id) {
        let mut track = track_arc.lock();
        let amount_linear = db_to_linear(amount_db);
        if let Some(send) = track
            .sends
            .iter_mut()
            .find(|s| s.target_track_id == return_track_id)
        {
            send.amount = amount_linear;
            Ok(format!(
                "Send from track {source_track_id} to return {return_track_id} set to {amount_db:.2} dB"
            ))
        } else {
            Err(format!(
                "No send from track {source_track_id} to return {return_track_id}"
            ))
        }
    } else {
        Err(format!("Track {source_track_id} not found"))
    }
}

/// Remove a send from a source track to a return track.
pub fn remove_send(source_track_id: TrackId, return_track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    if let Some(track_arc) = track_manager.get_track(source_track_id) {
        let mut track = track_arc.lock();
        if let Some(pos) = track
            .sends
            .iter()
            .position(|s| s.target_track_id == return_track_id)
        {
            track.sends.remove(pos);
            Ok(format!(
                "Removed send from track {source_track_id} to return {return_track_id}"
            ))
        } else {
            Err(format!(
                "No send from track {source_track_id} to return {return_track_id}"
            ))
        }
    } else {
        Err(format!("Track {source_track_id} not found"))
    }
}

/// Remove a return track and all sends that target it.
pub fn remove_return(return_track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let mut track_manager = graph.track_manager.lock();
    let mut effect_manager = graph.effect_manager.lock();

    let return_arc = track_manager
        .get_track(return_track_id)
        .ok_or_else(|| format!("Return track {return_track_id} not found"))?;
    if return_arc.lock().track_type != TrackType::Return {
        return Err(format!("Track {return_track_id} is not a return track"));
    }

    let effect_ids: Vec<u64> = return_arc.lock().fx_chain.clone();
    for effect_id in effect_ids {
        effect_manager.remove_effect(effect_id);
    }

    for track_arc in track_manager.get_all_tracks() {
        let mut track = track_arc.lock();
        track
            .sends
            .retain(|send| send.target_track_id != return_track_id);
    }

    if !track_manager.remove_track(return_track_id) {
        return Err(format!("Failed to remove return track {return_track_id}"));
    }

    Ok(format!("Removed return track {return_track_id}"))
}

/// Get sends for a track as CSV: "return_id,amount_db,return_name;..."
pub fn get_track_sends(track_id: TrackId) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    let Some(source_arc) = track_manager.get_track(track_id) else {
        return Err(format!("Track {track_id} not found"));
    };
    // Snapshot the sends and drop the source-track lock before resolving return
    // names: TrackManager::get_track walks every track and locks each one to
    // check the id, so if we held the source lock here it would deadlock the
    // moment the iterator hit the source track. parking_lot::Mutex is not
    // re-entrant.
    let sends: Vec<(TrackId, f32)> = {
        let source = source_arc.lock();
        source
            .sends
            .iter()
            .map(|s| (s.target_track_id, s.amount))
            .collect()
    };

    let entries: Vec<String> = sends
        .iter()
        .filter_map(|(target_id, amount)| {
            track_manager.get_track(*target_id).map(|return_arc| {
                let return_track = return_arc.lock();
                format!(
                    "{},{:.2},{}",
                    target_id,
                    linear_to_db(*amount),
                    // Encoded: a `,`/`;` in the name would corrupt fields or
                    // split entries (C34). Dart decodes via decodeCsvField.
                    encode_csv_field(&return_track.name)
                )
            })
        })
        .collect();

    Ok(entries.join(";"))
}

/// Get all return tracks as CSV: "return_id,name,effect_type;..."
pub fn get_all_returns() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let effect_manager = graph.effect_manager.lock();

    let entries: Vec<String> = track_manager
        .get_all_tracks()
        .iter()
        .filter_map(|track_arc| {
            let track = track_arc.lock();
            if track.track_type != TrackType::Return {
                return None;
            }
            let effect_type = primary_effect_type_for_return(&effect_manager, &track.fx_chain)
                .unwrap_or_else(|| "unknown".to_string());
            Some(format!(
                "{},{},{}",
                track.id,
                // Encoded for the same reason as get_track_sends (C34).
                encode_csv_field(&track.name),
                effect_type
            ))
        })
        .collect();

    Ok(entries.join(";"))
}

/// Count how many tracks send to a return track.
pub fn count_sends_to_return(return_track_id: TrackId) -> Result<usize, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();

    let count = track_manager
        .get_all_tracks()
        .iter()
        .filter(|track_arc| {
            track_arc
                .lock()
                .sends
                .iter()
                .any(|send| send.target_track_id == return_track_id)
        })
        .count();

    Ok(count)
}

/// Get whether the master track row is visible in the timeline.
pub fn get_master_timeline_visible() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let master_arc = track_manager.get_master_track();
    let master = master_arc.lock();
    Ok(master.timeline_visible)
}

/// Explicitly show or hide the master timeline row.
pub fn set_master_timeline_visible(visible: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let master_arc = track_manager.get_master_track();
    let mut master = master_arc.lock();
    master.timeline_visible = visible;
    Ok(format!("Master timeline row visible: {visible}"))
}

/// Sync master timeline visibility with automation presence.
pub fn sync_master_timeline_visibility() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let track_manager = graph.track_manager.lock();
    let master_arc = track_manager.get_master_track();
    let mut master = master_arc.lock();
    master.timeline_visible = master.has_volume_automation();
    Ok(master.timeline_visible)
}
