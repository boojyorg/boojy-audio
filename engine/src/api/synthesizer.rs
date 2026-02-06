//! Per-track synthesizer API functions
//!
//! Functions for managing synthesizers and samplers on MIDI/Sampler tracks.

use std::sync::Arc;
use super::helpers::get_audio_graph;
use crate::audio_file::load_audio_file;
use crate::effects::EffectType;

// ============================================================================
// PER-TRACK SYNTHESIZER API
// ============================================================================

/// Set instrument for a track
/// Returns instrument ID or -1 on error
pub fn set_track_instrument(track_id: u64, _instrument_type: String) -> Result<i64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    let instrument_id = synth_manager.create_synth(track_id);
    println!(
        "✅ Created instrument {instrument_id} for track {track_id}"
    );
    Ok(instrument_id as i64)
}

/// Set synthesizer parameter for a track
pub fn set_synth_parameter(
    track_id: u64,
    param_name: String,
    value: String,
) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    synth_manager.set_parameter(track_id, &param_name, &value);
    Ok(format!(
        "Set {param_name} = {value} for track {track_id}"
    ))
}

/// Get synthesizer parameters for a track
pub fn get_synth_parameters(_track_id: u64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let _graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // TODO: Return actual parameters once implemented
    Ok(String::new())
}

/// Send MIDI note on to track synthesizer and any VST3 instruments
/// Also records the event if MIDI recording is active
pub fn send_track_midi_note_on(track_id: u64, note: u8, velocity: u8) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get current playhead position for timestamping
    let timestamp_samples = graph.get_playhead_samples();

    // Record to MIDI recorder if recording is active
    if let Ok(mut recorder) = graph.midi_recorder.lock() {
        if recorder.is_recording() {
            use crate::midi::{MidiEvent, MidiEventType};
            let event = MidiEvent {
                event_type: MidiEventType::NoteOn { note, velocity },
                timestamp_samples,
            };
            recorder.record_event(event);
        }
    }

    // Send to track synthesizer for live playback (built-in synth)
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
    synth_manager.note_on(track_id, note, velocity);

    // Also send to VST3 instruments in the track's FX chain
    // Get the track's FX chain and send MIDI to any VST3 plugins
    let fx_chain: Vec<u64> = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let track = track_arc.lock().map_err(|e| e.to_string())?;
            track.fx_chain.clone()
        } else {
            Vec::new()
        }
    };

    // Send MIDI to VST3 plugins in the FX chain
    if !fx_chain.is_empty() {
        let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;
        for effect_id in fx_chain {
            if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
                if let Ok(mut effect) = effect_arc.lock() {
                    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                    if let EffectType::VST3(ref mut vst3) = *effect {
                        // event_type 0 = note on
                        if let Err(e) = vst3.process_midi_event(0, 0, i32::from(note), i32::from(velocity), 0) {
                            eprintln!("⚠️ Failed to send MIDI to VST3 {effect_id}: {e}");
                        }
                    }
                }
            }
        }
    }

    Ok(format!("Track {track_id} note on: {note}"))
}

/// Send MIDI note off to track synthesizer and any VST3 instruments
/// Also records the event if MIDI recording is active
pub fn send_track_midi_note_off(track_id: u64, note: u8, velocity: u8) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Get current playhead position for timestamping
    let timestamp_samples = graph.get_playhead_samples();

    // Record to MIDI recorder if recording is active
    if let Ok(mut recorder) = graph.midi_recorder.lock() {
        if recorder.is_recording() {
            use crate::midi::{MidiEvent, MidiEventType};
            let event = MidiEvent {
                event_type: MidiEventType::NoteOff { note, velocity },
                timestamp_samples,
            };
            recorder.record_event(event);
        }
    }

    // Send to track synthesizer for live playback (built-in synth)
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;
    synth_manager.note_off(track_id, note);

    // Also send to VST3 instruments in the track's FX chain
    let fx_chain: Vec<u64> = {
        let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
        if let Some(track_arc) = track_manager.get_track(track_id) {
            let track = track_arc.lock().map_err(|e| e.to_string())?;
            track.fx_chain.clone()
        } else {
            Vec::new()
        }
    };

    // Send MIDI to VST3 plugins in the FX chain
    if !fx_chain.is_empty() {
        let effect_manager = graph.effect_manager.lock().map_err(|e| e.to_string())?;
        for effect_id in fx_chain {
            if let Some(effect_arc) = effect_manager.get_effect(effect_id) {
                if let Ok(mut effect) = effect_arc.lock() {
                    #[cfg(all(feature = "vst3", not(target_os = "ios")))]
                    if let EffectType::VST3(ref mut vst3) = *effect {
                        // event_type 1 = note off
                        if let Err(e) = vst3.process_midi_event(1, 0, i32::from(note), i32::from(velocity), 0) {
                            eprintln!("⚠️ Failed to send MIDI to VST3 {effect_id}: {e}");
                        }
                    }
                }
            }
        }
    }

    Ok(format!("Track {track_id} note off: {note}"))
}

// ============================================================================
// SAMPLER API
// ============================================================================

/// Create a sampler instrument for a track
/// Returns instrument ID or -1 on error
pub fn create_sampler_for_track(track_id: u64) -> Result<i64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    let instrument_id = synth_manager.create_sampler(track_id);
    println!("✅ Created sampler for track {track_id}");
    Ok(instrument_id as i64)
}

/// Load a sample file into a sampler track
/// `root_note`: MIDI note that plays sample at original pitch (default 60 = C4)
pub fn load_sample_for_track(track_id: u64, path: String, root_note: u8) -> Result<String, String> {
    // Load the audio file
    let audio_clip = load_audio_file(&path)
        .map_err(|e| format!("Failed to load sample '{path}': {e}"))?;

    let duration = audio_clip.duration_seconds;
    let clip_arc = Arc::new(audio_clip);

    // Get the audio graph and load into sampler
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    if synth_manager.load_sample(track_id, clip_arc, root_note) {
        Ok(format!(
            "Loaded sample '{path}' ({duration:.2}s) to track {track_id} with root note {root_note}"
        ))
    } else {
        Err(format!("Track {track_id} is not a sampler track"))
    }
}

/// Set sampler parameter for a track (`root_note`, `attack_ms`, `release_ms`)
pub fn set_sampler_parameter(
    track_id: u64,
    param_name: String,
    value: String,
) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let mut synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    // Check if this is a sampler track
    if !synth_manager.has_sampler(track_id) {
        return Err(format!("Track {track_id} is not a sampler track"));
    }

    synth_manager.set_parameter(track_id, &param_name, &value);
    Ok(format!(
        "Set sampler {param_name} = {value} for track {track_id}"
    ))
}

/// Check if a track has a sampler instrument
pub fn is_sampler_track(track_id: u64) -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    let synth_manager = graph.track_synth_manager.lock().map_err(|e| e.to_string())?;

    Ok(synth_manager.has_sampler(track_id))
}
