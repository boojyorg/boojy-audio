# Boojy Audio Roadmap

**Current Version:** v0.5.1 (developing v0.5.2)
**Working On:** v0.5.2 — "Correct on real hardware, right after undo" — the correctness cycle set by the [2026-06-05 review chain](reviews/triage_2026_06_05.md): both criticals (stopped-path deadlock, clip-move undo desync), silent save/reload corruption, stuck notes + synth clicks, export correctness, FFI hardening, hook/CI parity, the first engine api/ffi tests, and the sample-rate sweep + carried device items (metronome loop-wrap, MIDI hot-plug, C99/C104). Spec: [plans/v0.5.2-plan.md](plans/v0.5.2-plan.md).
**Goal:** v1.0 public release

---

## What's Next (v0.4.0)

**Visual & UX polish** — the first dedicated UI/UX pass, scoped from the [2026-05-30 review](reviews/ui_ux_review_2026_05_30.md) and specced in [archive/plans/v0.4-plan.md](archive/plans/v0.4-plan.md). Sequenced **foundation → contained re-treats → top-bar A/B → chrome & dogfood polish**. Shipped: bundled Inter + JetBrains Mono, a unified "gunmetal" dark palette, a persisted UI Scale setting; piano-roll keyboard-contrast lanes + readout behaviour; the macOS title fix + top-bar A/B (Variant A won); a dogfood polish batch (shared ▲udio wordmark, centred transport, note resize in Select mode, type-coloured Add-Track buttons, dB-readout + Delete-focus fixes — PR #29); and two pre-tag fixes (VST3 instruments reopen with sound; narrow top-bar no longer overflows). The earlier quick-win bug batch folds into this release (no separate v0.3.3 tag). The piano-roll lane-colour refinement was **deferred to v0.5.0**.

The v0.3.x beat-making candidates (ghost notes, clip polish, stock drum kit / step sequencer, quantize) are **deferred** — picked up in the **v0.6 "Sound"** cycle below.

### After v0.4.0 (themes set by the 2026-06-01 review chain)

A three-review pre-release audit ([codebase](reviews/codebase_review_2026_06_01.md) · [UI/UX](reviews/ui_ux_review_2026_06_01.md) · [feature-gap](reviews/feature_gap_review_2026_06_01.md) · [triage](reviews/v0.4.0_pre_release_triage_2026_06_01.md)) confirmed v0.4.0 is taggable (the critical bugs are pre-existing, not v0.4 regressions) and the three reviews independently converged on the next two themes:

- **v0.5 — "Trust & Legibility":** correctness/hardening for the moment a session leaves the happy path (VST3 lifecycle, DeleteTrack undo content-loss, recorder audio-thread blocking, round-trip tempo, command/undo holes) **+** make the design tokens load-bearing (tokenise the ~390 hardcoded colours; painters theme + scale). Do first: fix CI/test trust (integration tests skip when the dylib is absent; clippy non-fatal) + the FEATURE_TRACKER accuracy sweep.
- **v0.5.1 — "UI polish & fixes":** a small dogfood follow-up — the "+ MIDI Track" / "+ Audio Track" buttons moved into the top bar (out of the cramped mixer header), the Master strip made selectable so you can add effects to the master bus from the editor, the Library search field aligned flush with the loop bar, and a fix for right-click → Delete silently failing in debug builds (the confirm dialog read its theme from the wrong context).
- **v0.5.2 — "Correct on real hardware, right after undo"** *(rescoped by the [2026-06-05 review chain](reviews/triage_2026_06_05.md); absorbs the old "loop & device polish" scope)*: the second trust/correctness pass — the two criticals (C32 stopped-path deadlock, C46/C63 clip-move undo desync), silent save/reload corruption (C55/C61/C65/C66), stuck notes + synth clicks (C38/C41/C7/C10), export correctness (C16/C18/C68), FFI hardening (C33/C34), hook/CI parity + lockfiles (C76–C79), the first engine api/ffi tests (C69), then the sample-rate sweep + the carried device items (metronome loop-wrap doubling, MIDI hot-plug, C99/C104, sampler blank-panel fix). Spec: [plans/v0.5.2-plan.md](plans/v0.5.2-plan.md).
- **v0.6 — "Sound"** *(rescoped 2026-06-05 — **no stock instruments**, deliberately deferred)*: drum kit (engine PR #44 + editor PR #45 already merged; 1 starter kit / 8 sounds), automation flag-flip + gesture QA, input monitoring UI, Join MIDI/audio clips (as proper Commands — subsumes C37/C50), reverse audio, clip normalize, plus the UI fixes ledger from the 2026-06-05 UI/UX review in steady small batches. Sequenced *after* the v0.5.2 hardening so a beginner's first from-scratch song doesn't land on the shakiest code paths.

Shipped in v0.3.0:

- **Send/return:** ⚡ FX button on strips → insert or shared send; return section in mixer; engine DSP (realtime + export)
- **Master row:** Hidden in arrangement by default; shown when master automation exists or via View → Show Master Row
- Spec archived: [archive/plans/v0.3.0-plan.md](archive/plans/v0.3.0-plan.md)

Shipped in v0.3.1 — **trust/correctness hardening** (data-loss & undo-corruption cluster from the [2026-05-29 review](reviews/)): mono export fix, redo-corruption fix, time-signature / MIDI-CC / clip-metadata persistence, grouped multi-clip move undo.

Shipped in v0.3.2 — **plugins & the audio thread**: VST3 plugins processed a whole buffer at a time instead of one sample at a time (the critical glitch), on top of a realtime safety net (NaN/Inf guard, denormal flush, stereo/48 kHz validation, plugin-thread fixes), live plugin/clip UI fixes (H-8/H-9/M-3), overlap-move undo (H-11), and a dead-code sweep.

---

## Version Plan

| Version | Theme | Status |
| --------- | ------- | -------- |
| v0.2.2 | UI polish & piano roll | Complete |
| v0.2.3 | Foundation & consolidation | Complete |
| v0.2.4 | Finish the foundation | Complete |
| v0.3.0 | Send/return routing (minimal) | Complete |
| v0.3.1 | Trust/correctness hardening (data-loss) | Complete |
| v0.3.2 | Plugins & the audio thread (VST3 per-buffer, safety net) | Complete |
| v0.4.0 | Visual & UX polish (type/palette/scale → re-treats → top-bar) | Complete |
| v0.5.0 | Trust & Legibility (correctness/hardening + token/painter legibility) | Complete |
| v0.5.1 | UI polish & fixes (top-bar add-track, selectable Master, library alignment, delete fix) | Complete |
| v0.5.2 | Correct on real hardware, right after undo (criticals, save/reload honesty, sample-rate sweep, device polish) | In progress |
| v0.6.0 | Sound (drum kit + starter sounds, automation, monitoring, join/reverse/normalize, UI fixes) | Planned |

---

## Completed

### v0.1.x — Foundation

Core DAW functionality: multi-track timeline, audio/MIDI recording, piano roll editor, mixer with volume/pan/mute/solo, audio editing (warp, pitch, split, consolidate), track automation, VST3 plugin hosting, library browser, MIDI import/export, WAV/MP3/stem export, project save/load. Design system (Material icons, typography tokens, animation constants), transport bar redesign, empty states, start screen.

### v0.2.0 — Recording & Mixing Essentials

Sustain pedal support, instrument on/off toggle, plugin-as-instrument redesign (embedded native GUIs), plugin preset navigation, float/embed toggle, first-run tooltip tour, device chain view, MIDI track creation with default clips, audio editor tab, crash logging, effect Reset to Default.

### v0.2.1 — Quality of Life

Removed unused UI (MIDI capture button, virtual piano button, new project toast). Fixed data persistence (track colors, loop region, duplicate save paths). Arrangement screenshot thumbnails. Visual polish (record button always-red, darker piano roll toolbar, mixer empty state). Fixed mixer overflow.

### v0.2.2 — UI Polish & Piano Roll

Warm charcoal arrangement background, star field removed. Piano roll controls bar simplified (CLIP + GRID only; Scale/Transform/Lanes in sidebar). FL Studio-inspired keyboard (shorter black keys, labeled notes). MIDI notes use track color. Tool and tab buttons visible when inactive. Automation UI hidden behind feature flag (data preserved).

---

## Road to v1.0 (Prioritized)

For the full checklist, see [FEATURE_TRACKER.md](FEATURE_TRACKER.md).

**Tier 1 (v0.2.3–v0.3.0):**

- Persistence reliability and integration tests
- Send/return routing (minimal aux bus)
- Ghost notes in piano roll

**Tier 2 (pre-v1.0):**

- Loop recording and comping / take lanes
- Stock instruments (synth, drums, sampler)
- Plugin delay compensation
- Markers, crossfades, clip polish

**Tier 3 (v1.0+ / platform):**

- Windows hardening and Linux
- AU support, tempo automation, LUFS metering
- Undo history panel, customizable shortcuts

---

## Engineering Health

- Latest review: [codebase_review_2026_05_22.md](archive/reviews/codebase_review_2026_05_22.md) (v0.2.2 snapshot; partially addressed in v0.2.3–v0.2.4)
- `timeline_view.dart` phase 1 split **done** (~1,200 lines); `daw_screen.dart` still ~4,200
- Persistence **centralized** via `ProjectPersistence` (engine `project.json` + UI `ui_layout.json` split remains by design)
- CI: macOS full pipeline (analyze, unit + integration tests, clippy) + Windows analyze/test/clippy (no VST3)
- Pre-v0.3.0 scoped audit **done** — see [v0.3.0-plan.md](archive/plans/v0.3.0-plan.md#pre-v0-3-scoped-audit-2026-05-22)

---

## Design Principles

- **Performance first** — Runs smoothly on modest hardware
- **Minimal but complete** — Every feature polished, nothing half-done
- **Progressive disclosure** — Simple by default, powerful when needed
- **Cross-platform** — Same experience on Mac, Windows, Linux, and Web
- **Ecosystem thinking** — Designed as part of the Boojy suite from day one

## Design References

| Feature | Primary Reference | Reasoning |
| --------- | ------------------- | ----------- |
| Piano Roll | FL Studio | Gold standard — ghost notes, scale highlighting, intuitive interactions |
| Arrangement View | Studio One | Draggable sections, scratch pads, excellent drag-and-drop |
| Audio Recording | Logic Pro | Excellent comping, beginner-friendly, professional results |
| Audio Editing/Warping | Ableton Live | Best-in-class warping, intuitive, sounds good |
| Automation | Studio One / Bitwig | Inline lanes below tracks, no mode switching, multiple visible |
| Mixer | Ableton Live | Minimal, readable, clean |
| Stock Sounds | Logic Pro | High quality, well-organized, massive library |
| Stock Effects | Ableton Live | Simple interfaces, hard to mess up, good defaults |
| UI Design | Logic Pro | Cohesive, polished, modern but timeless |
| Sidechaining | Logic Pro | Simple dropdown in compressor, easy to discover |

## Not Including (Design Decisions)

| Feature | Reason |
| --------- | -------- |
| Detachable windows | Keep UI simple, beginner-friendly |
| Pattern-based workflow | Use arranger track instead |
| Tagging system | Keep library simple |
| Read/Write automation modes | Too complex for beginners |
| Drummer/Session Player | Focus on great instruments |
| AI auto-mastering | Give users control with guidance |
| Complex groove pool | Too overwhelming, use swing + presets |
| Info panel | Use tooltips instead |
| Sync preview to key | Too complex for v1.0 |

---

## Historical

For the original milestone-based development history (M0-M10), see [archive/MILESTONES.md](archive/MILESTONES.md) and [archive/IMPLEMENTATION.md](archive/IMPLEMENTATION.md).

For shipped release plans, see [archive/plans/](archive/plans/).
