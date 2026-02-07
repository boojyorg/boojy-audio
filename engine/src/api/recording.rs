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

    Ok(format!("Selected input device {device_index}"))
}

/// Get list of available audio output devices
pub fn get_audio_output_devices() -> Result<Vec<(String, String, bool)>, String> {
    use crate::audio_graph::AudioGraph;
    Ok(AudioGraph::get_output_devices())
}

/// Set audio output device by name
/// Pass empty string to use system default
pub fn set_audio_output_device(device_name: &str) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let name = if device_name.is_empty() {
        None
    } else {
        Some(device_name.to_string())
    };

    graph.set_output_device(name).map_err(|e| e.to_string())?;

    Ok(format!("Output device set to: {}", if device_name.is_empty() { "System Default" } else { device_name }))
}

/// Get currently selected output device name (empty string = system default)
pub fn get_selected_audio_output_device() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.get_selected_output_device().unwrap_or_default())
}

/// Get current sample rate
pub fn get_sample_rate() -> u32 {
    use crate::audio_graph::AudioGraph;
    AudioGraph::get_sample_rate()
}

// ============================================================================
// AUDIO INPUT METERING
// ============================================================================

/// Get input channel peak level for metering
/// Returns peak amplitude (0.0 to 1.0+) for the specified channel (0=left, 1=right)
pub fn get_input_channel_level(channel: u32) -> Result<f32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
    Ok(input_manager.get_channel_peak(channel))
}

/// Get number of input channels for the current device
pub fn get_input_channel_count() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    let input_manager = graph.input_manager.lock().map_err(|e| e.to_string())?;
    Ok(u32::from(input_manager.get_input_channels()))
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

/// Start recording audio (also enables metronome/count-in for MIDI recording)
///
/// Note: Audio input capture failures are non-fatal - MIDI recording can still proceed.
pub fn start_recording() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    // Capture playhead position BEFORE starting playback
    // This is where the recorded clip will be placed on the timeline
    let playhead_seconds = graph.get_playhead_position();

    // Calculate count-in duration so we know the actual recording start position
    let count_in_bars = graph.recorder.get_count_in_bars();
    let tempo = graph.recorder.get_tempo();
    let time_sig = graph.recorder.get_time_signature();
    let count_in_seconds = if count_in_bars > 0 {
        f64::from(count_in_bars) * f64::from(time_sig) * 60.0 / tempo
    } else {
        0.0
    };

    // Determine recording start position
    let punch_in = graph.recorder.is_punch_in_enabled();
    let recording_start = if punch_in {
        // Punch-in: clip will be placed at the punch-in point
        graph.recorder.get_punch_in_seconds()
    } else {
        // Normal: clip placed at current playhead
        playhead_seconds
    };
    graph.recorder.set_recording_start_seconds(recording_start);

    // Seek back by count-in duration for pre-roll
    if punch_in && count_in_seconds > 0.0 {
        // Punch mode: pre-roll before the punch-in point
        let seek_position = (recording_start - count_in_seconds).max(0.0);
        eprintln!("🔊 [API] Punch pre-roll: seeking to {seek_position:.3}s (punch-in at {recording_start:.3}s, count-in: {count_in_seconds:.3}s)");
        graph.seek(seek_position);
    } else if count_in_seconds > 0.0 {
        // Normal: pre-roll before current playhead
        let seek_position = (playhead_seconds - count_in_seconds).max(0.0);
        eprintln!("🔊 [API] Seeking back for count-in: {playhead_seconds:.3}s → {seek_position:.3}s (count-in: {count_in_seconds:.3}s)");
        graph.seek(seek_position);
    }

    // FIRST: Start playback state (lock-free atomic operation)
    // This must happen before starting audio input to avoid deadlock
    eprintln!("🔊 [API] Setting transport to playing for recording...");
    graph.play().map_err(|e| e.to_string())?;

    // Start the recorder state machine (count-in, etc.)
    graph.recorder.start_recording()?;
    let state = graph.recorder.get_state();

    // NOW try to start audio input (non-fatal if it fails - MIDI recording can still work)
    // We do this AFTER play() to avoid deadlock: the audio callback tries to lock input_manager,
    // and start_capture() calls stream.play() which may wait for the audio callback.
    eprintln!("🎙️  [API] Attempting to acquire input_manager lock...");
    let audio_input_started = {
        let mut input_manager = if let Ok(guard) = graph.input_manager.try_lock() { guard } else {
            eprintln!("⚠️  [API] Could not acquire input_manager lock, skipping audio input");
            return Ok(format!("Recording started (MIDI only, input busy): {state:?}"));
        };

        // Auto-enumerate and select default device if none selected
        if input_manager.get_selected_device_index().is_none() {
            eprintln!("🎙️  [API] No input device selected, auto-selecting default...");
            let _ = input_manager.enumerate_devices(); // This auto-selects default
        }

        if input_manager.get_selected_device_index().is_some() && !input_manager.is_capturing() {
            match input_manager.start_capture(10.0) {
                Ok(()) => {
                    eprintln!("🎙️  [API] Audio input capture started");
                    true
                }
                Err(e) => {
                    eprintln!("⚠️  [API] Audio input capture failed (MIDI recording will still work): {e}");
                    false
                }
            }
        } else if input_manager.is_capturing() {
            true
        } else {
            eprintln!("⚠️  [API] No audio input device available (MIDI recording will still work)");
            false
        }
    };

    let msg = if audio_input_started {
        format!("Recording started (audio + MIDI): {state:?}")
    } else {
        format!("Recording started (MIDI only): {state:?}")
    };
    Ok(msg)
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
        // Find armed audio tracks — only place audio clips on explicitly armed tracks.
        // If no audio tracks are armed, discard the audio clip (MIDI-only recording).
        let armed_tracks: Vec<(u64, u32)> = {
            let tm = graph.track_manager.lock().map_err(|e| e.to_string())?;
            let armed: Vec<(u64, u32)> = tm.get_all_tracks()
                .into_iter()
                .filter_map(|t| {
                    if let Ok(track) = t.lock() {
                        if track.track_type == crate::track::TrackType::Audio && track.armed {
                            Some((track.id, track.input_channel))
                        } else {
                            None
                        }
                    } else {
                        None
                    }
                })
                .collect();
            armed
        };

        // No armed audio tracks — discard audio clip (MIDI-only recording)
        if armed_tracks.is_empty() {
            eprintln!("🎙️ [API] No armed audio tracks — discarding audio clip");
            return Ok(None);
        }

        eprintln!("🎙️ [API] Recording will be added to {} track(s): {:?}", armed_tracks.len(), armed_tracks);

        // Place clip at the position where recording started (after count-in)
        let start_position = graph.recorder.get_recording_start_seconds();
        eprintln!("🎙️ [API] Placing recorded clip at position {start_position:.3}s");

        let stereo_samples = &clip.samples;
        let duration = clip.duration_seconds;
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let mut first_clip_id = None;
        let clips_mutex = get_audio_clips()?;
        let mut clips_map = clips_mutex.lock().map_err(|e| e.to_string())?;

        for (track_id, input_channel) in &armed_tracks {
            // Extract this track's assigned input channel from the stereo recording
            // Channel 0 = left (even indices), Channel 1 = right (odd indices)
            // Create a stereo clip where both channels contain the mono source
            let track_samples: Vec<f32> = if armed_tracks.len() == 1 {
                // Single track: use the full stereo recording as-is
                stereo_samples.clone()
            } else {
                // Multi-track: extract assigned channel and duplicate to stereo
                let channel_offset = *input_channel as usize;
                let frame_count = stereo_samples.len() / 2;
                let mut samples = Vec::with_capacity(frame_count * 2);
                for frame in 0..frame_count {
                    let sample = stereo_samples.get(frame * 2 + channel_offset.min(1))
                        .copied().unwrap_or(0.0);
                    samples.push(sample); // Left
                    samples.push(sample); // Right (same mono source)
                }
                samples
            };

            let track_clip = crate::audio_file::AudioClip {
                samples: track_samples,
                channels: 2,
                sample_rate: crate::audio_file::TARGET_SAMPLE_RATE,
                duration_seconds: duration,
                file_path: format!("recorded_t{track_id}_{timestamp}.wav"),
            };

            let track_clip_arc = Arc::new(track_clip);
            let clip_id = graph.add_clip_to_track(*track_id, track_clip_arc.clone(), start_position)
                .ok_or(format!("Failed to add recorded clip to track {track_id}"))?;

            clips_map.insert(clip_id, track_clip_arc);

            if first_clip_id.is_none() {
                first_clip_id = Some(clip_id);
            }

            eprintln!("✅ [API] Added clip {clip_id} to track {track_id} (input ch {input_channel})");
        }

        let clip_id = first_clip_id.ok_or("Failed to create any clips")?;

        eprintln!("📊 [API] Created {} clips for {} armed tracks", armed_tracks.len(), armed_tracks.len());

        Ok(Some(clip_id))
    } else {
        Ok(None)
    }
}

