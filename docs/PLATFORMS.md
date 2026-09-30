# Boojy Audio Platforms

Why the stack is what it is, which platforms ship when, and what each needs. Scheduling lives
in [BACKLOG.md](BACKLOG.md). Revisit the stack question once, at v1.0, with real users. Not
before.

## Release plan

| Milestone | Platforms |
| --- | --- |
| v0.8 | macOS, Windows |
| After v0.8 | Linux, once the engine and UX are at or near 8/10 |
| Beta | macOS, Windows, Linux |
| v1.0 candidates | web, iPad (phone after) |

**The goal is one app that looks and behaves the same on every device**, with every task
reachable by mouse, trackpad, keyboard or touch. The touch-ready rules in
[EDITING.md](EDITING.md#every-input-method) apply to UI work now. No test rigs or infrastructure
are built before a platform is scheduled; each gets its release checklist in
[RELEASING.md](RELEASING.md) when it ships.

## The stack, and why it stays

Flutter UI over a Rust engine, joined by a plain C ABI through raw `dart:ffi`; C++ only for the
VST3 SDK, Swift or C++ only where a platform demands it.

The engine is the asset: Rust with portable dependencies and a C ABI, so it moves to any UI
toolkit unchanged. Changing stack means rewriting the UI (tens of thousands of lines of Dart, 30+
custom painters), months of solo work for a marginal gain. Flutter gives one UI codebase for
every target, a GPU canvas (which is what a timeline is) and hot reload. It costs native feel:
menu bar, text fields, accessibility and IME are Flutter's own, desktop is its least-loved
target, and plugin GUIs need a native view per OS.

| Alternative | Why not |
| --- | --- |
| Swift (SwiftUI / AppKit) | Best macOS feel, but Windows needs a second UI, and a DAW canvas ends up in AppKit and Metal anyway. |
| React Native | Sparse desktop support, no desktop canvas story. |
| **Tauri** (Rust shell, web UI) | The one credible alternative, and the exit if Flutter desktop stalls: same engine, no FFI shim. Costs a WebView per platform and harder plugin windows. |
| JUCE (C++) | Hosting built in, but C++ everywhere, a dated UI toolkit and a GPL-or-commercial licence. |
| Rust-native GUI (Vizia, iced, egui, Slint) | Immature text input, accessibility and polish. |
| Qt / QML | No advantage over Flutter for custom painters. |

Keep the FFI boundary a plain C ABI so the Tauri exit stays real.

## What each platform needs

- **Windows (shipping):** WASAPI shared mode (ASIO deferred: needs the Steinberg SDK), VST3 GUI
  hosting to verify, a native updater (none yet), and more testers.
- **Linux:** a packaging decision (AppImage or Flatpak), a CI job mirroring Windows, and an
  honest README note that Linux plugins are scarce. The cheapest of the three.
- **iPad:** a touch pass over every gesture (small if the touch-ready rules hold), a CoreMIDI
  channel in Swift in place of `midir`, iOS audio-session and sandbox handling, App Store review.
  No VST3 on iPad; AUv3 hosting is a separate, later decision, so the built-in sounds carry it.
- **Web:** the real engine compiled to WebAssembly inside an AudioWorklet, talking to the UI
  through shared memory. The current web target (`ui/lib/audio_engine_web.dart`) is a Dart-side
  fake and will be deleted, not extended. In order:
  1. A pure render path ("fill these 128 frames", no threads or clocks inside); worth doing
     anyway, it improves desktop.
  2. A `dart:js_interop` binding beside the FFI one, over the shared `api/` layer.
  3. A worklet host with a shared ring buffer for playhead and meters (needs cross-origin
     isolation headers on boojy.org).
  4. Projects and recordings in the browser's origin-private filesystem.
  5. Check that `signalsmith-stretch` (C++) builds for WASM; the one unknown.

  Chromium is fine for playback and MIDI, marginal for live monitoring; Safari lacks Web MIDI
  and is visibly worse. Roughly two to four months after step 1.
