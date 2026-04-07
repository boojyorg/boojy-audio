# Boojy Audio — v1.0 Feature Tracker

Detailed checklist of all features planned for v1.0 and their current status.

---

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
