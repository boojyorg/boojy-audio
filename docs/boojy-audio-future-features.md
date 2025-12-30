# Boojy Audio - Complete Feature Specification

## Overview

This document specifies all features and their target versions for Boojy Audio.

---

## Version Summary

| Version | Focus |
|---------|-------|
| **v1.0** | Core DAW - everything needed to make music |
| **v1.1** | Polish, more effects, iPad, accessibility |
| **v1.2** | Advanced features (pitch correction, stem separation, MIDI effects) |
| **v1.3** | Collaboration, notation, video sync |
| **v2.0** | DJ Mode / Live Performance |

---

## VIEWS / WORKFLOW

| Feature | Version | Notes |
|---------|---------|-------|
| Arrangement View | v1.0 | Linear timeline for composing |
| Session/Clip View | v2.0 | DJ Mode - non-linear clip launcher |
| Dual View | v2.0 | Both views simultaneously |
| Pattern-based workflow | No | Instead: Arranger track (like Studio One) |
| Arranger Track | v1.0 | Drag sections to rearrange song structure |
| Mixer in Arrangement | v1.0 | See mixer while in timeline |
| Detachable windows | No | Keep UI simple and beginner-friendly |
| Multiple monitors | v1.0 | Plugin windows on second monitor |
| Pop-out Mixer/Editor | v1.1 | Optional second window for mixer or editor |
| Themes | v1.0 | Light, Dark, Light HC, Dark HC |
| UI customization | Limited | Only UI size scaling, layout stays rigid |

---

## RECORDING

| Feature | Version | Notes |
|---------|---------|-------|
| MIDI recording | v1.0 | From keyboard/controller |
| Audio recording | v1.0 | From mic/interface |
| Loop recording | v1.0 | Multiple takes in a loop |
| Comping / Take lanes | v1.0 | Pick best parts from multiple takes |
| Punch in/out | v1.0 | Record only specific section |
| Count-in | v1.0 | Metronome count before recording |
| Pre-roll | v1.0 | Playback before record point (get into groove) |
| Post-roll | v1.0 | Playback after record stops (hear in context) |
| Input monitoring | v1.0 | Hear yourself while recording |
| Capture MIDI | v1.0 | Capture what you played even if not recording |

---

## EDITING - MIDI

| Feature | Version | Notes |
|---------|---------|-------|
| Piano roll | v1.0 | Note editor for melodic instruments |
| Step sequencer | v1.0 | Grid editor, default for drums |
| Drums default to step sequencer | v1.0 | When loading drum kit, open step sequencer |
| Switch between piano roll / step seq | v1.0 | User can toggle |
| Quantize | v1.0 | Snap notes to grid |
| Humanize | v1.0 | Add slight randomness |
| Velocity editing | v1.0 | Change note loudness |
| Note length editing | v1.0 | Stretch/shorten notes |
| Scale/Key highlighting | v1.0 | Show notes in scale |
| Chord tools | v1.0 | Generate/detect chords |
| MIDI transformations | v1.2 | Arpeggiate, strum, etc. |
| MIDI generators | v1.2 | Generate patterns |
| MIDI effects | v1.2 | Arpeggiator, Chord, Scale |
| Score/notation view | v1.3 | Sheet music editing |

### MIDI Effects (v1.2)

| Effect | Priority |
|--------|----------|
| Arpeggiator | High |
| Chord (add intervals) | High |
| Scale (force to scale) | High |
| Velocity (randomize/compress) | Medium |
| Note Length | Medium |
| Humanize | Medium |

---

## EDITING - AUDIO

| Feature | Version | Notes |
|---------|---------|-------|
| Cut/Copy/Paste | v1.0 | Basic clip editing |
| Split clips | v1.0 | Divide at playhead |
| Merge clips | v1.0 | Combine clips |
| Crossfades | v1.0 | Smooth transitions |
| Fade in/out | v1.0 | Volume fades on clips |
| Reverse audio | v1.0 | Play backwards |
| Normalize | v1.0 | Maximize volume |
| Time stretch | v1.0 | Change length without pitch |
| Pitch shift | v1.0 | Change pitch without length |
| Warp/Flex Time | v1.0 | Adjust timing of audio |
| Transient detection | v1.0 | Find drum hits/attacks |
| Flex Pitch / Pitch correction | v1.2 | Like Melodyne - graphical pitch editing |
| Slice to MIDI | v1.2 | Chop audio to sampler |
| Audio to MIDI | v1.2 | Convert melody to notes (do this WELL) |
| Stem separation | v1.2 | Split vocals/drums/bass/other |

