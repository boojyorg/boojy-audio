# Boojy Audio — Codebase Review

**Date:** 2026-05-22
**Version reviewed:** v0.2.2
**Next focus:** [v0.2.3 plan](../plans/v0.2.3-plan.md) — Foundation & consolidation

---

## Executive Summary

Boojy Audio is a serious alpha DAW, not a prototype. For v0.2.2, the stack (Flutter UI + Rust engine + VST3 bridge), documentation, and CI discipline are unusually strong. The main risks are **scale of a few UI files**, **split project persistence**, and **test coverage that doesn't yet protect the hardest user flows**.

**Bottom line:** The hard parts are built (engine, VST3, recording, piano roll, export). The next phase should combine **consolidation** (split mega-widgets, unify persistence, integration tests) with **one big mixing feature** (sends/returns in v0.3.0) and **one big editing feature** (ghost notes).

---

## Scorecard

| Area | Grade | Notes |
|------|-------|-------|
| Architecture | B+ | Strong split; mega-files and split persistence hold it back |
| Engine (Rust) | A- | Solid realtime/offline design; needs PDC + more integration tests |
| UI (Flutter) | B | Polished design system; complexity concentrated in few files |
| Testing | B- | Great unit/model coverage; weak on integration & critical paths |
| Docs / process | A | Roadmap, architecture, changelog, FFI workflow — excellent |
| Release / CI | B+ | macOS pipeline mature; Windows needs CI parity |
| Product readiness | Alpha+ | Core DAW works; routing, comping, stock instruments gap to v1.0 |

---

## Architecture

### Strengths

- **Clean platform split** — conditional imports for native/web/stub (`audio_engine.dart`, project managers).
- **Testable engine interface** — `AudioEngineInterface` + `MockAudioEngine` + command classes.
- **Mixin decomposition on DAW screen** — `DAWPlaybackMixin`, `DAWRecordingMixin`, etc.
- **FFI organization** — `api/` for logic, `ffi/` for C bindings, `audio_graph/` for rendering.
- **Structured engine errors** — `EngineResult` handles legacy strings and JSON `{ok, error}`.

### Concerns

**God files:**

| File | ~Lines | Risk |
|------|--------|------|
| `timeline_view.dart` | 4,900 | Hard to change without regressions |
| `daw_screen.dart` | 4,200 | Orchestration + state + wiring mixed |
| `piano_roll.dart` | 2,600 | Same |
| `library_panel.dart` | 1,900 | Same |
| `track_mixer_strip.dart` | 2,000 | Same |

**Split persistence model.** Engine state in Rust `project.json`; UI state in Dart `ui_layout.json` (panel sizes, loop region, track colors, view state, automation UI data). v0.2.1 bugs (track colors, loop region, duplicate save paths) came directly from this split.

**`api/remaining.rs`.** 625-line catch-all for track/clip utilities — maintenance smell as FFI surface grows.

**Locking in realtime path.** Renderer uses mutexes heavily. Snapshot-based playback path in `renderer.rs` is good — extend that pattern as VST3 and routing grow.

---

## Rust Audio Engine

### Strengths

- Pedantic Clippy with pragmatic allows.
- Module boundaries: effects, sampler, stretch, export (WAV/MP3/stems), VST3 behind feature flag.
- Unit tests in export, sampler, recorder, synth, audio_file.
- Offline vs realtime separation in `audio_graph/`.
- VST3 hosting is a major differentiator.

### Concerns

- No integration/FFI tests in CI for full workflows.
- Debug logging via `eprintln!` in hot paths — gate before v1.0.
- Plugin delay compensation not implemented — matters for send/return and heavy VST chains.
- Dual clip state — undo/redo re-adds clips via engine while UI maintains clip models.

---

## Flutter UI

### Strengths

- Strict linting (`analysis_options.yaml` — 60+ rules).
- Real design system: tokens, `AppColors`, Phosphor icons, shared components.
- Command palette + keyboard shortcuts.
- Feature-flag pattern for automation (`UIConstants.enableAutomation = false`).
- v0.2.2 polish coherent: warmer bg, piano roll simplification, track-colored notes.

### Concerns

- **Undo/redo coverage uneven** — `UndoRedoManager` referenced in ~12 files; many user actions may bypass `Command`.
- **State management mostly `setState` + Provider** — `timeline_view.dart` has 80+ `setState` calls.
- **Web engine parity** secondary — VST3, recording, full I/O are native-first (correct priority).

---

## Testing & CI

### What exists

- 43 Flutter test files — strong on models, serialization, commands, controllers.
- CI on every PR: format, analyze, Flutter tests, Clippy, Rust tests.
- Release pipeline: macOS (signed, notarized, Sparkle) + Windows installer.

### Gaps

| Area | Coverage | Risk |
|------|----------|------|
| Timeline clip drag/split/trim | None | Core workflow |
| Recording → clip creation | None | Core workflow |
| Project save/load roundtrip | Partial | Data loss bugs |
| Export WAV/MP3/stems | None in UI tests | User-facing |
| VST3 load/unload | None | Crash-prone |
| Windows CI | Release only | Platform regressions |

No `integration_test/` folder yet.

---

## Product / Roadmap Alignment

Roughly **55–60%** toward v1.0 on arrangement/editing basics; **~20–30%** on routing, stock instruments, comping, platform polish.

**Biggest v1.0 blockers (dependency order):**

1. Routing — sends/returns, bus tracks, sidechain
2. Recording depth — loop record, comping
3. Stock instruments — synth/drums/sampler
4. Clip polish — crossfades, markers, ghost notes
5. Windows hardening
6. Plugin PDC + preset management

See [ROADMAP.md](../ROADMAP.md) for the prioritized tier breakdown and [FEATURE_TRACKER.md](../FEATURE_TRACKER.md) for the full checklist.

---

## Where to Focus Next

Superseded by the active [v0.2.3 plan](../plans/v0.2.3-plan.md). Summary:

1. **v0.2.3** — Persistence audit, integration tests, undo audit, timeline decomposition phase 1, Windows CI, dead code cleanup
2. **v0.3.0** — Send/return routing (minimal aux bus)
3. **v0.3.x** — Ghost notes, clip polish

---

## Review Index

| Date | Doc | Scope |
|------|-----|-------|
| 2026-03-26 | [2026_03_26_ui_review.md](2026_03_26_ui_review.md) | UI/UX vs competitors |
| 2026-03-29 | [2026_03_29_ui_review.md](2026_03_29_ui_review.md) | UI/UX follow-up |
| 2026-05-22 | This doc | Full codebase architecture & engineering |
