# Boojy Audio Architecture

How the system works today. What should change about it lives in [BACKLOG.md](BACKLOG.md);
the hazards to respect when changing it live in `.claude/rules/`.

## The split

A Flutter desktop UI (macOS, Windows) drives a Rust audio engine over a raw `dart:ffi`
boundary. The engine owns everything that makes sound: the audio graph, instruments, effects,
recording, VST3 hosting and offline export. The UI owns layout, editing gestures, undo/redo and
project files that describe the UI's own state.

```
engine/                       Rust → libengine.{dylib,dll}
  src/api/                    business logic, one module per domain, no raw pointers
  src/ffi/                    extern "C" shims over api/, one file per domain
  src/audio_graph/            realtime renderer, offline renderer, device management, project I/O
  src/export/                 WAV (pure Rust) and MP3 (ffmpeg shell-out), see .claude/rules/audio-export.md
  src/{synth,sampler,drum_kit,effects,stretch,midi*,recorder}.rs
  vst3_host/                  C++ wrapper over the VST3 SDK (see its README); vst3sdk/ submodule
ui/lib/
  audio_engine*.dart          the Dart side of the FFI boundary
  models/                     immutable data classes with JSON (ClipData, MidiNoteData, TrackData…)
  services/                   ProjectManager, ProjectPersistence, UndoRedoManager + commands/, library, auto-save, snapshots, MIDI playback/capture, VST3, updater, settings
  controllers/                playback, recording, track, MIDI-clip, automation (ChangeNotifiers)
  screens/daw/                DAWScreen + mixins/ (clip, track, playback, recording, project, library, VST3, UI)
  widgets/                    transport_bar, timeline, piano_roll, mixer, device_chain, editors, library, start_screen, dialogs, shared/, painters/
  theme/                      colours, BI icon facade, theme provider
  state/                      UI layout state
ui/test/native/               engine golden-path tests over dart:ffi (plain flutter test, needs ./build.sh)
ui/test/goldens/              CustomPainter screenshot tests (macOS reference)
```

## FFI boundary

Three layers, no codegen: `engine/src/api/` (pure Rust, returns `Result`) → `engine/src/ffi/`
(`#[no_mangle] extern "C"` shims that stringify results) → Dart bindings that `lookupFunction`
each symbol. On the Dart side `AudioEngine` is composed from per-domain mixins
(`_TransportMixin`, `_RecordingMixin`, `_TracksMixin`, `_SendsMixin`, `_PluginsMixin`) over
`_AudioEngineBase`, and every engine method is declared on `AudioEngineInterface`.
`audio_engine.dart` selects the implementation by conditional export: native (FFI), web
(JS interop stub), or stub. The same native/web/stub pattern is used for project management,
drop targets and file dialogs.

Every FFI call serialises on one global graph mutex; the realtime audio callback is the only
concurrent thread. Lock order, the non-reentrant track locks, and the beats-vs-seconds contract
are in `.claude/rules/ffi.md`. Adding a function: the `add-ffi` skill.

## Audio graph and mixer routing

The realtime callback (`audio_graph/renderer.rs`) and offline export (`audio_graph/offline.rs`)
run the same signal chain, so a bounced file matches what you hear:

```
per track:  clips → instrument/synth → track FX chain → fader (volume/pan)
                                                          │
                                                          ├── main mix ──────────┐
                                                          └── post-fader sends ─┐ │
                                                                                ▼ │
return bus: per-return accumulator → return FX chain ───────────────────────┐  │ │
                                                                             ▼  ▼ ▼
                                       master volume → master pan → master FX → limiter → output
```

- **Sends are post-fader** and summed into a per-return accumulator each frame.
- **Returns are shared by effect type** (`api/sends.rs`): several tracks feed one reverb return
  rather than spawning duplicates.
- **The master stage is not applied to stems**, so a single-track stem equals the mix only after
  factoring it out. Details and the export processing order: `.claude/rules/audio-export.md`.
- **No plugin delay compensation.** Return-chain latency is not aligned against the dry signal.

**Stock instrument designs are kept deliberately small** ([PRODUCT.md](PRODUCT.md) says why).
The built-in synth is one oscillator (sine/saw/square/triangle), a one-pole lowpass, ADSR and
eight-voice polyphony, not three oscillators, a resonant filter, an LFO or a modulation matrix.
Growing it is a product decision, not a refactor.

## UI structure

```
Widgets (TransportBar, TimelineView, PianoRoll, Mixer, DeviceChain, LibraryPanel, EditorPanel)
    │ read/notify
Controllers (Playback, Recording, Track, MidiClip, Automation)   Services   UI state / Theme
    │
AudioEngine (dart:ffi)
```

- **State** is `provider` + `ChangeNotifier`, used lightly; most state flows through services
  and controllers rather than a deep provider tree. Riverpod is the deliberate future target
  only if this starts to hurt (`.claude/rules/flutter-ui.md`).
- **`DAWScreen`** is a `State` composed from mixins in `screens/daw/mixins/` (clip, track,
  playback, recording, project, library, VST3, UI). Recording: the engine's `stop_recording`
  returns the new clip id, and `daw_recording_mixin.dart` builds the clip and captured notes.
- **Large editors are mixin-composed too.** `PianoRoll` and `TimelineView` split behaviour into
  state, gesture, selection and operation mixins; `timeline_view.dart` additionally uses `part`
  files, so it is one library. Import the entry file only.
- **Painting** is `CustomPainter` (`widgets/painters/`): grid, notes, velocity and CC lanes,
  automation, ruler, nav bar. Golden tests cover the load-bearing ones.
- **Menus and pickers** share one overlay surface, `showBoojyMenu` in `widgets/shared/`;
  `BoojyDropdown` is the standard trigger chip and `ContextMenuHelper` routes right-clicks to it.

## Undo/redo

The command pattern: `Command` (execute/undo against the engine and UI), `CompositeCommand`
(runs all, undoes in reverse), `UndoRedoManager` (history). Every state-changing user action is
a command, including mixer and effect-parameter changes; in debug builds the manager rethrows
command errors so silently-dead handlers surface.

## Project persistence

A project folder holds two files with different owners. UI-only fields must go through
`ProjectPersistence.collect()` / `applyUILayout()` in `ui/lib/services/project_persistence.dart`
so manual save, auto-save and crash recovery stay in sync.

| Data | Owner | File |
| --- | --- | --- |
| Tracks, clips, tempo, instruments, effects and their state, audio file paths | Rust engine | `project.json` |
| Panel layout, loop region, track colours, view state, automation UI data | Dart UI | `ui_layout.json` |

Save: `DAWProjectMixin.getCurrentUILayout()` → `ProjectPersistence.collect()` →
`ProjectManager.saveProject()`, which writes `ui_layout.json` beside the engine's `project.json`.
Load: `ProjectManager.loadProject()` → `applyUILayout()`. `AutoSaveService` and
`SnapshotManager` reuse the same path. Bundled samples are copied from the asset bundle to app
support on first use (`bundled_content_service.dart`); the engine loads by filesystem path only.
