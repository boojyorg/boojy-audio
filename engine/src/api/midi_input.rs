//! MIDI input and recording API functions
//!
//! Functions for MIDI device management, input capture, and MIDI recording.

use super::helpers::get_audio_graph;
use crate::effects::EffectType;
use crate::midi::MidiEventType;
use crate::track::{TrackId, TrackType};
use std::sync::Arc;

// ============================================================================
// MIDI DEVICE MANAGEMENT
// ============================================================================

/// Get list of available MIDI input devices
pub fn get_midi_input_devices() -> Result<Vec<(String, String, bool)>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    let devices = midi_manager.get_devices();

    // Convert to tuple format: (id, name, is_default)
    let device_list: Vec<(String, String, bool)> = devices
        .into_iter()
        .map(|d| (d.id, d.name, d.is_default))
        .collect();

    Ok(device_list)
}

/// Refresh MIDI devices (rescan)
/// Returns success message - devices are fetched fresh each time get_midi_input_devices is called
pub fn refresh_midi_devices() -> Result<String, String> {
    // The device list is fetched fresh each time get_midi_input_devices is called,
    // so this just returns success to satisfy the API contract
    Ok("MIDI devices refreshed".to_string())
}

/// Select a MIDI input device by index
pub fn select_midi_input_device(device_index: i32) -> Result<String, String> {
    if device_index < 0 {
        return Err("Invalid device index".to_string());
    }

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    midi_manager.select_device(device_index as usize).map_err(|e| e.to_string())?;

    Ok(format!("Selected MIDI input device {}", device_index))
}

// ============================================================================
// MIDI INPUT CAPTURE
// ============================================================================

