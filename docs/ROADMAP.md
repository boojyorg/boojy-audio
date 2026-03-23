# Boojy Audio Roadmap

**Current Version:** v0.1.5 (Alpha)

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

## What's Next

### v0.2.0 — Recording & Mixing Essentials

- [ ] Send/Return effects (beginner-friendly presets + manual setup)
- [ ] Better Sampler editor (real waveform, loop points, one-shot, full audio controls)
- [ ] MIDI CC recording (sustain pedal + pitch bend)
- [x] Input monitoring (hear live input through DAW) — done in v0.1.5
- [ ] Tempo automation (master tempo track)
- [x] Punch in/out recording — done in v0.1.5
- [ ] Freeze/bounce track (non-destructive)
- [x] Scale/key snapping in piano roll — done in v0.1.5
- [ ] MIDI Learn (map hardware controllers to parameters)

See [v0.2-design.md](v0.2-design.md) for full design spec with mockups.

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
- [x] Track automation (volume/pan)
- [x] Velocity UI improvements

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

**Recording Workflow:** ✅ Complete

- [x] Redesigned transport controls (three-button behavior during recording)
- [x] Count-in with song context (hear actual song during count-in)
- [x] Recording overlap trimming (new recording always wins)
- [x] Undo support for recording (single Cmd+Z for entire operation)
- [x] Manual resize overlap blocking (clips clamped at adjacent boundaries)
- [x] Real-time MIDI note drawing during recording
- [x] Count-in ring timer on record button
- [x] Play → Record (no count-in when already playing)

**Multi-Track Audio Recording:** ✅ Complete

- [x] Per-track input device and channel assignment
- [x] Input selector dropdown on mixer strip with live level meters
- [x] Input monitoring on armed tracks (auto mode)
- [x] Multi-channel recording (each armed track records independently)
- [x] Auto-assign input channels on track creation
- [x] Input selector locked during recording

**MIDI File Import/Export:** ✅ Complete

- [x] Export MIDI clips as Standard MIDI Files (.mid)
- [x] Import .mid files by drag from library or Finder
- [x] Library panel shows .mid files alongside audio files

**Build System:** ✅ Complete

- [x] `build.sh` script (debug/release with auto dylib installation)
- [x] sccache integration for Rust compilation caching
- [x] Xcode auto-build (engine builds on `flutter run`)
- [x] Optimized debug dependencies (opt-level 2)
- [x] Zero Rust compiler warnings

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

### v0.6.0 — Polish & UX

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
- [x] Import/export MIDI — done in v0.1.5

---

## v1.0 Feature Progress

Detailed tracker of all v1.0 features and their status.

### Views & Workflow

**Arrangement View:**
- [x] Linear timeline for composing
- [x] Multi-track display with track headers
- [x] Time ruler with bars/beats
- [x] Playhead indicator (blue, draggable)
- [x] Horizontal scrolling and zooming
- [x] Loop region markers (with draggable handles)
- [x] Snap dropdown (Off/Bar/Beat/1/2/1/4)
- [x] Loop toggle button (L keyboard shortcut)
- [x] Context menus (clips, empty area, ruler)
- [ ] Arranger track (drag sections to rearrange)

**Mixer:**
- [x] Always-visible mixer panel (right side)
- [x] Volume faders per track
- [x] Pan controls per track
- [x] Mute/Solo buttons
- [x] Master track with limiter
- [x] Stereo level meters
- [ ] Track grouping (link tracks together)
- [ ] Bus/Aux sends UI

**UI & Themes:**
- [x] 3-panel layout (Library | Timeline | Mixer)
- [x] Resizable panels with drag dividers
- [x] Dark theme (Boojy Design System)
- [x] Bottom panel (Piano Roll / FX Chain / Instrument)
- [ ] High contrast themes (Light HC, Dark HC)
- [ ] Multiple monitor support (plugin windows on second monitor)

### Recording

**Audio Recording:**
- [x] Record from mic/interface
- [x] Input selection per track
- [x] Record arm button
- [x] Count-in metronome (1 bar)
- [x] Punch in/out
- [x] Input monitoring (auto mode)
- [ ] Loop recording (multiple takes)
- [ ] Comping / take lanes
- [ ] Pre-roll / Post-roll

**MIDI Recording:**
- [x] Record from MIDI controller
- [x] Virtual piano keyboard input
- [x] Computer keyboard mapping (ASDF keys)
- [ ] Capture MIDI (retroactive recording)