---

## AUTOMATION

| Feature | Version | Notes |
|---------|---------|-------|
| Basic automation | v1.0 | Draw volume/pan curves |
| Automation lanes | v1.0 | Separate lane per parameter |
| Automation shapes | v1.0 | Sine, square, ramp presets |
| Automation curves (Bezier) | v1.1 | Smooth curved automation |
| LFO automation | v1.2 | Modulate with LFO |
| Read/Write modes | Skip | Too complex for beginners |
| Clip automation | v1.1 | Automation inside clips (copies with clip) |

---

## MIXING

| Feature | Version | Notes |
|---------|---------|-------|
| Volume faders | v1.0 | Track levels |
| Pan controls | v1.0 | Stereo position |
| Mute/Solo/Record | v1.0 | M S R buttons |
| Track grouping | v1.0 | Link tracks together |
| Bus/Aux sends | v1.0 | Route to effect buses |
| Pre/Post fader sends | v1.0 | Send before or after fader |
| Sidechain routing | v1.0 | Duck one track with another |
| Plugin insert slots | v1.0 | Add effects to tracks |
| Plugin delay compensation | v1.0 | Keep plugins in sync |
| Peak metering | v1.0 | Prevent clipping |
| RMS metering | v1.0 | Average loudness |
| LUFS metering | v1.0 | Modern loudness standard |
| Beginner-friendly mastering | v1.0 | Show target for Spotify/Apple Music |
| Surround sound (5.1, 7.1) | v1.0 | Advanced mixing |
| Dolby Atmos | v1.2 | Spatial audio |

### Mastering Meter UI (v1.0)

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

---

## TEMPO / TIME

| Feature | Version | Notes |
|---------|---------|-------|
| Fixed tempo | v1.0 | Single BPM |
| Tempo automation | v1.0 | Change tempo over time |
| Tap tempo | v1.0 | Tap to set BPM |
| Time signature | v1.0 | 4/4, 3/4, etc. |
| Time signature changes | v1.0 | Different per section |
| Swing | v1.0 | Simple 0-100% slider |
| Groove presets | v1.1 | 5-10 presets (Light, Heavy, MPC, etc.) |
| Smart Tempo | v1.2 | Detect tempo from audio |
| Tempo follower | v1.2 | DAW follows live audio |

### Swing UI (v1.0)

```
Swing: [0%--------*--------100%]

v1.1 presets:
[None] [Light] [Heavy] [Triplet] [MPC] [Vintage]
```

---

## TRACKS / ORGANIZATION

| Feature | Version | Notes |
|---------|---------|-------|
| Track limit | v1.0 | 500 tracks max (performance) |
| Audio tracks | v1.0 | Contains audio clips, records audio |
| MIDI tracks | v1.0 | Contains MIDI clips, plays instruments |
| Aux/Bus tracks | v1.0 | Receives audio for shared processing |
| Master track | v1.0 | Final output |
| Track colors | v1.0 | Auto by instrument + manual override |
| Track icons | v1.0 | Visual icons per track |
| Track folders/groups | v1.0 | Collapse tracks + optional summing |
| Summing groups | v1.0 | Folder + bus combined |
| Freeze tracks | v1.0 | Bounce to save CPU (reversible!) |
| Unfreeze tracks | v1.0 | Restore original MIDI/plugins |
| Bounce in place | v1.0 | Render to audio permanently |
| Track templates | v1.0 | Pre-configured track setups |
| Markers/Locators | v1.0 | Label song sections |
| Arranger track | v1.0 | Define and rearrange song sections (like Studio One) |
| Chord track | v1.1 | Global chord progression, clips can follow |

### Arranger Track (v1.0 - Like Studio One)

