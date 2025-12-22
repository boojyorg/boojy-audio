# Boojy Audio - MVP Specification (v1.0)

**Last Updated:** December 22, 2025
**Status:** In Development (M6.8 Complete - Track Height Resizing, M7 In Progress)
**Target Platform:** macOS 12+, iOS 15+ (iPad support added)

---

## Philosophy

**Boojy Audio is:**
- **Beautiful, simple, cross-platform DAW** (macOS first, iPad/iPhone later)
- **GarageBand ease-of-use + Ableton power** (accessible to beginners, powerful for pros)
- **Hide complexity, focus on music-making** (no overwhelming options, clean UI)
- **Audio recording first, MIDI second** (optimized for recording, mixing, editing)

**Core Values:**
- ☀️ **Free forever** - No paywalls, no track limits, no subscriptions
- 🌍 **Open-source** - GPL v3, community-driven, transparent
- 🎨 **Modern design** - Beautiful UI, Ableton-inspired, not dated
- 🚀 **Cross-platform** - macOS, iPad, iPhone, Web (future: Windows, Linux)
- 🔒 **Privacy-first** - No data selling, no tracking, local-first

---

## Core Features (v1.0)

### Audio Engine

**Sample Rate & Bit Depth:**
- Auto-detect from audio interface (44.1kHz, 48kHz, 96kHz)
- Fallback to 44.1kHz if no interface detected
- 24-bit internal processing (high quality)

**Buffer Size:**
- User-selectable in Preferences: 64, 128, 256, 512, 1024 samples
- Default: 256 samples (good balance of latency vs. CPU)
- Lower = less latency (good for recording)
- Higher = more CPU headroom (good for mixing)

**CPU Management:**
- Warning banner when CPU overloads
- Audio glitches (like Ableton) but keeps playing
- Suggests: "Increase buffer size or freeze tracks"

**Master Limiter:**
- Always on by default (-0.3dB ceiling)
- Transparent, prevents clipping
- Advanced users can disable in Preferences

---

### User Interface (M5.5 Complete)

**3-Panel Layout:**
- Library Panel (left): 200px default, resizable 40-400px
- Timeline (center): Flexible width, always visible
- Mixer Panel (right): 380px default, resizable 200-600px
- Bottom Panel: 250px default, resizable 100-500px (Piano Roll / FX / Virtual Piano)

**Resizable Panels:**
- Drag dividers to adjust panel sizes
- Double-click dividers to collapse/expand
- Panel sizes saved per project (ui_layout.json)
- Subtle hover effects for discoverability

**Master Track:**
- Always positioned at bottom of timeline and mixer
- Green border for visual distinction
- Built-in limiter (always on)

**Theme:**
- Light grey theme (better visibility in well-lit environments)
- Dark text on light background (easier to read)
- Side panels: #707070, Timeline: #909090 (lighter for focus)
- Accent colors: Green (play/active), Red (record), Yellow (solo), Blue (metronome)

**Zoom Controls:**
- Compact +/- buttons in top-right of timeline
- Shows current zoom level between buttons
- Keyboard shortcuts: Cmd +/- (coming soon)

---

### Recording & Playback

**Recording:**
- Click `🔴` button to arm track for recording
- Press `R` or click `[⏺]` to start recording
- 1-bar count-in by default (toggleable next to metronome)
- Press `Space` to stop recording and keep take
- New clip appears on armed track at playhead position
- Audio file copied to project folder (`audio/` subfolder)

**Audio Input:**
- Auto-select first available input (built-in mic or interface)
- Show input selector in track header dropdown
- User can change per-track (Mic 1, Line In, etc.)

**Metronome:**
- Toggle button `[🎵]` in transport bar
- Plays during recording AND playback (user can toggle)
- 1-bar count-in before recording (default ON)
- Option to change count-in: 0, 1, 2, or 4 bars

**Input Monitoring:**
- Auto mode (default): Monitor during recording only
- On mode: Always monitor (good for live performance)
- Off mode: Never monitor (prevents feedback when recording computer audio)
- Toggle in track inspector panel

