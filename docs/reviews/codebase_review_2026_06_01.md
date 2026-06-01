# Boojy Audio — State-of-the-App Review

**Date:** 2026-06-01
**Version under review:** v0.4.0 (in development, `pubspec 0.4.0+3`; v0.3.2 last released), end of the visual/UX-polish cycle — last item before tag is the piano-roll lane colours
**Scope:** whole-app correctness audit — engine realtime path, DSP, persistence/export, VST3 hosting, FFI lock safety, UI screens/editors, command/undo layer, round-trip fidelity, testing, and repo/CI. Improve the app, *not* add features.
**Extends:** `docs/reviews/codebase_review_2026_05_29.md` (the v0.3.x trust/correctness audit). This one is the v0.4-family follow-up: it re-confirms which of those defects are *still live* after the v0.3.1/v0.3.2 hardening, and surfaces a new cluster the polish work never touched (recorder audio-thread blocking, VST3 lifecycle protocol violations, FFI lock-order inversions, DeleteTrack content loss).

**How this review was produced:** parallel subsystem reads followed by **adversarial verification** — every candidate defect was re-checked by independent skeptics trying to refute it. **51 confirmed; 33 refuted and dropped.** All findings are **code-level confidence**: no GUI reproduction was run, so runtime-repro steps are noted where cheap. The green test suite does not exercise any of these paths.

> **Read this first:** the suite is green, so this review is *not* about failing tests. It is about **latent correctness bugs the green suite never reaches**. The happy path the dev tests on (120 BPM, 48 kHz built-in stereo, single-machine projects, no plugins) is solid. The app is fragile the moment a real session diverges from that: a non-default device rate, a real VST3 plugin, an undo after a destructive edit, or a project file from another tempo/machine.

---

## 1. Executive summary + scorecard

Boojy Audio remains a capable alpha DAW with strong architecture and exemplary FFI *discipline*, but this audit confirms that the v0.3.x hardening cycle fixed the *playing* path while leaving three parallel weak spots untouched, and that the v0.4 polish cycle (correctly) touched none of them. The standouts:

- **The recorder runs the audio thread like a non-RT thread.** `recorder.process_frame` takes 2–6 blocking `parking_lot::Mutex` locks *per sample* (C2) and emits `eprintln!` on state transitions and every 2 seconds *on the audio thread* (C3) — the exact pattern the renderer deliberately replaced with contention counters. The stopped-path renderer callback also still takes blocking locks per frame (C1). The playing path was hardened; the recording and idle paths were not.
- **VST3 violates the plugin lifecycle protocol at the C++ boundary.** `setActive()` is never called (C30, **critical** — strictly-compliant Steinberg plugins output silence or crash), freshly-loaded plugins always report `is_effect=true` so every instrument loaded from a project is silent (C32), preset changes never reach the processor (C34), and `restartComponent` flags are dropped (C35). This subsystem (**D**) breaks the moment a user opens a plugin from a saved project.
- **`DeleteTrackCommand` is a content shredder.** Undo recreates an empty shell — clips, MIDI patterns, effects, and sends are never captured before delete and never restored (C68/C76/C97), and redo targets a stale engine ID so the restored track never goes away (C62). Track deletion is the single most common destructive action and its undo is broken three ways.
- **A systemic stale-ID-on-redo / silent-no-op pattern persists in the command and round-trip layers.** Split-clip undo leaves ghost clips (C52/C63/C64), several editor actions skip the undo system entirely (C53/C54/C59), and `UndoRedoManager` *permanently discards* a command if its undo throws (C66) — silent history corruption with no diagnostic.
- **Round-trip fidelity breaks on any non-default project.** Engine tempo is not synced before MIDI restore, so a 140 BPM project reopens with notes on the wrong grid (C72); a failed `loadProject` is treated as success and overwrites the project path (C73/C77); an in-flight recording clip can be written into `ui_layout.json` mid-record (C74); and untrusted/hand-edited project files throw unhandled `FormatException`s that silently reset the whole UI layout (C79/C80).

The bright spots are still real: FFI panic-guarding and the documented snapshot pattern are correct *where applied*. But the FFI **lock** architecture earns a **D** this round — the snapshot pattern was *not* applied consistently (add_send self-send, remove_return during playback, an AB/BA lock-order inversion in `load_audio_file_to_track_api`), and a sentinel `0` return collides with the master track ID. The audit's most uncomfortable finding is unchanged from last cycle and now confirmed across more subsystems: **the green suite is green because it runs single-threaded, at 48 kHz, on the happy path, and silently no-ops when the dylib is absent.**

### Scorecard

