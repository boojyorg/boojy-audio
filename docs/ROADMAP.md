# Boojy Audio - Development Roadmap

**Last Updated:** December 23, 2025
**Current Status:** M6.8 Complete (Track Height Resizing), M7 In Progress

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

### Boojy Suite Branding

Each app in the Boojy suite uses a letter in its name as a cloud connection status indicator:

| App | Status Letter | Connected | Offline | Error |
|-----|---------------|-----------|---------|-------|
| Boojy Audio | O (outline) | Blue | Yellow | Red |
| Boojy Video | O (filled) | Blue | Yellow | Red |
| Boojy Design | D | Blue | Yellow | Red |

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

## Timeline Overview

```
Week 0    Week 10   Week 15   Week 22
  │         │         │         │
  M0 ─ M5 ─┤         │         │
           M6 ─ M8 ──┤         │
                    M9 ── M10 ─┤
                             Beta: Dec 1
```

**Weeks 0-10:** Foundation (audio, recording, mixing) ✅
**Weeks 11-15:** MIDI, VST3, Instruments 🚧
**Weeks 16-22:** Polish, Beta Launch 📋
**Target Beta:** December 1, 2025

---

## Current Status

**✅ Complete:**
- M0: Project Setup
- M1: Core Playback
- M2: Recording
- M3: Editing
- M4: Mixing
- M5: Save & Export
- M5.5: UI Redesign & Polish (3-panel layout, light grey theme)
- M6: MIDI & Instruments (piano roll, synthesizer, drag-and-drop)
- M6.1: MIDI Playback Fixes (clip playback, track cleanup, stuck notes)
- M6.2: Toolbar Reorganization (grouped controls, enhanced File menu)
- M6.3: Native Menu Bar & Editor Panel (macOS menu integration, keyboard shortcuts)
- M6.4: Bug Fixes & Synth Refinements (virtual piano fix, MIDI bar-snapping, simplified synth)
- M6.5: MIDI & Arrangement Improvements (stereo meters, beat grid, pan fix)
- M6.6: iOS/iPad Support (cross-platform, audio latency control)
- M6.7: Piano Roll Improvements (FL Studio-style note preview)
- M6.8: Track Height Resizing (mixer-controlled, synced with timeline)

**🚧 In Progress:**
- M7: VST3 Plugin Support

**📋 Upcoming:**
- M8: Stock Instruments
- M9: Polish & UX
- M10: Beta Testing & Launch

---

## Milestones

### M6: MIDI & Instruments (Weeks 11-13) ✅

**Completed:** October 29, 2025

**Implemented:**
- ✅ Piano roll with velocity lane (FL Studio-style)
- ✅ Virtual piano (bottom panel, polyphonic)
- ✅ Note editing (draw, move, resize, delete, undo/redo)
- ✅ Computer keyboard mapping (ASDF keys)
- ✅ Polyphonic synthesizer (8 voices, ADSR, filter)
- ✅ Instrument browser with drag-and-drop
- ✅ Ableton-style workflow (drag from library → timeline)
- ✅ Auto-create MIDI tracks on instrument drop
- ✅ App branding update (Boojy Audio logo)
- ✅ MIDI clip playback during transport (M6.1)
- ✅ Proper track deletion cleanup (M6.1)

**Deferred to Future:**
- MIDI recording (planned for M7/M8)
- Quantize options (planned for M7/M8)

---

### M6.2: Toolbar Reorganization ✅

**Completed:** October 30, 2025

**Implemented:**
- ✅ Reorganized transport bar with logical grouping
- ✅ New layout: [Logo] [File] | [Transport] | [Tools & Time] | [Mixer]
- ✅ Enhanced File menu with 10 actions:
  - New Project, Open Project
  - Save, Save As, Make a Copy
  - Export Audio, Export MIDI
  - Project Settings, Close Project
- ✅ Visual dividers between control groups
- ✅ Material icons throughout menu (no emojis)
- ✅ Placeholder dialogs for future features (MIDI export, settings)

---

### M6.3: Native Menu Bar & Editor Panel ✅

**Completed:** October 30, 2025

