# Changelog

All notable changes to Boojy Audio will be documented in this file.

## v0.1.0 — 2026-01-16

> Initial public alpha. Early test build for validating the build and release pipeline.

### Features

**Audio Engine**
- Multi-track audio recording and playback
- Built-in effects: EQ, Compressor, Reverb, Delay
- WAV file export
- Configurable audio latency (buffer size)

**MIDI & Instruments**
- Piano roll editor with note preview
- Built-in polyphonic synthesizer (8 voices, sine/saw/square/triangle)
- ADSR envelope and lowpass filter
- MIDI clip editing with bar-snapping

**VST3 Support**
- Plugin scanning and loading
- Plugin UI hosting (docked and floating windows)
- Plugin state persistence with projects

**User Interface**
- 3-panel layout: Library, Timeline, Mixer
- Mixer with stereo level meters
- Resizable panels and track heights
- Native macOS menu bar integration
- Keyboard shortcuts

**Project Management**
- Project save/load
- Track duplication
- Inline track renaming

### Known Issues

- Duplicate button can behave unexpectedly
- Window may not start at correct resolution
- App is not code-signed (macOS Gatekeeper warning)
- Library panel hidden if window is too narrow
- Virtual piano keyboard is disabled
- Built-in effects require refresh before appearing
- Clip names can overflow in arrangement view
- Windows build not yet tested
- Undo/redo can be unreliable

---

[View all releases](https://github.com/tyrbujac/boojy-audio/releases)
