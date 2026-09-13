# AGENTS.md

Boojy Audio is a free, open-source, cross-platform DAW for composing, recording, arranging,
mixing and mastering music. It combines MIDI programming with audio recording in a calm,
approachable interface. Designed for musicians: sensible defaults, minimal setup, and sound
first. Visuals support listening. Flutter UI over a Rust audio engine, joined by raw `dart:ffi`;
ships on macOS and Windows. Detailed positioning and scope: `docs/PRODUCT.md`.

Suite-wide process (memory model, changelog, branch discipline, context hygiene, working
preferences) lives in the suite root `~/Documents/Projects/boojy/AGENTS.md`. This file is the
boojy-audio index: where things are, how to build and gate, and which rules file to read before
touching each area. **Each fact has one home; everything else here is a pointer.**

## Where things are

| Doc | What it holds |
| --- | --- |
| `docs/BACKLOG.md` | The one planning document: active priority, paused work, decisions, candidates. Read it first. |
| `docs/ARCHITECTURE.md` | How the system works today: engine/UI split, FFI contract, routing, persistence. |
| `docs/PRODUCT.md` | Who Boojy is for and the product principles that decide scope. |
| `docs/RELEASING.md` | Release steps, version sync, Windows smoke test, milestone-review cadence. |
| `.claude/rules/*.md` | Full-text engineering gotchas, one area per file. See the index below. |
| `docs/reviews/` | Only the live triage plus untriaged reports. Everything older: `docs/archive/`. |
| `CHANGELOG.md` | Completed work, `## Unreleased` on top. |

## Build & run

- **Toolchains:** Rust **1.98.1** (`engine/rust-toolchain.toml`); Flutter **3.44.0 / Dart 3.12**
  via FVM (`ui/.fvmrc`). Run Flutter/Dart from `ui/` as `fvm flutter …` / `fvm dart …`. CI pins
  the same versions (`FLUTTER_VERSION` in `.github/workflows/*.yml`).
- **Engine:** `./build.sh` (debug) or `./build.sh release` builds Rust and refreshes the dylib
  symlink. Uses `sccache` automatically if installed. Dev deps build at `opt-level = 2`.
- **App:** `cd ui && fvm flutter run -d macos`. Don't auto-start it from an agent shell.
- Stuck on "initializing" → missing FFI symbol → `.claude/rules/ffi.md`.

Layout: `engine/src/{api,ffi,audio_graph,export}` (Rust) · `ui/lib/{models,services,controllers,
screens/daw/mixins,widgets,theme}` (Flutter) · `ui/test/native/` (engine tests over `dart:ffi`)
· `docs/`. Full map in `docs/ARCHITECTURE.md`.

## Gates

A post-edit hook runs the fast gate on every edit: `.rs` under `engine/` → `cargo check` +
`cargo clippy --all-targets -- -D warnings`; `.dart` under `ui/` → `flutter analyze --fatal-infos`.

**Local before committing: scope to what changed.** UI-only diff → the hook's analyze +
`fvm dart format` + the test files near the change (e.g. `fvm flutter test test/widgets/`).
Engine diff → `cargo test` + clippy, plus `test/native/` if the FFI surface moved. Always re-run
analyze after format (format can reflow into a lint violation).

**CI runs the full matrix on every PR** (macOS full pipeline + Windows analyze/test/clippy).
Master is protected: `flutter-checks` and `rust-checks` must pass before a PR can merge. Full set:

- `./build.sh` then `cd ui && fvm flutter test` (CI adds `--dart-define=BOOJY_CI=true` so
  `test/native` fails loudly when the dylib is missing)
- `cd engine && cargo test` · `cargo clippy --all-targets`
- `cd ui && fvm flutter analyze --fatal-infos` · `fvm dart format --set-exit-if-changed lib/ test/`

Lints: Dart `flutter_lints` + strict rules in `analysis_options.yaml`; Rust `clippy::pedantic`
with exceptions in `lib.rs`. Logging: Rust `println!`; Dart `Log.d()/.e()/.i()` from
`utils/logger.dart`, never `print()`.

## Rules index: read before touching

| Area | Read | The one-line version |
| --- | --- | --- |
| `engine/src/api/`, `engine/src/ffi/`, `ui/lib/audio_engine_*.dart` | `.claude/rules/ffi.md` | Raw `dart:ffi`, three layers (`api/` → `ffi/` shim → Dart binding); use the `add-ffi` skill. **Engine is real seconds everywhere, UI thinks in beats.** Every tempo write goes through `_onTempoChanged`, never bare `setTempo`. Locks are non-reentrant: snapshot, drop the guard, then call `TrackManager`. |
| `ui/lib/**` | `.claude/rules/flutter-ui.md` | `BI.*` icons only. One shared menu surface (`showBoojyMenu`), never `showMenu`/`PopupMenuButton`. Never read `context.colors` in an event handler. `ui_layout.json` fields go through `ProjectPersistence`. Import `timeline_view.dart`, never its part files. |
| `engine/src/export/` | `.claude/rules/audio-export.md` | Range → LUFS → mixdown → normalise, in that order. Stems = mix minus the master stage. |
| `build.sh`, `ui/test/native/`, `ui/test/goldens/` | `.claude/rules/build-and-test.md` | Rust must be built release for the symlink to see it. Goldens refresh on macOS only. |

Rules with no better home:

- **Undo/redo is the command pattern** (`Command`, `CompositeCommand`, `UndoRedoManager`). Every
  state-changing user action is wrapped in a Command: clip edits, mixer controls, effect params,
  new controls alike.
- **Don't reintroduce `flutter_rust_bridge`, `phosphor_flutter`, or any icon package.**
  Reasons are in the rules files above.
- **`.claude/rules/` `paths:` auto-loading is flaky.** Read the matching file deliberately.

## Working style

- **One active priority at a time**, recorded in `docs/BACKLOG.md`. Deferred ideas don't
  schedule work. Only call a feature complete when users reach it end-to-end.
- **After each release, dogfood** on a real project; the next theme comes from a deliberate
  review (`docs/RELEASING.md`), not guesswork.
- **UI/UX before code:** brainstorm tradeoffs with Tyr first; when layout is ambiguous, offer
  3–4 ASCII mockups and let him pick.
- **Prefer simple, minimal.** The principles and decision filter that decide scope (listen first,
  minimal setup, complete core workflows) are in `docs/PRODUCT.md`; stock-instrument designs are
  in `docs/ARCHITECTURE.md`.

## Claude Code–specific

- Post-edit gate = `.claude/settings.json` → `.claude/hooks/post-edit-validation.sh`. Skips if
  a toolchain is missing. Do not bypass it.
- `add-ffi` skill wires a new engine function through all 7–8 files.
- Review workflows (`ui-ux-review`, `codebase-review`, `feature-gap-review`) live in
  `.claude/workflows/`; when and how to run them is in `docs/RELEASING.md`.
- `CLAUDE.md` is a symlink to this file.
