# Boojy Audio - Feature Specification

## Overview

This document is the **single source of truth** for all Boojy Audio features, organized by version with progress tracking.

**Related Documentation:**

- [ROADMAP.md](ROADMAP.md) — Vision, timeline, and strategic overview
- [IMPLEMENTATION.md](IMPLEMENTATION.md) — Detailed development tasks
- [UI_DESIGN.md](UI_DESIGN.md) — UI specifications and component details

---

## Version Progress Summary

| Version | Status | Target | Progress |
|---------|--------|--------|----------|
| **v1.0** | In Progress | Jan 2026 | ████████░░ ~55% |
| **v1.1** | Planned | Q1 2026 | ░░░░░░░░░░ 0% |
| **v1.2** | Planned | Q2 2026 | ░░░░░░░░░░ 0% |
| **v1.3** | Planned | Q3 2026 | ░░░░░░░░░░ 0% |
| **v2.0** | Planned | 2027 | ░░░░░░░░░░ 0% |

---

## Version Definitions

### v1.0 - Core DAW (Target: January 2026)
Everything needed to make music: recording, editing, mixing, MIDI, VST3, stock instruments.

### v1.1 - Polish & iPad (Target: Q1 2026)
iPad optimization, more effects, accessibility features, automation curves, CLAP support.

### v1.2 - Advanced Features (Target: Q2 2026)
Pitch correction, stem separation, MIDI effects, Dolby Atmos, smart tempo.

### v1.3 - Collaboration (Target: Q3 2026)
Cloud sync, real-time collaboration, notation view, video sync.

### v2.0 - Live Performance (Target: 2027)
DJ Mode, Session View, clip launcher, crossfader, live looping.

---

# v1.0 - Core DAW

**Status:** In Progress (~55% complete)
**Target:** January 2026

---

## Views & Workflow

### Arrangement View
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

### Mixer
- [x] Always-visible mixer panel (right side)
- [x] Volume faders per track
- [x] Pan controls per track
- [x] Mute/Solo buttons
- [x] Master track with limiter
- [x] Stereo level meters
- [ ] Track grouping (link tracks together)
- [ ] Bus/Aux sends UI

### UI & Themes
- [x] 3-panel layout (Library | Timeline | Mixer)
- [x] Resizable panels with drag dividers
- [x] Light grey theme
- [x] Bottom panel (Piano Roll / FX Chain / Instrument)
- [ ] Dark theme
- [ ] High contrast themes (Light HC, Dark HC)
- [ ] Multiple monitor support (plugin windows on second monitor)

---

## Recording

### Audio Recording
- [x] Record from mic/interface
- [x] Input selection per track
- [x] Record arm button
- [x] Count-in metronome (1 bar)
- [ ] Loop recording (multiple takes)
- [ ] Comping / take lanes
- [ ] Punch in/out
- [ ] Pre-roll / Post-roll
- [ ] Input monitoring modes (Auto/On/Off)

### MIDI Recording
- [x] Record from MIDI controller
- [x] Virtual piano keyboard input
- [x] Computer keyboard mapping (ASDF keys)
- [ ] Capture MIDI (retroactive recording)

---

## MIDI Editing

### Piano Roll
- [x] Basic note drawing and editing
- [x] Velocity lane
- [x] Note preview on click/drag (FL Studio-style)
- [x] Real-time pitch audition while moving notes
- [x] Delete notes (right-click or delete key)
- [x] Multi-note selection
- [ ] Ghost notes (show notes from other clips)
- [ ] Scale/key highlighting
- [ ] Chord detection and tools
- [ ] Quantize options (1/4, 1/8, 1/16, 1/32)
- [ ] Humanize

### Step Sequencer
- [ ] 16-step grid editor
- [ ] Default for drum instruments
- [ ] Per-step velocity editing
- [ ] Swing control
- [ ] Pattern length selector

---

## Audio Editing

### Clip Operations
- [x] Cut/copy/paste clips
- [x] Split clips at playhead (Cmd+E)
- [x] Move clips
- [x] Delete clips
- [x] Quantize clips to grid (Q key)
- [x] Multi-selection (Shift+click, Cmd+click)
- [x] Consolidate clips (Cmd+J)
- [ ] Merge clips
- [ ] Duplicate clips

### Clip Trimming
- [x] Audio clip left/right edge trim
- [x] MIDI clip left edge trim
- [x] Non-destructive trimming (offset)
- [x] Grid snapping for trim operations
- [ ] Crossfades between clips

