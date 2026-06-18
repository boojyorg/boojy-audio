# Boojy Audio - Architecture Documentation

## Overview

Boojy Audio is a cross-platform Digital Audio Workstation (DAW) built with Flutter for the UI and Rust for the audio engine. The architecture follows a clean separation between the high-performance audio processing backend and the reactive, cross-platform UI frontend.

## Directory Structure

```
Boojy Audio/
├── engine/                 # Rust audio engine (FFI)
│   ├── src/               # Rust source code
│   │   ├── api/          # Internal API modules (called by ffi/)
│   │   ├── ffi/          # C-compatible FFI shims (one file per domain)
│   │   ├── audio_graph/  # Renderer, device mgmt, offline processing
│   │   ├── export/       # Offline render to WAV/MP3
│   │   └── bin/          # CLI tool(s)
│   ├── rust-toolchain.toml # Pinned Rust channel (EH-3b)
│   ├── vst3sdk/          # VST3 SDK submodule (deliberately dirty patch)
│   └── lib/              # Prebuilt VST3 host static libs
│
├── ui/                    # Flutter UI application
│   ├── lib/              # Main application source
│   ├── test/             # Unit tests
│   └── [platform dirs]   # macOS, Windows configs
│
└── docs/                  # Project documentation
```

## UI Architecture (Flutter)

### Layer Overview

```
┌─────────────────────────────────────────────────┐
│                   Widgets                        │
│  (TransportBar, TimelineView, PianoRoll, etc.)  │
└─────────────────────┬───────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   Controllers     Services     UI State
   (Playback,      (Project,    (Layout,
    Recording,      Undo/Redo,   Theme)
    Track)          Library)
        │             │             │
        └─────────────┴─────────────┘
                      │
                      ▼
              ┌───────────────┐
              │ Audio Engine  │
              │    (FFI)      │
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │  Rust Engine  │
              └───────────────┘
```

### Folder Structure

| Folder | Purpose |
|--------|---------|
| `lib/models/` | Immutable data classes (ClipData, MidiNoteData, etc.) |
| `lib/screens/` | Main screens (DAWScreen) |
| `lib/controllers/` | User interaction state (PlaybackController, etc.) |
| `lib/services/` | Business logic (ProjectManager, UndoRedoManager, etc.) |
| `lib/state/` | UI layout state |
| `lib/theme/` | Theme system (colors, extensions, provider) |
| `lib/widgets/` | All UI components |
| `lib/utils/` | Utility functions |

### Widget Organization

```
lib/widgets/
├── Compound Widgets (Major Components)
│   ├── transport_bar.dart      # Playback controls, tempo
│   ├── timeline_view.dart      # Arrangement editor (entry point; uses part files)
│   ├── piano_roll.dart         # MIDI editor (entry point)
│   ├── library_panel.dart      # Asset browser
│   └── editor_panel.dart       # Bottom panel container
│
├── Specialized Submodules
│   ├── piano_roll/            # Piano roll components
│   │   ├── operations/       # Note operations (quantize, legato, swing…)
│   │   ├── gestures/         # Input handling
│   │   ├── utilities/        # Coordinate math
│   │   └── *_mixin.dart      # Behavior mixins (velocity lane, CC lane…)
│   │
│   ├── timeline/             # Timeline components
│   │   ├── timeline_gesture_layer.dart  # part of timeline_view — drag/trim/eraser
│   │   ├── timeline_track_list.dart     # part of timeline_view — track rows
│   │   ├── operations/       # Clip operations
│   │   └── utilities/        # Coordinate math
│   │
│   ├── device_chain/         # Device chain view (instruments + effects shell)
│   │   └── effect_data.dart  # Effect parameter model (replaces effect_parameter_panel)
│   │
│   ├── audio_editor/         # Audio clip waveform editor
│   ├── sampler_editor/       # Sampler waveform editor
│   ├── drum_kit_editor/      # Drum kit pad editor
│   ├── mixer/                # Mixer strip components
│   ├── transport_bar/        # Transport bar sub-widgets & models
│   ├── editor/               # Editor panel sub-widgets
│   └── start_screen/         # Start/welcome screen
│
├── shared/                   # Reusable UI components
│   ├── arc_knob.dart         # 270° arc knob (effect parameters)
│   ├── boojy_dropdown.dart   # Unified filled-chip dropdown + showBoojyMenu
│   ├── boojy_tooltip.dart    # Themed tooltip (title, description, shortcut)
│   ├── boojy_switch.dart     # Compact pill toggle
│   ├── circular_toggle_button.dart
│   ├── split_button.dart     # Multi-action button
│   └── panel_header.dart     # Collapsible headers
│
├── painters/                 # CustomPainter classes
│   ├── grid_painter.dart
│   ├── note_painter.dart
│   ├── cc_lane_painter.dart
│   └── time_ruler_painter.dart
│
├── dialogs/                  # Modal dialogs
└── transport_bar/            # Transport bar split-button widgets
```

**Timeline note:** `timeline_gesture_layer.dart` and `timeline_track_list.dart` are `part` files of `timeline_view.dart` — they share private methods within one library. Do not import them directly.

