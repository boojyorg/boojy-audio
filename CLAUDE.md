# Claude Code Instructions

**Suite-wide process/conventions live in the root `~/Documents/Projects/boojy/CLAUDE.md`**
(memory model, changelog/release skeleton, branch discipline, context-hygiene, working prefs);
this file is the app-specific architecture, stack, and gotchas.

## Memory & docs (repo-specific)

Docs/memory model (CLAUDE.md / `.claude/rules/` / `dreams.md` / auto-memory / git log) → root
`CLAUDE.md`. Local layout:

- **`dreams.md` §1** — the active engineering target + milestone checklist. Read it first.
- **`docs/ROADMAP.md`** (ordered intentions) · **`docs/BACKLOG.md`** (unscheduled someday) ·
  **`docs/FEATURE_TRACKER.md`** (built-vs-not, v1.0 checklist) split the overflow.
- **`docs/plans/vX.Y-plan.md`** — detailed spec for the active version (features, mockups, scope).
- **`docs/reviews/`** — dated deep-review reports that set each version's theme (see Milestone
  Reviews). **`docs/ARCHITECTURE.md`** — system design, folder structure, FFI patterns.
- **`.claude/rules/*.md`** — per-area gotchas with `paths:` frontmatter (`ffi.md`, `audio-export.md`,
  `flutter-ui.md`, `state.md`, `build-and-test.md`). Conditional loading is flaky in early-2026
  Claude Code, so treat these as organization — genuinely global rules live here in `CLAUDE.md`.

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
  - `lib/services/bundled_content_service.dart` - Bundled samples (`ui/assets/samples/drums/`,
    licences in its `LICENSES.md`) copied to app-support on first use — the engine loads by
    filesystem path, never from the asset bundle. Bump `contentRevision` when bundled content
    changes; keep `drumSamples` in sync with the pubspec asset dirs
  - `lib/screens/daw/mixins/` - DAW screen mixins (recording, playback, etc.)
  - `lib/widgets/` - UI components (timeline, piano roll, painters, shared)
  - `lib/controllers/` - Playback, recording, track controllers
  - `integration_test/` - Native engine golden-path tests (macOS)
- `docs/` - Architecture docs, roadmap, design specs

## Gates

A `PostToolUse` hook (`.claude/hooks/post-edit-validation.sh`) runs a **fast** gate after each edit,
at CI strictness: `.rs` under `engine/` → `cargo check` + `cargo clippy --all-targets -- -D warnings`;
`.dart` under `ui/` → `flutter analyze --fatal-infos`. It skips gracefully if the toolchain is
missing. Full test suites are **not** run in that loop — run
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

## Design philosophy (repo-specific)

General "prefer simple, minimal — avoid over-engineering" → root `CLAUDE.md`. The concrete audio
anchor: the built-in synth is deliberately **one oscillator (sine/saw/square/triangle) + one-pole
lowpass + ADSR + 8-voice polyphony** — *not* 3 oscillators + resonant filter + LFO + modulation
matrix. Add complexity only when explicitly asked.

## Working style (repo-specific)

General design-decision posture (defer on taste, push back on architecture) → root `CLAUDE.md` + the
global `~/.claude`. Audio-specific habits:

- **One milestone at a time** — only one active `docs/plans/vX.Y-plan.md`. `docs/ROADMAP.md` +
  `docs/FEATURE_TRACKER.md` are a backlog, **not** a pre-scheduled ladder.
- **After each release, dogfood** on a real project, then pick the next theme from the friction you
  hit (see Milestone Reviews — the theme comes from a deliberate review, not guesswork).
- **UI/UX before code:** brainstorm tradeoffs with Tyr first; when layout is ambiguous, offer **3–4
  ASCII mockups** and let him pick before implementing.

## Release (repo-specific)

General changelog + release flow → root `CLAUDE.md`. Local specifics: **`ui/pubspec.yaml`** is the
version source (drives the in-app version label via `PackageInfo` — bump on every release, it's easy
to forget); tagging `v*` triggers GitHub Actions to build the draft release (DMG/EXE), which you then
edit + publish. When a change *completes* a `docs/FEATURE_TRACKER.md` item, tick it in the **same
PR** — and only when the feature is **reachable by a user end-to-end**, not when the engine/FFI
exists but no UI path does (annotate those `(partial: …)`). Full version-reference checklist →
**Version Sync** below.

