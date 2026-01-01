# Boojy Audio - Architecture Documentation

## Overview

Boojy Audio is a cross-platform Digital Audio Workstation (DAW) built with Flutter for the UI and Rust for the audio engine. The architecture follows a clean separation between the high-performance audio processing backend and the reactive, cross-platform UI frontend.

## Directory Structure

```
Boojy Audio/
├── engine/                 # Rust audio engine (FFI)
│   ├── src/               # Rust source code
│   │   ├── api/          # FFI API modules
│   │   ├── export/       # Audio export functionality
│   │   └── *.rs          # Core modules (audio_graph, synth, effects)
│   ├── vst3sdk/          # VST3 SDK submodule
│   └── build_vst3/       # VST3 build artifacts
│
├── ui/                    # Flutter UI application
│   ├── lib/              # Main application source
│   ├── test/             # Unit tests
│   └── [platform dirs]   # iOS, macOS, Windows configs
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
│   ├── timeline_view.dart      # Arrangement editor
│   ├── piano_roll.dart         # MIDI editor
│   ├── library_panel.dart      # Asset browser
│   └── editor_panel.dart       # Bottom panel container
│
├── Specialized Submodules
│   ├── piano_roll/            # Piano roll components
│   │   ├── operations/       # Note operations
│   │   ├── gestures/         # Input handling
│   │   ├── utilities/        # Coordinate math
│   │   └── *_mixin.dart      # Behavior mixins
│   │
│   └── timeline/             # Timeline components
│       ├── operations/       # Clip operations
│       └── utilities/        # Coordinate math
│
├── shared/                   # Reusable UI components
│   ├── mini_knob.dart       # Compact knob control
│   ├── compact_dropdown.dart # Space-efficient dropdown
│   ├── split_button.dart    # Multi-action button
│   └── panel_header.dart    # Collapsible headers
│
├── painters/                 # CustomPainter classes
│   ├── grid_painter.dart
│   ├── note_painter.dart
│   └── time_ruler_painter.dart
│
├── dialogs/                  # Modal dialogs
└── context_menus/            # Right-click menus
```

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

## Future Improvement Opportunities

### High Priority

1. **Widget Size Reduction**
   - `timeline_view.dart` (123KB) - Extract more operations into mixins
   - `transport_bar.dart` (48KB) - Split into smaller components
   - Target: No widget file > 50KB

2. **State Management Enhancement**
   - Consider Riverpod for more granular rebuilds
   - Implement selector patterns to reduce unnecessary rebuilds
   - Add state persistence for UI preferences

3. **Testing Coverage**
   - Add widget tests for critical components
   - Integration tests for audio engine operations
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
   - Complete timeline_view mixin extraction (like piano_roll)
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
            │       ├── ClipOperations
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

## Services Overview

| Service | Responsibility |
|---------|---------------|
| `ProjectManager` | Save/load projects, file I/O |
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