**Playback Controls:**
- `Space` = Play/Pause
- `R` = Start recording
- `[▶]` Play, `[⏹]` Stop, `[⏺]` Record buttons in transport

---

### Timeline

**Waveform Display:**
- Centered waveforms (Ableton-style)
- `─▀█▀──▀█▀──────` shows audio from center line
- Stereo info visible (left/right channels)
- Clean, modern look

**Grid Lines:**
- Thick lines every bar (1, 2, 3, 4...)
- Thin lines every beat (1.1, 1.2, 1.3, 1.4)
- Subdivision lines (16ths) only when zoomed in close
- Easy to see timing at a glance

**Playhead:**
- White vertical line during playback
- Red vertical line during recording
- Shows position: "1.2.2" (bar.beat.subdivision)

**Navigation:**
- Scroll horizontally = pan left/right
- Cmd+Scroll = zoom in/out (not in v1.0, but planned)
- Two-finger trackpad drag = pan
- Click and drag timeline background = pan

**Snap to Grid:**
- Toggle button `[⚡ Snap: 1/16]` next to metronome
- Default: ON (clips snap to 16th notes)
- Click to toggle on/off
- Click again to change snap resolution (1/4, 1/8, 1/16, 1/32)

**Track Colors:**
- Auto-assign from 8-color palette:
  - Track 1 = Red
  - Track 2 = Orange
  - Track 3 = Yellow
  - Track 4 = Green
  - Track 5 = Blue
  - Track 6 = Purple
  - Track 7 = Pink
  - Track 8 = Gray
  - Track 9+ = Repeat cycle
- Clips inherit track color

**Clip Naming:**
- Auto-named from imported file ("kick_808.wav" → "kick_808")
- Recordings auto-named: "Recording 1", "Recording 2", etc.
- Double-click clip to rename (like macOS Finder)
- Name appears on clip in timeline

---

### Mixer

**Layout:**
- Right panel (20% of screen width)
- Vertical track strips
- Master fader always at bottom

**Per-Track Controls:**
- Track name (editable, click to rename)
- `[S]` Solo button (yellow when active)
- `[M]` Mute button (gray when active)
- Volume fader (vertical slider, `|||`)
- Pan knob (horizontal slider, `<─o─>`)
- Input selector (for audio tracks)

**Master Track:**
- Always visible at bottom of mixer
- Volume fader only (no pan)
- Limiter always active (-0.3dB)

**Track Types:**
- Audio (records audio, plays audio clips)
- MIDI (records MIDI, plays virtual instruments)
- Master (final mix output)

**Track Creation:**
- Click `[+]` button in mixer
- Choose: Audio, MIDI
- Track appears in timeline and mixer
- Auto-named: "Audio 1", "MIDI 1", etc.

---

### Built-in Effects (v1.0)

**Effect Types:**
1. **EQ (Parametric 4-band)**
   - Low shelf (100 Hz, ±12 dB)
   - Mid 1 (500 Hz, ±12 dB, Q 0.5-10)
   - Mid 2 (2000 Hz, ±12 dB, Q 0.5-10)
   - High shelf (8000 Hz, ±12 dB)
   - Presets: "Flat", "Bass Boost", "Vocal Presence", "Air", "Telephone"

2. **Compressor**
   - Threshold (-40 to 0 dB)
   - Ratio (1:1 to 20:1)
   - Attack (0.1 to 100 ms)
   - Release (10 to 1000 ms)
   - Makeup Gain (0 to +20 dB)
   - Presets: "Gentle", "Punchy", "Aggressive", "Limiter", "Parallel"

3. **Reverb**
   - Room Size (0-100%)
   - Damping (0-100%)
   - Wet/Dry Mix (0-100%)
   - Presets: "Small Room", "Large Hall", "Plate", "Spring", "Cathedral"

4. **Delay**
   - Time (1/32 to 2 bars, synced to tempo)
   - Feedback (0-100%)
   - Wet/Dry Mix (0-100%)
   - Presets: "Slap", "Eighth Note", "Dotted Eighth", "Ping Pong", "Dub"