| Area | Grade | Note |
|---|---|---|
| Engine — realtime path | **C+** | Playing path hardened (sub-block render, NaN guards, per-sample alloc removed, contention counters). But the *stopped* callback still blocks per-frame, the *recorder* takes 2–6 locks + does `eprintln!` I/O per sample, per-callback `Vec::clone` allocs live inside the snapshot, a `stretch_factor=0` divide makes clip_end infinite, and the offline `has_vst3` heuristic silences built-in synths on any track with FX. |
| Engine — DSP | **C+** | Three live high-sev correctness bugs: synth release click (fades from sustain not current level), hardcoded 48 kHz across *all* effects, sampler infinite loop from a serialized project. Sampler envelope is right; synth envelope is not. No denormal protection on ARM desktop. Suite tests only the 48 kHz happy path. |
| Engine — persistence / export | **C+** | Core save/load works; but audio-clip ID aliasing breaks multi-file projects, MIDI CC is saved then dropped on offline render, "mono" export writes dual-mono stereo, LUFS K-weighting ignores sample rate, VST3 block size hardcoded to 512 on reload, and the `duration<=1.0` guard skips legitimate 1-second projects. |
| VST3 hosting | **D** | Loads + plays in the happy path, but multiple crash-class bugs activate on: opening a project from another machine, opening an editor, a mono-output instrument, or a MIDI CC. Per-plugin mutex held across `process()` while the edit controller is poked from the same thread — a logical race the mutex doesn't protect. |
| FFI — lock safety | **D** | Multiple confirmed/latent deadlock paths (add_send self-send, remove_return during playback, AUDIO_CLIPS/AUDIO_GRAPH lock-order inversion), a silent error-swallowing background helper, and an ambiguous `0` sentinel that collides with master track ID. The correct snapshot pattern exists but is *not* applied consistently. Green only because tests run single-threaded with no live stream. |
| UI — screens / editors | **C+** | Command/undo scaffolding is structurally sound, but split, consolidate, and piano-roll-delete undo paths have holes a real session hits immediately: ghost clips after undo, a permanently-broken undo stack after note-delete. |
| Commands / undo | **C+** | Architecturally sound; several hazards correctly guarded with `_currentXyzId`. But four high-sev defects live: DeleteTrack redo stale ID, SplitAudioClip leaves right clip audible + left untrimmed after undo, Bypass/SetParam store stale `effectId` across a remove/undo cycle, and UndoRedoManager discards commands on exception. |
| Round-trip fidelity | **C+** | Dual-source split is well-conceived and `toUiLayoutJson`/`fromUiLayoutJson` cleanly separate engine- vs UI-owned fields. But load-path defects mean a project from a different tempo / an auto-save backup / a post-delete-undo state opens with wrong note timing, missing clips, or an uncleared project path — invisible at default 120 BPM. |
| Testing | **C+** | Real teeth (golden save/reload, send/undo round-trips, WAV energy; good model + command unit coverage). But two dead-stub command classes silently no-op, RecordingComplete redo targets stale IDs, UndoRedoManager loses commands on failure, **zero** painter tests, and the engine integration suite silently skips when the dylib is absent. Not pre-1.0 safe for undo-heavy musicians. |
| Repo / CI | **C+** | CI `cargo clippy` is **not** `-D warnings` despite CLAUDE.md claiming "CI rejects warnings" (trains devs to ignore Rust warnings); empty-stub `MoveMidiClipCommand`; no device-disconnect recovery; both lockfiles gitignored (non-reproducible builds). |

---

## 2. Confirmed bugs (severity-ranked)

51 adversarially-confirmed defects, grouped by severity. All are **code-confirmed**; no interactive GUI repro was run. Cheap repros noted where available.

### Critical

- **C30** — **VST3 `IComponent::setActive()` is never called** — `engine/vst3_host/vst3_host.cpp:709`. `vst3_activate_plugin` calls `setProcessing(true)` but skips the mandated `setupProcessing → setActive(true) → setProcessing(true)` order; teardown skips `setActive(false)`. Strictly-compliant plugins output silence or crash in `process()`. *Repro: load a Steinberg stock VST3 (e.g. Retrologue), play a note → silent.*
- **C52** — **MIDI split undo leaks both halves; three clips end up on the track** — `ui/lib/widgets/timeline/timeline_gesture_layer.dart:394`. `SplitMidiClipCommand.onUndo` restores the original via `onCopied` but never `onDeleted`s the left/right halves. *Repro: draw a MIDI clip → Slice tool click middle → Cmd+Z → three clips remain.*

### High