### MIDI Editing

**Piano Roll:**
- [x] Basic note drawing and editing
- [x] Velocity lane
- [x] Note preview on click/drag (FL Studio-style)
- [x] Real-time pitch audition while moving notes
- [x] Delete notes (right-click or delete key)
- [x] Multi-note selection
- [x] Scale/key highlighting
- [ ] Ghost notes (show notes from other clips)
- [ ] Chord detection and tools
- [ ] Quantize options (1/4, 1/8, 1/16, 1/32)
- [ ] Humanize

**Step Sequencer:**
- [ ] 16-step grid editor
- [ ] Default for drum instruments
- [ ] Per-step velocity editing
- [ ] Swing control
- [ ] Pattern length selector

### Audio Editing

**Clip Operations:**
- [x] Cut/copy/paste clips
- [x] Split clips at playhead (Cmd+E)
- [x] Move clips
- [x] Delete clips
- [x] Quantize clips to grid (Q key)
- [x] Multi-selection (Shift+click, Cmd+click)
- [x] Consolidate clips (Cmd+J)
- [ ] Merge clips
- [ ] Duplicate clips

**Clip Trimming:**
- [x] Audio clip left/right edge trim
- [x] MIDI clip left edge trim
- [x] Non-destructive trimming (offset)
- [x] Grid snapping for trim operations
- [ ] Crossfades between clips

**Audio Processing:**
- [x] Fade in/out (basic)
- [x] Warp/time stretch
- [x] Pitch shift (semitones/cents)
- [ ] Reverse audio
- [ ] Normalize
- [ ] Transient detection

### Automation

- [x] Basic automation lanes (volume/pan)
- [x] Draw automation points
- [ ] Automation shapes (sine, square, ramp)
- [ ] Per-parameter automation lanes

### Mixing

**Track Controls:**
- [x] Volume faders
- [x] Pan controls (proper stereo imaging)
- [x] Mute/Solo/Record buttons
- [x] Track height resizing (from mixer)
- [ ] Track colors (auto-assign from palette)
- [ ] Track icons

**Routing:**
- [ ] Sidechain routing UI
- [ ] Pre/Post fader sends
- [ ] Track folders/groups
- [ ] Summing groups (folder + bus)

**Metering:**
- [x] Peak metering (stereo)
- [ ] RMS metering
- [ ] LUFS metering with platform targets
- [ ] Mastering meter UI (Spotify/Apple Music targets)

**Effects:**
- [x] EQ
- [x] Compressor
- [x] Reverb
- [x] Delay
- [x] Limiter (master)
- [x] FX Chain view (horizontal signal flow)
- [x] Effect bypass toggle
- [x] Drag-to-reorder effects
- [ ] Chorus
- [ ] Plugin delay compensation

### Tempo & Time

- [x] Fixed tempo (BPM display)
- [ ] Time signature changes
- [ ] Tempo automation
- [ ] Tap tempo
- [ ] Swing (0-100% slider)

### Tracks & Organization

- [x] Audio tracks
- [x] MIDI tracks
- [x] Master track (always at bottom)
- [x] Add track menu (Audio/MIDI dropdown)
- [ ] Aux/Bus tracks
- [ ] Freeze tracks (save CPU)
- [ ] Bounce in place
- [ ] Track templates
- [ ] Markers/Locators

### Browser & Library

- [x] Library panel (left side)
- [x] Expandable categories (Sounds, Instruments, Effects, Plugins)
- [x] Drag instruments to timeline (auto-create track)
- [x] Preview/Audition sounds
- [ ] File browser
- [ ] Sync preview to tempo
- [ ] Favorites
- [ ] Search
- [ ] Collections

### Project & File

**Save/Load:**
- [x] Save projects (.boojy format)
- [x] Load projects
- [x] Auto-save
- [ ] Backup versions
- [ ] Version history
- [ ] Project templates
- [ ] Collect all and save

**Export:**
- [x] Export WAV (16/24/32-bit)
- [x] Export MP3 (128/192/320 kbps)
- [x] Stem export (per-track)
- [x] Export MIDI
- [x] Import MIDI
- [ ] Export with LUFS normalization
- [ ] Export progress tracking
- [ ] ID3 metadata for MP3
- [ ] Export FLAC

### Plugins

