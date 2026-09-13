# Boojy Audio Platforms

Why the stack is what it is, which platforms ship when, and what each one needs. Decided
2026-09-13. Scheduling lives in [BACKLOG.md](BACKLOG.md); how the system works lives in
[ARCHITECTURE.md](ARCHITECTURE.md). Revisit the stack question once, at v1.0, with real users
to inform it. Not before.

## Release plan

| Milestone | Platforms |
| --- | --- |
| Beta | macOS, Windows |
| v1.0 candidates | Linux, web, iPad |

The intent is to ship on all five. Each platform gets its own release checklist in
[RELEASING.md](RELEASING.md) when it ships, not before. No test rigs or infrastructure are built
ahead of a platform being scheduled.

## The stack, and why it stays

Flutter UI over a Rust engine, joined by a plain C ABI through raw `dart:ffi`, with C++ only for
the VST3 SDK and Swift or C++ only where a platform demands it (Sparkle, plugin windows).

The engine is the asset. It is roughly 30k lines of Rust with portable dependencies (cpal,
midir, symphonia, rubato, hound) and a C ABI, so it moves to any UI toolkit unchanged. The UI is
roughly 98k lines of Dart with 33 custom painters. Any stack change is a rewrite of the UI and
nothing else, which is six months or more of solo work for a marginal gain.

What Flutter gives: one UI codebase for every target, a GPU-composited canvas (which is what a
timeline and piano roll are), hot reload for a design-led workflow, and a large enough corpus
that AI-assisted development works well.

What it costs: nothing is native. Menu bar, text fields, scrollbars, accessibility and IME are
Flutter's own. Desktop is Flutter's least-loved target and Google's commitment to it is the
largest external risk. Plugin GUIs need a native platform view per OS. Each engine function
crosses seven or eight files. Binaries are large.

### Alternatives considered

| Stack | Why not |
| --- | --- |
| Swift (SwiftUI or AppKit) | Best macOS feel and AU hosting, but Windows needs an entire second UI. SwiftUI cannot do a DAW canvas; you end up in AppKit and Metal anyway. |
| React Native | Desktop support is sparse and there is no desktop canvas story. Strictly worse than Flutter for a canvas-heavy app. |
| Tauri (Rust shell, web frontend) | The one credible alternative and the exit if Flutter desktop stalls: same engine, no FFI shim, designer-friendly UI. Costs: a WebView per platform, shared-memory meters, harder plugin-window embedding. |
| JUCE (C++) | Industry standard with hosting built in, but C++ everywhere, a dated UI toolkit, GPL-or-commercial licence, and the weakest fit for AI-assisted solo work. |
| Rust-native GUI (Vizia, iced, egui, Slint) | Zero FFI, but immature on text input, accessibility and polish; the audio-focused ones have stalled. |
| Qt with QML | Mature desktop, no advantage over Flutter for custom painters, smaller corpus. |

Keep the FFI boundary a plain C ABI so the Tauri exit stays real.

## Per-platform ceilings

Achievable quality with realistic effort, out of 10. Not the current state.

| Platform | Ceiling | What caps it |
| --- | --- | --- |
| macOS | 9 | Non-native menu bar, accessibility, IME. Everything audio is native. Signing, notarisation and Sparkle are wired. |
| Windows | 8 | WASAPI shared-mode latency without ASIO (ASIO needs the Steinberg SDK; deferred). VST3 GUI hosting to verify. No native updater yet. Fewer testers. |
| Linux | 7 | cpal and Flutter both work. Packaging (AppImage or Flatpak), audio-stack variety, scarce Linux plugin builds, and nobody testing. |
| Web, Chromium | 7 | Round-trip latency is fine for playback and MIDI programming, marginal for live monitoring. Browser shortcut collisions. No plugins. Load time and storage limits. |
| Web, Safari | 5 | No Web MIDI at the time of writing, weaker threading, worse latency; Flutter falls back to the single-threaded renderer. |
| iPad | 6 now, 8 with a redesign | Every gesture needs a touch-first rework (right-click, hover, modifier drags). midir does not build for iOS; VST3 does not exist there and AUv3 is a separate bridge. App Store review and audio-session handling. |

## What web needs

A real web version runs the actual engine, compiled to WebAssembly, inside an AudioWorklet so it
sits on the browser's real-time audio thread. The UI talks to it through shared memory. This is
the pattern shipping browser DAWs use.

**The current web target is not this.** The WASM build opens an AudioContext and a gain node and
never renders the engine into it; `ui/lib/audio_engine_web.dart` fakes transport and clips on
the Dart side. It is a demo, not a foundation, and it will be deleted rather than extended.

Work, in order of size:

1. **Pure render path.** The audio graph must be callable as "here are 128 frames, fill them"
   with no threads, timers or clocks inside. Thread and clock use today is in file loading,
   preview, init and recording timestamps, not the renderer, so this is a cleanup. It improves
   the desktop engine regardless.
2. **Second binding layer.** `dart:ffi` does not exist on web. The `api/` layer is shared; add a
   `dart:js_interop` binding beside the FFI one. The three-layer split in ARCHITECTURE is what
   makes this feasible.
3. **Worklet host and shared memory.** A small JavaScript layer that instantiates the WASM module
   inside the worklet, plus a shared ring buffer for playhead and meter data so the UI never
   blocks audio. The site must be served with cross-origin isolation headers (boojy.org on
   Cloudflare can set them).
4. **Storage.** Projects and recordings go to the browser's origin-private filesystem. Real
   folder access exists on Chromium only; no user sample folders on Safari.
5. **Verify the C++ dependency.** `signalsmith-stretch` compiles C++ through its build script.
   It needs a WASM-capable C++ toolchain or a Rust replacement. This is the one unknown; resolve
   it before scheduling web.

No Flutter change is needed. Use the WASM-based web renderer on Chromium and accept the fallback
on Safari. Expect two to four months of focused work after step 1, for one developer with AI
assistance.

The case for web: beginner-first plus minimal setup is strongest when the setup is a URL, and a
web Boojy is the best demo the desktop app could have. The cost: a second release target that
every engine change must keep alive, and Safari users get a visibly worse product.

## What iPad needs

A touch-first pass over every gesture in the timeline, piano roll and mixer; a CoreMIDI channel
in Swift to replace midir; an AUv3 hosting decision (separate from VST3, and not required for a
first iPad release); iOS audio-session and file-sandbox handling; App Store review. Treat it as a
second product built on the same engine, not a port.

## What Linux needs

A packaging decision (AppImage or Flatpak), a CI job mirroring the Windows one, and an honest
note in the README that plugin availability is thin. Technically the cheapest of the three.