**Engine — realtime**
- **C1** — **Stopped-path callback takes blocking locks per sample** — `engine/src/audio_graph/renderer.rs:567`. The not-playing branch acquires `effect_manager.lock()` + `track_manager.lock()` inside the per-frame loop (567/569/573); the playing path's try_lock-once treatment was never ported here. *Repro: add an effect via FFI while MIDI preview is active → dropout on stop.*
- **C2** — **`recorder.process_frame` takes 2–6 blocking Mutex locks per sample** — `engine/src/recorder.rs:399`. `state.lock()`, then unconditional `tempo.lock()` + `time_signature.lock()` (413/414), plus extra locks + a second `state.lock()` on transitions. None use `try_lock`. *Repro: drag the tempo slider while recording → xruns.*
- **C3** — **`eprintln!` blocking I/O on the audio thread during recorder state transitions** — `engine/src/recorder.rs:472` (also 477/485/498/515/533, incl. a 2-second modulo at 532). The renderer replaced exactly these for xrun reasons; the recorder was missed. *Repro: enable count-in, start recording.*
- **C4** — **Per-callback `Vec::clone` allocations inside the snapshot while holding `track_manager`** — `engine/src/audio_graph/renderer.rs:736`. `audio_clips/midi_clips/fx_chain/volume_automation.clone()` + `sends...collect()` per track per callback; only the outer `snapshot_buf` is pre-allocated, not the inner per-track Vecs. *Repro: 8 tracks × 10 clips, profile malloc inside the callback.*
- **C6** — **Offline `has_vst3` heuristic silences the built-in synth on any track with FX** — `engine/src/audio_graph/offline.rs:175` (same at 561). `has_vst3 = !fx_chain.is_empty()` routes all MIDI to the VST3 queue even for built-in-only chains; the synth never gets note_on/off. The realtime path inspects the actual `EffectType`. *Repro: add reverb to a MIDI track, export → that track is silent.*

**Engine — DSP**
- **C11** — **Synth release always fades from sustain, ignoring actual `env_level`** — `engine/src/synth.rs:218`. `sustain * (1 - release_progress)` instead of `self.env_level`. The sampler captures `release_start_level` correctly; the synth (the default instrument) does not. *Repro: attack=2s, sustain=0.7, release after 0.05s → audible jump/click.*
- **C12** — **All effects hardcode `TARGET_SAMPLE_RATE=48000`** — `engine/src/effects.rs:88`. Biquad design, compressor/limiter coefficients, delay/chorus buffer sizing, chorus LFO phase all ignore the real device rate. At 44.1 kHz a 1 kHz EQ band lands at ~916 Hz; compressor attack is ~9% short. Invisible because tests use the constant directly. *Repro: set output to 44.1 kHz, apply a 1 kHz peaking band.*

**Engine — persistence / export**
- **C22** — **"Mono" export writes a dual-mono stereo file** — `engine/src/export/wav.rs:45-48` (MP3 at `mp3.rs:64-67`). `stereo_to_mono` then `mono_to_stereo`; all writers hardcode `channels: 2`. *Repro: export with mono=true, inspect header → channels=2.*
- **C23** — **MIDI CC restored to clips but dropped on offline render** — `engine/src/audio_graph/offline.rs:326-328` (and `render_track_offline` at 702). CC is serialized (`project.rs:145-166`) and reconstructed (`project.rs:932-943`) but both render paths have a bare `{}` arm. *Repro: record a clip with sustain held, export → notes don't sustain.*
- **C24** — **VST3 block size hardcoded to 512 on reload** — `engine/src/audio_graph/project.rs:665`. Ignores the user's buffer-size preset; if the runtime block exceeds 512 the plugin processes an oversized buffer (UB/silence). The comment admits it. *Repro: load a VST3 project with a 2048-frame "High Stability" buffer.*

**VST3**
- **C32** — **`vst3_get_plugin_info()` always reports `is_effect=true`** — `engine/vst3_host/vst3_host.cpp:644`. Accurate subcategory detection only runs on scan; `VST3Effect::new()` reads `get_info()` after load, so every plugin loaded from a project path is treated as an effect. *Repro: load any VST3 instrument from a project file → MIDI produces silence.*
- **C33** — **`vst3_set_parameter_value()` pokes `IEditController` from the audio thread** — `engine/vst3_host/vst3_host.cpp:980`. Called via `VST3Effect::set_parameter_value()` from the UI thread while audio is inside `process()`; the controller is UI-thread-affine. The codebase documents and avoids this race for the CC path (893-900) but leaves the direct-set path unguarded. *Repro: drag a plugin param knob while playing.*
- **C34** — **`vst3_set_program()` never pushes the change to the processor** — `engine/vst3_host/vst3_host.cpp:1535`. Calls `setParamNormalized` on the controller but never queues it into `param_changes`/`inputParameterChanges`, so the editor updates but the sound doesn't. *Repro: select a factory preset → name changes, audio doesn't.*
- **C35** — **`restartComponent()` ignores all restart flags** — `engine/vst3_host/vst3_host.cpp:82`. Returns `kResultOk` to everything; `kReloadComponent`/`kIoChanged` (sample-rate / IO reconfig) are dropped, leaving plugins in an undefined state. *Repro: change sample rate on an aggregate device while a VST3 is in the chain.*

