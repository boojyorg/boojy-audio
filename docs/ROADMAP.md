# Boojy Audio Roadmap

**Current Version:** v0.2.4 (developing v0.3.0)
**Working On:** v0.3.0 — Send/return via ⚡ FX picker + hidden master row
**Goal:** v1.0 public release

---

## What's Next (v0.3.0)

Spec: [plans/v0.3.0-plan.md](plans/v0.3.0-plan.md)

- **Send/return:** ⚡ FX button on strips → insert or shared send; return section in mixer; engine DSP (realtime + export)
- **Master row:** Hidden in arrangement by default; show when master automation exists or View → Show Master Row
- Data model + project save/load exist; **renderer DSP and UI are the work**

---

## Version Plan

| Version | Theme | Status |
|---------|-------|--------|
| v0.2.2 | UI polish & piano roll | Complete |
| v0.2.3 | Foundation & consolidation | Complete |
| v0.2.4 | Finish the foundation | Complete |
| v0.3.0 | Send/return routing (minimal) | Active |
| v0.3.x | Ghost notes, clip polish | Planned |

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
- Pre-v0.3.0 scoped audit **done** — see [v0.3.0-plan.md](plans/v0.3.0-plan.md#pre-v0-3-scoped-audit-2026-05-22)

---

## Design Principles

- **Performance first** — Runs smoothly on modest hardware
- **Minimal but complete** — Every feature polished, nothing half-done
- **Progressive disclosure** — Simple by default, powerful when needed
- **Cross-platform** — Same experience on Mac, Windows, Linux, and Web
- **Ecosystem thinking** — Designed as part of the Boojy suite from day one

## Design References

| Feature | Primary Reference | Reasoning |
|---------|-------------------|-----------|
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
|---------|--------|
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