5. **Limiter**
   - No user parameters (always active on master)
   - Transparent brick-wall limiting
   - -0.3 dB ceiling (prevents clipping)

**Effect Routing:**
- Visual chain (Ableton-style boxes with arrows)
- Drag to reorder effects
- Bypass button per effect (on/off)
- Click effect to open parameter window

**Effect Presets:**
- Each effect ships with 3-5 presets
- Dropdown menu: "Preset: [Bass Boost]"
- Default: Blank (neutral settings)
- Last-used preset loads when reopening project

**Effect Window:**
- Opens in separate window (Ableton-style)
- Knobs and sliders for parameters
- Bypass button (on/off)
- Preset dropdown at top
- Close button (X)

---

### Built-in Instruments (v1.0)

**Instrument Types:**
1. **Piano**
   - Realistic grand piano (sampled)
   - Velocity-sensitive (127 levels)
   - Sustain pedal support (MIDI CC64)
   - 88 keys (A0 to C8)

2. **Synth**
   - 2-oscillator subtractive synth
   - Waveforms: Sine, Saw, Square, Triangle
   - ADSR envelope (Attack, Decay, Sustain, Release)
   - Low-pass filter with resonance
   - LFO for vibrato/tremolo

3. **Sampler**
   - Drag any audio file to map to keys
   - Multi-sample support (different samples per key)
   - Velocity layers (loud/soft samples)
   - Loop points (sustain loops)
   - ADSR envelope

4. **Drums**
   - 16-pad machine (4×4 grid)
   - Pre-loaded drum kits: "808", "909", "Acoustic", "Electronic"
   - Drag samples to pads to customize
   - Velocity-sensitive pads
   - Step sequencer (future v1.1)

5. **Bass**
   - Sub bass synthesizer
   - 808-style sine wave oscillator
   - Pitch envelope (snap/glide)
   - Saturation control (warmth)
   - Filter with envelope

**Instrument Presets:**
- Each instrument ships with 3-5 presets
- Piano: "Grand", "Bright", "Soft", "Honky Tonk"
- Synth: "Lead", "Pad", "Bass", "Pluck", "FX"
- Drums: "808", "909", "Acoustic", "Electronic"

**Loading Instruments:**
- Click `[+]` in mixer → Add MIDI Track
- Track appears with default instrument (Piano)
- Click instrument name in mixer to change
- Dropdown: Piano, Synth, Sampler, Drums, Bass

---

### MIDI

**Piano Roll:**
- Opens in bottom panel (30% of screen height)
- Piano keys on left (C0 to C8)
- Grid with bar/beat lines
- MIDI notes as horizontal blocks (`■■■■`)
- Velocity lane below (FL Studio-style)
- Drag to draw notes, click to delete
- Shift+Drag to select multiple notes
- Cmd+D to duplicate selected notes

**Velocity Lane:**
- Below piano roll (FL Studio-style)
- Vertical bars show velocity (0-127)
- Drag bars to adjust velocity
- Color-coded: Dark = low, Bright = high

**Virtual Piano:**
- Separate tab in bottom panel
- 2-octave keyboard (C3 to C5)
- Black and white keys (clickable)
- Computer keyboard mapping:
  - White keys: A S D F G H J K
  - Black keys: W E   T Y U
- Plays to armed MIDI track
- Records if track is armed + recording

**MIDI Input:**
- Always listen to MIDI keyboard (even when not recording)
- User hears notes immediately (low-latency)
- Records to armed MIDI track when `[⏺]` pressed
- Supports sustain pedal (MIDI CC64)
- Supports pitch bend and mod wheel

**Quantize:**
- Options in Preferences:
  - Auto-quantize on record (notes snap to grid)
  - Record freely, quantize after (manual button)
  - Ask user (popup on first record)
- Quantize resolution: 1/4, 1/8, 1/16, 1/32
- Apply to selected notes or entire clip

---

### VST3 Plugin Support (v1.0!)

**Plugin Scanner:**
- Scans common VST3 locations on macOS:
  - `/Library/Audio/Plug-Ins/VST3/`
  - `~/Library/Audio/Plug-Ins/VST3/`