**FFI — locks**
- **C44** — **Lock-order inversion between AUDIO_CLIPS and AUDIO_GRAPH** — `engine/src/api/mod.rs:135`. `load_audio_file_to_track_api` takes CLIPS then GRAPH (136/139); every other site (e.g. `stop_recording`, `recording.rs:248-307`) takes GRAPH then CLIPS — a classic AB/BA deadlock. Exercised on every audio-file drag. *Repro: drag an audio file while stopping a recording on a multi-core device.*
- **C46** — **`try_with_graph_mut` background helper silently discards the `Result`** — `engine/src/api/helpers.rs:76`. On lock contention it spawns a thread, returns `Ok(queued_msg)` immediately, then `let _ = f(...)` swallows any `Err` and runs in an arbitrary thread with no ordering vs subsequent API calls (undo/redo can reorder). Currently zero callers — latent. *Repro: wire a caller with a failing closure → Err dropped, UI shows success.*
- **C47** — **`find_return_by_effect_type` returns `0` for "not found", colliding with master track ID** — `engine/src/ffi/sends.rs:21`. Returns `0` on `Ok(None)`, `-1` on error; master is always ID 0 (`track.rs:583`). Dart cannot distinguish "no return" from "master is the return". *Repro: call with an unknown effect type on a fresh project → Dart receives 0.*

**UI — screens**
- **C53** — **`consolidateSelectedClips` bypasses undo entirely** — `ui/lib/screens/daw/mixins/daw_clip_mixin.dart:310`. Calls `deleteClip`/`addClip` directly, no `Command`. *Repro: select two MIDI clips → Consolidate → Cmd+Z undoes some unrelated action.*
- **C54** — **`deleteSelectedNotes` misses `saveToHistory`** — `ui/lib/widgets/piano_roll/operations/note_operations.dart:86`. `commitToHistory` returns early because `snapshotBeforeAction` is null; deletion executes with no undo entry. *Repro: piano roll → select notes → Delete → Cmd+Z no-ops, notes gone.*

**Commands / undo**
- **C62** — **`DeleteTrackCommand` redo uses a stale track ID** — `ui/lib/services/commands/track_commands.dart:76`. Undo creates a new engine track but never stores its ID; redo calls `engine.deleteTrack(trackId)` on the original gone ID → no-op, restored track persists. *Repro: add track → undo → redo → track stays.*
- **C63** — **`SplitAudioClipCommand` undo leaves the right clip audible** — `ui/lib/widgets/timeline/timeline_gesture_layer.dart:347`. Removes the right clip from the UI list but never `engine.removeAudioClip()`s the engine ID registered at line 327. *Repro: split an audio clip → Ctrl+Z → right half still plays.*
- **C64** — **`SplitAudioClipCommand` never trims the left clip in the engine** — `ui/lib/widgets/timeline/timeline_gesture_layer.dart:303`. `onSplit` `copyWith`s the UI clip but never `engine.setClipDuration()`; the engine plays full pre-split length, overlapping the right region. *Repro: split any audio clip → left clip sounds full-length.*
- **C65** — **`BypassEffectCommand`/`SetEffectParameterCommand` go stale after a RemoveEffect undo** — `ui/lib/services/commands/effect_commands.dart:131`. `effectId` is a `final` field; after RemoveEffect undo the engine assigns a new ID (`_currentEffectId` updates in RemoveEffect but not in already-queued commands). *Repro: add → tweak → remove → undo×3 → bypass/param undo no-ops on the stale ID.*
- **C66** — **`UndoRedoManager` discards a command if its undo throws** — `ui/lib/services/undo_redo_manager.dart:116`. Pops from `_undoStack` before `command.undo()`; on throw, catch returns false but the command is added to neither stack — permanently lost, silent history corruption. Same in `redo()`. *Repro: make undo throw (e.g. null engine) → entry disappears.*

