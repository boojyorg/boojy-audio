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
  - `lib/screens/daw/mixins/` - DAW screen mixins (recording, playback, etc.)
  - `lib/widgets/` - UI components (timeline, piano roll, painters, shared)
  - `lib/controllers/` - Playback, recording, track controllers
- `docs/` - Architecture docs, roadmap, design specs

## Running Tests

- **Flutter tests**: `cd ui && flutter test`
- **Rust tests**: `cd engine && cargo test`
- **Static analysis**: `cd ui && flutter analyze --fatal-infos`
- **Rust lints**: `cd engine && cargo clippy --all-targets`
- **Format check**: `cd ui && dart format --set-exit-if-changed .`
- CI runs all of the above on every PR — all must pass

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
- **Engine interface** uses mixins: `AudioEngine extends _AudioEngineBase with _TransportMixin, _RecordingMixin, ...`
- **Platform-specific code** uses conditional imports (native/web/stub pattern)
- **Recording flow**: engine `stop_recording()` returns `RecordingResult`, handled by `daw_recording_mixin.dart`

## UI Change Guidelines

When modifying UI widgets:
- **Check parent consumers**: Before changing a widget's API or layout, check all places it's used
- **Preserve existing behavior**: Design changes should not break functionality in other panels
- **Test at different window sizes**: The DAW layout is responsive — verify changes at small and large sizes
- **Painters are sensitive**: Changes to `CustomPainter` classes affect rendering across the timeline
- **Use `Log.d()` / `Log.e()` / `Log.i()`** for logging (from `utils/logger.dart`), not `print()`

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