## Key Architectural Patterns

### 1. State Management (Provider + ChangeNotifier)

```dart
// Controllers notify UI of state changes
class PlaybackController extends ChangeNotifier {
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  void play() {
    _isPlaying = true;
    notifyListeners();
  }
}

// Usage in widgets
Consumer<PlaybackController>(
  builder: (context, controller, child) {
    return IconButton(
      icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
      onPressed: controller.isPlaying ? controller.pause : controller.play,
    );
  },
)
```

### 2. Command Pattern (Undo/Redo)

```dart
abstract class Command {
  String get description;
  void execute(AudioEngine engine);
  void undo(AudioEngine engine);
}

class AddMidiNoteCommand extends Command {
  final MidiNoteData note;

  @override
  void execute(AudioEngine engine) => engine.addNote(note);

  @override
  void undo(AudioEngine engine) => engine.removeNote(note.id);
}

// Grouping multiple commands
class CompositeCommand extends Command {
  final List<Command> commands;
  // Executes all, undoes in reverse order
}
```

### 3. Immutable Data Models

```dart
class MidiNoteData {
  final int id;
  final int midiNote;
  final double startBeat;
  final double duration;
  final int velocity;

  const MidiNoteData({...});

  MidiNoteData copyWith({int? velocity, double? duration}) {
    return MidiNoteData(
      id: id,
      midiNote: midiNote,
      startBeat: startBeat,
      duration: duration ?? this.duration,
      velocity: velocity ?? this.velocity,
    );
  }

  Map<String, dynamic> toJson() => {...};
  factory MidiNoteData.fromJson(Map<String, dynamic> json) => ...;
}
```

### 4. Mixin Pattern (Widget Behavior Composition)

```dart
// Base state mixin
mixin PianoRollStateMixin on State<PianoRoll> {
  ClipData? currentClip;
  Set<int> selectedNoteIds = {};
  double pixelsPerBeat = 40.0;
}

// Behavior mixins
mixin AuditionMixin on State<PianoRoll>, PianoRollStateMixin {
  void startAudition(int midiNote, int velocity) {...}
  void stopAudition() {...}
}

mixin ZoomMixin on State<PianoRoll>, PianoRollStateMixin {
  void zoomIn() {...}
  void zoomOut() {...}
}

// Composed widget
class _PianoRollState extends State<PianoRoll>
    with PianoRollStateMixin,
         NoteOperationsMixin,
         AuditionMixin,
         ZoomMixin {
  // Uses methods from all mixins
}
```

### 5. Custom Painters (High-Performance Rendering)

```dart
class GridPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double scrollOffset;

  @override
  void paint(Canvas canvas, Size size) {
    // Efficient grid drawing
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return oldDelegate.pixelsPerBeat != pixelsPerBeat ||
           oldDelegate.scrollOffset != scrollOffset;
  }
}

// Usage
CustomPaint(
  painter: GridPainter(pixelsPerBeat: 40, scrollOffset: offset),
  child: child,
)
```

## Audio Engine Integration (FFI)

```dart
// audio_engine.dart - FFI bindings to Rust
class AudioEngine {
  late final DynamicLibrary _lib;

  // Playback control
  void play() => _enginePlay(_lib);
  void pause() => _enginePause(_lib);
  void seek(double position) => _engineSeek(_lib, position);

  // Track operations
  int createTrack(String name) => _engineCreateTrack(_lib, name.toNativeUtf8());
  void deleteTrack(int trackId) => _engineDeleteTrack(_lib, trackId);

  // MIDI operations
  void sendTrackMidiNoteOn(int trackId, int note, int velocity) {...}
  void sendTrackMidiNoteOff(int trackId, int note, int velocity) {...}
}
```

## Audio Graph & Mixer Routing

The Rust engine mixes every track through the same signal chain in both the
realtime callback (`audio_graph/renderer.rs`) and offline export
(`audio_graph/offline.rs`), so a bounced file matches what you hear:

```
per track:  clips → instrument/synth → track FX chain → fader (volume/pan)
                                                          │
                                                          ├── main mix ──────────┐
                                                          └── post-fader sends ─┐ │
                                                                                ▼ │
return bus: per-return accumulator → return FX chain ───────────────────────┐  │ │
                                                                             ▼  ▼ ▼
                                                                  master FX → output
```

- **Sends are post-fader.** A track's send amount is applied *after* its
  volume/pan, summed into a per-return accumulator each frame; the return's own
  FX chain (e.g. a shared Reverb) then processes that sum into the master mix.
- **Returns are shared by effect type.** The ⚡ FX picker's "shared" path dedups
  by effect type via `api/sends.rs`, so several tracks feed one reverb return
  instead of spawning duplicates.
- **No plugin delay compensation yet.** Return-chain latency is not aligned
  against the dry signal (tracked in FEATURE_TRACKER).

### Track locks are non-reentrant (deadlock hazard)