**Round-trip**
- **C72** — **Engine tempo not synced before MIDI restore on open** — `ui/lib/screens/daw/mixins/daw_project_mixin.dart:195`. `restoreClipsFromEngine(tempo, …)` runs with the pre-existing Dart tempo (defaults 120) before `getTempo()`/`setTempo` sync; every note start/end is recalculated at the wrong tempo. Fix: `recordingController.setTempo(audioEngine!.getTempo())` before restore. *Repro: save at 140 BPM, reopen → notes shifted off the grid.*
- **C73** — **Engine `loadProject` `Error:` string treated as success** — `ui/lib/services/project_manager_native.dart:68`. Never checks `loadResult.startsWith('Error:')`; always sets `_currentProjectPath` and returns `success: true`. The crash-recovery gate at `daw_screen.dart:2525` is meaningless because success is always true. *Repro: open a folder whose `project.json` references missing files → UI renders as if loaded.*
- **C74** — **In-flight recording clip written into `ui_layout.json`** — `ui/lib/services/midi_playback_manager.dart:30`. The `midiClips` getter appends `_liveRecordingClip!` (sentinel `clipId=-1`); any auto-save mid-record persists it, and reload deserializes a phantom or merges metadata onto the wrong clip. *Repro: start recording → auto-save/Cmd+S → stop → reopen → ghost clip.*
- **C76** — **`DeleteTrackCommand` undo does not restore MIDI clips** — `ui/lib/services/commands/track_commands.dart:76`. `onTrackDeleted` calls `removeClipsForTrack` before the command is pushed, but undo has no `addClip`. *Repro: MIDI track + notes → Cmd+Z twice → empty track.*
- **C83** — **`DeleteMidiClipCommand.execute/undo` are empty stubs** — `ui/lib/services/commands/clip_commands.dart:350`. Exported from the commands library; the working class is `DeleteMidiClipFromArrangementCommand`. Any caller silently no-ops. *Repro: call `DeleteMidiClipCommand(...).execute(engine)` → clip persists.*

**Repo / CI**
- **C95** — **CI `cargo clippy` is not fatal** — `.github/workflows/ci.yml:145`. No `-- -D warnings` / `RUSTFLAGS`, despite CLAUDE.md lines 55/149 claiming "CI rejects warnings." Trains devs to ignore Rust warnings. *Repro: land a clippy-warned function → CI green.*
- **C96** — **`MoveMidiClipCommand.execute/undo` are empty stubs** — `ui/lib/services/commands/clip_commands.dart:36`. Distinct from the working `MoveMidiClipPositionCommand` (line 1027); never instantiated, but a footgun for anyone wiring MIDI moves.
- **C97** — **`DeleteTrackCommand.undo` restores no clips/effects/sends** — `ui/lib/services/commands/track_commands.dart:76`. Recreates a mixer-settings-only shell; contradicts the CLAUDE.md "all state-changing actions wrapped in a Command" guarantee. *Repro: track + clip + reverb → delete → Ctrl+Z → empty shell.*

### Medium