```
+-----------------------------------------------------------+
| ARRANGER | Intro | Verse | Chorus | Verse | Chorus | Out  |
+-----------------------------------------------------------+
| Track 1  |.......|#######|########|#######|########|....| |
| Track 2  |.......|#######|########|#######|########|....| |
+-----------------------------------------------------------+

Drag sections to rearrange:
| Intro | Verse | Verse | Chorus | Chorus | Out |
```

---

## BROWSER / LIBRARY

| Feature | Version | Notes |
|---------|---------|-------|
| File browser | v1.0 | Browse files |
| Sound browser | v1.0 | Browse presets/sounds |
| Preview/Audition | v1.0 | Hear before loading |
| Sync preview to tempo | v1.0 | Preview in project tempo |
| Sync preview to key | Skip | Too complex for now |
| Favorites | v1.0 | Mark favorites |
| Search | v1.0 | Search library |
| Collections | v1.0 | Organize into folders |
| Tagging system | Skip | Keep it simple |
| Sound similarity | v1.3 | Find similar sounds |
| Cloud integration | TBD | Maybe v1.3 |

---

## PROJECT / FILE

| Feature | Version | Notes |
|---------|---------|-------|
| Save/Load projects | v1.0 | .boojy format |
| Auto-save | v1.0 | Automatic saving |
| Backup versions | v1.0 | Keep old versions |
| Version history | v1.0 | See past versions |
| Project templates | v1.0 | Start from template |
| Collect all and save | v1.0 | Package project with files |
| Export WAV | v1.0 | Lossless audio |
| Export MP3 | v1.0 | Compressed audio |
| Export FLAC | v1.0 | Lossless compressed |
| Export stems | v1.0 | Individual tracks |
| Export MIDI | v1.0 | Save MIDI files |
| Import MIDI | v1.0 | Load MIDI files |
| Import audio | v1.0 | Load audio files |
| Video import | v1.3 | Import video for scoring |
| AAF/OMF export | v1.1 | Pro Tools interchange |

---

## PLUGINS

| Feature | Version | Notes |
|---------|---------|-------|
| VST3 support | v1.0 | Standard plugin format |
| AU support (Mac) | v1.0 | Mac plugin format |
| VST2 support | v1.0 | Legacy plugins |
| CLAP support | v1.1 | New plugin format |
| Plugin manager | v1.0 | Organize plugins |
| Plugin presets | v1.0 | Save/recall plugin settings |
| Plugin sandboxing | v1.1 | Crash protection |

---

## AI / SMART FEATURES

| Feature | Version | Notes |
|---------|---------|-------|
| Drummer/Session Player | No | Focus on great instruments instead |
| MIDI generators | v1.2+ | Chord progressions, patterns |
| Stem separation | v1.2 | ML-based source separation |
| Mastering assistant | No | Instead: beginner-friendly manual tools |
| Pitch correction | v1.2 | Real-time + graphical |
| Smart tempo | v1.2 | Detect tempo from audio |

**Philosophy:** Use ML where helpful (stem separation, tempo detection) but avoid "AI magic" that removes user control.

---

## LIVE PERFORMANCE

| Feature | Version | Notes |
|---------|---------|-------|
| DJ Mode | v2.0 | Clip launcher, live performance |
| Clip launcher | v2.0 | Trigger clips live |
| Scene launching | v2.0 | Trigger rows of clips |
| Follow actions | v2.0 | Auto-advance clips |
| MIDI mapping | v1.0 | Map controls to MIDI |
| Key mapping | v1.0 | Map to keyboard |
| Crossfader | v2.0 | DJ-style fader |
| Looper | v2.0 | Live audio looping |

---

## COLLABORATION

| Feature | Version | Notes |
|---------|---------|-------|
| Cloud save | v1.3 | Save projects to cloud |
| Project sharing | v1.3 | Share with others |
| Real-time collaboration | v2.0 | Work together live |
| Version history | v1.0 | See past versions (local) |

---

## ACCESSIBILITY / QoL

