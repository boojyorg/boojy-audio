# Boojy Audio

A modern, cross-platform DAW (Digital Audio Workstation) designed for **speed, simplicity, and collaboration**.

![Boojy Audio Screenshot](docs/screenshots/screenshot_v0.1.0.png)

## Download

[![Download for macOS](https://img.shields.io/badge/Download-macOS-blue?style=for-the-badge&logo=apple)](https://github.com/tsbujacncl/boojy-audio/releases/latest/download/Boojy-Audio-v0.1.0-mac.dmg)
[![Download for Windows](https://img.shields.io/badge/Download-Windows-blue?style=for-the-badge&logo=windows)](https://github.com/tsbujacncl/boojy-audio/releases/latest/download/Boojy-Audio-v0.1.0-win.exe)

Or visit [boojy.org](https://boojy.org) for more information.

## Overview

Boojy Audio combines professional workflows with beginner-friendly UX. Built with Flutter (UI) and Rust (audio engine), it's designed to work seamlessly across macOS, iPad, and eventually web, Windows, Linux, iOS, and Android.

**Current Status:** Early Alpha (v0.1.0) — See [CHANGELOG.md](CHANGELOG.md) for details.

## Features

### Audio & Recording
- Multi-track audio recording and playback
- Metronome and count-in support
- Configurable audio latency (buffer size)
- WAV file export

### MIDI & Instruments
- Piano roll editor with note preview
- Built-in polyphonic synthesizer (8 voices)
- ADSR envelope and lowpass filter
- MIDI clip editing with bar-snapping

### VST3 Plugin Support
- Plugin scanning and loading
- Plugin UI hosting (docked and floating windows)
- Plugin state persistence with projects

### Mixing
- Built-in effects: EQ, Compressor, Reverb, Delay
- Stereo level meters
- Per-track volume, pan, mute, solo

### User Interface
- 3-panel layout: Library, Timeline, Mixer
- Resizable panels and track heights
- Native macOS menu bar integration
- Keyboard shortcuts

### Project Management
- Project save/load
- Track duplication
- Inline track renaming

## Tech Stack

- **UI:** Flutter (cross-platform)
- **Audio Engine:** Rust (native + WASM-ready)
- **Plugin Support:** VST3 (optional module)

## Architecture

```text
┌─────────────────────────────────────┐
│   UI Layer (Flutter)                │  ← Cross-platform UI
└──────────────┬──────────────────────┘
               │ flutter_rust_bridge
┌──────────────▼──────────────────────┐
│   Audio Engine Core (Rust)          │  ← Platform-agnostic DSP
│   - Audio graph, DSP, automation    │
│   - Built-in FX & instruments       │
└──────────────┬──────────────────────┘
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼─────┐         ┌────▼──────┐
│ Native  │         │  Web      │
│ I/O     │         │  I/O      │
│ (CPAL)  │         │ (WebAudio)│
└─────────┘         └───────────┘
```

## Project Structure

```text
/engine         # Rust audio engine
  /core         # Platform-agnostic DSP & graph
  /dsp          # Built-in effects & instruments
  /host-vst3    # VST3 hosting (optional)
  /io           # I/O backends (native/web)
  /bridge       # FFI glue for Flutter
/ui             # Flutter application
  /lib          # Dart code
    /screens    # Main views
    /widgets    # Reusable components
    /state      # State management
  /assets       # Icons, fonts, samples
/packs          # Starter sample packs
/docs           # Documentation
```

## Setup Instructions

### Prerequisites

- **Rust:** `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Flutter:** [Install Flutter](https://docs.flutter.dev/get-started/install)
- **macOS:** Xcode Command Line Tools
- **Windows:** Visual Studio 2022 with "Desktop development with C++" + CMake

### Windows VST3 Setup

For VST3 plugin support on Windows:

1. **Install Build Tools:**
   - CMake: `winget install Kitware.CMake`
   - Visual Studio 2022 Community with "Desktop development with C++" workload

2. **Build VST3 C++ Libraries:**

   ```powershell
   cd engine/vst3_host
   mkdir build_win
   cd build_win
   cmake -G "Visual Studio 17 2022" -A x64 ..
   cmake --build . --config Release
   cd ../../..
   copy engine/vst3_host/build_win/lib/Release/*.lib engine/lib/
   ```

3. **VST3 Plugin Paths:**
   - Default: `C:\Program Files\Common Files\VST3\`
   - Custom paths can be added via plugin browser in app

### Build & Run

```bash
# Clone the repository
git clone https://github.com/tsbujacncl/boojy-audio.git
cd boojy-audio

# Build Rust engine
cd engine
cargo build --release

# Run Flutter app
cd ../ui
flutter run -d macos    # macOS
flutter run -d windows  # Windows
```

## Keyboard Shortcuts

| Shortcut            | Action                            |
|---------------------|-----------------------------------|
| Space               | Play/Stop                         |
| R                   | Record toggle                     |
| B                   | Toggle Library Panel              |
| M                   | Toggle Mixer Panel                |
| Cmd+K               | Command Palette                   |
| Cmd+S               | Save                              |
| Cmd+Shift+S         | Save to Cloud                     |
| Cmd+Z / Cmd+Shift+Z | Undo/Redo                         |
| Tab                 | Toggle Piano Roll / Step Sequencer|

## Contributing

This project is currently in early development (pre-v1). Contributions will be welcomed after the initial public release.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contact

- **GitHub:** [@tsbujacncl](https://github.com/tsbujacncl)
- **Repository:** [boojy-audio](https://github.com/tsbujacncl/boojy-audio)

---

**Built with Rust and Flutter**
