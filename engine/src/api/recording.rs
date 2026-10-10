//! Recording and audio input API functions
//!
//! Functions for audio recording, input device management, and recording state.

use super::helpers::{get_audio_clips, get_audio_graph};
use crate::audio_input::InputChoice;
use std::fmt::Write as _;
use std::sync::Arc;

/// Every audio clip the last [`stop_recording`] made, one per armed audio
/// track. `stop_recording` returns only the first.
static LAST_RECORDED_CLIPS: parking_lot::Mutex<Vec<u64>> = parking_lot::Mutex::new(Vec::new());

// ============================================================================
// AUDIO INPUT DEVICES
// ============================================================================

/// Get list of available audio input devices
pub fn get_audio_input_devices() -> Result<Vec<(String, String, bool)>, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    // Re-enumerate so a device plugged in since launch shows up in Settings.
    let mut input_manager = graph.input_manager.lock();
    let devices = input_manager
        .enumerate_devices()
        .unwrap_or_else(|_| input_manager.get_devices());

    // Convert to tuple format: (id, name, is_default)
    let device_list: Vec<(String, String, bool)> = devices
        .into_iter()
        .map(|d| (d.id, d.name, d.is_default))
        .collect();

    Ok(device_list)
}

/// Settings value meaning "never open an input".
pub const INPUT_OFF: &str = "__off__";

/// Choose the audio input: `""` follows the system default, [`INPUT_OFF`]
/// turns input off, anything else is a device name. A running capture
/// reopens on the new device straight away.
pub fn set_audio_input_choice(name: &str) -> Result<String, String> {
    let choice = match name {
        "" => InputChoice::SystemDefault,
        INPUT_OFF => InputChoice::Off,
        other => InputChoice::Named(other.to_string()),
    };

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    // The audio callback only ever try_locks the input manager, so holding it
    // while the input stream restarts can't deadlock against it.
    {
        let mut input_manager = graph.input_manager.lock();
        input_manager.set_choice(choice.clone());
        // Close so the sync below reopens on the new device.
        if input_manager.is_capturing() {
            input_manager.stop_capture().map_err(|e| e.to_string())?;
        }
    }
    graph.sync_input_to_armed_tracks();
    Ok(format!("Input set to {choice:?}"))
}

/// The input as it resolves right now, without opening it:
/// `"off|fell_back|channels|device name"` with 1/0 flags. The name is last
/// because device names may contain `|`; it is empty when off or absent.
pub fn get_audio_input_status() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let mut input_manager = graph.input_manager.lock();

    let off = *input_manager.choice() == InputChoice::Off;
    let channels = if off {
        0
    } else {
        input_manager.probe().map_err(|e| e.to_string())?
    };
    let (name, fell_back) = input_manager
        .active()
        .map_or((String::new(), false), |a| (a.name.clone(), a.fell_back));
    Ok(format!(
        "{}|{}|{channels}|{name}",
        u8::from(off),
        u8::from(fell_back)
    ))
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
    let mut graph = graph_mutex.lock();

    let name = if device_name.is_empty() {
        None
    } else {
        Some(device_name.to_string())
    };

    graph.set_output_device(name).map_err(|e| e.to_string())?;
    // A new output may run at another rate; the input must match it.
    graph.sync_input_to_armed_tracks();

    Ok(format!(
        "Output device set to: {}",
        if device_name.is_empty() {
            "System Default"
        } else {
            device_name
        }
    ))
}

/// Get currently selected output device name (empty string = system default)
pub fn get_selected_audio_output_device() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.get_selected_output_device().unwrap_or_default())
}

/// Get current sample rate
pub fn get_sample_rate() -> u32 {
    use crate::audio_graph::AudioGraph;
    AudioGraph::get_sample_rate()
}

/// Take (read-and-clear) the last audio output stream error (C99).
/// Returns an empty string when the stream is healthy. The UI polls this and
/// shows the error once — e.g. when the output device is disconnected
/// mid-playback, which otherwise fails silently.
pub fn get_audio_stream_error() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.take_stream_error().unwrap_or_default())
}

// ============================================================================
// AUDIO INPUT METERING
// ============================================================================

/// Get input channel peak level for metering
/// Returns peak amplitude (0.0 to 1.0+) for the specified channel (0=left, 1=right)
pub fn get_input_channel_level(channel: u32) -> Result<f32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    let input_manager = graph.input_manager.lock();
    Ok(input_manager.get_channel_peak(channel))
}

/// The input's state for the "can't hear your input" notice: the
/// [`InputHealth`](crate::audio_input::InputHealth) code in the low byte, plus
/// 256 when arming held monitoring back because the input and output look
/// like the computer's own mic and speakers. Cheap; the UI polls it.
pub fn get_audio_input_health() -> Result<i32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let input_manager = graph.input_manager.lock();
    let guarded = if input_manager.feedback_guarded() {
        256
    } else {
        0
    };
    Ok(input_manager.health().code() | guarded)
}

