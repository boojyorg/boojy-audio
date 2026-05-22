# Claude Code Instructions

## Build & Run

- **Debug build**: `./build.sh` (builds Rust engine, updates symlinks, copies dylib)
- **Release build**: `./build.sh release`
- **Run app**: `cd ui && flutter run -d macos` (Xcode run script auto-builds the engine)
- **sccache**: If installed (`brew install sccache`), build.sh uses it automatically
- Dev deps are built with `opt-level = 2` for audio performance even in debug
- If the app gets stuck on "initializing", it's likely a missing FFI symbol

## Project Structure

- `engine/` - Rust audio engine (builds to libengine.dylib)
  - `src/ffi/` - C-compatible FFI layer (one file per domain: transport, clips, recording, etc.)
  - `src/api/` - Internal API modules called by FFI functions
  - `src/audio_graph/` - Audio renderer, offline processing, device management
- `ui/` - Flutter frontend
  - `lib/models/` - Immutable data classes with JSON serialization
  - `lib/services/commands/` - Undo/redo command classes
  - `lib/services/project_persistence.dart` - Canonical UI layout save/load checklist
  - `lib/screens/daw/mixins/` - DAW screen mixins (recording, playback, etc.)
  - `lib/widgets/` - UI components (timeline, piano roll, painters, shared)
  - `lib/controllers/` - Playback, recording, track controllers
  - `integration_test/` - Native engine golden-path tests (macOS)
- `docs/` - Architecture docs, roadmap, design specs

## Running Tests

- **Flutter tests**: `cd ui && flutter test`
- **Integration tests**: `./build.sh` first, then `cd ui && flutter test integration_test/ -d macos`
- **Rust tests**: `cd engine && cargo test`
- **Static analysis**: `cd ui && flutter analyze --fatal-infos`
- **Rust lints**: `cd engine && cargo clippy --all-targets`
- **Format check**: `cd ui && dart format --set-exit-if-changed lib/ test/ integration_test/`
- CI runs all of the above on every PR (macOS full pipeline + Windows analyze/test/clippy, no VST3) — all must pass

## FFI Workflow (Adding a New Engine Function)

When adding a new function that bridges Rust and Dart:

**Rust side:**
1. Add the business logic in the appropriate `engine/src/api/` module
2. Add the FFI wrapper in the appropriate `engine/src/ffi/` file:
   ```rust
   #[no_mangle]
   pub extern "C" fn my_function_ffi(param: c_int) -> *mut c_char {
       match api::my_function(param as i32) {
           Ok(msg) => safe_cstring(msg).into_raw(),
           Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
       }
   }
   ```

**Dart side (in `ui/lib/audio_engine_native.dart`):**
3. Add native typedef, Dart typedef, late final field, and symbol lookup in constructor
4. Add a wrapper method that calls the native function
5. Use `print()` not `debugPrint()` in this file (no Flutter foundation import)

**Interface:**
6. Add the method signature to `AudioEngineInterface`
7. Add stubs in `audio_engine_stub.dart` and `audio_engine_web.dart`

## Architecture Rules

- **MIDI clips** use **beats** for startTime/duration; **Audio clips** use **seconds**
- **Undo/redo** uses the command pattern: `Command`, `CompositeCommand`, `UndoRedoManager`
  - All state-changing user actions should be wrapped in a Command
  - Known covered areas: clip move/trim, mixer fader/pan/mute/solo, built-in + VST3 effect params — new controls (e.g. send knobs in v0.3.0) must follow the same pattern
- **UI persistence**: new fields saved in `ui_layout.json` must go through `ProjectPersistence.collect()` / `applyUILayout()` — do not scatter field lists across project managers
- **Timeline layout**: `timeline_view.dart` uses `part` files for `timeline_gesture_layer.dart` and `timeline_track_list.dart` — private methods share one library; import `timeline_view.dart` only, never the part files directly
- **Engine interface** uses mixins: `AudioEngine extends _AudioEngineBase with _TransportMixin, _RecordingMixin, ...`
- **Platform-specific code** uses conditional imports (native/web/stub pattern)
- **Recording flow**: engine `stop_recording()` returns `RecordingResult`, handled by `daw_recording_mixin.dart`
- **Track locks are non-reentrant**: engine uses `parking_lot::Mutex` which does **not** support recursive locking. `TrackManager::get_track`, `get_master_track`, and `remove_track` all walk the track list and call `.lock()` on each track to compare ids — so calling any of them while holding another `Track` lock **deadlocks the API thread silently** (no panic, no log, the UI just freezes). Snapshot what you need (`id`, `fx_chain`, `sends.iter().map(...)`) into local variables and drop the `MutexGuard` before calling back into `TrackManager`. See `find_return_by_effect_type` and `get_track_sends` in `engine/src/api/sends.rs` for the snapshot pattern.