**Windows smoke test — every release, before publishing the draft.** Development happens on macOS,
so the installed Windows build is the one artifact nobody has run. Install the freshly built
`Boojy-Audio-win.exe` on the Windows machine (~5 min):

1. App launches; taskbar + title bar show the Boojy icon (not the Flutter default)
2. Audio devices listed in settings; default output works (play the metronome or a clip)
3. Record a short MIDI clip with the built-in synth → it plays back
4. Load/save a project round-trips
5. In-app version label matches the tag

(v0.5.2 and earlier shipped without `engine.dll` because nothing exercised the installer — this
checklist exists so that class of bug is caught on day one.)

## Milestone Reviews

Each version's theme should come from a **deliberate review, not guesswork** — both the v0.3.x
trust/correctness theme and the v0.4 visual-polish theme were chosen this way. Run the matching
review **before opening a new `docs/plans/vX.Y-plan.md`**, save its report to `docs/reviews/`, and
let it drive the plan. Two reusable multi-agent workflows live in `.claude/workflows/`:

- **UI/UX review — every minor version.** Lighter (~16 agents). Include the word "workflow" in your
  message, then run `Workflow({ name: 'ui-ux-review', args: { screenshots: ['<abs paths>'] } })`.
  Pass current screenshots so it grounds against the real UI.
- **Whole-app codebase audit — at major boundaries** (pre-1.0, or once per minor-version *family*),
  not every patch. Heavier — ~$30–50 with model tiering (was ~$101 untiered). Run
  `Workflow({ name: 'codebase-review' })`. Confirm gates are green first.

Both **return** a markdown report (save it to `docs/reviews/`) and are **human-triggered, never
scheduled** — their value is in you reading and triaging the output. They tier models to control
cost (readers → Sonnet, adversarial verifiers → Haiku, synthesis → Opus); see the
`review-workflow-cost-tuning` auto-memory.

## Version Sync

All markdown files must stay in sync with the current development version.

**When starting a new version (creating a new plan doc):**
1. Run the matching **Milestone Review** (above) and save its report to `docs/reviews/` — the plan's theme comes from it
2. Update `docs/ROADMAP.md` — set "Current Version" and "Working On" lines, update version table
3. Update `README.md` — update the version/status line
4. Verify `CHANGELOG.md` has an empty `## Unreleased` section ready

**When releasing a version:**
1. `CHANGELOG.md` — rename `## Unreleased` → `## vX.Y.Z — YYYY-MM-DD`, add new empty `## Unreleased`
2. `docs/ROADMAP.md` — update "Current Version", mark version as Complete in table, update "Working On" to next version
3. `README.md` — update version reference
4. Move completed plan from `docs/plans/` → `docs/archive/plans/`
5. Update `docs/FEATURE_TRACKER.md` — check off newly completed features
6. `ui/pubspec.yaml` — bump `version:` to the new `X.Y.Z+build` (the in-app version label reads this via `PackageInfo`)

**Files that reference the version (keep in sync):**
- `README.md` — project status line
- `docs/ROADMAP.md` — "Current Version" and "Working On" header lines
- `CHANGELOG.md` — release section headers
- `docs/FEATURE_TRACKER.md` — checked/unchecked items
- `ui/pubspec.yaml` — `version:` line; drives the in-app version label (About box, start screen, settings) via `PackageInfo` — bump on every release, it is easy to forget

## Linting & Formatting

- **Dart**: `flutter_lints` with 60+ rules in `analysis_options.yaml` — strict mode
- **Rust**: `clippy::pedantic` enabled with pragmatic exceptions in `lib.rs`
- **Formatting**: `dart format` for Dart, `rustfmt` for Rust
- **Debug logging**: Rust uses `println!` during development; Dart/Flutter uses `Log.d()/.e()/.i()`
  (`utils/logger.dart`), **not** `print()`.
- Run `flutter analyze` and `cargo clippy` before submitting — CI rejects warnings