/// Get number of input channels for the current device
pub fn get_input_channel_count() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    let input_manager = graph.input_manager.lock();
    Ok(u32::from(input_manager.get_input_channels()))
}

// ============================================================================
// AUDIO RECORDING
// ============================================================================

/// Start recording audio (also enables metronome/count-in for MIDI recording)
///
/// Note: Audio input capture failures are non-fatal - MIDI recording can still proceed.
pub fn start_recording() -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let mut graph = graph_mutex.lock();

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

    // Near bar 1 there's no room for a full pre-roll seekback, so (part of)
    // the count-in plays "in place" — over the very bars being recorded.
    // Flag it so the renderer mutes track playback during the count-in
    // (the metronome stays audible).
    graph
        .recorder
        .set_count_in_in_place(count_in_seconds > 0.0 && recording_start < count_in_seconds);

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

    // Only an armed audio track needs the input; a MIDI-only take leaves it shut.
    if !graph.has_armed_audio_track() {
        return Ok(format!("Recording started (MIDI only): {state:?}"));
    }

    // NOW try to start audio input (non-fatal if it fails - MIDI recording can still work)
    // We do this AFTER play() to avoid deadlock: the audio callback tries to lock input_manager,
    // and start_capture() calls stream.play() which may wait for the audio callback.
    eprintln!("🎙️  [API] Attempting to acquire input_manager lock...");
    let audio_input_started = {
        let Some(mut input_manager) = graph.input_manager.try_lock() else {
            eprintln!("⚠️  [API] Could not acquire input_manager lock, skipping audio input");
            return Ok(format!(
                "Recording started (MIDI only, input busy): {state:?}"
            ));
        };

        if *input_manager.choice() == InputChoice::Off {
            eprintln!("🎙️  [API] Input is off (MIDI recording will still work)");
            false
        } else {
            // Usually already open because an audio track is armed. A failed
            // open is kept for get_audio_input_health (MIDI still records).
            input_manager.sync_open(true, graph.current_stream_sample_rate());
            input_manager.is_capturing()
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
    LAST_RECORDED_CLIPS.lock().clear();
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    // Use the rate the stream actually ran at — duration math and resampling
    // inside stop_recording depend on it (C22).
    let clip_option = graph
        .recorder
        .stop_recording(graph.current_stream_sample_rate())?;

    // Close the input unless an audio track is still armed: then it stays
    // open so the meter keeps moving and you keep hearing yourself.
    let audio_was_captured = graph.input_manager.lock().is_capturing();
    graph.sync_input_to_armed_tracks();

    // No input was open (off, or it failed to start): the take holds no audio,
    // so don't leave an empty clip on the armed tracks.
    let clip_option = clip_option.filter(|_| audio_was_captured);

    if let Some(clip) = clip_option {
        // Find armed audio tracks — only place audio clips on explicitly armed tracks.
        // If no audio tracks are armed, discard the audio clip (MIDI-only recording).
        let armed_tracks: Vec<(u64, u32)> = {
            let tm = graph.track_manager.lock();
            let armed: Vec<(u64, u32)> = tm
                .get_all_tracks()
                .into_iter()
                .filter_map(|t| {
                    let track = t.lock();
                    if track.track_type == crate::track::TrackType::Audio && track.armed {
                        Some((track.id, track.input_channel))
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

        eprintln!(
            "🎙️ [API] Recording will be added to {} track(s): {:?}",
            armed_tracks.len(),
            armed_tracks
        );

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
        let mut clips_map = clips_mutex.lock();

        for (track_id, input_channel) in &armed_tracks {
            // Tracks record one input channel ("In 1", "In 2"), centred: a
            // mic in input 1 of a stereo interface used to land on the left
            // side only when a single track was armed.
            let track_samples = take_channel_centred(stereo_samples, *input_channel);

            let track_clip = crate::audio_file::AudioClip {
                samples: track_samples,
                channels: 2,
                sample_rate: crate::audio_file::TARGET_SAMPLE_RATE,
                duration_seconds: duration,
                file_path: format!("recorded_t{track_id}_{timestamp}.wav"),
            };

            let track_clip_arc = Arc::new(track_clip);
            let clip_id = graph
                .add_clip_to_track(*track_id, track_clip_arc.clone(), start_position)
                .ok_or(format!("Failed to add recorded clip to track {track_id}"))?;

            clips_map.insert(clip_id, track_clip_arc);
            LAST_RECORDED_CLIPS.lock().push(clip_id);

            if first_clip_id.is_none() {
                first_clip_id = Some(clip_id);
            }

            eprintln!(
                "✅ [API] Added clip {clip_id} to track {track_id} (input ch {input_channel})"
            );
        }

        let clip_id = first_clip_id.ok_or("Failed to create any clips")?;

        eprintln!(
            "📊 [API] Created {} clips for {} armed tracks",
            armed_tracks.len(),
            armed_tracks.len()
        );

        Ok(Some(clip_id))
    } else {
        Ok(None)
    }
}

/// Every audio clip the last [`stop_recording`] made, comma-separated (empty
/// if it made none).
#[must_use]
pub fn get_last_recorded_clip_ids() -> String {
    LAST_RECORDED_CLIPS
        .lock()
        .iter()
        .map(u64::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

/// Get current recording state (0=Idle, 1=CountingIn, 2=Recording, 3=WaitingForPunchIn)
pub fn get_recording_state() -> Result<i32, String> {
    use crate::recorder::RecordingState;

    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
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
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_recorded_duration())
}

/// The live waveform of the take in progress, from peak `from` on:
/// `"total|l,r,l,r,…"`, one left/right pair per 10 ms of recording. `total`
/// is how many peaks the take has; less than `from` means a new take started,
/// so the caller should start again from 0. Never touches the recorded
/// samples, so polling it can't stall the audio thread.
pub fn get_live_recording_peaks(from: usize) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    let peaks = graph.recorder.live_peaks();
    let total = peaks.len();
    let mut out = format!("{total}|");
    for i in from.min(total)..total {
        let (l, r) = peaks.get(i);
        if i > from {
            out.push(',');
        }
        let _ = write!(out, "{l:.3},{r:.3}");
    }
    Ok(out)
}

/// Set count-in duration in bars
pub fn set_count_in_bars(bars: u32) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    graph.recorder.set_count_in_bars(bars);
    Ok(format!("Count-in set to {bars} bars"))
}

/// Get count-in duration in bars
pub fn get_count_in_bars() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_count_in_bars())
}

/// Get current count-in beat number (1-indexed, 0 when not counting in)
pub fn get_count_in_beat() -> Result<u32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_count_in_beat())
}