- **C7** — **`return_bus_l/r.resize_with` allocates `Vec<f32>` on the audio thread when return count grows** — `engine/src/audio_graph/renderer.rs:816`. *Repro: add a return track while playing.*
- **C8 / C103** — **`query_coreaudio_latency` always queries the default device, not the selected one** — `engine/src/audio_graph/device.rs:82`. Latency display + compensation wrong for any non-default interface. *Repro: select a non-default DAC → latency readout shows built-in speakers.*
- **C9** — **Input-monitoring channel selector falls through for `input_channel >= 2`** — `engine/src/audio_graph/renderer.rs:993`. `ch == 0 ? input_l : input_r` — channels 2/3/4 all monitor the right channel. *Repro: set input_channel=2 on a multi-channel interface.*
- **C15** — **Voice stealing always evicts `voice[0]`** — `engine/src/synth.rs:380` (sampler at `sampler.rs:570`). Drops the oldest sustained note (typically the bass drone). *Repro: hold 8 notes, press a 9th → first note cuts out.*
- **C16** — **Synth one-pole filter coefficient is not sample-rate-corrected** — `engine/src/synth.rs:318`. `coeff = cutoff.clamp(...)` instead of `1 - exp(-2π fc/sr)`; cutoff knob is uncalibrated and rate-dependent. *Repro: set cutoff=0.5, the −3 dB point lands at ~5300 Hz at 48 kHz, shifts at 96 kHz.*
- **C26** — **LUFS K-weighting ignores `sample_rate`** — `engine/src/export/normalize.rs:135`. Hardcoded `alpha=0.98`, `let _ = sample_rate;`; BS.1770 coefficients are rate-dependent, so Spotify/Apple targets over/undershoot at 44.1 kHz. *Repro: export a reference tone at 44.1 kHz with PlatformTarget::Spotify, measure with a compliant meter.*
- **C27** — **`MidiRecorder.recording_start_samples` defaults to 0** — `engine/src/midi_recorder.rs:47`. Only set via `set_recording_start` (`api/midi_input.rs:313`); a path that skips it leaves the pre-boundary CC-exclusion guard (line 124) inconsistent.
- **C38** — **`VST3Plugin` is `Send+Sync` over a raw C++ pointer with no internal sync** — `engine/src/vst3_host.rs:655`. `Drop` (`vst3_unload_plugin`) runs on whatever thread drops the last `Arc`; thread-affine C++ resources (macOS NSView) crash if torn down off-main. *Repro: drop a VST3Effect with an open editor from a Dart isolate thread.*
- **C57** — **Captured MIDI clip never scheduled via `rescheduleClip`** — `ui/lib/screens/daw/mixins/daw_clip_mixin.dart:652`. `captureMidi` calls `addRecordedClip` but not `rescheduleClip` (cf. `_onMidiFileDroppedOnEmpty:1209`). *Repro: arm → play → Capture MIDI → spacebar → silent.*
- **C59** — **`createSamplerTrackWithSample` / `_convertAudioTrackToSampler` bypass undo** — `ui/lib/screens/daw_screen.dart:1430`. Call `createTrack` directly. *Repro: right-click audio clip → Open in Sampler → Cmd+Z → sampler track persists.*
- **C60** — **Left-trim overlap check uses initial start time, not current sibling end** — `ui/lib/widgets/timeline/timeline_gesture_layer.dart:1133`. A sibling whose end equals the target's right edge prematurely locks the left-trim handle.
- **C68** — **`DeleteTrackCommand` undo loses clips and MIDI patterns** — `ui/lib/services/commands/track_commands.dart:76`. (Companion to C76/C97.)
- **C69** — **`ReorderTrackCommand` and `ArmTrackCommand` are dead code** — `ui/lib/services/commands/track_commands.dart:156`. Reorder goes straight to `trackController.reorderTrack` (`daw_track_mixin.dart:207`); arm via `setTrackArmed` (`track_mixer_panel.dart:545`). Neither is undoable.
- **C77** — **`_currentProjectPath` overwritten on a failed load** — `ui/lib/services/project_manager_native.dart:73`. A later auto-save then overwrites the bad path. *Repro: open a corrupt folder over a valid project → auto-save replaces it on disk.*
- **C80** — **`int.parse(k)` on `track_colors` keys throws unhandled `FormatException`** — `ui/lib/services/project_persistence.dart:114`. A non-numeric key (`"master"`) propagates to `_loadUILayout`'s `catch`, silently dumping the whole layout. Use `int.tryParse`. *Repro: set `"track_colors": {"master": …}` and open.*
- **C85 / C94** — **FFI native memory freed before `toDartString`; mixed `malloc`/`calloc`** — `ui/lib/audio_engine_tracks.dart:44` (and `addEffectToTrack:358`). Inconsistent free ordering across ~15 wrappers leaks on a thrown exception. *Repro: trigger an FFI fault while recording, watch native heap.*
- **C86** — **`UndoRedoManager.undo()` swallows command exceptions, corrupting both stacks** — `ui/lib/services/undo_redo_manager.dart:116`. (Same root as C66; dangerous for `RemoveReturnCommand.undo` → `createReturnWithEffect` can return -1.)
- **C87** — **`AddSharedSendCommand.undo` keeps an orphaned return on engine error** — `ui/lib/services/commands/send_commands.dart:113`. `countSendsToReturn` returns -1 on error; `-1 == 0` is false, so the return bus keeps routing at full wet. *Repro: instrument `countSendsToReturn` to return -1, undo.*
- **C89 / C90** — **Zero painter test coverage; `NotePainter.shouldRepaint` omits `noteColor`** — `ui/lib/widgets/painters/note_painter.dart:223`. A track-color change with the same `notes` reference does not repaint; no test catches it (all 13+ painters untested). *Repro: `shouldRepaint` with color A vs B, identical other fields → false.*
- **C91** — **`RecordingController` (712 LOC, 6-state machine) has zero unit tests** — `ui/lib/controllers/recording_controller.dart:1`. Hot-plug device re-selection, auto-punch (`stopRecording` while transport plays), `restartRecording` timer hygiene all uncovered. *Observed regression: count-in bars=0 with `isAlreadyPlaying` leaves `_isCountingIn` stuck.*
- **C92** — **Integration tests skip silently when the dylib is absent** — `ui/integration_test/project_golden_paths_test.dart:57`. `if (!isNativeEngineAvailable) return;` → "9 tests passed" with every body skipped; a missing `./build.sh` step in CI produces a fully green vacuous suite. *Repro: delete `libengine.dylib`, run integration tests → 9 pass in ~0.1s.*
- **C98** — **Both lockfiles gitignored (non-reproducible builds)** — `.gitignore:4` (`Cargo.lock`), line 13 (`pubspec.lock`). For an application, both should be committed.
- **C99** — **Audio stream error callback only logs; device disconnect silently kills playback** — `engine/src/audio_graph/renderer.rs:1224`. No `DeviceDisconnected` event to Dart, no reconnection. *Repro: start playback, unplug the interface → playhead advances, no audio.*

### Low