/// Start capturing MIDI input
/// Routes incoming MIDI to:
/// 1. MIDI recorder (if recording)
/// 2. All armed MIDI track synthesizers (for live playback)
/// 3. All VST3 instruments in armed tracks' FX chains
pub fn start_midi_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;

    // Clone all needed Arc references for the callback
    let midi_recorder = graph.midi_recorder.clone();
    let track_manager = graph.track_manager.clone();
    let synth_manager = graph.track_synth_manager.clone();
    let effect_manager = graph.effect_manager.clone();
    let playhead_samples = graph.playhead_samples.clone();

    midi_manager.set_event_callback(move |event| {
        // Override midir timestamp with engine playhead position (correct unit: samples)
        // midir gives microseconds which don't match the engine's sample-based timeline
        use std::sync::atomic::Ordering;
        let current_playhead = playhead_samples.load(Ordering::SeqCst);
        let mut engine_event = event;
        engine_event.timestamp_samples = current_playhead;

        // 1. Record to MIDI recorder if recording
        if let Ok(mut recorder) = midi_recorder.lock() {
            if recorder.is_recording() {
                recorder.record_event(engine_event);
            }
        }

        // 2. Route to all armed MIDI track synthesizers and VST3 instruments
        // Collect armed tracks with their FX chains (MIDI and Sampler tracks can receive MIDI)
        let armed_tracks_with_fx: Vec<(TrackId, Vec<u64>)> = {
            if let Ok(tm) = track_manager.lock() {
                tm.get_all_tracks()
                    .iter()
                    .filter_map(|track_arc| {
                        if let Ok(track) = track_arc.lock() {
                            if (track.track_type == TrackType::Midi || track.track_type == TrackType::Sampler) && track.armed {
                                Some((track.id, track.fx_chain.clone()))
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    })
                    .collect()
            } else {
                vec![]
            }
        };

        // Route to each armed track's synthesizer OR VST3 instruments (not both)
        for (track_id, fx_chain) in armed_tracks_with_fx {
            // Check if track has VST3 plugins - if so, skip built-in synth
            let has_vst3 = !fx_chain.is_empty();

            // Only route to built-in synth if NO VST3 plugins in the chain
            if !has_vst3 {
                if let Ok(mut sm) = synth_manager.lock() {
                    match &engine_event.event_type {
                        MidiEventType::NoteOn { note, velocity } => {
                            sm.note_on(track_id, *note, *velocity);
                        }
                        MidiEventType::NoteOff { note, velocity: _ } => {
                            sm.note_off(track_id, *note);
                        }
                    }
                }
            }

            // Route to VST3 instruments in the track's FX chain
            #[cfg(all(feature = "vst3", not(target_os = "ios")))]
            if has_vst3 {
                if let Ok(em) = effect_manager.lock() {
                    for effect_id in fx_chain {
                        if let Some(effect_arc) = em.get_effect(effect_id) {
                            if let Ok(mut effect) = effect_arc.lock() {
                                if let EffectType::VST3(ref mut vst3) = *effect {
                                    match &engine_event.event_type {
                                        MidiEventType::NoteOn { note, velocity } => {
                                            // event_type 0 = note on
                                            if let Err(e) = vst3.process_midi_event(0, 0, *note as i32, *velocity as i32, 0) {
                                                eprintln!("⚠️ [MIDI] Failed to send note on to VST3 {}: {}", effect_id, e);
                                            }
                                        }
                                        MidiEventType::NoteOff { note, velocity } => {
                                            // event_type 1 = note off
                                            if let Err(e) = vst3.process_midi_event(1, 0, *note as i32, *velocity as i32, 0) {
                                                eprintln!("⚠️ [MIDI] Failed to send note off to VST3 {}: {}", effect_id, e);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    });

    midi_manager.start_capture().map_err(|e| e.to_string())?;

    Ok("MIDI input started".to_string())
}

/// Stop capturing MIDI input
pub fn stop_midi_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_manager = graph.midi_input_manager.lock().map_err(|e| e.to_string())?;
    midi_manager.stop_capture().map_err(|e| e.to_string())?;

    Ok("MIDI input stopped".to_string())
}

// ============================================================================
// MIDI RECORDING
// ============================================================================

/// Start recording MIDI
/// Calculates the recording start position (after count-in) so that
/// MIDI events during count-in are discarded and timestamps are correct.
pub fn start_midi_recording() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Calculate recording start (after count-in), matching audio recorder logic
    let playhead_samples = graph.get_playhead_samples();
    let count_in_bars = graph.recorder.get_count_in_bars();
    let tempo = graph.recorder.get_tempo();
    let time_sig = graph.recorder.get_time_signature();

    let recording_start = if count_in_bars > 0 {
        let count_in_seconds = (count_in_bars as f64) * (time_sig as f64) * 60.0 / tempo;
        let count_in_samples = (count_in_seconds * crate::audio_file::TARGET_SAMPLE_RATE as f64) as u64;
        playhead_samples + count_in_samples
    } else {
        playhead_samples
    };

    let mut midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;
    midi_recorder.set_recording_start(recording_start);
    midi_recorder.start_recording()?;

    eprintln!("🎹 [API] MIDI recording started (recording_start_samples: {}, count_in_bars: {})", recording_start, count_in_bars);
    Ok("MIDI recording started".to_string())
}

/// Stop recording MIDI and return the clip ID
/// Adds the clip to all armed MIDI tracks at the recording start position (after count-in)
pub fn stop_midi_recording() -> Result<Option<u64>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;
    let clip_option = midi_recorder.stop_recording()?;

    if let Some(clip) = clip_option {
        let clip_arc = Arc::new(clip);

        // Place clip at the recording start position (after count-in),
        // matching audio clip placement logic
        let playhead_seconds = graph.recorder.get_recording_start_seconds();

        // Find all armed MIDI/Sampler tracks
        let armed_midi_track_ids: Vec<TrackId> = {
            let track_manager = graph.track_manager.lock().map_err(|e| e.to_string())?;
            track_manager.get_all_tracks()
                .iter()
                .filter_map(|track_arc| {
                    if let Ok(track) = track_arc.lock() {
                        if (track.track_type == TrackType::Midi || track.track_type == TrackType::Sampler) && track.armed {
                            Some(track.id)
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect()
        };

        // If no MIDI/Sampler tracks are armed, add clip to global storage
        // First add clip to global storage to get an ID
        let clip_id = graph.add_midi_clip(clip_arc.clone(), playhead_seconds);

        if armed_midi_track_ids.is_empty() {
            eprintln!("✅ [API] MIDI clip recorded with ID: {} (no armed tracks, added globally)", clip_id);
            return Ok(Some(clip_id));
        }

        // Add clip to each armed MIDI track using the same clip_id
        for track_id in armed_midi_track_ids {
            if let Some(_) = graph.add_midi_clip_to_track(track_id, clip_arc.clone(), playhead_seconds, clip_id) {
                eprintln!("✅ [API] MIDI clip {} added to armed track {}", clip_id, track_id);
            }
        }

        Ok(Some(clip_id))
    } else {
        Ok(None)
    }
}

/// Get current MIDI recording state (0=Idle, 1=Recording)
pub fn get_midi_recording_state() -> Result<i32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;

    use crate::midi_recorder::MidiRecordingState;
    let state = match midi_recorder.get_state() {
        MidiRecordingState::Idle => 0,
        MidiRecordingState::Recording => 1,
    };

    Ok(state)
}

// ============================================================================
// LIVE MIDI RECORDING EVENTS (for real-time UI preview)
// ============================================================================

/// Get live MIDI recording events for real-time UI display
/// Returns CSV: "note,velocity,type,timestamp_samples;..." where type: 0=NoteOff, 1=NoteOn
/// Returns empty string if not recording or no events
pub fn get_midi_recorder_live_events() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let midi_recorder = graph.midi_recorder.lock().map_err(|e| e.to_string())?;

    if !midi_recorder.is_recording() {
        return Ok(String::new());
    }

    let events = midi_recorder.get_events_snapshot();
    if events.is_empty() {
        return Ok(String::new());
    }

    // Build CSV: "note,velocity,type,timestamp_samples;..."
    let mut result = String::with_capacity(events.len() * 20);
    for (i, event) in events.iter().enumerate() {
        if i > 0 {
            result.push(';');
        }
        match &event.event_type {
            MidiEventType::NoteOn { note, velocity } => {
                result.push_str(&format!("{},{},1,{}", note, velocity, event.timestamp_samples));
            }
            MidiEventType::NoteOff { note, velocity } => {
                result.push_str(&format!("{},{},0,{}", note, velocity, event.timestamp_samples));
            }
        }
    }

    Ok(result)
}

// ============================================================================
// LEGACY SYNTH API (deprecated)
// ============================================================================

/// Set synthesizer oscillator type (LEGACY - use set_synth_parameter instead)
pub fn set_synth_oscillator_type(_osc_type: i32) -> Result<String, String> {
    // Legacy API - no-op, use set_synth_parameter for per-track synths
    Ok("Legacy API deprecated - use set_synth_parameter".to_string())
}

/// Set synthesizer master volume (LEGACY - use track volume instead)
pub fn set_synth_volume(_volume: f32) -> Result<String, String> {
    // Legacy API - no-op, use track volume for per-track synths
    Ok("Legacy API deprecated - use track volume".to_string())
}