/// Get count-in progress (0.0-1.0, ring depletion amount)
pub fn get_count_in_progress() -> Result<f32, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();

    Ok(graph.recorder.get_count_in_progress())
}

// ============================================================================
// PUNCH IN/OUT RECORDING
// ============================================================================

pub fn set_punch_in_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    graph.recorder.set_punch_in_enabled(enabled);
    Ok(format!(
        "Punch-in {}",
        if enabled { "enabled" } else { "disabled" }
    ))
}

pub fn is_punch_in_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.recorder.is_punch_in_enabled())
}

pub fn set_punch_out_enabled(enabled: bool) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    graph.recorder.set_punch_out_enabled(enabled);
    Ok(format!(
        "Punch-out {}",
        if enabled { "enabled" } else { "disabled" }
    ))
}

pub fn is_punch_out_enabled() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.recorder.is_punch_out_enabled())
}

pub fn set_punch_region(in_seconds: f64, out_seconds: f64) -> Result<String, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    graph.recorder.set_punch_region(in_seconds, out_seconds);
    Ok(format!(
        "Punch region set: {in_seconds:.3}s - {out_seconds:.3}s"
    ))
}

pub fn get_punch_in_seconds() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.recorder.get_punch_in_seconds())
}

pub fn get_punch_out_seconds() -> Result<f64, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.recorder.get_punch_out_seconds())
}

pub fn is_punch_complete() -> Result<bool, String> {
    let graph_mutex = get_audio_graph()?;
    let graph = graph_mutex.lock();
    Ok(graph.recorder.is_punch_complete())
}

/// One channel of an interleaved stereo take, copied to both sides. Even
/// channels are the left of the captured pair, odd the right (only a stereo
/// pair is captured).
pub(crate) fn take_channel_centred(stereo: &[f32], channel: u32) -> Vec<f32> {
    let side = (channel % 2) as usize;
    stereo
        .as_chunks::<2>()
        .0
        .iter()
        .flat_map(|frame| [frame[side], frame[side]])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::take_channel_centred;

    #[test]
    fn input_one_is_centred_not_left_only() {
        let take = [0.5, 0.0, 0.25, 0.0];
        assert_eq!(take_channel_centred(&take, 0), vec![0.5, 0.5, 0.25, 0.25]);
    }

    #[test]
    fn input_two_takes_the_right_side() {
        let take = [0.0, 0.5, 0.0, 0.25];
        assert_eq!(take_channel_centred(&take, 1), vec![0.5, 0.5, 0.25, 0.25]);
    }
}