- **C17** — Compressor "level" is instantaneous peak, mislabeled RMS; under-compresses hard-panned transients; `f32::midpoint` needs Rust 1.85+ — `engine/src/effects.rs:401`.
- **C18** — `ParametricEQ.update_coefficients()` doesn't `reset()` biquad state → zipper noise on EQ sweeps — `engine/src/effects.rs:240`.
- **C20** — Chorus (and delay at 487) use integer-truncated delay reads → aliased stepping artifacts — `engine/src/effects.rs:872`.
- **C28** — MP3 missing-ffmpeg error omits Windows instructions — `engine/src/export/mp3.rs:44-49`.
- **C29** — `start_recording` logs "Cleared 0 previous samples" (logs after `clear()`) — `engine/src/recorder.rs:113-115`.
- **C40** — `vst3_get_parameter_info()` lossy UTF-16→ASCII cast garbles non-Latin param names; a correct `string128_to_utf8` helper already exists — `engine/vst3_host/vst3_host.cpp:955`.
- **C51** — `get_all_track_ids` locks each track sequentially while holding `track_manager` → UI-poll stalls behind the render thread — `engine/src/api/tracks.rs:280`.
- **C61** — `_getSelectedTrackType` / `_getSelectedTrackName` duplicated in `daw_screen.dart:821` alongside the `DAWTrackMixin` versions — divergence risk.
- **C71** — Rust string pointer leaked if `toDartString()` throws before `_freeRustString` (no try/finally) — `ui/lib/audio_engine_tracks.dart:33`.
- **C93** — `SplitMidiClipCommand`/`SplitAudioClipCommand` have zero unit tests; a straddling note's right portion silently disappears (intentional, undocumented, untested) — `ui/lib/services/commands/clip_commands.dart:515`.
- **C104** — Selected output device name not persisted in `project.json`; reverts to system default on reload — `engine/src/project.rs:20`.

> **33 candidates were refuted and dropped** by the adversarial pass — do not re-hunt them (mirrors the `v0.3-audit-deferred-and-false-positives` memory). They are not listed here; the survivors above are the actionable set.

---

## 3. Prioritized improvement backlog

Ranked by severity × impact ÷ effort. **No new features** — fixes, hardening, tests, refactors. Effort: S/M/L/XL.

| # | Item | Sev | Effort | Bugs / files |
|---|---|---|---|---|
| 1 | **VST3 lifecycle protocol: call `setActive()`, fix post-load type, deliver preset changes to the processor, honour restart flags** | critical | M | C30, C32, C34, C35 — `vst3_host.cpp:709/644/1535/82` |
| 2 | **Make `DeleteTrackCommand` capture & restore clips/MIDI/effects/sends, and store the new engine ID for redo** | high | M | C62, C68, C76, C97 — `track_commands.dart:76` |
| 3 | **Stop blocking + I/O on the audio thread: try_lock the stopped-path callback and the recorder, replace `eprintln!` with contention counters** | high | M | C1, C2, C3 — `renderer.rs:567`, `recorder.rs:399/472` |
| 4 | **Fix `UndoRedoManager` exception handling so a failed undo/redo never loses the command** | high | S | C66, C86 — `undo_redo_manager.dart:116` |
| 5 | **Fix split-clip undo: delete both MIDI halves, remove the right engine audio clip, trim the left engine clip** | high | M | C52, C63, C64 — `timeline_gesture_layer.dart:394/347/303` |
| 6 | **Gate `loadProject` on the `Error:` prefix; don't set `_currentProjectPath` on failure** | high | S | C73, C77 — `project_manager_native.dart:68/73` |
| 7 | **Sync engine tempo before `restoreClipsFromEngine` on project open** | high | S | C72 — `daw_project_mixin.dart:195` |
| 8 | **Route consolidate + piano-roll note-delete through the undo system (`saveToHistory`/Command)** | high | S | C53, C54 — `daw_clip_mixin.dart:310`, `note_operations.dart:86` |
| 9 | **Fix `has_vst3` heuristic in offline render to inspect `EffectType`** | high | S | C6 — `offline.rs:175/561` |
| 10 | **Write true 1-channel mono on mono export** | high | S | C22 — `wav.rs:45-48`, `mp3.rs:64-67` |
| 11 | **Deliver MIDI CC during offline render (both render paths)** | high | S | C23 — `offline.rs:326/702` |
| 12 | **Make CI clippy fatal (`-D warnings`) — match the CLAUDE.md claim** | high | S | C95 — `ci.yml:145` |
| 13 | **Re-base all effects on the live device sample rate (or resample at the boundary)** | high | L | C12 — `effects.rs:88` |
| 14 | **Fix synth release to fade from current `env_level`; fix per-callback stale `effectId` in Bypass/SetParam** | high | M | C11, C65 — `synth.rs:218`, `effect_commands.dart:131` |
| 15 | **Resolve FFI lock-order inversion + sentinel collision; apply the snapshot pattern to add_send/remove_return** | high | M | C44, C46, C47 — `api/mod.rs:135`, `helpers.rs:76`, `ffi/sends.rs:21` |
| 16 | **Stop writing the live recording clip into `ui_layout.json`; guard `int.tryParse` on track_colors** | high | S | C74, C80 — `midi_playback_manager.dart:30`, `project_persistence.dart:114` |
| 17 | **Don't poke `IEditController` / drop+reattach from the audio thread (queue param/program changes)** | high | M | C33 — `vst3_host.cpp:980` |
| 18 | **Remove dead stub commands; wire MoveMidiClip/Reorder/Arm or delete them** | high | S | C83, C96, C69 — `clip_commands.dart:36/350`, `track_commands.dart:156` |
| 19 | **VST3 block size from the user's buffer-size preset on reload** | medium | S | C24 — `project.rs:665` |
| 20 | **Make integration tests fail (not skip) when the dylib is absent; commit both lockfiles** | medium | S | C92, C98 — `project_golden_paths_test.dart:57`, `.gitignore` |
| 21 | **NaN/Inf + device-disconnect resilience: surface a `DeviceDisconnected` event to Dart** | medium | M | C99 — `renderer.rs:1224` |
| 22 | **Sample-rate-correct LUFS K-weighting and the synth one-pole filter; calibrate the cutoff knob** | medium | M | C26, C16 — `normalize.rs:135`, `synth.rs:318` |
| 23 | **Eliminate per-callback inner-Vec clones + return-bus resize allocs** | medium | M | C4, C7 — `renderer.rs:736/816` |
| 24 | **Voice-stealing policy (release-phase first, then oldest); multi-channel input routing + selected-device latency** | medium | M | C15, C9, C8/C103 — `synth.rs:380`, `renderer.rs:993`, `device.rs:82` |
| 25 | **Capture-MIDI playback scheduling; sampler/convert-track undo; left-trim sibling check** | medium | M | C57, C59, C60 — `daw_clip_mixin.dart:652`, `daw_screen.dart:1430`, `timeline_gesture_layer.dart:1133` |
| 26 | **Add the missing tests: RecordingController state machine, painter `shouldRepaint`/golden, split + send error paths** | medium | L | C89, C90, C91, C93, C87 |
| 27 | **DSP polish: EQ state reset, interpolated chorus/delay, denormal flush** | low | S | C18, C20 — `effects.rs:240/872` |
| 28 | **Cleanup: UTF-8 param names, FFI free-ordering/try-finally, duplicate selected-track getters, log fixes, MP3 Windows hint, persist output device** | low | M | C40, C71, C85, C94, C61, C29, C28, C104, C38 |