- Runs on first launch
- Rescans when user clicks "Preferences → Rescan Plugins"

**Plugin Loader:**
- Loads VST3 bundles (`.vst3` files)
- Validates plugin (checks if VST3 compliant)
- Creates instance in audio graph

**Plugin Window:**
- Opens in separate window (Ableton default behavior)
- Plugin UI renders natively (not embedded)
- Close window = plugin stays active
- Reopen by clicking plugin in effects chain

**Plugin Presets:**
- Loads default preset on first add
- Saves last-used settings per project
- Plugin's native preset system works
- No Boojy-specific preset layer (v1.0)

**Plugin Parameters:**
- Automation support (future v1.2)
- MIDI learn support (future v1.2)
- Parameters saved with project

---

### File Management

**Project Format:**
- `.audio/` folder (macOS bundle, appears as single file)
- Contains:
  - `project.json` - All metadata and state
  - `audio/` - Imported audio files
  - `cache/` - Waveform peaks (future)

**Project Structure:**
```
MyProject.audio/
├── project.json
├── audio/
│   ├── 001-drums.wav
│   ├── 002-bass.wav
│   └── 003-vocals.wav
└── cache/
    └── (waveform peaks, future)
```

**Saving:**
- File → Save As... (first time)
- Enter project name in dialog
- Choose location with macOS folder picker
- Audio files copied to `audio/` subfolder
- `project.json` written with all state
- Success toast: "Project saved"

**Loading:**
- File → Open...
- Select `.audio` folder with macOS folder picker
- `project.json` parsed
- Tracks restored with settings
- Effects recreated with parameters
- Audio files loaded from `audio/`
- Success toast: "Project loaded"

**Auto-save:**
- Every 2 minutes
- Background thread (non-blocking)
- Saves to current project path
- No prompt, silent save
- If "Untitled Project", saves to temp location

**Recent Projects:**
- File → Recent (shows 10 recent projects)
- Sorted by last modified date
- Click to open instantly

**Closing Without Saving:**
- Prompt: "Save changes to [Project Name]?"
- Options: Save, Don't Save, Cancel
- Prevents accidental data loss

---

### Export

**Export to WAV:**
- Default: 16-bit, 44.1kHz (CD quality)
- Alternative: 24-bit, 48kHz (high quality)
- Checkbox in export dialog to choose

**Export to MP3:**
- 320kbps CBR (constant bit rate)
- Highest quality MP3
- Optional checkbox in export dialog

**Export Both:**
- Checkbox: "Export WAV + MP3"
- Creates two files: `MyProject.wav` and `MyProject.mp3`

**Export Dialog:**
- File → Export...
- Choose name and location
- Checkboxes: WAV, MP3, or both
- Progress bar during export
- Success toast: "Export complete"

**Offline Rendering:**
- Exports faster than real-time
- Renders all tracks with effects
- Applies master limiter
- No glitches or dropouts

---

### Undo/Redo

**What's Undoable:**
- ✅ Moving clips
- ✅ Recording audio
- ✅ Editing MIDI notes
- ✅ Adding/removing effects
- ✅ Changing volume/pan
- ✅ Renaming tracks/clips
- ✅ Deleting tracks
- ✅ All parameter changes

**Undo Behavior:**
- Unlimited undo steps
- Stored in memory (RAM)
- Cleared on project close
- Keyboard shortcuts: Cmd+Z (undo), Cmd+Shift+Z (redo)

**Undo History:**
- No visual history panel (v1.0)
- Simple linear undo/redo
- Future v1.1: History panel showing all actions

---

### UI/UX

**Error Handling:**
- Toast notifications (bottom-right corner, auto-dismiss after 5 seconds)
  - "Audio file imported"
  - "Effect added"
  - "Project saved"
- Banner warnings (top of window, stays until dismissed)
  - "Audio interface disconnected. Using built-in mic."
  - "CPU overload. Increase buffer size."
  - "Missing audio files. Some clips won't play."

