//! Recording and audio input API functions
//!
//! Functions for audio recording, input device management, and recording state.

use super::helpers::{get_audio_clips, get_audio_graph};
use std::sync::Arc;

// ============================================================================
// AUDIO INPUT DEVICES
// ============================================================================

/// Get list of available audio input devices
pub fn get_audio_input_devices() -> Result<Vec<(String, String, bool)>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
    let devices = input_manager.get_devices();

    // Convert to tuple format: (id, name, is_default)
    let device_list: Vec<(String, String, bool)> = devices
        .into_iter()
        .map(|d| (d.id, d.name, d.is_default))
        .collect();

    Ok(device_list)
}

/// Select an audio input device by index
pub fn set_audio_input_device(device_index: i32) -> Result<String, String> {
    if device_index < 0 {
        return Err("Invalid device index".to_string());
    }

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
    input_manager.select_device(device_index as usize).map_err(|e| e.to_string())?;

    Ok(format!("Selected input device {}", device_index))
}

/// Get list of available audio output devices
pub fn get_audio_output_devices() -> Result<Vec<(String, String, bool)>, String> {
    use crate::audio_graph::AudioGraph;
    Ok(AudioGraph::get_output_devices())
}

/// Get current sample rate
pub fn get_sample_rate() -> u32 {
    use crate::audio_graph::AudioGraph;
    AudioGraph::get_sample_rate()
}

// ============================================================================
// AUDIO INPUT CAPTURE
// ============================================================================

/// Start capturing audio from the selected input device
pub fn start_audio_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;

    // Start capturing with 10 seconds of buffer
    input_manager.start_capture(10.0).map_err(|e| e.to_string())?;

    Ok("Audio input started".to_string())
}

/// Stop capturing audio
pub fn stop_audio_input() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let mut input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
    input_manager.stop_capture().map_err(|e| e.to_string())?;

    Ok("Audio input stopped".to_string())
}

// ============================================================================
// AUDIO RECORDING
// ============================================================================

/// Start recording audio
pub fn start_recording() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Start audio input if not already started
    {
        let mut input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
        if !input_manager.is_capturing() {
            input_manager.start_capture(10.0).map_err(|e| e.to_string())?;
        }
    }

    // CRITICAL: Ensure output stream is running so audio callback processes recording
    // If not playing, we need to start the output stream for metronome and recording
    // Note: play() checks internally if already playing and returns early if so
    eprintln!("🔊 [API] Ensuring output stream is running for recording...");
    graph.play().map_err(|e| e.to_string())?;

    graph.recorder.start_recording()?;

    let state = graph.recorder.get_state();
    Ok(format!("Recording started: {:?}", state))
}

/// Stop recording and return the recorded clip ID
pub fn stop_recording() -> Result<Option<u64>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let clip_option = graph.recorder.stop_recording()?;

    // Stop audio input to prevent buffer overflow
    {
        let mut input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
        if input_manager.is_capturing() {
            eprintln!("🛑 [API] Stopping audio input after recording...");
            input_manager.stop_capture().map_err(|e| e.to_string())?;
        }
    }

    if let Some(clip) = clip_option {
        // Store the recorded clip and add to ALL armed tracks (Ableton-style multi-arm)
        let clip_arc = Arc::new(clip);

        // Find ALL armed audio tracks
        let target_track_ids: Vec<u64> = {
            let mut tm = graph.track_manager.lock().map_err(|e| e.to_string())?;
            let audio_tracks: Vec<_> = tm.get_all_tracks()
                .into_iter()
                .filter(|t| {
                    if let Ok(track) = t.lock() {
                        track.track_type == crate::track::TrackType::Audio
                    } else {
                        false
                    }
                })
                .collect();

            if audio_tracks.is_empty() {
                // No audio tracks exist, create one
                vec![tm.create_track(crate::track::TrackType::Audio, "Audio 1".to_string())]
            } else {
                // Find ALL armed tracks
                let armed_tracks: Vec<u64> = audio_tracks.iter()
                    .filter_map(|t| {
                        if let Ok(track) = t.lock() {
                            if track.armed {
                                Some(track.id)
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    })
                    .collect();

                if armed_tracks.is_empty() {
                    // No armed tracks, use first track
                    if let Some(first_track) = audio_tracks.first() {
                        if let Ok(track) = first_track.lock() {
                            vec![track.id]
                        } else {
                            // Mutex poisoned, create new track
                            vec![tm.create_track(crate::track::TrackType::Audio, "Audio 1".to_string())]
                        }
                    } else {
                        // Should not happen since we checked is_empty, but be safe
                        vec![tm.create_track(crate::track::TrackType::Audio, "Audio 1".to_string())]
                    }
                } else {
                    // Use all armed tracks
                    armed_tracks
                }
            }
        };

        eprintln!("🎙️ [API] Recording will be added to {} track(s): {:?}", target_track_ids.len(), target_track_ids);

        // Add clip to ALL armed tracks at position 0.0
        let mut first_clip_id = None;
        for track_id in &target_track_ids {
            let clip_id = graph.add_clip_to_track(*track_id, clip_arc.clone(), 0.0)
                .ok_or(format!("Failed to add recorded clip to track {}", track_id))?;

            if first_clip_id.is_none() {
                first_clip_id = Some(clip_id);
            }

            eprintln!("✅ [API] Added clip {} to track {}", clip_id, track_id);
        }

        let clip_id = first_clip_id.ok_or("Failed to create any clips")?;

        // Store in AUDIO_CLIPS map with the first clip ID
        let clips_mutex = get_audio_clips()?;
        let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;
        clips_map.insert(clip_id, clip_arc);

        eprintln!("📊 [API] Recorded clip duplicated to {} armed tracks", target_track_ids.len());

        Ok(Some(clip_id))
    } else {
        Ok(None)
    }
}

/// Get current recording state (0=Idle, 1=CountingIn, 2=Recording)
pub fn get_recording_state() -> Result<i32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    use crate::recorder::RecordingState;
    let state = match graph.recorder.get_state() {
        RecordingState::Idle => 0,
        RecordingState::CountingIn => 1,
        RecordingState::Recording => 2,
    };

    Ok(state)
}

/// Get recorded duration in seconds
pub fn get_recorded_duration() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_recorded_duration())
}

/// Get recording waveform preview (downsampled for display)
/// Returns CSV of peak values (0.0-1.0) for UI display
pub fn get_recording_waveform(num_peaks: usize) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let peaks = graph.recorder.get_recording_waveform(num_peaks);
    let csv = peaks.iter()
        .map(|p| format!("{:.3}", p))
        .collect::<Vec<_>>()
        .join(",");

    Ok(csv)
}

/// Set count-in duration in bars
pub fn set_count_in_bars(bars: u32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    graph.recorder.set_count_in_bars(bars);
    Ok(format!("Count-in set to {} bars", bars))
}

/// Get count-in duration in bars
pub fn get_count_in_bars() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_count_in_bars())
}