---

## 4. Recommended next theme

**Primary — "Trust under a real session" (a v0.5-family correctness/hardening cycle, after v0.4 ships its colour polish).** Items #1–#12 above. The throughline is identical to the v0.3.x theme and it is *not yet resolved*: the app silently betrays the user the moment a session leaves the happy path. The new evidence is that the failure surface widened — it is now (a) any real VST3 plugin (lifecycle violations, **D** grade), (b) the single most common destructive action (DeleteTrack content loss, three ways), (c) the recording path (audio-thread blocking + I/O the renderer already fixed elsewhere), and (d) any project from a different tempo/machine (round-trip). These are mostly S/M fixes that cluster in four files (`vst3_host.cpp`, `track_commands.dart`, `recorder.rs`, the project-load mixin), and a single save/reload-fidelity test plus an execute→undo→redo command test covers a large fraction at once. Highest signal-to-effort; directly resumes the dogfood beat.

**Alternative — "DSP & device correctness" (the audio-quality cluster: #13, #22, #23, #24, #27).** The cost: this is the *right* eventual work (every effect mistuned off 48 kHz is embarrassing for a music tool), but it is heavier and lower-urgency than the trust cluster. The sample-rate refactor (#13) is L-effort and risks regressing the playing path that v0.3.x just hardened, and it has no user-visible payoff for the dev's own 48 kHz machine — so it would be invisible progress that *feels* slow. It also doesn't stop data loss; shipping audio polish on top of DeleteTrack shredding undo just buries the trust problem deeper. Do it as the cycle *after* the trust cluster, once the fidelity and command round-trip tests exist to catch regressions.

**Recommendation:** finish v0.4's lane-colour item and tag, then open the v0.5 plan around the trust cluster (#1–#12). Crucially — **fix C92 (integration tests skip when the dylib is absent) and C95 (clippy non-fatal) first**, because every other fix in this list is only as trustworthy as the suite that guards it, and right now a green suite can mean "nothing ran."

---

*Generated 2026-06-01 from a multi-agent deep read + adversarial verification (51 confirmed, 33 refuted/dropped). Bug confidence is code-level; interactive GUI reproduction was not performed. Save to `docs/reviews/`.*
