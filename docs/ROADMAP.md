# Boojy Audio Roadmap

**Current Version:** v0.1.1 (Alpha)

---

## What's Next

### v0.2.0 — Core Workflow
- MIDI controller recording
- Audio clip operations (slice, copy, move)
- Loop toggle button
- Capture MIDI (retroactive recording)

---

## Version Plan

### v0.1.x — Stability & Polish (Current)

Focus: Fix bugs, stabilize existing features

**Done:**

- [x] Audio engine loading fix
- [x] Window sizing (1280x800, centered)
- [x] Code signing and notarization
- [x] Panel auto-expand on resize
- [x] MIDI clip looping visualization
- [x] MIDI loop playback (note-off timing)
- [x] Library panel refresh fix
- [x] Mixer track alignment

**Remaining:**

- [ ] Undo/redo reliability
- [ ] Clip name overflow in arrangement
- [ ] Duplicate button behavior

---

### v0.2.0 — Core Workflow Complete

Focus: Make the basic workflow reliable end-to-end

**Recording:**

- [ ] MIDI controller recording
- [ ] Capture MIDI (retroactive)

**Editing:**

- [ ] Audio clip operations (slice, copy, move)
- [ ] Piano roll button audit (verify all work)

**Arrangement:**

- [ ] Loop toggle button
- [ ] Playhead indicator improvements
- [ ] Horizontal scroll/zoom polish

**Mixing:**

- [ ] Verify pan controls work correctly
- [ ] Verify mute/solo work correctly

---

### v0.3.0 — Essential Features

Focus: Features users expect from any DAW

**Library:**

- [ ] Search functionality
- [ ] Preview/audition sounds

**Effects:**

- [ ] Chorus effect
- [ ] Verify EQ/Compressor/Reverb/Delay work well

**Piano Roll:**

- [ ] Velocity lane improvements
- [ ] Quantize options

**Quality of Life:**

- [ ] Auto-update mechanism
- [ ] Virtual piano (re-enable)

---

### v0.4.0 — Stock Instruments

Focus: Built-in instruments that sound good

- [ ] Boojy Synth (wavetable, Serum-style)
- [ ] Boojy Drums (pad grid + step sequencer)
- [ ] Boojy Sampler (drag audio, map to keys)

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