## UI Change Guidelines

When modifying UI widgets:
- **Check parent consumers**: Before changing a widget's API or layout, check all places it's used
- **Preserve existing behavior**: Design changes should not break functionality in other panels
- **Test at different window sizes**: The DAW layout is responsive — verify changes at small and large sizes
- **Painters are sensitive**: Changes to `CustomPainter` classes affect rendering across the timeline
- **Use `Log.d()` / `Log.e()` / `Log.i()`** for logging (from `utils/logger.dart`), not `print()`

## Milestone Workflow

Plan **one milestone at a time** — only one active [docs/plans/vX.Y-plan.md](docs/plans/). After each release: **dogfood** on a real project, then pick the next theme from friction (ROADMAP + FEATURE_TRACKER are backlog, not a pre-scheduled ladder).

### Design decisions (UI/UX)

Before locking implementation:

1. **Brainstorm with Tyr** — tradeoffs first (UX, then implementation). Ask; don’t dictate.
2. **ASCII mockups — 3–4 variants** when layout is ambiguous; Tyr picks before code.
3. **Defer on taste, push back on architecture** — one clear preference, then collaborate.

### v0.3.0 active plan

[docs/plans/v0.3.0-plan.md](docs/plans/v0.3.0-plan.md) — send/return via ⚡ FX picker, hidden master row.

## Changelog Workflow

When making bug fixes or feature changes:
1. Update `CHANGELOG.md` immediately after each fix
2. Add entries under the `## Unreleased` section
3. Use categories: `### Bug Fixes`, `### Features`, `### Improvements`
4. On release, change "Unreleased" to the version number and date

## Release Process

1. Update CHANGELOG.md with release date
2. Commit all changes
3. Tag with version: `git tag v0.x.x && git push origin v0.x.x`
4. GitHub Actions builds and creates draft release
5. Edit release notes in GitHub, then publish

## Documentation Layout

- `docs/ROADMAP.md` — version plan and what's being worked on now
- `docs/plans/vX.Y-plan.md` — detailed spec for the active version (features, mockups, scope)
- `docs/ARCHITECTURE.md` — system design, folder structure, FFI patterns
- `docs/FEATURE_TRACKER.md` — v1.0 feature checklist (what exists vs what's planned)
- `CHANGELOG.md` — release history; add entries under "Unreleased" during development

## Version Sync

All markdown files must stay in sync with the current development version.

**When starting a new version (creating a new plan doc):**
1. Update `docs/ROADMAP.md` — set "Current Version" and "Working On" lines, update version table
2. Update `README.md` — update the version/status line
3. Verify `CHANGELOG.md` has an empty `## Unreleased` section ready

**When releasing a version:**
1. `CHANGELOG.md` — rename `## Unreleased` → `## vX.Y.Z — YYYY-MM-DD`, add new empty `## Unreleased`
2. `docs/ROADMAP.md` — update "Current Version", mark version as Complete in table, update "Working On" to next version
3. `README.md` — update version reference
4. Move completed plan from `docs/plans/` → `docs/archive/plans/`
5. Update `docs/FEATURE_TRACKER.md` — check off newly completed features

**Files that reference the version (keep in sync):**
- `README.md` — project status line
- `docs/ROADMAP.md` — "Current Version" and "Working On" header lines
- `CHANGELOG.md` — release section headers
- `docs/FEATURE_TRACKER.md` — checked/unchecked items

## Linting & Formatting

- **Dart**: `flutter_lints` with 60+ rules in `analysis_options.yaml` — strict mode
- **Rust**: `clippy::pedantic` enabled with pragmatic exceptions in `lib.rs`
- **Formatting**: `dart format` for Dart, `rustfmt` for Rust
- Run `flutter analyze` and `cargo clippy` before submitting — CI rejects warnings

## Common Issues

<!-- Add recurring bugs and gotchas here as they come up -->
<!-- Format: - **Symptom** — cause and fix -->
- **App stuck on "initializing"** — Missing FFI symbol. Check that the Dart constructor's symbol lookup matches the Rust `#[no_mangle]` function name exactly
- **Tests pass but app crashes** — Likely a dylib mismatch. Run `./build.sh` to rebuild
- **Integration tests fail or skip on macOS** — Run `./build.sh` first so `libengine.dylib` exists