| Feature | Version | Notes |
|---------|---------|-------|
| Keyboard shortcuts | v1.0 | Hotkeys |
| Customizable shortcuts | v1.2 | Remap keys |
| Undo/Redo | v1.0 | History |
| Undo history (multiple levels) | v1.0 | Many undo steps |
| Tooltips | v1.0 | Hover help (more added over time) |
| Long-press tooltips (tablet) | v1.0 | Tablet accessibility |
| Built-in tutorial | v1.0 | Interactive onboarding |
| Screen reader support | v1.1 | VoiceOver, NVDA |
| Themes | v1.0 | Light, Dark, Light HC, Dark HC |
| CPU meter | v1.0 | Monitor performance |
| Info panel | No | Use tooltips instead |

---

## Step Sequencer Specification (v1.0)

### Default Behavior
- **Melodic instruments:** Open Piano Roll
- **Drum kits:** Open Step Sequencer

### Step Sequencer Layout

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

### Features
- Click to toggle steps on/off
- Drag to draw multiple steps
- Velocity editing below grid
- Per-row volume/pan
- Pattern length selector
- Swing amount
- Switch to Piano Roll for advanced editing

---

## Mastering Tools (v1.0) - Beginner Friendly

### Philosophy
Make mastering approachable. Show users what to aim for. No "AI auto-master" - give users control with guidance.

### Master Channel Strip

```
+-------------------------------------------------------------------+
| MASTER                                                            |
+-------------------------------------------------------------------+
|                                                                   |
|  +-----------+  +-----------+  +-----------+                      |
|  |    EQ     |  | COMPRESSOR|  |  LIMITER  |                      |
|  |   [Edit]  |  |   [Edit]  |  |   [Edit]  |                      |
|  +-----------+  +-----------+  +-----------+                      |
|                                                                   |
+-------------------------------------------------------------------+
| METERING                                                          |
|                                                                   |
|  Loudness    -12.3 LUFS  [############....]                       |
|  True Peak   -1.2 dB     [##############..] OK                    |
|                                                                   |
|  Target: [Spotify v]                                              |
|                                                                   |
|  +-----------------------------------------------------------+   |
|  | OK Your track is ready for Spotify                        |   |
|  |   Loudness: Good (-14 LUFS target)                        |   |
|  |   Peak: Safe (no clipping)                                |   |
|  +-----------------------------------------------------------+   |
|                                                                   |
+-------------------------------------------------------------------+
```

### Target Presets

| Preset | Target LUFS | True Peak |
|--------|-------------|-----------|
| Spotify | -14 LUFS | -1 dB |
| Apple Music | -16 LUFS | -1 dB |
| YouTube | -14 LUFS | -1 dB |
| SoundCloud | -14 LUFS | -1 dB |
| CD / Club | -9 LUFS | -0.3 dB |
| Podcast | -16 LUFS | -1 dB |

---

## DEFAULT SETTINGS & PREFERENCES

### Undo/Redo
| Setting | Value |
|---------|-------|
| Undo history levels | 100 |
| Undo includes mixer changes | Yes |

### Auto-Save
| Setting | Value |
|---------|-------|
| Auto-save interval | 5 minutes |
| Keep backup versions | Yes (last 10) |
| Backup location | Project folder/.backups |

### Sample Rate & Recording
| Setting | Default |
|---------|---------|
| Default sample rate | 48 kHz |
| Available rates | 44.1, 48, 96 kHz |
| Internal recording format | WAV (32-bit float) |
| Bit depth options | 16, 24-bit export |

### Metronome
| Setting | Default |
|---------|---------|
| Count-in bars | 1 bar |
| Count-in options | 1, 2, 4 bars |
| Click sounds | 3 options (Classic, Modern, Soft) |
| Visual metronome | v1.1 (for accessibility) |

### Piano Roll Defaults
| Setting | Default |
|---------|---------|
| Default note length | Grid length (snap setting) |
| Default velocity | 100 |
| Default snap | 1/16 |
| Scale highlighting | Off (user enables) |

### Clip Colors
| Setting | Behavior |
|---------|----------|
| New clip color | Inherits from track color |
| Manual override | Yes (right-click -> Change Color) |

### Export
| Setting | Default |
|---------|---------|
| Filename pattern | `Project Name.wav` |
| Default format | WAV |
| Default bit depth | 24-bit |
| Default sample rate | Project sample rate |

### Startup Behavior
| Setting | Default |
|---------|---------|
| On launch | Show Start Screen |
| Start screen shows | Recent projects, Templates, Tutorial |