**Implemented:**
- ✅ Native macOS menu bar integration using PlatformMenuBar
- ✅ Complete menu structure with keyboard shortcuts:
  - **Audio menu**: About, Services, Hide (⌘H), Hide Others (⌥⌘H), Show All, Quit (⌘Q)
  - **File menu**: New (⌘N), Open (⌘O), Save (⌘S), Save As (⇧⌘S), Make Copy, Export Audio/MIDI, Settings (⌘,), Close (⌘W)
  - **Edit menu**: Undo (⌘Z), Redo (⇧⌘Z), Cut (⌘X), Copy (⌘C), Paste (⌘V), Delete (Del), Select All (⌘A) - all disabled for now
  - **View menu**: Toggle Library (⌘L), Mixer (⌘M), Editor (⌘E), Piano (⌘P), Reset Layout, Zoom In/Out/Fit (disabled for now)
- ✅ Renamed "Bottom Panel" to "Editor Panel" throughout codebase
- ✅ Added View dropdown to toolbar with checkmarks for panel visibility
- ✅ Panel toggle methods: Library, Mixer, Editor, Virtual Piano
- ✅ Reset Panel Layout functionality (restores default sizes and visibility)
- ✅ All keyboard shortcuts working natively through macOS system
- ✅ Updated AppDelegate.swift for proper menu bar integration

---

### M6.4: Bug Fixes & Synth Refinements ✅

**Completed:** December 20, 2025

**Implemented:**

- ✅ Virtual piano works during pause/stop (audio stream stays active for live playing)
- ✅ MIDI clip bar-snapping (Ableton-style: clips align to bar boundaries)
- ✅ Simplified synthesizer architecture:
  - Single oscillator (sine, saw, square, triangle)
  - One-pole lowpass filter with cutoff control
  - ADSR envelope (attack, decay, sustain, release)
  - 8-voice polyphony with voice stealing
- ✅ Synth UI updated to match minimal architecture

---

### M6.5: MIDI & Arrangement Improvements ✅

**Completed:** December 2025

**Implemented:**

- ✅ Fixed MIDI clips rendering in timeline
- ✅ MIDI clip move and delete functionality
- ✅ Fixed note-off triggering at exact clip boundary
- ✅ Piano roll note audition while editing
- ✅ Beat-based grid display with transparency
- ✅ Fixed pan implementation with proper stereo imaging
- ✅ Stereo level meters in mixer
- ✅ Refactored daw_screen.dart: extracted service managers
- ✅ Fixed audio file routing to correct tracks
- ✅ Fixed library path resolution for different working directories
- ✅ Improved error handling throughout

---

### M6.6: iOS/iPad Support ✅

**Completed:** December 2025

**Implemented:**

- ✅ iOS support with FFI linking and proper audio initialization
- ✅ iPad/touch compatibility improvements
- ✅ Configurable audio latency control (buffer size settings)
- ✅ Optimized audio callback for mobile performance

---

### M6.7: Piano Roll Improvements ✅

**Completed:** December 2025

**Implemented:**

- ✅ FL Studio-style note preview (click and drag to preview before placing)
- ✅ Real-time pitch audition while moving notes
- ✅ Improved note movement with horizontal constraints
- ✅ Delete notes with right-click or delete key

---

### M6.8: Track Height Resizing ✅

**Completed:** December 2025

**Implemented:**

- ✅ Drag bottom edge of mixer strips to resize track heights
- ✅ Master track: drag TOP edge (opposite direction)
- ✅ Heights sync between mixer panel and timeline view
- ✅ Range: 50px min to 300px max, 100px default (60px for master)

---

### M7: VST3 Plugin Support (Weeks 14-15)

- Scan installed VST3 plugins
- Load third-party plugins
- Plugin UI in separate window (Ableton-style)
- Parameter save/load with projects
- Compatible with commercial plugins

**Target:** Late December 2025

---

### M8: Stock Instruments (Weeks 16-18)

Build 5 high-quality instruments:
- Piano (sampled grand)
- Synth (2-oscillator subtractive)
- Sampler (drag audio, map to keys)
- Drums (16-pad machine, 808/909 kits)
- Bass (808-style sub bass)