/// Get current recording state (0=Idle, 1=CountingIn, 2=Recording, 3=WaitingForPunchIn)
pub fn get_recording_state() -> Result<i32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    use crate::recorder::RecordingState;
    let state = match graph.recorder.get_state() {
        RecordingState::Idle => 0,
        RecordingState::CountingIn => 1,
        RecordingState::Recording => 2,
        RecordingState::WaitingForPunchIn => 3,
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
        .map(|p| format!("{p:.3}"))
        .collect::<Vec<_>>()
        .join(",");

    Ok(csv)
}

/// Set count-in duration in bars
pub fn set_count_in_bars(bars: u32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    graph.recorder.set_count_in_bars(bars);
    Ok(format!("Count-in set to {bars} bars"))
}

/// Get count-in duration in bars
pub fn get_count_in_bars() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_count_in_bars())
}

/// Get current count-in beat number (1-indexed, 0 when not counting in)
pub fn get_count_in_beat() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_count_in_beat())
}

/// Get count-in progress (0.0-1.0, ring depletion amount)
pub fn get_count_in_progress() -> Result<f32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;

    Ok(graph.recorder.get_count_in_progress())
}

// ============================================================================
// PUNCH IN/OUT RECORDING
// ============================================================================

pub fn set_punch_in_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    graph.recorder.set_punch_in_enabled(enabled);
    Ok(format!("Punch-in {}", if enabled { "enabled" } else { "disabled" }))
}

pub fn is_punch_in_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    Ok(graph.recorder.is_punch_in_enabled())
}

pub fn set_punch_out_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    graph.recorder.set_punch_out_enabled(enabled);
    Ok(format!("Punch-out {}", if enabled { "enabled" } else { "disabled" }))
}

pub fn is_punch_out_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    Ok(graph.recorder.is_punch_out_enabled())
}

pub fn set_punch_region(in_seconds: f64, out_seconds: f64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    graph.recorder.set_punch_region(in_seconds, out_seconds);
    Ok(format!("Punch region set: {in_seconds:.3}s - {out_seconds:.3}s"))
}

pub fn get_punch_in_seconds() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    Ok(graph.recorder.get_punch_in_seconds())
}

pub fn get_punch_out_seconds() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    Ok(graph.recorder.get_punch_out_seconds())
}

pub fn is_punch_complete() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock().map_err(|e| e.to_string())?;
    Ok(graph.recorder.is_punch_complete())
}