**First-Run Experience:**
- Blank project on first launch
- No tutorial overlay (keep it simple)
- Tooltips on hover (Ableton-style help text)
- Welcome message: "Press R to record, Space to play"

**Tooltips:**
- Hover over any button for help text
- Shows keyboard shortcut if available
- Examples:
  - `[▶]` → "Play (Space)"
  - `[⏺]` → "Record (R)"
  - `[S]` → "Solo (S)"
  - `[M]` → "Mute (M)"

**Built-in Tips:**
- Random tip shown in status bar
- Examples:
  - "Pro tip: Press Cmd+K to open command palette"
  - "Tip: Double-click clip to rename"
  - "Tip: Shift+Drag to select multiple notes"
- Rotates every 30 seconds
- Can be disabled in Preferences

**Preferences Window:**
- Menu: Audio → Preferences (Cmd+,)
- 4 tabs:
  1. **Audio** - Interface, buffer size, sample rate
  2. **MIDI** - Input devices, quantize options
  3. **File** - Auto-save interval, project location
  4. **Appearance** - Theme (dark only in v1.0), colors
- Simple, under 15 settings total

**Keyboard Shortcuts:**
- Match Ableton Live (muscle memory for power users)
- Common shortcuts:
  - `Space` - Play/Pause
  - `R` - Record
  - `B` - Toggle Library Panel
  - `M` - Toggle Mixer Panel (Note: conflicts with mute, will be resolved)
  - `P` - Toggle Bottom Panel (coming soon)
  - `Cmd +/-` - Zoom In/Out Timeline
  - `Cmd+Z` - Undo
  - `Cmd+Shift+Z` - Redo
  - `Cmd+D` - Duplicate
  - `Cmd+K` - Command palette (future)
  - `S` - Solo selected track
  - `Delete` - Delete selected clip
  - `Cmd+S` - Save
  - `Cmd+O` - Open
  - `Cmd+E` - Export

---

### Platform

**macOS Support:**
- macOS 12+ (Monterey or later)
- Intel and Apple Silicon (M1/M2/M3/M4)
- Minimum window size: 1280×720
- Recommended: 1920×1080 or larger

**Windows Support (v1.0):**
- Windows 10+ (alongside macOS launch)
- x64 architecture
- Same features as macOS version

**Technology Stack:**
- Frontend: Flutter (Dart) + SwiftUI (macOS)
- Backend: Rust (audio engine)
- FFI: C bindings (Rust ↔ Dart)

**Future Platforms (v1.1+):**
- iPad (January 2026 - shared SwiftUI codebase)
- iPhone (adapted UI)
- Linux (TBD)
- Web (Flutter Web + WebAssembly - TBD)

---

## What's NOT in v1.0

### Deferred to v1.1+

**❌ Cloud Saving**
- Optional cloud sync
- Version history
- Deferred to future release (TBD)

**❌ Session View / DJ Mode**
- Clip launching (Ableton-style grid)
- Live performance features
- Deferred to v1.2+ (after launch feedback)

**❌ Send Effects**
- Reverb/delay buses
- Per-track send knobs
- Return tracks
- Deferred to v1.2+ (complex routing)

**❌ MIDI Learn**
- Map MIDI controller knobs to parameters
- Deferred to v1.2+ (live performance feature)

**❌ MPE Support**
- ROLI Seaboard, Linnstrument, etc.
- Deferred to v2.0 (niche feature, <5% of users)

**❌ Templates**
- Save as template
- Template picker on first run
- Deferred to v1.1 (nice-to-have)

**❌ Collaboration**
- Real-time editing (Google Docs-style)
- Async sharing (Dropbox-style)
- Deferred to future (TBD)

**❌ iPad/iPhone Versions**
- Touch-optimized UI
- Mobile workflows
- Deferred to v1.1 (January 2026)

**❌ Linux Port**
- Cross-platform build
- Platform-specific audio APIs
- Deferred to future (TBD)

**❌ Advanced Features**
- Spectral editing
- Notation/score export
- **Video sync** (import video, sync playhead, frame-accurate scoring)
- Surround sound (5.1/7.1)
- Advanced time-stretching
- All deferred to v2.0+ (pro features)

