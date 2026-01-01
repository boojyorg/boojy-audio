import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';
import '../../models/midi_cc_data.dart';
import '../../models/scale_data.dart';
import '../../models/chord_data.dart';
import '../../services/undo_redo_manager.dart';
import '../piano_roll.dart';

/// Mixin containing all state variables for PianoRoll.
/// This separates state management from UI logic.
mixin PianoRollStateMixin on State<PianoRoll> {
  // ============================================
  // ZOOM AND VIEW STATE
  // ============================================

  /// Horizontal zoom (pixels per beat).
  double pixelsPerBeat = 80.0;

  /// Vertical zoom (height of each piano key) - fixed.
  final double pixelsPerNote = 16.0;

  /// View range constants.
  static const int minMidiNote = 0;
  static const int maxMidiNote = 127;
  static const int defaultViewEndNote = 84; // C6 (default scroll position)

  /// View width for dynamic zoom limits (captured from LayoutBuilder).
  double viewWidth = 800.0;

  // ============================================
  // SCROLL CONTROLLERS
  // ============================================

  final ScrollController horizontalScroll = ScrollController();
  final ScrollController rulerScroll = ScrollController();
  final ScrollController loopBarScroll = ScrollController();
  final ScrollController verticalScroll = ScrollController();

  /// Prevent infinite sync loops between scroll controllers.
  bool isSyncingScroll = false;

  /// Whether currently creating a new loop by dragging.
  bool isCreatingLoop = false;

  // ============================================
  // GRID AND SNAP SETTINGS
  // ============================================

  /// Grid division (1/16th note = 0.25 beats).
  double gridDivision = 0.25;

  /// Whether snap to grid is enabled.
  bool snapEnabled = true;

  // ============================================
  // CLIP STATE
  // ============================================

  /// Current MIDI clip being edited.
  MidiClipData? currentClip;

  // ============================================
  // UI INTERACTION STATE
  // ============================================

  /// Preview note shown during creation.
  MidiNoteData? previewNote;

  /// Drag start position.
  Offset? dragStart;

  /// Current interaction mode.
  InteractionMode currentMode = InteractionMode.draw;

  /// ID of note being resized.
  String? resizingNoteId;

  /// Edge being resized ('left' or 'right').
  String? resizingEdge;

  /// Current cursor style.
  MouseCursor currentCursor = SystemMouseCursors.basic;

  /// Temporary mode override via modifier keys.
  ToolMode? tempModeOverride;

  // ============================================
  // PAINT MODE STATE
  // ============================================

  /// Whether painting mode is active.
  bool isPainting = false;

  /// Beat where painting started.
  double? paintStartBeat;

  /// Note pitch being painted.
  int? paintNote;

  /// Last beat where a note was painted.
  double lastPaintedBeat = 0.0;

  // ============================================
  // NOTE TRACKING STATE
  // ============================================

  /// ID of note just created by click (for immediate drag-to-move).
  String? justCreatedNoteId;

  /// ID of note currently being moved (without selection highlight).
  String? movingNoteId;

  /// Original note positions at drag start for delta calculation.
  Map<String, MidiNoteData> dragStartNotes = {};

  // ============================================
  // ERASER MODE STATE
  // ============================================

  /// Whether eraser mode is active.
  bool isErasing = false;

  /// Set of note IDs already erased in current eraser operation.
  Set<String> erasedNoteIds = {};

  /// Right-click start position for context menu.
  Offset? rightClickStartPosition;

  /// Note under right-click for context menu on release.
  MidiNoteData? rightClickNote;

  // ============================================
  // DUPLICATE MODE STATE
  // ============================================

  /// Whether duplicate mode is active.
  bool isDuplicating = false;

  // ============================================
  // VELOCITY LANE STATE
  // ============================================

  /// Whether velocity lane is expanded.
  bool velocityLaneExpanded = false;

  /// Velocity lane height in pixels.
  static const double velocityLaneHeight = 80.0;

  /// ID of note being velocity-edited.
  String? velocityDragNoteId;

  /// Velocity randomization amount (0-100%).
  double velocityRandomizeAmount = 0.0;

  // ============================================
  // CC AUTOMATION LANE STATE
  // ============================================

  /// Whether CC lane is expanded.
  bool ccLaneExpanded = false;

  /// CC lane height in pixels.
  static const double ccLaneHeight = 80.0;

  /// Current CC lane data.
  MidiCCLane ccLane = MidiCCLane(ccType: MidiCCType.modWheel);

  // ============================================
  // MULTI-SELECT STATE
  // ============================================

  /// Whether box selection is active.
  bool isSelecting = false;

  /// Selection rectangle start.
  Offset? selectionStart;

  /// Selection rectangle end.
  Offset? selectionEnd;

  // ============================================
  // UNDO/REDO STATE
  // ============================================

  /// Snapshot of clip before an action (for undo).
  MidiClipData? snapshotBeforeAction;

  /// Clipboard for copy/paste operations.
  List<MidiNoteData> clipboard = [];

  /// Global undo/redo manager.
  final UndoRedoManager undoRedoManager = UndoRedoManager();

  // ============================================
  // LOOP SETTINGS
  // ============================================

  /// Whether loop is enabled.
  bool loopEnabled = true;

  /// Loop start position in beats.
  double loopStartBeats = 0.0;

  /// Whether loop end is being dragged.
  bool isDraggingLoopEnd = false;

  /// X position when loop drag started.
  double loopDragStartX = 0;

  /// Loop length at drag start.
  double loopLengthAtDragStart = 0;

  /// Loop marker drag mode.
  LoopMarkerDrag? loopMarkerDrag;

  /// Beat position when loop drag started.
  double loopDragStartBeat = 0.0;

  // ============================================
  // ZOOM DRAG STATE (Ableton-style)
  // ============================================

  /// Y position when zoom drag started.
  double zoomDragStartY = 0;

  /// Pixels per beat when zoom drag started.
  double zoomStartPixelsPerBeat = 0;

  /// Beat position to keep under cursor during zoom.
  double zoomAnchorBeat = 0;

  /// Local X position of cursor at drag start.
  double zoomAnchorLocalX = 0;

  // ============================================
  // NOTE CREATION SETTINGS
  // ============================================

  /// Last note duration (default = 1 beat = quarter note).
  double lastNoteDuration = 1.0;

  /// Insert marker position (in beats, separate from playhead).
  double? insertMarkerBeats;

  // ============================================
  // AUDITION SETTINGS
  // ============================================

  /// Whether note audition is enabled.
  bool auditionEnabled = true;

  /// Currently held note for sustained audition.
  int? currentlyHeldNote;

  // ============================================
  // TRANSFORM TOOL VALUES
  // ============================================

  /// Time stretch amount.
  double stretchAmount = 1.0;

  /// Humanize amount.
  double humanizeAmount = 0.0;

  /// Swing amount.
  double swingAmount = 0.0;

  // ============================================
  // SCALE SETTINGS
  // ============================================

  /// Scale root note name.
  String scaleRoot = 'C';

  /// Scale type.
  ScaleType scaleType = ScaleType.major;

  /// Whether scale highlighting is enabled.
  bool scaleHighlightEnabled = false;

  /// Whether scale lock is enabled.
  bool scaleLockEnabled = false;

  /// Whether fold view is enabled.
  bool foldViewEnabled = false;

  /// Whether ghost notes are enabled.
  bool ghostNotesEnabled = false;

  /// Get current scale.
  Scale get currentScale => Scale(root: scaleRoot, type: scaleType);

  // ============================================
  // TIME SIGNATURE
  // ============================================

  /// Beats per bar.
  int beatsPerBar = 4;

  /// Beat unit (denominator).
  int beatUnit = 4;

  // ============================================
  // CHORD PALETTE STATE
  // ============================================

  /// Whether chord palette is visible.
  bool chordPaletteVisible = false;

  /// Current chord configuration.
  ChordConfiguration chordConfig = const ChordConfiguration(
    root: ChordRoot.c,
    type: ChordType.major,
  );

  /// Whether chord preview is enabled.
  bool chordPreviewEnabled = true;

  // ============================================
  // FOCUS
  // ============================================

  /// Focus node for keyboard events.
  final FocusNode focusNode = FocusNode();

  // ============================================
  // COMPUTED PROPERTIES
  // ============================================

  /// Get effective tool mode (temp override or widget prop).
  ToolMode get effectiveToolMode => tempModeOverride ?? widget.toolMode;

  /// True if slice mode is active.
  bool get isSliceModeActive => effectiveToolMode == ToolMode.slice;

  /// Get the loop length (active region in piano roll).
  double getLoopLength() {
    return currentClip?.loopLength ?? 4.0;
  }

  /// Calculate total visible beats (extends beyond loop for scrolling).
  double calculateTotalBeats() {
    final loopLength = getLoopLength();

    if (currentClip == null || currentClip!.notes.isEmpty) {
      return loopLength + 4.0;
    }

    final furthestBeat = currentClip!.notes
        .map((note) => note.startTime + note.duration)
        .reduce((a, b) => a > b ? a : b);

    final maxBeat = furthestBeat > loopLength ? furthestBeat : loopLength;
    final requiredBars = (maxBeat / 4).ceil();
    return (requiredBars + 1) * 4.0;
  }
}

/// Loop marker being dragged in ruler.
enum LoopMarkerDrag {
  start,
  end,
  middle,
}