### CPU Display
| Setting | Value |
|---------|-------|
| CPU meter | Percentage only |
| Location | Top bar / Control bar |

### Track Limit
| Setting | Value |
|---------|-------|
| Maximum tracks | 1000 |

---

## START SCREEN (v1.0)

Consistent design across all Boojy Suite apps.

```
+-------------------------------------------------------------------+
|                                                                   |
|                      BOOJY AUDIO                                  |
|                        v1.0.0                                     |
|                                                                   |
+-------------------------------------------------------------------+
|                                                                   |
|  NEW                           RECENT PROJECTS                    |
|  +---------------+            +-----------------------------+     |
|  | [+ Empty      |            | My Song.boojy               |     |
|  |    Project]   |            |    Modified: Today 2:30 PM  |     |
|  +---------------+            +-----------------------------+     |
|                               | Beat Demo.boojy             |     |
|  TEMPLATES                    |    Modified: Yesterday      |     |
|  +---------------+            +-----------------------------+     |
|  | Beat Making   |            | Remix WIP.boojy             |     |
|  | Recording     |            |    Modified: Dec 28         |     |
|  | Full Prod     |            +-----------------------------+     |
|  | + Custom...   |                                                |
|  +---------------+            [Open Other...]                     |
|                                                                   |
+-------------------------------------------------------------------+
|  [Start Tutorial]                            [Preferences]        |
+-------------------------------------------------------------------+
```

---

## BUILT-IN TUTORIAL (v1.0)

### Structure
Two tutorial paths + progress tracking:

| Path | Duration | For Who |
|------|----------|---------|
| **Quick Start** | 3 minutes | Impatient, experienced producers |
| **Full Course** | 5 parts x 3 min = 15 min | Beginners, thorough learners |

### Progress Tracking
- Checkboxes for each section
- Progress bar in Help menu
- "Continue where you left off"
- Completion badges/achievements (optional fun)

---

### Quick Start Tutorial (3 minutes)

**Goal:** Make a basic beat and export it.

| Step | Time | Action |
|------|------|--------|
| 1 | 30s | Add drum track, load kit |
| 2 | 45s | Create 8-bar pattern in step sequencer |
| 3 | 30s | Add synth track, draw simple melody |
| 4 | 30s | Adjust volumes in mixer |
| 5 | 30s | Export as MP3 |
| 6 | 15s | Done! Link to full course |

---

### Full Course (5 Parts)

#### Part 1: Interface & Navigation (3 min)
| Topic | Covered |
|-------|---------|
| Main panels | Arrangement, Mixer, Browser, Editor |
| Transport controls | Play, Stop, Record, Loop |
| Zooming & scrolling | Mouse, keyboard shortcuts |
| Creating tracks | MIDI, Audio, how to add |

**Completion checkbox:** Interface & Navigation

---

#### Part 2: Making Beats (3 min)
| Topic | Covered |
|-------|---------|
| Adding drums | Load Boojy Drums |
| Step sequencer | Toggle steps, velocity |
| Patterns | Create 1-2 bar loops |
| Arrangement | Duplicate patterns, build structure |

**Completion checkbox:** Making Beats

---

#### Part 3: Melody & Harmony (3 min)
| Topic | Covered |
|-------|---------|
| Adding synths | Load Boojy Synth |
| Piano roll basics | Draw notes, select, move |
| Chords | Stack notes for chords |
| Scale highlighting | Stay in key |

**Completion checkbox:** Melody & Harmony

---

#### Part 4: Recording (3 min)
| Topic | Covered |
|-------|---------|
| MIDI recording | Arm track, play keyboard |
| Audio recording | Set input, arm, record |
| Punch in/out | Record specific sections |
| Comping | Choose best takes |

**Completion checkbox:** Recording

---

#### Part 5: Mixing & Exporting (3 min)
| Topic | Covered |
|-------|---------|
| Volume & pan | Balance your mix |
| Adding effects | EQ, reverb, compression |
| Master meters | Check levels, LUFS |
| Exporting | WAV, MP3, stems |

**Completion checkbox:** Mixing & Exporting

---

### Tutorial UI