### Audio Processing
- [x] Fade in/out (basic)
- [ ] Reverse audio
- [ ] Normalize
- [ ] Time stretch
- [ ] Pitch shift
- [ ] Warp/Flex time
- [ ] Transient detection

---

## Automation

- [ ] Basic automation lanes (volume/pan)
- [ ] Draw automation curves
- [ ] Automation shapes (sine, square, ramp)
- [ ] Per-parameter automation lanes

---

## Mixing

### Track Controls
- [x] Volume faders
- [x] Pan controls (proper stereo imaging)
- [x] Mute/Solo/Record buttons
- [x] Track height resizing (from mixer)
- [ ] Track colors (auto-assign from palette)
- [ ] Track icons

### Routing
- [ ] Sidechain routing UI
- [ ] Pre/Post fader sends
- [ ] Track folders/groups
- [ ] Summing groups (folder + bus)

### Metering
- [x] Peak metering (stereo)
- [ ] RMS metering
- [ ] LUFS metering with platform targets
- [ ] Mastering meter UI (Spotify/Apple Music targets)

### Effects
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

---

## Tempo & Time

- [x] Fixed tempo (BPM display)
- [x] Time signature (4/4)
- [ ] Tempo automation
- [ ] Tap tempo
- [ ] Time signature changes
- [ ] Swing (0-100% slider)

---

## Tracks & Organization

- [x] Audio tracks
- [x] MIDI tracks
- [x] Master track (always at bottom)
- [x] Add track menu (Audio/MIDI dropdown)
- [ ] Aux/Bus tracks
- [ ] Freeze tracks (save CPU)
- [ ] Unfreeze tracks
- [ ] Bounce in place
- [ ] Track templates
- [ ] Markers/Locators

---

## Browser & Library

- [x] Library panel (left side)
- [x] Expandable categories (Sounds, Instruments, Effects, Plugins)
- [x] Drag instruments to timeline (auto-create track)
- [ ] File browser
- [ ] Preview/Audition sounds
- [ ] Sync preview to tempo
- [ ] Favorites
- [ ] Search
- [ ] Collections

---

## Project & File

### Save/Load
- [x] Save projects (.boojy format)
- [x] Load projects
- [x] Auto-save
- [ ] Backup versions
- [ ] Version history
- [ ] Project templates
- [ ] Collect all and save

### Export
- [x] Export WAV (16/24/32-bit)
- [x] Export MP3 (128/192/320 kbps)
- [x] Export with LUFS normalization
- [x] Export progress tracking
- [x] Stem export (per-track)
- [x] ID3 metadata for MP3
- [ ] Export FLAC
- [ ] Export MIDI
- [ ] Import MIDI

---

## Plugins

### VST3 Support
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

---

## Stock Instruments

- [x] Basic synthesizer (8-voice, ADSR, filter)
- [ ] Boojy Synth (wavetable, Serum-style)
- [ ] Boojy Sampler (simple/advanced modes)
- [ ] Boojy Drums (pad grid + step sequencer)
- [ ] Preset Player (piano, strings, etc.)

---

## Accessibility & QoL

### Keyboard Shortcuts
- [x] Space = Play/Pause
- [x] R = Record
- [x] L = Toggle Loop
- [x] M = Toggle Metronome
- [x] Cmd+S = Save
- [x] Cmd+E = Split clip
- [x] Q = Quantize clip
- [x] Cmd+J = Consolidate clips
- [x] Native macOS menu bar shortcuts
- [x] ? = Show keyboard shortcuts overlay
- [ ] Customizable shortcuts

### Help & Learning
- [ ] Tooltips on all buttons
- [ ] Built-in tutorial (Quick Start + Full Course)
- [ ] First launch onboarding

### Performance
- [x] CPU meter display
- [ ] Undo/Redo with 100+ levels
- [ ] Undo history panel

---

## Platforms

- [x] macOS (Intel + Apple Silicon)
- [x] iOS/iPad (basic support)
- [ ] Windows
- [ ] Linux (future)

---

# v1.1 - Polish & iPad

**Status:** Planned (0% complete)
**Target:** Q1 2026

## iPad Optimization
- [ ] Touch-optimized UI
- [ ] Apple Pencil support
- [ ] Touch gestures for editing

## Effects & Processing
- [ ] Automation curves (Bezier)
- [ ] Clip automation
- [ ] Groove presets (MPC, SP-1200, TR-808, etc.)
- [ ] AAF/OMF export (Pro Tools interchange)