**Target:** Mid-December 2025

---

### M9: Polish & UX (Weeks 19-20)

- Tooltips on all buttons
- Built-in tips system
- Error handling (toast notifications + banners)
- Preferences window (Audio, MIDI, File, Appearance)
- Track colors (auto-assign from palette)
- Keyboard shortcuts (Ableton-style)
- Bug fixes and optimization

**Target:** Late December 2025

---

### M10: Beta Testing & Launch (Weeks 21-22)

**Week 1: Private Beta**
- Invite small group of testers
- Collect feedback
- Fix critical bugs

**Week 2: Public Beta & Launch**
- Public beta on GitHub
- Tutorial videos and documentation
- v1.0 launch announcement
- Reddit, Hacker News, YouTube

**Target Beta Launch:** December 1, 2025

---

## Feature Priority

### v1.0 (Launch)

**Must-Have (Complete):**

- ✅ Audio recording/playback
- ✅ Multiple tracks with mixing
- ✅ Built-in effects (EQ, Compressor, Reverb, Delay, Limiter)
- ✅ Save/load/export
- ✅ MIDI editing with piano roll
- ✅ MIDI playback during transport
- ✅ Synthesizer instrument

**Must-Have (In Progress):**

- 📋 VST3/AU plugin support
- 📋 Additional stock instruments:
  - **Boojy Synth** — Simplified Serum-style wavetable synth
  - **Boojy Sampler** — Simple/Advanced toggle, one instrument for all sampling needs
  - **Boojy Drums** — Pad grid + step sequencer hybrid
  - **Preset Player** — For bundled sounds (piano, strings, etc.)
- 📋 Windows release (alongside macOS)
- 📋 Inline automation lanes (Studio One/Bitwig approach)
- 📋 Mastering Assistant with LUFS metering and platform targets
- 📋 Reference track comparison with auto-volume matching
- 📋 Genre templates (Lo-Fi, Hip-Hop, Pop, Electronic, etc.)
- 📋 Track templates/presets (save and reuse track configurations)
- 📋 Freeze/flatten with non-destructive undo
- 📋 Markers and arrangement markers
- 📋 Stem separation
- 📋 Tempo and time signature automation

**Won't-Have (v1.0):**

- Cloud saving → Future (TBD)
- Session View / DJ Mode → v2.0+
- Library Mode → v2.0+
- Send effects → v1.2+
- MIDI learn → v1.2+
- Collaboration → Future (TBD)
- iPad/iPhone → Basic support added in M6.6, full optimization in v1.1
- Linux → Future (TBD)

---

### v1.1 (January 2026)

**Focus:** iPad + More Instruments

- iPad version (shared SwiftUI code)
- Touch-optimized UI
- Apple Pencil support
- 10-15 additional instruments
- Better onboarding

---

### v1.2 (Timeline TBD)

**Focus:** Live Performance & Advanced Features

- MIDI learn (controller mapping)
- Send effects (reverb/delay buses)
- Loop recording
- Collaboration features
- Linux support
- Cloud saving

---

### v2.0+ — Live Mode & Advanced Features

**Focus:** Pro Features, Live Performance & Specialized Workflows

#### Live Mode

Three sub-modes for performance and DJing:

| Sub-mode | What It Is |
|----------|------------|
| Session | Ableton-style clip grid. Launch loops, build arrangements live |
| DJ | Two decks, crossfader, beatmatching |
| Hybrid | Both — clip grid + deck. Launch stems while mixing full tracks |

**Session View:**
- Clip grid with per-track columns
- Scene launching (trigger full rows)
- Stop clips per track or globally
- Volume control per track

**DJ Mode:**
- Two decks with waveform display
- BPM and key detection
- Cue points and loops
- Crossfader with curve control
- Sync and manual beatmatching

#### Library Mode (Media Player)

- Browse and play audio files like iTunes/Spotify
- Filter by BPM, key, genre
- Integration with Boojy projects
- Right-click to load to DJ deck or import to project
- Audio analysis (BPM, key, energy)

