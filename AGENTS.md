# AGENTS.md

Boojy Audio is a free, open-source DAW: a Flutter UI over a Rust audio engine, joined by raw
`dart:ffi`, shipping on macOS and Windows. What it's for and what's in scope:
`docs/PRODUCT.md`. Suite-wide process (changelog, branches, release skeleton, memory model) is in
the suite root `~/Documents/Projects/boojy/AGENTS.md`. **Each fact has one home; this file points.**

## Read this first

1. This file.
2. `docs/BACKLOG.md` **Now** and **Known bugs**: the priority and what's broken.
3. The rules file for the area you're touching (index below).

Only when the task needs it: `docs/ARCHITECTURE.md` (changing structure), `docs/EDITING.md` (the
planned editing model; the five-tool row's problems are known), `docs/PLATFORMS.md`,
`docs/RELEASING.md` (release gate, severity rule, reviews), `docs/PRODUCT.md` (scope calls).

## Build & run

- **Toolchains** are pinned in `engine/rust-toolchain.toml` and `ui/.fvmrc` (CI mirrors them).
  Run Flutter from `ui/` as `fvm flutter …` / `fvm dart …`.
- **Engine:** `./build.sh` (debug) or `./build.sh release`; it points the app at that build.
  Dogfood on `release`: the debug engine crackles on its own.
- **App:** `cd ui && fvm flutter run -d macos`. Tyr runs it; don't launch it from an agent shell.
  To look at new UI, render it to PNG with `ui/test/helpers/render_preview.dart`.
- Stuck on "initializing" → a missing FFI symbol (`.claude/rules/ffi.md`).

Layout: `engine/src/{api,ffi,audio_graph,export}` · `ui/lib/{models,services,controllers,
screens/daw/mixins,widgets,theme}` · `ui/test/native/` (engine tests over `dart:ffi`). Full map:
`docs/ARCHITECTURE.md`.

## Gates

A post-edit hook runs `cargo check` + `cargo clippy --all-targets -D warnings` on `.rs` edits and
`flutter analyze --fatal-infos` on `.dart` edits. Don't bypass it.

**Locally, scope to what changed:** UI → analyze, `fvm dart format`, analyze again (format can
reflow into a lint), and the tests near the change. Engine → `cargo test` + clippy, plus
`ui/test/native/` if the FFI surface moved. **CI runs the full matrix** on every PR; `master` is
protected and needs `flutter-checks` and `rust-checks` green.

Lints: `flutter_lints` + `analysis_options.yaml`; Rust `clippy::pedantic` with exceptions in
`lib.rs`. Logging: Rust `println!`, Dart `Log.d()/.e()/.i()`, never `print()`.

## Rules index: read before touching

| Area | Read | The one-line version |
| --- | --- | --- |
| `engine/src/{api,ffi}/`, `ui/lib/audio_engine_*.dart` | `.claude/rules/ffi.md` | Use the `add-ffi` skill. **Engine is seconds, UI is beats**; every tempo write goes through `_onTempoChanged`. Locks are non-reentrant and ordered `synth → track → effect`. |
| `ui/lib/**` | `.claude/rules/flutter-ui.md` | `BI.*` icons; one menu surface (`showBoojyMenu`); messages via `Notices`, never `SnackBar`, no success notices; never read `context.colors` in a handler; no `onDoubleTap` above buttons. |
| `engine/src/export/` | `.claude/rules/audio-export.md` | Range → LUFS → mixdown → normalise. Stems = mix minus the master stage. |
| `build.sh`, `ui/test/native/`, `ui/test/goldens/` | `.claude/rules/build-and-test.md` | `./build.sh` picks the engine the app runs. Goldens refresh on macOS only. |

Everywhere: **every state-changing user action is an undoable `Command`**. Don't reintroduce
`flutter_rust_bridge`, `phosphor_flutter` or any icon package. Rules auto-loading by `paths:` is
flaky, so read the matching file deliberately.

## Claude Code

- Skills: `add-ffi` (wires a new engine function through all 7 files). Review workflows
  (`ui-ux-review`, `codebase-review`, `feature-gap-review`) are in `.claude/workflows/`; when to
  run them is in `docs/RELEASING.md`.
- `CLAUDE.md` is a one-line pointer to this file (not a symlink).
