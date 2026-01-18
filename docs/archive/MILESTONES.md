# Historical Milestones (Archived)

This document preserves the original milestone-based development plan from Boojy Audio's early development. The project has since transitioned to a version-based roadmap (see [ROADMAP.md](../ROADMAP.md)).

---

## Milestone Overview

| Milestone | Focus | Status |
|-----------|-------|--------|
| M0 | Project Setup | ✅ Complete |
| M1 | Audio Engine Foundation | ✅ Complete |
| M2 | Basic UI & Playback | ✅ Complete |
| M3 | MIDI & Piano Roll | ✅ Complete |
| M4 | VST3 Plugin Support | ✅ Complete |
| M5 | Mixing & Effects | ✅ Complete |
| M6 | Project Save/Load | ✅ Complete |
| M7 | Recording | Partially Complete |
| M8 | Polish & UX | Not Started |
| M9 | Stock Instruments | Not Started |
| M10 | Release Prep | Not Started |

---

## M0 — Project Setup

**Goal:** Establish project structure and build pipeline

- Flutter project initialization
- Rust audio engine scaffolding
- FFI bridge setup (Rust ↔ Dart)
- macOS build configuration
- GitHub Actions CI/CD

---

## M1 — Audio Engine Foundation

**Goal:** Core audio playback and processing

- CPAL audio output
- Sample-accurate playback
- Basic mixer (volume, pan)
- Audio file loading (WAV, MP3, FLAC via Symphonia)
- Buffer management

---

## M2 — Basic UI & Playback

**Goal:** Functional timeline and transport

- 3-panel layout (Library | Timeline | Mixer)
- Track headers and lanes
- Transport controls (play, pause, stop)
- Playhead with position display
- Time ruler (bars/beats)
- Basic zoom and scroll

---

## M3 — MIDI & Piano Roll

**Goal:** MIDI editing capabilities

- MIDI track type
- Piano roll editor
- Note drawing and editing
- Velocity lane
- Built-in synthesizer (8-voice polyphonic)
- MIDI clip management

---

## M4 — VST3 Plugin Support

**Goal:** Third-party plugin integration

- VST3 plugin scanning
- Plugin loading and instantiation
- Plugin UI hosting (embedded and floating)
- Plugin state persistence
- Instrument vs Effect distinction

---

## M5 — Mixing & Effects

**Goal:** Professional mixing capabilities

- Built-in effects (EQ, Compressor, Reverb, Delay)
- Effect chain UI
- Effect bypass and reordering
- Master track with limiter
- Stereo metering

---

## M6 — Project Save/Load

**Goal:** Project persistence

- .boojy project format
- Track state serialization
- Plugin state persistence
- Audio file references
- Auto-save functionality

---

## M7 — Recording (Partial)

**Goal:** Audio and MIDI recording

- Audio input selection
- Record arm per track
- Audio recording to clip
- Count-in metronome
- *MIDI controller recording (not yet complete)*
- *Capture MIDI (not yet complete)*

---

## M8 — Polish & UX (Planned)

**Goal:** User experience improvements

- Tooltips on all controls
- Keyboard shortcuts overlay
- Undo/redo reliability
- Performance optimization
- Error handling improvements

---

## M9 — Stock Instruments (Planned)

**Goal:** Built-in instruments

- Boojy Synth (wavetable)
- Boojy Drums (pad grid + step sequencer)
- Boojy Sampler (drag-and-drop sampling)

---

## M10 — Release Prep (Planned)

**Goal:** Production readiness

- All known bugs fixed
- Documentation complete
- Website and distribution
- Windows support
- Linux support

---

## Detailed Milestone Documentation

Individual milestone planning documents are preserved in:

- [M0/](milestones/M0/) — Project setup notes
- [M1/](milestones/M1/) — Audio engine specifications
- [M2/](milestones/M2/) — UI wireframes and plans
- [M3/](milestones/M3/) — MIDI implementation details
- [M4/](milestones/M4/) — VST3 integration research
- [M5/](milestones/M5/) — Effects architecture
- [M6/](milestones/M6/) — Project format specification

---

## Transition to Version-Based Roadmap

As of January 2026, the project transitioned from milestone-based to version-based planning:

| Old Milestone | → | New Version |
|---------------|---|-------------|
| M7 (Recording) | → | v0.2.0 Core Workflow |
| M8 (Polish) | → | v0.5.0 Polish & UX |
| M9 (Instruments) | → | v0.4.0 Stock Instruments |
| M10 (Release) | → | v1.0.0 Public Release |

See [ROADMAP.md](../ROADMAP.md) for the current development plan.