**VST3 Support:**
- [x] Scan installed VST3 plugins
- [x] Load VST3 instruments
- [x] Load VST3 effects
- [x] Plugin UI embedded in bottom panel
- [x] Floating plugin windows
- [x] Plugin state save/load with projects
- [x] Per-plugin display preferences (embed/float)
- [ ] Plugin preset browsing
- [ ] AU support (Mac)
- [ ] VST2 support (legacy)
- [ ] Plugin manager

### Stock Instruments

- [ ] Basic synthesizer (8-voice, ADSR, filter)
- [ ] Boojy Synth (wavetable, Serum-style)
- [ ] Boojy Sampler (simple/advanced modes)
- [ ] Boojy Drums (pad grid + step sequencer)
- [ ] Preset Player (piano, strings, etc.)

### Keyboard Shortcuts

- [x] Space = Play/Pause
- [x] R = Record
- [x] L = Toggle Loop
- [x] B = Toggle Library Panel
- [x] M = Toggle Mixer Panel
- [x] Cmd+S = Save
- [x] Cmd+E = Split clip
- [x] Q = Quantize clip
- [x] Cmd+J = Consolidate clips
- [x] Cmd+Z / Cmd+Shift+Z = Undo/Redo
- [x] Cmd+K = Command Palette
- [x] Native macOS menu bar shortcuts
- [ ] ? = Show keyboard shortcuts overlay
- [ ] Customizable shortcuts

### Accessibility & Performance

- [x] CPU meter display
- [x] Undo/Redo
- [ ] Undo history panel
- [ ] Tooltips on all buttons
- [ ] Built-in tutorial (Quick Start + Full Course)
- [ ] First launch onboarding

### Platforms

- [x] macOS (Intel + Apple Silicon)
- [x] iOS/iPad (basic support)
- [ ] Windows
- [ ] Linux (future)

---

## Remaining Milestones

### M8: Stock Instruments (3 weeks)

**Goal:** Add 5 built-in instruments (Piano, Synth, Sampler, Drums, Bass).

**Tasks:**
- Rust: Create `Instrument` trait, integrate into audio graph
- Piano: Multi-sample player with velocity layers, sustain pedal, ADSR
- Synth: 2-oscillator subtractive, ADSR, low-pass filter with resonance, LFO
- Sampler: Multi-sample support, velocity layers, loop points, ADSR
- Drums: 16-pad machine (4×4), pre-loaded kits (808, 909, Acoustic)
- Bass: Sub bass synthesizer (808-style), pitch envelope, saturation, filter
- Flutter: Instrument selector dropdown on MIDI track headers

### M9: Polish & UX (2 weeks)

**Goal:** Final UX polish, tooltips, error handling, keyboard shortcuts, preferences.

**Tasks:**
- Tooltips on all buttons with keyboard shortcut hints
- Toast notifications for minor events, banner warnings for critical errors
- Preferences window (Cmd+,): Audio, MIDI, File, Appearance tabs
- Track colors (auto-assign from palette)
- Clip naming (auto from filename, double-click to rename)
- UI polish: spacing, alignment, animations
- Bug fixes and performance profiling

### M10: Beta Testing & Launch (2 weeks)

**Goal:** Private beta → public beta → v1.0 launch.

**Week 1:** Private beta with 5-10 testers, feedback form, fix critical bugs
**Week 2:** Public beta tag, Reddit/social posts, YouTube tutorials, launch day

---

## Future Versions (Post-1.0)

### v1.1 — iPad & Accessibility

- Touch-optimized UI
- Apple Pencil support
- Screen reader support
- CLAP plugin support
- Automation curves (Bezier)
- Groove presets (MPC, SP-1200, TR-808, etc.)

### v1.2 — Advanced Features

- Pitch correction (Melodyne-style)
- Stem separation (ML-based)
- MIDI effects (arpeggiator, chord, scale)
- Dolby Atmos
- Smart tempo (detect tempo from audio)
- Customizable keyboard shortcuts

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

Boojy Audio is open-source (MIT). Contributions welcome!

- Report bugs: [GitHub Issues](https://github.com/tyrbujac/boojy-audio/issues)
- Suggest features: [GitHub Discussions](https://github.com/tyrbujac/boojy-audio/discussions)
- Contribute code: Pull Requests

---

## Historical Milestones

For the original milestone-based development history (M0-M10), see [archive/MILESTONES.md](archive/MILESTONES.md) and [archive/IMPLEMENTATION.md](archive/IMPLEMENTATION.md).
