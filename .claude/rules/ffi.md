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
- **Track locks are non-reentrant.** The engine uses `parking_lot::Mutex`, which does **not** support
  recursive locking. `TrackManager::get_track`, `get_master_track`, and `remove_track` each walk the
  track list and `.lock()` every track to compare ids — so calling any of them while already holding
  a `Track` lock **deadlocks the API thread silently** (no panic, no log; the UI just freezes).
  Snapshot what you need (`id`, `fx_chain`, `sends.iter().map(...)`) into locals and drop the
  `MutexGuard` before calling back into `TrackManager`. See `find_return_by_effect_type` and
  `get_track_sends` in `engine/src/api/sends.rs` for the snapshot pattern.
- **MIDI clips use beats** for startTime/duration; **audio clips use seconds.**