---

## User Workflows

### Recording Your First Song

1. **Launch Boojy Audio**
   - Opens to blank project
   - Master track visible
   - Transport bar ready

2. **Add Audio Track**
   - Click `[+]` in mixer
   - Select "Audio"
   - Track appears, auto-armed (🔴 red)

3. **Select Input**
   - Click track header dropdown
   - Choose: "Built-in Mic" or interface input
   - Levels show in track meter

4. **Record Audio**
   - Press `R` or click `[⏺]`
   - 1-bar count-in (click-click-click-click)
   - Start singing/playing
   - Press `Space` to stop
   - Clip appears on timeline

5. **Add More Tracks**
   - Click `[+]` → "Audio" for more recordings
   - Click `[+]` → "MIDI" for virtual instruments
   - Repeat record process

6. **Mix**
   - Adjust volume faders in mixer
   - Pan tracks left/right
   - Solo/Mute to isolate tracks

7. **Add Effects**
   - Select track
   - Click `[+]` in effects section
   - Choose EQ, Compressor, Reverb, etc.
   - Adjust parameters in effect window

8. **Save**
   - File → Save As...
   - Name: "My First Song"
   - Choose location
   - Success!

9. **Export**
   - File → Export...
   - Check: WAV + MP3
   - Click "Export"
   - Share your song!

---

### Working with MIDI

1. **Add MIDI Track**
   - Click `[+]` → "MIDI"
   - Default instrument: Piano
   - Track auto-armed

2. **Play Notes**
   - Click piano keys in virtual piano tab
   - Or press computer keyboard (A S D F...)
   - Or play MIDI keyboard
   - Hear notes immediately

3. **Record MIDI**
   - Press `R` or click `[⏺]`
   - Play notes
   - Press `Space` to stop
   - MIDI clip appears on timeline

4. **Edit MIDI**
   - Double-click MIDI clip
   - Piano roll opens in bottom panel
   - Draw notes with mouse
   - Adjust velocity in velocity lane
   - Drag notes to move/resize

5. **Change Instrument**
   - Click instrument name in mixer
   - Choose: Synth, Sampler, Drums, Bass
   - Notes now play with new instrument

6. **Add Effects to MIDI Track**
   - Same as audio tracks
   - EQ, Reverb, Delay work on instruments
   - Effects process instrument output

---

### Using VST3 Plugins

1. **Scan Plugins**
   - First launch: Boojy auto-scans VST3 folders
   - Or: Preferences → Rescan Plugins

2. **Add Plugin to Track**
   - Select track
   - Click `[+]` in effects section
   - Scroll to find VST3 plugins (below built-in effects)
   - Click plugin name

3. **Open Plugin Window**
   - Plugin window opens automatically
   - Native plugin UI appears
   - Adjust parameters

4. **Close Plugin Window**
   - Close window (plugin stays active)
   - Reopen: Click plugin box in effects chain

5. **Save Project**
   - Plugin parameters saved with project
   - Reopening project restores plugin state

---

## Technical Constraints

### Audio

**Sample Rates:**
- Supported: 44.1kHz, 48kHz, 96kHz
- Auto-detect from interface
- Fallback: 44.1kHz

**Bit Depth:**
- Internal: 24-bit processing
- Export: 16-bit or 24-bit (user choice)

**Buffer Sizes:**
- Options: 64, 128, 256, 512, 1024 samples
- Default: 256 samples
- Lower = less latency, more CPU usage
- Higher = more latency, less CPU usage

**Track Limits:**
- Unlimited audio tracks (CPU-limited)
- Unlimited MIDI tracks (CPU-limited)
- Realistic: 50+ tracks on modern Mac

**Effect Limits:**
- Unlimited effects per track (CPU-limited)
- Realistic: 10-20 effects per track

---

### File Formats

**Import:**
- Audio: WAV, MP3, FLAC, OGG
- MIDI: Not supported in v1.0 (future)

**Export:**
- Audio: WAV (16/24-bit, 44.1/48kHz), MP3 (320kbps)

