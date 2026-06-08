//! First unit tests for the API layer (C69, v0.5.2 P7).
//!
//! These exercise the real public API functions against the global engine
//! singletons (`AUDIO_GRAPH` / `AUDIO_CLIPS`) — the same state the FFI shims
//! drive. The graph is headless under `cfg(test)` (no cpal stream opened),
//! so everything here runs on CI.
//!
//! Because the engine state is process-wide, every test starts with
//! `engine_lock()`, which (a) serializes API tests against each other and
//! (b) resets the engine to a clean slate (no tracks, 120 BPM, 4/4).
//!
//! First slice, per `docs/plans/v0.5.2-plan.md` Phase 7:
//! - save → load round-trip fidelity (locks Phase 2: C55/C65/C66)
//! - command execute → undo → redo vs engine state (locks Phase 1: C46/C63)
//! - export smoke: range, LUFS target, stem-vs-mix gain order (locks Phase 4)

use super::*;
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::audio_graph::AudioGraph;
use crate::midi::{MidiEvent, MidiEventType};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

// ============================================================================
// HARNESS
// ============================================================================

/// Serializes API tests (they all share the global engine singletons) and
/// resets the engine to a clean slate before each test body runs.
fn engine_lock() -> parking_lot::MutexGuard<'static, ()> {
    static TEST_GUARD: Mutex<()> = Mutex::new(());
    let guard = TEST_GUARD.lock();

    AUDIO_GRAPH.get_or_init(|| Mutex::new(AudioGraph::new().expect("headless AudioGraph::new")));
    AUDIO_CLIPS.get_or_init(|| Mutex::new(HashMap::new()));

    reset_engine();
    guard
}

/// Back to a known baseline: no tracks (master reset), no clips, 120 BPM, 4/4.
fn reset_engine() {
    clear_all_tracks().expect("clear_all_tracks");
    // clear_all_tracks removes per-track MIDI clips, but clips created via
    // create_midi_clip() and never attached to a track live only in the
    // global timeline — clear those too.
    {
        let graph = get_audio_graph().expect("graph").lock();
        graph.get_midi_clips().lock().clear();
    }
    set_tempo(120.0).expect("set_tempo");
    set_time_signature(4).expect("set_time_signature");
}

/// Fresh temp directory for a test, cleaned of any previous run's leftovers.
fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("boojy_api_test_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("create temp dir");
    dir
}