**First Launch / Help Menu:**
```
+-------------------------------------------------------------------+
| LEARN BOOJY AUDIO                                          [X]   |
+-------------------------------------------------------------------+
|                                                                   |
|  +-----------------------------------------------------------+   |
|  |  QUICK START                                     3 min    |   |
|  |     Make your first beat in 3 minutes                     |   |
|  |                                          [Start ->]       |   |
|  +-----------------------------------------------------------+   |
|                                                                   |
|  --- FULL COURSE -------------------------------------------------|
|  Progress: ####...... 40% (2/5 complete)                          |
|                                                                   |
|  [x] Part 1: Interface & Navigation         3 min  [Review]       |
|  [x] Part 2: Making Beats                   3 min  [Review]       |
|  [ ] Part 3: Melody & Harmony               3 min  [Start ->]     |
|  [ ] Part 4: Recording                      3 min  [Locked]       |
|  [ ] Part 5: Mixing & Exporting             3 min  [Locked]       |
|                                                                   |
|  --- EXTRA TUTORIALS ---------------------------------------------|
|  [ ] Advanced: Automation                   2 min  [Locked]       |
|  [ ] Advanced: Sidechain Compression        2 min  [Locked]       |
|  [ ] Advanced: Arranger Track               2 min  [Locked]       |
|                                                                   |
+-------------------------------------------------------------------+
|  Tip: Press [?] anytime to see tooltips                           |
+-------------------------------------------------------------------+
```

### Progress Storage
- Saved locally (persists between sessions)
- Synced to cloud account (if logged in, future feature)

### Unlocking
**Option A:** Linear (must complete in order)
**Option B:** Open (can do any, but suggested order)

**Recommendation:** Option B (Open) - don't frustrate experienced users who just want one topic.

### Tutorial Start Options (First Launch)
```
+-------------------------------------------------------------------+
|                                                                   |
|                   Welcome to Boojy Audio!                         |
|                                                                   |
+-------------------------------------------------------------------+
|                                                                   |
|  How would you like to get started?                               |
|                                                                   |
|  +-------------+  +-------------+  +-------------+                |
|  |   Quick     |  |   Full      |  |    Skip     |                |
|  |   Start     |  |   Course    |  |   for now   |                |
|  |             |  |             |  |             |                |
|  |  3 minutes  |  |  15 minutes |  |  Jump right |                |
|  |  Make a beat|  |  Learn it all|  |     in     |                |
|  +-------------+  +-------------+  +-------------+                |
|                                                                   |
|         You can access tutorials anytime from Help -> Learn       |
|                                                                   |
+-------------------------------------------------------------------+
```

### Access Points
| Location | Action |
|----------|--------|
| First launch | Tutorial prompt appears |
| Help menu | Help -> Learn Boojy Audio |
| Start screen | [Tutorial] button |
| Keyboard shortcut | `?` or `F1` |

### Future: More Tutorials (v1.1+)
Can add more advanced tutorials over time:
- Synthesis deep dive
- Mixing masterclass
- Genre-specific (trap beats, lo-fi, etc.)
- New feature tutorials (when features added)

---

## MULTIPLE MONITORS (v1.0)

### Default Behavior
- Main Boojy window on primary monitor
- Plugin windows can open on any monitor
- Optional: Pop-out panels to second monitor

### Pop-out Panels
| Panel | Can Pop Out? |
|-------|--------------|
| Mixer | Yes |
| Piano Roll / Editor | Yes |
| Browser | No (stays in main window) |

### Settings
```
Preferences -> Display
  - Plugin windows open on: [Same as main v] / [Second monitor]
  - Allow pop-out panels: [x]
  - Remember panel positions: [x]
```

### Pop-out UI
```
MIXER panel header:
+-------------------------------------------------------------------+
| MIXER                                              [-> Pop Out]   |
```

When popped out:
```
+-------------------------------------------------------------------+
| MIXER                                    [<- Return to Main]      |
```

---

## METERING SYSTEM (v1.0)

### Master Track - Built-in Meters

**Collapsed view (default):**
```
+-----------------+-----------------------------------------------+
|                 |   -12.9 dB  (o)     [||] <- Click to expand   |
|     MASTER      |   [=========*=========]                       |
|                 |                                               |
+-----------------+-----------------------------------------------+
```