The engine uses `parking_lot::Mutex`, which does **not** support recursive
locking. `TrackManager::get_track` / `get_master_track` / `remove_track` walk
the track list and `.lock()` each track to compare ids — so calling any of them
**while holding a `Track` lock deadlocks the API thread silently** (no panic, no
log; the UI just freezes). Snapshot what you need (`id`, `fx_chain`,
`sends.iter().map(...)`) into locals and drop the guard before calling back into
`TrackManager`. See the snapshot pattern in `api/sends.rs` (`get_track_sends`,
`find_return_by_effect_type`) and CLAUDE.md.

## Future Improvement Opportunities

### High Priority

1. **Widget Size Reduction**
   - `timeline_view.dart` phase 1 **done** (~1,200 lines main file + ~3,800 in `part` mixins) — phase 2: further splits, `daw_screen.dart` (~4,200 lines)
   - `transport_bar.dart` (48KB) - Split into smaller components
   - Target: No widget file > 50KB

2. **State Management Enhancement**
   - Consider Riverpod for more granular rebuilds
   - Implement selector patterns to reduce unnecessary rebuilds
   - Add state persistence for UI preferences

3. **Testing Coverage**
   - Native-engine golden-path tests — `ui/test/native/` (run as plain `flutter test` over `dart:ffi`; native golden paths incl. send/return save+reload, shared-send dedup, reverb-send tail energy); plus Rust stock-effect output guards in `effects.rs`
   - Add widget tests for critical components
   - Golden tests for visual regression

### Medium Priority

4. **Shared Component Library Expansion**
   - Create `DraggableControlMixin` for knob/slider boilerplate
   - Standardize all context menus through `ContextMenuHelper`
   - Add more reusable animation components

5. **Performance Optimizations**
   - Implement virtualized lists for large clip/note counts
   - Add lazy loading for library assets
   - Optimize painter caching strategies

6. **Code Organization**
   - Timeline phase 2 extraction (remaining mixins; `daw_screen.dart` decomposition)
   - Consolidate duplicate dropdown implementations
   - Standardize error handling patterns

### Lower Priority

7. **Developer Experience**
   - Add code generation for models (freezed/json_serializable)
   - Implement stricter lint rules
   - Add architecture decision records (ADRs)

8. **Accessibility**
   - Add semantic labels throughout
   - Keyboard navigation improvements
   - Screen reader support

9. **Documentation**
   - Add inline documentation for complex algorithms
   - Create widget catalog with examples
   - Document FFI API contracts

## Component Dependencies

```
ThemeProvider
    └── DAWScreen
            ├── TransportBar
            │       └── PlaybackController
            │
            ├── TimelineView
            │       ├── TimelineViewStateMixin
            │       ├── TimelineGestureLayerMixin (part file)
            │       ├── TimelineTrackListMixin (part file)
            │       ├── TimelineSelectionMixin
            │       └── AudioEngine (clips, playback)
            │
            ├── PianoRoll
            │       ├── PianoRollStateMixin
            │       ├── NoteOperationsMixin
            │       ├── AuditionMixin
            │       └── AudioEngine (MIDI)
            │
            ├── LibraryPanel
            │       └── LibraryService
            │
            └── EditorPanel
                    └── [Context-dependent editors]
```

## Project Persistence

Project data is split between the Rust engine and the Flutter UI. All UI-only fields must go through `ProjectPersistence.collect()` in [`ui/lib/services/project_persistence.dart`](../ui/lib/services/project_persistence.dart) so manual save, auto-save, and crash recovery stay in sync.

| Data | Owner | File |
|------|-------|------|
| Tracks, clips, tempo, effects, audio files | Rust engine | `project.json` |
| Panel layout, loop region, track colors, view state | Dart UI | `ui_layout.json` |
| Automation (UI hidden) | Both | engine + `ui_layout.json` |

**Save flow:** `DAWProjectMixin.getCurrentUILayout()` → `ProjectPersistence.collect()` → `ProjectManager.saveProject()` writes `ui_layout.json` alongside the engine's `project.json`.

**Load flow:** `ProjectManager.loadProject()` reads `ui_layout.json` → `DAWProjectMixin.applyUILayout()` restores panel state, loop region, track colors, automation UI data, and optional view state.

## Services Overview

| Service | Responsibility |
|---------|---------------|
| `ProjectManager` | Save/load projects, file I/O |
| `ProjectPersistence` | Canonical checklist of UI fields in `ui_layout.json` |
| `UndoRedoManager` | Command history, undo/redo stack |
| `LibraryService` | Browse presets, samples, instruments |
| `AutoSaveService` | Periodic project auto-save |
| `SnapshotManager` | Project version snapshots |
| `MidiPlaybackManager` | MIDI timing and scheduling |
| `MidiCaptureBuffer` | Retroactive MIDI recording |
| `VST3PluginManager` | VST3 plugin discovery and loading |
| `UserSettings` | User preferences persistence |

## Conclusion

The architecture prioritizes:
- **Separation of concerns** - Clear boundaries between UI, business logic, and audio
- **Reusability** - Shared component library for consistent UI
- **Performance** - CustomPainters and FFI for demanding operations
- **Maintainability** - Mixin pattern for composable widget behavior
- **Testability** - Immutable models and command pattern for predictable state

The codebase is actively being refactored to reduce file sizes and improve modularity.
