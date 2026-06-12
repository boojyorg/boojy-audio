---
paths:
  - engine/src/ffi/**
  - engine/src/api/**
  - ui/lib/audio_engine_*.dart
  - ui/lib/**/*_native.dart
---

# FFI: bridging the Rust engine and the Flutter UI

The engine boundary is **raw `dart:ffi`** — no codegen, no bridge crate. It has **three layers**:

1. **Native API** — `engine/src/api/` (one module per domain). Pure Rust business logic, returns
   `Result<String, _>` etc. No `extern "C"`, no raw pointers here.
2. **`extern "C"` shims** — `engine/src/ffi/` (one file per domain) that `use crate::api` and wrap
   each API call in a C-ABI function. Pattern:
   ```rust
   #[no_mangle]
   pub extern "C" fn my_function_ffi(param: c_int) -> *mut c_char {
       match api::my_function(param as i32) {
           Ok(msg) => safe_cstring(msg).into_raw(),
           Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
       }
   }
   ```
3. **Dart binding** — the UI opens `libengine.{dylib,dll,so}` with `DynamicLibrary.open` and resolves
   each symbol via `lookupFunction` (see `ui/lib/audio_engine_base.dart` /
   `ui/lib/audio_engine_native.dart`). Use `print()` not `debugPrint()` in the native Dart file (no
   Flutter foundation import there).

**Adding an engine function = 3 steps: `api/` → `ffi/` extern-"C" shim → Dart binding.** Then add the
method to `AudioEngineInterface` and stub it in `audio_engine_stub.dart` + `audio_engine_web.dart`.

➡️ **The `add-ffi` skill automates most of this** (it touches the 7–8 files involved). Prefer it
over doing the wiring by hand.

## Don't reintroduce flutter_rust_bridge

FRB was considered (an old "M1" plan) and **deliberately dropped** — raw `dart:ffi` is the chosen
boundary. The `flutter_rust_bridge` Cargo dependency and its stale "replaced in M1" comment were
removed. Don't reintroduce FRB casually; it's an architecture-level change, not a convenience.

## Gotchas

- **App stuck on "initializing"** → a missing FFI symbol. The Dart `lookupFunction` name must match
  the Rust `#[no_mangle]` function name exactly.
- **Manager lock order is `synth → track → effect`.** The audio callback holds
  `track_synth_manager` across the whole buffer and only then takes `track_manager` /
  `effect_manager` — so any API path that holds either of those and *then* locks
  `track_synth_manager` can deadlock against a concurrent callback (silent freeze, no panic —
  this froze `save_project` twice in CI on 2026-06-12). API-vs-API can't deadlock (every FFI
  call serialises on the global graph mutex); the callback is the only concurrent thread.
  Acquire managers in callback order, or snapshot what you need and drop the guard before
  locking `track_synth_manager`. Canonical examples: `export_to_project_data` /
  `restore_from_project_data` in `engine/src/audio_graph/project.rs`.
- **Track locks are non-reentrant.** The engine uses `parking_lot::Mutex`, which does **not** support
  recursive locking. `TrackManager::get_track`, `get_master_track`, and `remove_track` each walk the
  track list and `.lock()` every track to compare ids — so calling any of them while already holding
  a `Track` lock **deadlocks the API thread silently** (no panic, no log; the UI just freezes).
  Snapshot what you need (`id`, `fx_chain`, `sends.iter().map(...)`) into locals and drop the
  `MutexGuard` before calling back into `TrackManager`. See `find_return_by_effect_type` and
  `get_track_sends` in `engine/src/api/sends.rs` for the snapshot pattern.
- **Time domains: the ENGINE is real seconds everywhere; only the UI thinks in beats.**
  UI-side, MIDI clips/notes use **beats** for startTime/duration and audio clips use **seconds**;
  every position crossing the FFI is converted to **real seconds at the current tempo**
  (`seconds = beats × 60 / tempo`). The engine never scales time by tempo — a legacy
  `tempo/120` playhead ratio in the renderer/export was removed in v0.6 batch 2 after it made
  audio clips play early *and* pitch-shifted at any tempo ≠ 120. Consequence: **on a tempo
  change the UI must re-push every engine position** — MIDI via
  `midiPlaybackManager.rescheduleAllClips`, audio clips via `setClipStartTime`, automation via
  `syncAllVolumeAutomationToEngine` — all of which live in `_onTempoChanged` (daw_screen.dart);
  route ANY tempo write through that handler, never bare `audioEngine.setTempo()`.