**Expanded view (click meters):**
```
+-------------------------------------------------------------------+
| MASTER METER                                         [Collapse]   |
+-------------------------------------------------------------------+
|                                                                   |
|  PEAK        L [##############..]  -2.1 dB                        |
|              R [#############...]  -3.4 dB                        |
|                                                                   |
|  RMS         L [##########......]  -8.2 dB                        |
|              R [#########.......]  -9.1 dB                        |
|                                                                   |
|  LUFS          [############....]  -12.3 LUFS                     |
|                          ^ Target: -14 LUFS                       |
|                                                                   |
|  View: [Peak x] [RMS x] [VU] [LUFS x]                             |
|                                                                   |
|  Target: [Spotify v]                                              |
|  +-----------------------------------------------------------+   |
|  | Warning: Your track is 1.7 dB too loud for Spotify.       |   |
|  |    Consider lowering the master fader.                    |   |
|  +-----------------------------------------------------------+   |
|                                                                   |
+-------------------------------------------------------------------+
```

### Meter Types Available

| Meter | Description | Shown By Default |
|-------|-------------|------------------|
| Peak | Instantaneous max level | Yes |
| RMS | Average level | Yes |
| VU | Weighted average (vintage) | Optional |
| LUFS | Loudness standard | Yes |

### Color Coding

| Level | Color | Meaning |
|-------|-------|---------|
| Safe | Green | Good to go |
| Caution | Yellow | Getting close |
| Over | Red | Too loud / clipping |

### Meter Effect Plugin

Also available as an effect plugin to add to any track:

```
Effects -> Utility -> Meter
```

Same features as Master meter, for checking individual track levels.

---

## CONVERT TO MIDI (v1.2)

Unified feature for Slice to MIDI and Audio to MIDI.

### Location
Built into Boojy Sampler:

```
+-------------------------------------------------------------------+
| BOOJY SAMPLER                                    [v Advanced]     |
+-------------------------------------------------------------------+
| [Sample Waveform with detected transients]                        |
|  ###   ###   ###   ###                                            |
|  |       |       |       |       <- Transient markers             |
|                                                                   |
| Slices: 8 detected          [Sensitivity: *--------]              |
|                                                                   |
| +-----------------------------------------------------------+    |
| | [Convert to MIDI v]                                       |    |
| |  - Rhythmic (slice at transients)                         |    |
| |  - Melodic (detect pitches)                               |    |
| +-----------------------------------------------------------+    |
+-------------------------------------------------------------------+
```

### Modes

| Mode | Best For | Output |
|------|----------|--------|
| **Rhythmic** | Drums, loops, percussive | MIDI triggering sample slices |
| **Melodic** | Bass, vocals, melody | MIDI notes matching detected pitches |

### Smart Detection
Boojy analyzes audio and suggests the best mode:
- Lots of transients, no clear pitch -> Suggest Rhythmic
- Clear pitch content -> Suggest Melodic
- User can override

### Goal: Better Than Ableton
Focus on accuracy for melodic detection:
- Handle vibrato well
- Detect polyphony (multiple notes)
- Clean MIDI output (not too many tiny notes)
- Confidence threshold (skip uncertain notes)

---

## TRACK GROUPS / BUSES (v1.0)

Simplified version of Logic's Track Stacks.

### Creating Groups

```
Select multiple tracks -> Right-click -> "Group Selected Tracks"
  - As Folder (organize only)
  - As Bus (shared processing)
```

### Folder Group
- Just collapse/expand
- No audio routing change
- Pure organization

```
> Drums (folder)
  (collapsed - 4 tracks inside)

v Drums (folder expanded)
  - Kick
  - Snare
  - Hats
  - Toms
```

### Bus Group
- Collapse/expand
- All tracks route to group fader
- Add effects to the group

```
v Drums [Bus] ---------------------------------------------------
  | [EQ] [Compressor]  <- Effects on the bus
  | Vol: [====*====]   <- Controls all drum levels
  - Kick
  - Snare
  - Hats
  - Toms
```

---

## GROOVE SYSTEM

### v1.0 - Simple Swing
```
MIDI Clip Inspector:
  - Quantize: [1/16 v]
  - Swing: [0%--------*--------100%]
```

