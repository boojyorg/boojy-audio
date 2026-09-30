---
paths:
  - engine/src/ffi/**
  - engine/src/api/**
  - ui/lib/audio_engine_*.dart
  - ui/lib/**/*_native.dart
---

# FFI: bridging the Rust engine and the Flutter UI

The boundary is **raw `dart:ffi`**, three layers (`api/` → `ffi/` shim → Dart binding); the
layout is in `docs/ARCHITECTURE.md`. **Use the `add-ffi` skill** to add a function: it wires all
7 files, including the `ffi_catch` wrapper every shim needs. Keep `api/` free of `extern "C"` and
raw pointers (one commented exception in `api/vst3.rs`). Don't reintroduce `flutter_rust_bridge`:
it was dropped on purpose.

## Gotchas

- **App stuck on "initializing"** → a missing FFI symbol. The Dart `lookupFunction` name must
  match the Rust `#[no_mangle]` name exactly.
- **Manager lock order is `synth → track → effect`.** The audio callback holds
  `track_synth_manager` for the whole buffer and then takes `track_manager` / `effect_manager`, so
  an API path that holds either of those and *then* locks `track_synth_manager` deadlocks against
  the callback (silent freeze; froze `save_project` in CI). Lock in callback order, or snapshot and
  drop the guard first. Examples: `export_to_project_data` / `restore_from_project_data` in
  `engine/src/audio_graph/project.rs`.
- **Track locks are non-reentrant** (`parking_lot::Mutex`). `TrackManager::get_track`,
  `get_master_track` and `remove_track` lock every track, so calling them while holding a `Track`
  lock freezes the API thread silently. Snapshot into locals and drop the guard first (see
  `find_return_by_effect_type` / `get_track_sends` in `engine/src/api/sends.rs`).
- **The engine is real seconds everywhere; only the UI thinks in beats.** MIDI clips/notes are
  beats in the UI, audio clips seconds; everything crossing the FFI is seconds at the current
  tempo (`beats × 60 / tempo`). So **every tempo write goes through `_onTempoChanged`**
  (`daw_screen.dart`), which re-pushes MIDI, audio clip starts, automation and playback caches;
  never call bare `audioEngine.setTempo()`. **Except the playhead:** engine `set_tempo` already
  rescales it, so don't also `transportSeek` from Dart (it double-scales and drags the playhead).
