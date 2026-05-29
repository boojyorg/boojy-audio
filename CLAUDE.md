# Claude Code Instructions

## Memory

This repo uses a lightweight docs/memory system:

- **`dreams.md` (repo root), §1** — the active engineering target + a milestone checklist. Read it
  to know what we're working on now.
- **`.claude/rules/*.md`** — per-area gotchas with `paths:` frontmatter, meant to load when you
  touch matching files (`ffi.md`, `audio-export.md`, `flutter-ui.md`, `state.md`,
  `build-and-test.md`). Conditional loading is still flaky in early-2026 Claude Code, so treat these
  as organization — genuinely global rules live here in `CLAUDE.md`.
- **Claude Code auto memory** — incidental learnings (skim `/memory` after a big refactor).
- **git log** — the history. There is no incident log, backlog, or session ledger.

## Build & Run

- **Toolchain**: Flutter is pinned to **3.44.0 / Dart 3.12** via FVM (`ui/.fvmrc`). Run Flutter/Dart commands from `ui/` as **`fvm flutter …` / `fvm dart …`** so they use the pinned SDK. `build.sh` is unaffected (it only calls `cargo`). CI pins the same version in `.github/workflows/*.yml` (`FLUTTER_VERSION`).
- **Debug build**: `./build.sh` (builds Rust engine, updates symlinks, copies dylib)
- **Release build**: `./build.sh release`
- **Run app**: `cd ui && fvm flutter run -d macos` (Xcode run script auto-builds the engine)
- **sccache**: If installed (`brew install sccache`), build.sh uses it automatically
- Dev deps are built with `opt-level = 2` for audio performance even in debug
- If the app gets stuck on "initializing", it's likely a missing FFI symbol (see `.claude/rules/ffi.md`)

## Project Structure

- `engine/` - Rust audio engine (builds to libengine.dylib)
  - `src/ffi/` - C-compatible FFI layer (one file per domain: transport, clips, recording, etc.)
  - `src/api/` - Internal API modules called by FFI functions
  - `src/audio_graph/` - Audio renderer, offline processing, device management
  - `src/export/` - Offline render to WAV (pure Rust) / MP3 (see `.claude/rules/audio-export.md`)
- `ui/` - Flutter frontend
  - `lib/models/` - Immutable data classes with JSON serialization
  - `lib/services/commands/` - Undo/redo command classes
  - `lib/services/project_persistence.dart` - Canonical UI layout save/load checklist
  - `lib/screens/daw/mixins/` - DAW screen mixins (recording, playback, etc.)
  - `lib/widgets/` - UI components (timeline, piano roll, painters, shared)
  - `lib/controllers/` - Playback, recording, track controllers
  - `integration_test/` - Native engine golden-path tests (macOS)
- `docs/` - Architecture docs, roadmap, design specs

## Gates

A `PostToolUse` hook (`.claude/hooks/post-edit-validation.sh`) runs a **fast** gate after each edit:
`.rs` under `engine/` → `cargo check` + `cargo clippy`; `.dart` under `ui/` → `flutter analyze`. It
skips gracefully if the toolchain is missing. Full test suites are **not** run in that loop — run
them manually / let CI run them. Before committing, all of the following must be green (CI enforces
them on every PR — macOS full pipeline + Windows analyze/test/clippy, no VST3):

- **Flutter tests**: `cd ui && fvm flutter test`
- **Integration tests**: `./build.sh` first, then `cd ui && fvm flutter test integration_test/ -d macos`
- **Rust tests**: `cd engine && cargo test`
- **Static analysis**: `cd ui && fvm flutter analyze --fatal-infos`
- **Rust lints**: `cd engine && cargo clippy --all-targets`
- **Format check**: `cd ui && fvm dart format --set-exit-if-changed lib/ test/ integration_test/`

## Architecture Rules

- **MIDI clips** use **beats** for startTime/duration; **Audio clips** use **seconds**
- **FFI boundary** is raw `dart:ffi`, three layers (`api/` → `ffi/` extern-"C" shim → Dart binding). Adding an engine function is covered by the **`add-ffi` skill** and `.claude/rules/ffi.md`. `flutter_rust_bridge` was deliberately dropped — don't reintroduce it.
- **Undo/redo** uses the command pattern: `Command`, `CompositeCommand`, `UndoRedoManager`
  - All state-changing user actions should be wrapped in a Command
  - Known covered areas: clip move/trim, mixer fader/pan/mute/solo, built-in + VST3 effect params — new controls (e.g. send knobs in v0.3.0) must follow the same pattern
- **UI persistence**: new fields saved in `ui_layout.json` must go through `ProjectPersistence.collect()` / `applyUILayout()` — do not scatter field lists across project managers
- **Timeline layout**: `timeline_view.dart` uses `part` files for `timeline_gesture_layer.dart` and `timeline_track_list.dart` — private methods share one library; import `timeline_view.dart` only, never the part files directly
- **Engine interface** uses mixins: `AudioEngine extends _AudioEngineBase with _TransportMixin, _RecordingMixin, ...`
- **Platform-specific code** uses conditional imports (native/web/stub pattern)
- **Icons** go through the `BI` facade (`ui/lib/theme/boojy_icons.dart`), backed by Material Icons — prefer `BI.*` over importing `Icons.*` directly in widgets. Don't re-add `phosphor_flutter`; see `.claude/rules/flutter-ui.md`
- **UI state** is `provider` today; Riverpod is the deliberate future target — see `.claude/rules/state.md`
- **Recording flow**: engine `stop_recording()` returns `RecordingResult`, handled by `daw_recording_mixin.dart`
- **Track locks are non-reentrant**: engine uses `parking_lot::Mutex` which does **not** support recursive locking. `TrackManager::get_track`, `get_master_track`, and `remove_track` all walk the track list and call `.lock()` on each track to compare ids — so calling any of them while holding another `Track` lock **deadlocks the API thread silently** (no panic, no log, the UI just freezes). Snapshot what you need (`id`, `fx_chain`, `sends.iter().map(...)`) into local variables and drop the `MutexGuard` before calling back into `TrackManager`. See `find_return_by_effect_type` and `get_track_sends` in `engine/src/api/sends.rs` for the snapshot pattern.

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

- `dreams.md` — §1: active engineering target + milestone checklist
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