### v1.1 - Groove Presets
```
MIDI Clip Inspector:
  - Quantize: [1/16 v]
  - Swing: [0%--------*--------100%]
  - Groove: [None v]
            - None
            - Light Swing
            - Heavy Swing
            - MPC 60
            - SP-1200
            - TR-808
            - Live Drums
            - Triplet Feel
```

### Future (v1.2+) - Extract Groove
```
  - Groove: [None v]
            - ...presets...
            - [Extract from clip...]
```

---

## PLUGIN BROWSER STRUCTURE (v1.0)

```
BROWSER (Left Panel)
|
+-- Sounds
|   +-- Synth Presets
|   |   +-- Bass
|   |   +-- Lead
|   |   +-- Pad
|   |   +-- ...
|   +-- Drum Kits
|   +-- One-Shots
|   |   +-- Drums
|   |   +-- FX
|   |   +-- Instruments
|   +-- Favorites
|
+-- Instruments
|   +-- Boojy Synth
|   |   +-- Presets/
|   +-- Boojy Sampler
|   |   +-- Presets/
|   +-- Boojy Drums
|   |   +-- Presets/
|   +-- VST3 / AU
|       +-- Serum
|       |   +-- Presets/ (if exposed)
|       +-- ...
|
+-- Effects
|   +-- EQ
|   |   +-- Presets/
|   +-- Compressor
|   |   +-- Presets/
|   +-- Reverb
|   |   +-- Presets/
|   +-- VST3 / AU
|       +-- ...
|
+-- User
|   +-- My Presets
|   +-- My Samples
|
+-- Search
```

### Plugin Preset Browser (in plugin header)

```
+-------------------------------------------------------------------+
| BOOJY SYNTH    [<] Fat Bass 01 [>]   [Save] [Browse]              |
+-------------------------------------------------------------------+
| ...plugin interface...                                            |
+-------------------------------------------------------------------+
```

**Browse opens preset browser:**
```
+-------------------------------------+
| BOOJY SYNTH PRESETS                 |
+-------------------------------------+
| Factory                             |
|   +-- Bass                          |
|   |   +-- Fat Bass 01               |
|   |   +-- Sub Bass                  |
|   |   +-- ...                       |
|   +-- Lead                          |
|   +-- Pad                           |
+-------------------------------------+
| User                                |
|   +-- My Custom Bass                |
+-------------------------------------+
```

---

## CHORD TRACK (v1.1 - Maybe)

**Status:** Under consideration based on user feedback.

If implemented:
```
+-------------------------------------------------------------------+
| CHORD | Cmaj | Gmaj | Amin | Fmaj | Cmaj | Gmaj | Amin | Fmaj     |
+-------------------------------------------------------------------+
| Bass  |######|######|######|######| (follows chord track)         |
| Piano |######|######|######|######| (follows chord track)         |
| Synth |######|######|######|######| (independent)                 |
+-------------------------------------------------------------------+
```

---

## AUTO-TUNE EFFECT (v1.2)

Combined pitch correction effect.

```
+-------------------------------------------------------------------+
| AUTO-TUNE                                           [Presets v]   |
+-------------------------------------------------------------------+
|                                                                   |
|  Mode: [o Auto] [* Graphical]                                     |
|                                                                   |
|  --- AUTO MODE ---------------------------------------------------|
|  Key: [C Major v]                                                 |
|  Speed: [Slow o--------*--------o Fast]                           |
|         Natural              Robotic                              |
|                                                                   |
|  --- GRAPHICAL MODE ---------------------------------------------|
|  [Opens pitch editor - drag notes to correct]                     |
|                                                                   |
|  Humanize: [0%--------*--------100%]                              |
|  Formant: [Preserve x]                                            |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Feature Count Summary

| Version | New Features |
|---------|--------------|
| **v1.0** | ~85 features (core DAW) |
| **v1.1** | ~15 features (polish, iPad, accessibility) |
| **v1.2** | ~20 features (advanced audio, MIDI effects) |
| **v1.3** | ~10 features (collaboration, notation, video) |
| **v2.0** | ~15 features (DJ Mode, live performance) |

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
