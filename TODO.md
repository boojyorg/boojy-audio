# Boojy Audio - Remaining Work

## Project Status Overview

| Aspect | Status | Progress |
|--------|--------|----------|
| Core DAW | Complete | 85% |
| Audio Settings | Partial | 60% |
| ASIO Support | Not Started | 0% |
| Latency Testing | Backend Ready | 50% |
| VST3 Plugins | Complete | 100% |
| Recording | Complete | 100% |
| MIDI Editing | Complete | 100% |
| Mixing/Effects | Complete | 100% |
| Stock Instruments | Not Started | 0% |
| Polish/UX | In Progress | 30% |

---

## High Priority (v1.0 Blockers)

### Audio Settings - Complete Integration

- [ ] **Wire input device switching to audio engine**
  - UI dropdown exists at `app_settings_dialog.dart:608`
  - Rust API `set_audio_input_device()` exists but not called from Flutter
  - Need to add FFI binding in `audio_engine.dart`

- [ ] **Apply buffer size changes to running audio**
  - UI dropdown exists at `app_settings_dialog.dart:670`
  - Rust API `set_buffer_size()` exists in `latency.rs`
  - Buffer size persists in settings but not applied to audio stream

- [ ] **True driver switching in Rust engine**
  - Currently UI-only driver switching
  - No actual ASIO vs WASAPI switching in backend
  - Audio continues using whatever driver was initialized at startup

- [ ] **Hot-swap output device while playing**
  - `setAudioOutputDevice()` works at basic level
  - May need graceful stream restart

### Stock Instruments (M8)

- [ ] Boojy Synth (wavetable, Serum-style)
- [ ] Boojy Sampler (simple/advanced modes)
- [ ] Boojy Drums (pad grid + step sequencer)
- [ ] Preset Player (piano, strings, etc.)
- [ ] Piano (sampled grand)

### Polish & UX (M9)

- [ ] Tooltips on all buttons
- [ ] Built-in tutorial (Quick Start + Full Course)
- [ ] First launch onboarding
- [ ] Track colors (auto-assign from palette)
- [ ] Error handling (toast notifications + banners)

### Beta Testing & Launch (M10)

- [ ] Private beta testing
- [ ] Public beta release
- [ ] Documentation and tutorials

---

## Medium Priority (v1.1+)

### Latency Testing UI

- [ ] Create latency test dialog/panel
- [ ] Show test states (Idle, WaitingForSilence, Playing, Listening, Analyzing, Done, Error)
- [ ] Display measured latency result
- [ ] Error message display for failed tests
- [ ] Instructions for loopback setup

### ASIO Support

- [ ] Enumerate ASIO drivers programmatically on Windows
- [ ] Native ASIO API bindings in Rust (or via C++)
- [ ] ASIO4ALL runtime switching
- [ ] Manufacturer ASIO driver support (Focusrite, UA, PreSonus)

### Editing Features

- [ ] Ghost notes in piano roll (show notes from other clips)
- [ ] Scale/key highlighting
- [ ] Quantize options (1/4, 1/8, 1/16, 1/32)
- [ ] Humanize notes
- [ ] Step sequencer (16-step grid for drums)
- [ ] Audio clip reverse
- [ ] Time stretch/warping
- [ ] Pitch shift
- [ ] Crossfades between clips

### Mixing Features

- [ ] Track grouping/folders
- [ ] Bus/Aux sends UI
- [ ] Track colors
- [ ] RMS metering
- [ ] LUFS metering with platform targets
- [ ] Sidechain routing UI
- [ ] Plugin delay compensation

### Recording Features

- [ ] Loop recording (multiple takes)
- [ ] Comping / take lanes
- [ ] Punch in/out
- [ ] Pre-roll / Post-roll
- [ ] Input monitoring modes

### MIDI Features

- [ ] Chord detection and tools
- [ ] MIDI export
- [ ] MIDI import
- [ ] Groove presets (MPC, SP-1200, TR-808)

---

## Low Priority (v1.2+)

- [ ] Automation curves
- [ ] Tempo automation & tap tempo
- [ ] Time signature changes
- [ ] Swing control
- [ ] Arranger track
- [ ] Project templates
- [ ] Backup versions/version history
- [ ] Collection/favorites system
- [ ] Dark theme & accessibility themes
- [ ] AU support (macOS)
- [ ] VST2 support (legacy)
- [ ] CLAP support

---

## Known TODO Comments in Code

| File | Line | Description |
|------|------|-------------|
| `app_settings_dialog.dart` | 608 | Apply to audio engine when input device switching is implemented |
| `app_settings_dialog.dart` | 670 | Apply buffer size to audio engine |
| `vst3_host.rs` | 771 | Optimize by batching frames |
| `audio_graph.rs` | 1353 | Save VST3 plugin path and state |
| `audio_graph.rs` | 1725 | Get block_size from config (hardcoded to 512) |
| `project.rs` | 90 | Add proper clear methods to AudioGraph |
| `vst3.rs` | 26 | Get block_size from config (hardcoded to 512) |

---

## Key File Locations

| Feature | Location |
|---------|----------|
| Audio Settings UI | `ui/lib/widgets/app_settings_dialog.dart` |
| User Settings Data | `ui/lib/services/user_settings.dart` |
| Latency API | `engine/src/api/latency.rs` |
| Recording API | `engine/src/api/recording.rs` |
| Audio Graph | `engine/src/audio_graph.rs` |
| VST3 Support | `engine/src/vst3_host.rs` + `engine/vst3_host/` |
| FFI Bridge | `engine/src/ffi.rs` |
| Flutter FFI | `ui/lib/audio_engine.dart` |

---

## Completed Features Reference

### Core (M0-M2)
- Audio file loading/playback (WAV)
- Waveform visualization
- Transport controls (play, pause, stop)
- Recording from microphone
- Metronome with count-in
- Time ruler with bars/beats
- Playhead indicator

### MIDI & Piano Roll (M6)
- Piano roll editor (FL Studio-style)
- MIDI note drawing, moving, resizing, deletion
- Velocity lane editing
- Note preview on click/drag
- Virtual piano keyboard (ASDF keys)
- MIDI playback with polyphonic synthesizer
- MIDI clip operations

### Mixing & Effects (M4)
- Track volume faders & pan
- Mute/Solo/Record buttons
- Master track with limiter
- Stereo level meters
- 6 built-in effects (EQ, Compressor, Reverb, Delay, Limiter, Distortion)
- FX Chain view with drag-to-reorder
- Effect bypass toggle

### Save & Export (M5)
- Project save/load (.boojy format)
- Auto-save
- WAV export (16/24/32-bit)
- MP3 export (128/192/320 kbps)
- LUFS normalization
- Stem export
- ID3 metadata

### VST3 Plugins (M7)
- Scan installed plugins (Windows & macOS)
- Load VST3 instruments and effects
- Plugin UI (docked & floating)
- Plugin state save/load with projects
- MIDI note event handling