fn path_str(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

/// Write a stereo 48 kHz float32 440 Hz sine WAV and return its path.
fn write_sine_wav(dir: &Path, name: &str, duration_secs: f64, amplitude: f32) -> PathBuf {
    let path = dir.join(name);
    let spec = hound::WavSpec {
        channels: 2,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };
    let mut writer = hound::WavWriter::create(&path, spec).expect("create wav");
    let frames = (duration_secs * f64::from(TARGET_SAMPLE_RATE)) as usize;
    for i in 0..frames {
        let t = i as f32 / TARGET_SAMPLE_RATE as f32;
        let v = amplitude * (t * 440.0 * 2.0 * std::f32::consts::PI).sin();
        writer.write_sample(v).expect("write sample");
        writer.write_sample(v).expect("write sample");
    }
    writer.finalize().expect("finalize wav");
    path
}

// ============================================================================
// STATE-READING HELPERS (snapshot under the locks, assert outside them)
// ============================================================================

/// `(id, name)` of every non-master track.
fn track_ids_and_names() -> Vec<(u64, String)> {
    let graph = get_audio_graph().expect("graph").lock();
    let tm = graph.track_manager.lock();
    tm.get_all_tracks()
        .iter()
        .filter_map(|track_arc| {
            let track = track_arc.lock();
            (track.id != 0).then(|| (track.id, track.name.clone()))
        })
        .collect()
}

/// `(volume_db, pan)` of a track.
fn track_mix_state(track_id: u64) -> (f32, f32) {
    let graph = get_audio_graph().expect("graph").lock();
    let tm = graph.track_manager.lock();
    let track_arc = tm.get_track(track_id).expect("track exists");
    let track = track_arc.lock();
    (track.volume_db, track.pan)
}

/// `(id, start_time)` of a track's audio clips, sorted by start time.
fn audio_clip_positions(track_id: u64) -> Vec<(u64, f64)> {
    let graph = get_audio_graph().expect("graph").lock();
    let tm = graph.track_manager.lock();
    let track_arc = tm.get_track(track_id).expect("track exists");
    let track = track_arc.lock();
    let mut positions: Vec<(u64, f64)> = track
        .audio_clips
        .iter()
        .map(|c| (c.id, c.start_time))
        .collect();
    positions.sort_by(|a, b| a.1.total_cmp(&b.1));
    positions
}

/// `(id, start_time)` of a track's MIDI clips (the track-local copy).
fn midi_clip_positions(track_id: u64) -> Vec<(u64, f64)> {
    let graph = get_audio_graph().expect("graph").lock();
    let tm = graph.track_manager.lock();
    let track_arc = tm.get_track(track_id).expect("track exists");
    let track = track_arc.lock();
    track
        .midi_clips
        .iter()
        .map(|c| (c.id, c.start_time))
        .collect()
}

/// Start time of a clip in the GLOBAL MIDI timeline. Must agree with the
/// track-local copy after every move — the two stores diverging is exactly
/// the C63 class of bug.
fn global_midi_clip_start(clip_id: u64) -> f64 {
    let graph = get_audio_graph().expect("graph").lock();
    let midi_clips = graph.get_midi_clips().lock();
    midi_clips
        .iter()
        .find(|c| c.id == clip_id)
        .expect("clip in global timeline")
        .start_time
}

/// All MIDI events of the first MIDI clip on a track, as
/// `(is_note_on, note, seconds)` triples sorted by time.
fn midi_events_on_track(track_id: u64) -> Vec<(bool, u8, f64)> {
    let graph = get_audio_graph().expect("graph").lock();
    let tm = graph.track_manager.lock();
    let track_arc = tm.get_track(track_id).expect("track exists");
    let track = track_arc.lock();
    let clip = &track.midi_clips.first().expect("midi clip on track").clip;
    clip.events
        .iter()
        .filter_map(|e| {
            let secs = e.timestamp_samples as f64 / f64::from(clip.sample_rate);
            match e.event_type {
                MidiEventType::NoteOn { note, velocity } if velocity > 0 => {
                    Some((true, note, secs))
                }
                MidiEventType::NoteOff { note, .. } | MidiEventType::NoteOn { note, .. } => {
                    Some((false, note, secs))
                }
                MidiEventType::ControlChange { .. } => None,
            }
        })
        .collect()
}

/// An `AudioClip` constructed in memory (no file behind it).
fn in_memory_clip(duration_secs: f64) -> AudioClip {
    let frames = (duration_secs * f64::from(TARGET_SAMPLE_RATE)) as usize;
    AudioClip {
        samples: vec![0.1; frames * 2],
        channels: 2,
        sample_rate: TARGET_SAMPLE_RATE,
        duration_seconds: duration_secs,
        file_path: "in-memory-only.wav".to_string(),
    }
}

// ============================================================================
// SAVE → LOAD ROUND-TRIP (locks Phase 2: C55/C65/C66)
// ============================================================================

#[test]
fn midi_project_round_trips_through_save_and_load() {
    let _guard = engine_lock();

    set_tempo(100.0).unwrap();
    set_time_signature(3).unwrap();
    let track_id = create_track("Midi", "Keys".to_string()).unwrap();
    set_track_volume(track_id, -6.0).unwrap();
    set_track_pan(track_id, 0.25).unwrap();

    let clip_id = create_midi_clip().unwrap();
    add_midi_note_to_clip(clip_id, 60, 100, 0.0, 1.0).unwrap();
    add_midi_note_to_clip(clip_id, 64, 90, 1.0, 0.5).unwrap();
    add_midi_clip_to_track_api(track_id, clip_id, 2.5).unwrap();

    let dir = temp_dir("midi_round_trip");
    let project = dir.join("RoundTrip.audio");
    save_project("RoundTrip".to_string(), path_str(&project)).unwrap();

    // Drift the live state so the assertions below can only pass if load
    // actually restored the saved values (not just left them in place).
    set_tempo(140.0).unwrap();
    set_clip_start_time(track_id, clip_id, 9.0).unwrap();

    load_project(path_str(&project)).unwrap();

    assert!(
        (get_tempo().unwrap() - 100.0).abs() < 1e-6,
        "tempo restored"
    );
    assert_eq!(get_time_signature().unwrap(), 3, "time signature restored");

    let tracks = track_ids_and_names();
    assert_eq!(tracks.len(), 1, "exactly the one saved track");
    let (new_track_id, name) = tracks[0].clone();
    assert_eq!(name, "Keys");

    let (volume_db, pan) = track_mix_state(new_track_id);
    assert!((volume_db - (-6.0)).abs() < 1e-6, "volume restored");
    assert!((pan - 0.25).abs() < 1e-6, "pan restored");

    let clips = midi_clip_positions(new_track_id);
    assert_eq!(clips.len(), 1);
    assert!(
        (clips[0].1 - 2.5).abs() < 1e-9,
        "clip start restored to the SAVED position, not the post-save move"
    );

    let events = midi_events_on_track(new_track_id);
    let note_ons: Vec<_> = events.iter().filter(|(on, _, _)| *on).collect();
    assert_eq!(note_ons.len(), 2, "both notes survive the round-trip");
    assert!(note_ons
        .iter()
        .any(|(_, note, secs)| *note == 60 && secs.abs() < 1e-6));
    assert!(note_ons
        .iter()
        .any(|(_, note, secs)| *note == 64 && (secs - 1.0).abs() < 1e-6));
}

#[test]
fn held_note_is_flushed_to_clip_end_and_survives_reload() {
    let _guard = engine_lock();

    let track_id = create_track("Midi", "Held".to_string()).unwrap();
    let clip_id = create_midi_clip().unwrap();
    add_midi_note_to_clip(clip_id, 60, 100, 0.0, 1.0).unwrap();

    // Inject a NoteOn with no matching NoteOff — saving mid-sustain (C65).
    // Done before attaching so the track gets the updated clip Arc.
    let clip_end_secs = {
        let graph = get_audio_graph().unwrap().lock();
        let mut midi_clips = graph.get_midi_clips().lock();
        let timeline_clip = midi_clips.iter_mut().find(|c| c.id == clip_id).unwrap();
        let clip = Arc::make_mut(&mut timeline_clip.clip);
        clip.add_event(MidiEvent::note_on(64, 90, u64::from(TARGET_SAMPLE_RATE)));
        clip.duration_samples as f64 / f64::from(clip.sample_rate)
    };
    add_midi_clip_to_track_api(track_id, clip_id, 0.0).unwrap();

    let dir = temp_dir("held_note");
    let project = dir.join("Held.audio");
    save_project("Held".to_string(), path_str(&project)).unwrap();
    load_project(path_str(&project)).unwrap();

    let (new_track_id, _) = track_ids_and_names()[0].clone();
    let events = midi_events_on_track(new_track_id);

    let held_on = events
        .iter()
        .find(|(on, note, _)| *on && *note == 64)
        .expect("held note must not be dropped on save (C65)");
    assert!((held_on.2 - 1.0).abs() < 1e-6);

    let held_off = events
        .iter()
        .find(|(on, note, _)| !*on && *note == 64)
        .expect("held note gets a NoteOff at clip end");
    assert!(
        (held_off.2 - clip_end_secs).abs() < 1e-3,
        "flushed NoteOff lands at the clip end ({clip_end_secs}s), got {}s",
        held_off.2
    );
}

#[test]
fn multi_clip_audio_track_survives_save_load_save_load() {
    let _guard = engine_lock();

    let dir = temp_dir("multi_clip_audio");
    let wav = write_sine_wav(&dir, "source.wav", 2.0, 0.5);
    let track_id = create_track("Audio", "Guitar".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 3.0).unwrap();

    let project_a = dir.join("Take1.audio");
    save_project("Take1".to_string(), path_str(&project_a)).unwrap();
    load_project(path_str(&project_a)).unwrap();

    let (track_a, _) = track_ids_and_names()[0].clone();
    let clips = audio_clip_positions(track_a);
    assert_eq!(clips.len(), 2, "both clips survive the first reload (C66)");
    assert!(clips[0].1.abs() < 1e-9);
    assert!((clips[1].1 - 3.0).abs() < 1e-9);

    // The heart of C66: after a load, AUDIO_CLIPS must be re-keyed to the
    // FRESH timeline ids — otherwise this second save silently loses files.
    let project_b = dir.join("Take2.audio");
    save_project("Take2".to_string(), path_str(&project_b))
        .expect("save-after-load must not lose track of reloaded audio clips (C66)");
    load_project(path_str(&project_b)).unwrap();

    let (track_b, _) = track_ids_and_names()[0].clone();
    let clips = audio_clip_positions(track_b);
    assert_eq!(
        clips.len(),
        2,
        "both clips survive a second save/load cycle"
    );
    assert!(clips[0].1.abs() < 1e-9);
    assert!((clips[1].1 - 3.0).abs() < 1e-9);
}

#[test]
fn save_aborts_when_audio_clip_data_is_missing() {
    let _guard = engine_lock();

    let track_id = create_track("Audio", "Ghost".to_string()).unwrap();
    // Attach a clip to the track WITHOUT registering it in AUDIO_CLIPS —
    // the save must refuse rather than write a project that drops it (C55).
    {
        let graph = get_audio_graph().unwrap().lock();
        graph
            .add_clip_to_track(track_id, Arc::new(in_memory_clip(2.0)), 0.0)
            .expect("clip attaches");
    }

    let dir = temp_dir("save_aborts");
    let project = dir.join("Ghost.audio");
    let err = save_project("Ghost".to_string(), path_str(&project))
        .expect_err("saving a clip with no loaded audio data must fail honestly");
    assert!(
        err.contains("save aborted"),
        "error explains the abort, got: {err}"
    );
}

#[test]
fn load_reports_missing_audio_file_instead_of_dropping_the_clip() {
    let _guard = engine_lock();

    let dir = temp_dir("missing_audio");
    let wav = write_sine_wav(&dir, "source.wav", 2.0, 0.5);
    let track_id = create_track("Audio", "Vox".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    let project = dir.join("Vox.audio");
    save_project("Vox".to_string(), path_str(&project)).unwrap();

    // Simulate the asset vanishing from the project folder (moved/deleted).
    let audio_dir = project.join("audio");
    for entry in std::fs::read_dir(&audio_dir).unwrap() {
        std::fs::remove_file(entry.unwrap().path()).unwrap();
    }

    let err = load_project(path_str(&project))
        .expect_err("a missing audio file must be a load error, not a silently empty track (C66)");
    assert!(
        err.contains("Failed to load audio file"),
        "error names the failure, got: {err}"
    );
}

// ============================================================================
// COMMAND EXECUTE → UNDO → REDO vs ENGINE STATE (locks Phase 1: C46/C63)
// ============================================================================

#[test]
fn audio_clip_move_execute_undo_redo_tracks_engine_state() {
    let _guard = engine_lock();

    let dir = temp_dir("audio_clip_move");
    let wav = write_sine_wav(&dir, "source.wav", 2.0, 0.5);
    let track_id = create_track("Audio", "Drums".to_string()).unwrap();
    let clip_id = load_audio_file_to_track_api(path_str(&wav), track_id, 1.0).unwrap();

    // execute: the UI's MoveClipCommand.execute() routes here
    set_clip_start_time(track_id, clip_id, 5.0).unwrap();
    assert_eq!(audio_clip_positions(track_id), vec![(clip_id, 5.0)]);

    // undo: same call, original position
    set_clip_start_time(track_id, clip_id, 1.0).unwrap();
    assert_eq!(audio_clip_positions(track_id), vec![(clip_id, 1.0)]);

    // redo
    set_clip_start_time(track_id, clip_id, 5.0).unwrap();
    assert_eq!(audio_clip_positions(track_id), vec![(clip_id, 5.0)]);

    // a drag past the timeline origin clamps to 0, never goes negative
    set_clip_start_time(track_id, clip_id, -3.0).unwrap();
    assert_eq!(audio_clip_positions(track_id), vec![(clip_id, 0.0)]);
}

#[test]
fn midi_clip_move_keeps_track_and_global_timeline_in_sync() {
    let _guard = engine_lock();

    let track_id = create_track("Midi", "Keys".to_string()).unwrap();
    let clip_id = create_midi_clip().unwrap();
    add_midi_note_to_clip(clip_id, 60, 100, 0.0, 1.0).unwrap();
    add_midi_clip_to_track_api(track_id, clip_id, 2.0).unwrap();

    // execute → undo → redo; after EVERY move the track-local copy and the
    // global MIDI timeline must agree (C63 was them diverging).
    for target in [8.0, 2.0, 8.0] {
        set_clip_start_time(track_id, clip_id, target).unwrap();
        assert_eq!(midi_clip_positions(track_id), vec![(clip_id, target)]);
        assert!(
            (global_midi_clip_start(clip_id) - target).abs() < 1e-9,
            "global MIDI timeline must follow the move to {target}s (C63)"
        );
    }
}

#[test]
fn deleted_clip_restores_with_its_original_id_for_undo() {
    let _guard = engine_lock();

    let dir = temp_dir("delete_undo");
    let wav = write_sine_wav(&dir, "source.wav", 2.0, 0.5);
    let track_id = create_track("Audio", "Bass".to_string()).unwrap();
    let clip_id = load_audio_file_to_track_api(path_str(&wav), track_id, 2.0).unwrap();

    // execute: delete
    assert!(remove_audio_clip(track_id, clip_id).unwrap());
    assert!(audio_clip_positions(track_id).is_empty());

    // undo: restore must come back under the ORIGINAL id, or every later
    // command in the undo stack (holding the old id) dangles
    let restored = add_existing_clip_to_track(clip_id, track_id, 2.0, 0.0, None).unwrap();
    assert_eq!(restored, clip_id, "undo restores the original clip id");
    assert_eq!(audio_clip_positions(track_id), vec![(clip_id, 2.0)]);
}

// ============================================================================
// EXPORT SMOKE (locks Phase 4: C16/C18/C68)
// ============================================================================

fn export_options_json(options: &crate::export::ExportOptions) -> String {
    serde_json::to_string(options).expect("options serialize")
}

#[test]
fn export_honors_the_requested_range() {
    use crate::export::{ExportOptions, WavBitDepth};

    let _guard = engine_lock();

    let dir = temp_dir("export_range");
    let wav = write_sine_wav(&dir, "source.wav", 4.0, 0.5);
    let track_id = create_track("Audio", "Mix".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    let options = ExportOptions::wav(WavBitDepth::Float32)
        .with_sample_rate(TARGET_SAMPLE_RATE)
        .with_range(1.0, 3.0);
    let out = dir.join("range.wav");
    export_audio(path_str(&out), export_options_json(&options)).unwrap();

    let mut reader = hound::WavReader::open(&out).unwrap();
    let spec = reader.spec();
    let frames = reader.duration();
    let duration_secs = f64::from(frames) / f64::from(spec.sample_rate);
    assert!(
        (duration_secs - 2.0).abs() < 0.01,
        "a 1s–3s range must export 2s of audio (C18), got {duration_secs}s"
    );

    let peak = reader
        .samples::<f32>()
        .map(|s| s.unwrap().abs())
        .fold(0.0f32, f32::max);
    assert!(peak > 0.1, "the exported range contains the signal");
}

#[test]
fn export_with_an_empty_range_is_a_hard_error() {
    use crate::export::{ExportOptions, WavBitDepth};

    let _guard = engine_lock();

    let dir = temp_dir("export_empty_range");
    let wav = write_sine_wav(&dir, "source.wav", 4.0, 0.5);
    let track_id = create_track("Audio", "Mix".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    let options = ExportOptions::wav(WavBitDepth::Float32)
        .with_sample_rate(TARGET_SAMPLE_RATE)
        .with_range(2.0, 2.0);
    let out = dir.join("empty.wav");
    let err = export_audio(path_str(&out), export_options_json(&options))
        .expect_err("an empty export range must fail, not silently export everything (C18)");
    assert!(
        err.to_lowercase().contains("range"),
        "error mentions the range, got: {err}"
    );
}

#[test]
fn export_platform_target_lands_at_the_target_loudness() {
    use crate::export::{calculate_lufs, ExportOptions, PlatformTarget, WavBitDepth};

    let _guard = engine_lock();

    let dir = temp_dir("export_lufs");
    let wav = write_sine_wav(&dir, "source.wav", 4.0, 0.5);
    let track_id = create_track("Audio", "Mix".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    let options = ExportOptions::wav(WavBitDepth::Float32)
        .with_sample_rate(TARGET_SAMPLE_RATE)
        .with_platform(PlatformTarget::Spotify); // −14 LUFS
    let out = dir.join("spotify.wav");
    export_audio(path_str(&out), export_options_json(&options)).unwrap();

    let mut reader = hound::WavReader::open(&out).unwrap();
    let samples: Vec<f32> = reader.samples::<f32>().map(|s| s.unwrap()).collect();
    let lufs = calculate_lufs(&samples, TARGET_SAMPLE_RATE);
    assert!(
        (lufs - (-14.0)).abs() < 0.5,
        "platform target must actually be applied (C16): expected ≈ −14 LUFS, measured {lufs:.2}"
    );
}

#[test]
fn single_track_stem_matches_the_full_mix() {
    let _guard = engine_lock();

    let dir = temp_dir("stem_vs_mix");
    let wav = write_sine_wav(&dir, "source.wav", 4.0, 0.8);
    let track_id = create_track("Audio", "Mix".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    // A non-linear effect plus a non-default fader/pan: if stems applied
    // fader/pan BEFORE the FX (the C68 bug), the compressor would see a
    // different signal level than in the mix and the outputs would diverge.
    let effect_id = add_effect_to_track(track_id, "compressor").unwrap();
    set_effect_parameter(effect_id, "threshold", -30.0).unwrap();
    set_effect_parameter(effect_id, "ratio", 8.0).unwrap();
    set_track_volume(track_id, -6.0).unwrap();
    set_track_pan(track_id, 0.2).unwrap();

    let (mix, stem, master_gain, master_pan_l, master_pan_r) = {
        let graph = get_audio_graph().unwrap().lock();
        let duration = graph.calculate_project_duration();
        let mix = graph.render_offline(duration);
        let stem = graph.render_track_offline(track_id, duration);
        let tm = graph.track_manager.lock();
        let master_arc = tm.get_track(0).expect("master track");
        let master = master_arc.lock();
        let (pan_l, pan_r) = master.get_pan_gains();
        (mix, stem, master.get_gain(), pan_l, pan_r)
    };

    assert_eq!(mix.len(), stem.len());
    let mix_peak = mix.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
    assert!(mix_peak > 0.005, "the mix is not silent");

    // The full mix routes through the master bus (volume + constant-power
    // pan + transparent-below-threshold limiter); a solo stem deliberately
    // does not. Factor the master stage out and the two paths must agree
    // sample-for-sample — if stems applied fader/pan before the FX chain
    // (the C68 bug), the compressor would see a different signal level than
    // in the mix and the outputs would diverge.
    let max_diff = mix
        .chunks_exact(2)
        .zip(stem.chunks_exact(2))
        .map(|(m, s)| {
            let diff_l = (m[0] - s[0] * master_gain * master_pan_l).abs();
            let diff_r = (m[1] - s[1] * master_gain * master_pan_r).abs();
            diff_l.max(diff_r)
        })
        .fold(0.0f32, f32::max);
    assert!(
        max_diff < 1e-4,
        "single-track stem must equal the full mix after the master stage — \
         same gain-stage order (C68); max diff {max_diff}"
    );
}

// ============================================================================
// JOIN AUDIO CLIPS (render-only bounce of a clip subset)
// ============================================================================

#[test]
fn join_audio_clips_renders_selected_span_with_gaps() {
    let _guard = engine_lock();

    // Two 1 s clips on one track with a 1 s gap between them (0..1 and 2..3).
    let dir = temp_dir("join_audio");
    let wav = write_sine_wav(&dir, "a.wav", 1.0, 0.8);
    let track_id = create_track("Audio", "Join".to_string()).unwrap();
    let id1 = load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();
    let id2 = load_audio_file_to_track_api(path_str(&wav), track_id, 2.0).unwrap();

    let out = dir.join("joined.wav");
    let (start, duration) = {
        let graph = get_audio_graph().unwrap().lock();
        graph
            .render_audio_clips_to_wav(track_id, &[id1, id2], &out)
            .unwrap()
    };

    assert!(start.abs() < 1e-6, "joined clip starts at the earliest clip");
    assert!(
        (duration - 3.0).abs() < 0.05,
        "span 0..3s expected, got {duration}"
    );
    assert!(out.exists());

    let mut reader = hound::WavReader::open(&out).unwrap();
    assert_eq!(reader.spec().channels, 2);
    assert_eq!(reader.spec().sample_rate, 48000);
    let samples: Vec<f32> = reader.samples::<f32>().map(Result::unwrap).collect();

    let peak = |t0: f64, t1: f64| {
        let a = (t0 * 48000.0) as usize * 2;
        let b = (t1 * 48000.0) as usize * 2;
        samples[a..b].iter().map(|s| s.abs()).fold(0.0f32, f32::max)
    };
    // RENDER-ONLY bake: both clips audible, the gap between them silent.
    assert!(peak(0.1, 0.9) > 0.1, "first clip audible");
    assert!(peak(1.2, 1.8) < 0.01, "gap is silent");
    assert!(peak(2.1, 2.9) > 0.1, "second clip audible");

    // The originals are untouched — render-only never mutates the track.
    let graph = get_audio_graph().unwrap().lock();
    let tm = graph.track_manager.lock();
    let track = tm.get_track(track_id).unwrap();
    assert_eq!(track.lock().audio_clips.len(), 2);
}

// ============================================================================
// OFFLINE RENDER vs LIVE STREAM RATE (locks Phase 8: the C2 offline pin)
// ============================================================================

#[test]
fn offline_render_pins_builtin_fx_to_engine_rate_and_restores_the_live_rate() {
    let _guard = engine_lock();

    // A short burst at t=0 through a 100%-wet, no-feedback 500 ms delay: the
    // render is silent until the echo, whose position measures the delay's
    // effective sample rate.
    let dir = temp_dir("offline_rate_pin");
    let wav = write_sine_wav(&dir, "burst.wav", 0.05, 0.8);
    let track_id = create_track("Audio", "Echo".to_string()).unwrap();
    load_audio_file_to_track_api(path_str(&wav), track_id, 0.0).unwrap();

    let effect_id = add_effect_to_track(track_id, "delay").unwrap();
    set_effect_parameter(effect_id, "time", 500.0).unwrap();
    set_effect_parameter(effect_id, "feedback", 0.0).unwrap();
    set_effect_parameter(effect_id, "wet_dry", 1.0).unwrap();

    // Simulate a 44.1 kHz device: the renderer fans the real stream rate out
    // to every effect when the stream opens (C12), so the delay is now tuned
    // for 44.1 kHz — but offline renders are written as 48 kHz files.
    {
        let graph = get_audio_graph().unwrap().lock();
        graph.effect_manager.lock().set_sample_rate(44_100.0);
    }

    let first_audible = |samples: &[f32]| -> Option<usize> {
        samples
            .chunks_exact(2)
            .position(|frame| frame[0].abs() > 0.05 || frame[1].abs() > 0.05)
    };

    let (mix, stem, restored_rate) = {
        let graph = get_audio_graph().unwrap().lock();
        let mix = graph.render_offline(1.0);
        let stem = graph.render_track_offline(track_id, 1.0);
        let rate = graph.effect_manager.lock().sample_rate();
        (mix, stem, rate)
    };

    // Pinned to the engine rate during the render: the 500 ms echo lands at
    // 24000 frames (48 kHz), not 22050 (the live device rate).
    let mix_echo = first_audible(&mix).expect("mix should contain the echo");
    assert!(
        (24_000..24_050).contains(&mix_echo),
        "mix echo should land at 500 ms × 48 kHz ≈ 24000 frames, got {mix_echo}"
    );
    let stem_echo = first_audible(&stem).expect("stem should contain the echo");
    assert!(
        (24_000..24_050).contains(&stem_echo),
        "stem echo should land at 500 ms × 48 kHz ≈ 24000 frames, got {stem_echo}"
    );

    // …and the live device rate is put back afterwards.
    assert!(
        (restored_rate - 44_100.0).abs() < f32::EPSILON,
        "live stream rate must be restored after the render, got {restored_rate}"
    );

    // Clean up the simulated device rate for the tests that follow.
    {
        let graph = get_audio_graph().unwrap().lock();
        graph
            .effect_manager
            .lock()
            .set_sample_rate(TARGET_SAMPLE_RATE as f32);
    }
}