**Project:**
- Format: `.audio/` folder (macOS bundle)
- Contains: `project.json` + `audio/` subfolder
- Human-readable JSON (easy to debug)

---

### UI

**Window Size:**
- Minimum: 1280×720
- Recommended: 1920×1080 or larger
- Fullscreen supported

**Theme:**
- Dark theme only (v1.0)
- Light theme in v1.1+ (if users request)

**Accessibility:**
- High contrast mode (future)
- Keyboard navigation (future)
- Screen reader support (future)

---

## Success Metrics

### v1.0 MVP is successful if:

**Functional:**
- ✅ Can record audio and play it back without glitches
- ✅ Can add multiple tracks (audio + MIDI)
- ✅ Can apply effects with parameters
- ✅ Can save and load projects reliably
- ✅ Can export to WAV/MP3 without errors
- ✅ VST3 plugins load and work correctly
- ✅ MIDI recording and editing works
- ✅ Works on macOS without crashes

**Quality:**
- ✅ UI is beautiful and intuitive
- ✅ Audio quality is professional (no artifacts)
- ✅ Latency is acceptable (<10ms at 256 buffer)
- ✅ No memory leaks or crashes

**User Feedback:**
- ✅ 5-10 beta testers provide positive feedback
- ✅ Zero critical bugs reported
- ✅ Users say: "This is easier than Ableton/Logic"
- ✅ Users say: "UI looks amazing"

**Launch Goals:**
- 🎯 100+ GitHub stars in first week
- 🎯 50+ YouTube tutorial views
- 🎯 10+ Reddit upvotes
- 🎯 5+ positive user testimonials

---

## Launch Checklist

### Before Beta Launch (December 1, 2025)

- [ ] All M1-M10 features complete
- [ ] 5-10 private beta testers give feedback
- [ ] Fix critical bugs
- [ ] Create 5-10 YouTube tutorials (5 min each)
- [ ] Record product trailer (2 min)
- [ ] Write GitHub README
- [ ] Set up GitHub wiki for docs

### Beta Launch Day (December 1, 2025)

- [ ] Tag v0.9-beta release on GitHub
- [ ] Post to /r/WeAreTheMusicMakers
- [ ] Post to /r/linuxaudio
- [ ] Upload tutorials to YouTube
- [ ] Share on Twitter/X
- [ ] Email private beta testers
- [ ] Monitor feedback and fix critical bugs

### Post-Beta

- [ ] Iterate based on user feedback
- [ ] Fix bugs and polish UX
- [ ] Plan v1.0 stable release
- [ ] Plan v1.1 (iPad version)

---

## Roadmap After v1.0

### v1.1 (January 2026)

**Focus:** iPad + More Instruments
- iPad version (shared SwiftUI code)
- Touch-optimized UI
- Apple Pencil support
- 15-20 stock instruments (expand from 5)
- Better onboarding (welcome video)

**Timeline:** January 2026

---

### v1.2+ (Timeline TBD)

**Focus:** Live Performance & Advanced Features
- MIDI learn (controller mapping)
- DJ/Live Performance mode
- Send effects (reverb/delay buses)
- Session View (Ableton-style clip launching)
- Loop recording
- Cloud saving (optional)
- Collaboration features
- Linux support
- Templates
- Advanced features (time-stretch, spectral editing)

**Timeline:** TBD (based on user feedback and priorities)

---

## Documentation

**GitHub Wiki:**
- Getting Started guide
- Recording tutorial
- MIDI tutorial
- Mixing tutorial
- Effects reference
- Keyboard shortcuts
- FAQ

**Website (solaraudio.com):**
- Landing page
- Download link
- Tutorials page (embed YouTube videos)
- Documentation link (to GitHub wiki)
- Blog (development updates)

**YouTube Channel:**
- Tutorial series (5-10 videos × 5 min)
- Product trailer (2 min)
- Behind-the-scenes (development vlogs)

---

**End of MVP Specification**

**Next Step:** Start M6 (MIDI & Piano Roll) implementation! 🎹🚀