#### Optional Content Downloads

Sound packs and instruments available as optional downloads:

- **Sound Packs:** Starter Kit, Electronic Producer, Lo-Fi Collection, Orchestral, Hip-Hop & Trap
- **Instruments:** Boojy Keys (pianos), Boojy Strings (orchestral)
- **Workflows:** Podcast Mode, Film Scoring

#### Additional v2+ Features

- **iPad + Mobile support** (early 2026)
- **Video sync for film/TV scoring**
  - Import video file (MP4, MOV) to timeline
  - Video preview window synced to playhead
  - Frame-accurate positioning (timecode support)
  - Markers for scene changes
- **Podcast mode** — Voice presets, noise reduction, chapter markers
- **Real-time collaboration** with other Boojy users
- **A/B snapshots within effects**
- **Audio restoration/repair tools**
- **Score/notation view** (integrated or separate Boojy Score app)
- **Localization** (12-15 languages over time)
- **Advanced automation** (curves, LFOs)
- **Spectral editing**
- **Surround sound** (5.1/7.1)
- **MPE support** (ROLI, Linnstrument)

---

## Launch Plan

### Phase 1: Private Beta

- Small group of trusted testers
- Focus on bug finding and UX feedback
- Iterate quickly on issues

### Phase 2: Public Beta

- Open beta on GitHub
- Announce on Reddit, Twitter
- Gather wider feedback
- Final bug fixes

### Phase 3: v1.0 Launch

- Official release on GitHub
- Tutorial videos on YouTube
- Launch posts on Reddit, Hacker News
- Update website and documentation

### Phase 4: Post-Launch

- Monitor feedback and issues
- Fix critical bugs
- Plan v1.1 based on user requests

---

## Technology

**Core:**
- Frontend: Flutter (Dart) + SwiftUI
- Backend: Rust (audio engine)
- FFI: C bindings (Rust ↔ Dart)

**Audio:**
- CPAL (cross-platform audio)
- Symphonia (audio decoding)
- VST3 plugin hosting

**Platform:**
- macOS 12+ (Monterey or later)
- Windows 10+ (v1.0 release alongside macOS)
- Intel + Apple Silicon (M1/M2/M3/M4)

**Future:**
- iPad/iPhone (v1.1 - shared codebase)
- Linux (TBD)
- Web (Flutter Web + WebAssembly - TBD)

---

## Contributing

Boojy Audio is open-source (GPL v3). Contributions welcome!

**How to help:**
- Report bugs (GitHub Issues)
- Suggest features (GitHub Discussions)
- Contribute code (Pull Requests)
- Create sample packs and presets
- Write tutorials and documentation

---

## Communication

**Monthly Dev Vlogs/Blogs:**
- YouTube dev vlogs OR blog posts
- Behind-the-scenes development
- Demos and progress updates
- Posted once per month during development

**Launch Updates:**
- GitHub Discussions for announcements
- Twitter/X (@solaraudio)
- Reddit posts for major milestones

---

## Technical Debt

Items identified for future cleanup (not blocking current development):

**TODO Placeholders:**
- CPU usage monitoring display
- Stereo meters (currently mono)
- Piano roll playhead sync with transport

**Code Organization:**
- `ui/lib/screens/daw_screen.dart` (2600+ lines) - candidate for refactoring into smaller widget files

---

## Next Steps

**Current Focus (M7):**

- Complete VST3 native GUI integration
- Test with commercial plugins (Serum, Vital, etc.)
- Plugin preset save/load with projects

**Next Up (M8):**

- Stock instruments (Piano, Drums, Sampler, Bass)
- Expand instrument library

**Beta Target:**

- Complete M8-M9
- Private beta testing
- Public beta launch

**Recent Accomplishments (M6.5-M6.8):**

- iOS/iPad support with proper audio initialization
- FL Studio-style piano roll note preview
- Track height resizing from mixer panel
- Stereo level meters and proper pan implementation
- MIDI clip editing improvements (move, delete, audition)
- Code refactoring and improved error handling

---

**Let's build the future of music production! 🎵**
