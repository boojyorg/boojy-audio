# Boojy Audio Roadmap

**Current Version:** v0.1.3 (Alpha)

---

## What's Next

### v0.2.0 — Producer Workflow

- Track automation (volume/pan curves)
- Velocity UI improvements
- Library sound preview
- Sampler fixes

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

---

### v0.2.0 Details

Focus: Features that unblock beat-making and instrumental production

**Track Automation:**

- [ ] Volume automation lanes on timeline
- [ ] Pan automation lanes on timeline
- [ ] Click to add points, drag to edit
- [ ] Draw mode for freehand curves
- [ ] Sample-accurate playback interpolation

**Velocity Improvements:**

- [ ] Tooltip showing velocity value on hover
- [ ] Double-click to type exact value
- [ ] Humanize button (expose existing randomize function)
- [ ] Visual highlight for selected notes

**Library Preview:**

- [ ] Preview audio files before dragging (spacebar or button)
- [ ] Visual indicator while previewing
- [ ] Stop on selection change or drag start

**Sampler Fixes:**

- [ ] Fix stereo output (currently mono to both channels)
- [ ] Show actual sample waveform in editor
- [ ] Sample metadata display

---

### v0.3.0 — Recording & Mixing

Focus: Complete the recording workflow

**Recording:**

- [ ] MIDI controller recording
- [ ] Audio recording (mic/line input)
- [ ] Capture MIDI (retroactive)
- [ ] Input monitoring

**Mixing:**

- [ ] Mixer view (dedicated panel)
- [ ] Aux/return tracks (send effects)
- [ ] Track groups/folders

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