## Plugins
- [ ] CLAP support
- [ ] Plugin sandboxing (crash protection)

## Accessibility
- [ ] Screen reader support (VoiceOver, NVDA)
- [ ] Visual metronome
- [ ] Pop-out Mixer/Editor windows
- [ ] Chord track

---

# v1.2 - Advanced Features

**Status:** Planned (0% complete)
**Target:** Q2 2026

## Audio Processing
- [ ] Flex Pitch / Pitch correction (Melodyne-style)
- [ ] Slice to MIDI
- [ ] Audio to MIDI (melody detection)
- [ ] Stem separation (ML-based)
- [ ] Smart tempo (detect tempo from audio)
- [ ] Tempo follower

## MIDI Effects
- [ ] Arpeggiator
- [ ] Chord (add intervals)
- [ ] Scale (force to scale)
- [ ] Velocity (randomize/compress)
- [ ] Note Length
- [ ] Humanize
- [ ] MIDI transformations (arpeggiate, strum)
- [ ] MIDI generators (pattern generation)

## Mixing
- [ ] Dolby Atmos (spatial audio)
- [ ] LFO automation

## Other
- [ ] Customizable keyboard shortcuts

---

# v1.3 - Collaboration

**Status:** Planned (0% complete)
**Target:** Q3 2026

## Cloud & Sharing
- [ ] Cloud save (Boojy Cloud)
- [ ] Project sharing
- [ ] Sound similarity search

## Media
- [ ] Video import for scoring
- [ ] Score/notation view

---

# v2.0 - Live Performance

**Status:** Planned (0% complete)
**Target:** 2027

## DJ Mode
- [ ] Two decks with waveform display
- [ ] BPM and key detection
- [ ] Cue points and loops
- [ ] Crossfader with curve control
- [ ] Sync and manual beatmatching

## Session View
- [ ] Clip grid (Ableton-style)
- [ ] Scene launching
- [ ] Follow actions
- [ ] Stop clips per track/globally

## Live Features
- [ ] Live audio looping
- [ ] Real-time collaboration

## Library Mode
- [ ] Browse and play audio files
- [ ] Filter by BPM, key, genre
- [ ] Audio analysis

---

# Not Including (Design Decisions)

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

# Appendix: UI Mockups

## Step Sequencer Layout (v1.0)

```
+-------------------------------------------------------------------+
| STEP SEQUENCER                    [Pattern 1 v] [Piano Roll]      |
+-------------------------------------------------------------------+
|         | 1 . . . | 2 . . . | 3 . . . | 4 . . . | Steps: 16      |
+---------+---------+---------+---------+---------+                 |
| Kick    | * . . . | * . . . | * . . . | * . . . | [Vol] [Pan]     |
| Snare   | . . * . | . . * . | . . * . | . . * . | [Vol] [Pan]     |
| Hi-hat  | * . * . | * . * . | * . * . | * . * . | [Vol] [Pan]     |
| Clap    | . . . . | * . . . | . . . . | * . . . | [Vol] [Pan]     |
| 808     | * . . . | . . . . | * . . . | . . . . | [Vol] [Pan]     |
+---------+---------+---------+---------+---------+-----------------+
| VELOCITY                                                          |
| [_###_###_###_###]  <- Click step to edit velocity                |
+-------------------------------------------------------------------+
| Swing: [0%----*----100%]   Length: [1 bar v]   [Copy] [Clear]     |
+-------------------------------------------------------------------+
```

## Mastering Meter UI (v1.0)

```
+-----------------------------------------------------------+
| MASTERING METER                                           |
+-----------------------------------------------------------+
|  Loudness:  -12.3 LUFS   [############....]               |
|                          ^ Target: -14 LUFS (Spotify)     |
|                                                           |
|  Peak:      -1.2 dB      [##############..] Safe          |
|                                                           |
|  Target: [Spotify v]     Status: 1.7 dB too loud          |
|                                                           |
|  Presets: [Streaming] [CD/Club] [Podcast] [Custom]        |
+-----------------------------------------------------------+
```

## Target Presets

| Preset | Target LUFS | True Peak |
|--------|-------------|-----------|
| Spotify | -14 LUFS | -1 dB |
| Apple Music | -16 LUFS | -1 dB |
| YouTube | -14 LUFS | -1 dB |
| SoundCloud | -14 LUFS | -1 dB |
| CD / Club | -9 LUFS | -0.3 dB |
| Podcast | -16 LUFS | -1 dB |
