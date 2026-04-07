# Boojy Audio Roadmap

**Current Version:** v0.2.1
**Working On:** v0.2.2 — [plans/v0.2.2-plan.md](plans/v0.2.2-plan.md)
**Goal:** v1.0 public release

---

## What's Next

See the active plan doc: [plans/v0.2.2-plan.md](plans/v0.2.2-plan.md)

---

## Completed

### v0.1.x — Foundation

Core DAW functionality: multi-track timeline, audio/MIDI recording, piano roll editor, mixer with volume/pan/mute/solo, audio editing (warp, pitch, split, consolidate), track automation, VST3 plugin hosting, library browser, MIDI import/export, WAV/MP3/stem export, project save/load. Design system (Phosphor icons, typography tokens, animation constants), transport bar redesign, empty states, start screen.

### v0.2.0 — Recording & Mixing Essentials

Sustain pedal support, instrument on/off toggle, plugin-as-instrument redesign (embedded native GUIs), plugin preset navigation, float/embed toggle, first-run tooltip tour, device chain view, MIDI track creation with default clips, audio editor tab, crash logging, effect Reset to Default.

### v0.2.1 — Quality of Life

Removed unused UI (MIDI capture, virtual piano button, new project toast). Fixed data persistence (track colors, loop region, duplicate save paths). Arrangement screenshot thumbnails. Visual polish (record button always-red, darker piano roll toolbar, mixer empty state). Fixed mixer overflow.

---

## What's Next

See the active plan doc: [plans/v0.2.1-plan.md](plans/v0.2.1-plan.md)

---

## Road to v1.0

Feature areas still needed before public release (not assigned to specific versions — each release plan decides what to tackle next):

- **Clip editing** — Fades, crossfades, arrangement markers
- **Routing** — Send/return effects, sidechain, track groups/folders
- **Plugins** — AU support, preset management, parameter automation, delay compensation
- **Stock instruments** — Synth, drums, improved sampler
- **Tempo & time** — Tempo automation, time signature changes, tap tempo, swing
- **UX polish** — Tooltips, tutorial, undo history panel, track colors
- **Platform** — Windows, Linux
- **Advanced** — MIDI Learn, freeze/bounce, LUFS metering

For the full checklist, see [FEATURE_TRACKER.md](FEATURE_TRACKER.md).

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
