# Boojy Audio Roadmap

**Current Version:** v0.1.3 (Alpha)

---

## What's Next

### v0.2.0 — Recording & Mixing Essentials

- [ ] Send/Return effects (beginner-friendly presets + manual setup)
- [ ] Better Sampler editor (real waveform, loop points, one-shot, full audio controls)
- [ ] MIDI CC recording (sustain pedal + pitch bend)
- [ ] Input monitoring (hear live input through DAW)
- [ ] Tempo automation (master tempo track)
- [ ] Punch in/out recording
- [ ] Freeze/bounce track (non-destructive)
- [ ] Scale/key snapping in piano roll
- [ ] MIDI Learn (map hardware controllers to parameters)

See [docs/v0.2-design.md](v0.2-design.md) for full design spec with mockups.

---

## Version Plan

### v0.1.x — Foundation (Complete)

Focus: Core functionality, stability, audio clip features

**Done:**

- [x] Audio engine loading fix
- [x] Window sizing (1280x800, centered)
- [x] Code signing and notarization
- [x] Panel auto-expand on resize
- [x] MIDI clip looping visualization
- [x] MIDI loop playback (note-off timing)
- [x] Library panel refresh fix
- [x] Mixer track alignment
- [x] Audio clip Warp (time-stretching with pitch preservation)
- [x] Warp modes (Warp vs Re-Pitch)
- [x] Audio clip looping in arrangement
- [x] Audio Editor toolbar (signature, tempo, reverse)
- [x] Sampler track type (basic)
- [x] Project rename and versioning
- [x] Pitch control (semitones/cents)
- [x] Track automation (volume/pan) — see v0.2.0 Details
- [x] Velocity UI improvements — see v0.2.0 Details

---

### v0.1.5 — Producer Workflow Foundation (Complete)

Focus: Features that unblock beat-making and instrumental production

**Track Automation:** ✅ Complete

- [x] Volume automation lanes on timeline
- [x] Pan automation lanes on timeline
- [x] Click to add points, drag to edit
- [x] All 5 tools work: draw, select, delete, duplicate, slice
- [x] Sample-accurate playback interpolation (engine integration)
- [x] Clip-based automation (moves/loops/slices/copies with clips)
- [x] Piano Roll automation toggle button
- [x] Live value display during drag
- [x] Drag-to-erase, box selection, Shift+drag selection
- [x] Mutual exclusion with note selection

**Velocity Improvements:** ✅ Complete

- [x] Velocity affects note brightness (not transparency)
- [x] FL Studio-style "nearest circle" editing with pixel threshold
- [x] Velocity lane redesigned (vertical + horizontal line + circle)
- [x] Per-note brightness matching piano roll notes
- [x] White highlight for selected/dragged notes
- [x] Cleaner note appearance (no dark border, 2px white selection border)
- [x] Removed resize handles from selected notes
- [x] Removed [Rand] button from velocity lane

**Library Preview:** ✅ Complete

- [x] Preview audio files on click (audition mode)
- [x] Preview bar with waveform visualization (48px)
- [x] Visual indicator (speaker icon) on previewing item
- [x] Stop on drag start, selection change, or audition toggle off
- [x] Looping for short files (< 3 seconds)
- [x] Audition toggle with persistence
- [ ] Synth preset preview (play MIDI note) — stubbed, needs hidden track integration

**Sampler Fixes:**

- [ ] Fix stereo output (currently mono to both channels)
- [ ] Show actual sample waveform in editor
- [ ] Sample metadata display

**Remaining:**

- [ ] Clip automation playback (per-clip automation requires additional engine work)

---

### v0.3.0 — Polish & Advanced

Focus: Clip editing refinements and workflow improvements

- [ ] Fade in/out on audio clips (linear, exponential, S-curve)
- [ ] Crossfades between overlapping clips
- [ ] Track grouping/folders
- [ ] Plugin presets (save/load per effect/instrument)
- [ ] Arrangement markers (named timeline markers: Intro, Verse, etc.)

---

### v0.4.0 — Plugins & Effects

Focus: Plugin ecosystem and built-in effects

**Plugins:**

- [ ] AU plugin support (macOS)
- [ ] Plugin preset management
- [ ] Plugin parameter automation

**Built-in Effects:**

- [ ] Parametric EQ
- [ ] Compressor
- [ ] Reverb
- [ ] Delay
- [ ] Limiter

---

### v0.5.0 — Stock Instruments

Focus: Built-in instruments that sound good

- [ ] Boojy Synth (wavetable, Serum-style)
- [ ] Boojy Drums (pad grid + step sequencer)
- [ ] Improved Sampler (multi-sample, looping, zones)

---

### v0.5.0 — Polish & UX

Focus: Make it feel professional

- [ ] Tooltips on all buttons
- [ ] Built-in tutorial
- [ ] Dark theme
- [ ] Undo history panel
- [ ] Start screen

---

### v1.0.0 — Public Release

Focus: Ready for real users

- [ ] All known bugs fixed
- [ ] VST2/AU support
- [ ] Linux support
- [ ] Version history
- [ ] Import/export MIDI

---

## Vision

Boojy Audio is a free, open-source, cross-platform DAW designed to fill the gap between beginner-friendly but limited tools (GarageBand) and powerful but overwhelming professional software (Ableton, Logic, Pro Tools).

Part of the larger **Boojy creative software suite**, it aims to be the first DAW that is simultaneously accessible to beginners and capable enough for serious production.

### Core Principles

- **Performance first** — Runs smoothly on modest hardware
- **Minimal but complete** — Every feature polished, nothing half-done
- **Progressive disclosure** — Simple by default, powerful when needed
- **Cross-platform** — Same experience on Mac, Windows, Linux, and Web
- **Ecosystem thinking** — Designed as part of the Boojy suite from day one

---

## Design References

Each major feature draws inspiration from the best existing implementation:

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

---

## Future Versions (Post-1.0)

### v1.1 — iPad & Accessibility

- Touch-optimized UI
- Apple Pencil support
- Screen reader support
- CLAP plugin support

### v1.2 — Advanced Features

- Pitch correction (Melodyne-style)
- Stem separation (ML-based)
- MIDI effects (arpeggiator, chord, scale)
- Dolby Atmos

### v1.3 — Collaboration

- Cloud sync (Boojy Cloud)
- Real-time collaboration
- Video import for scoring
- Notation view

### v2.0 — Live Performance

- DJ Mode (two decks, crossfader)
- Session View (Ableton-style clip launcher)
- Live audio looping

---

## Technology

**Core:**

- Frontend: Flutter (Dart)
- Backend: Rust (audio engine)
- FFI: C bindings (Rust ↔ Dart)

**Audio:**

- CPAL (cross-platform audio)
- Symphonia (audio decoding)
- VST3 plugin hosting

**Platform Support:**

- [x] macOS (Intel + Apple Silicon)
- [x] iOS/iPad (basic)
- [ ] Windows
- [ ] Linux

---

## Contributing

Boojy Audio is open-source (GPL v3). Contributions welcome!

- Report bugs: [GitHub Issues](https://github.com/tyrbujac/boojy-audio/issues)
- Suggest features: [GitHub Discussions](https://github.com/tyrbujac/boojy-audio/discussions)
- Contribute code: Pull Requests

---

## Historical Milestones

For the original milestone-based development history (M0-M10), see [docs/archive/MILESTONES.md](archive/MILESTONES.md).
