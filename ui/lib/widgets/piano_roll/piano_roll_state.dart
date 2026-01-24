import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';
import '../../models/midi_cc_data.dart';
import '../../models/scale_data.dart';
import '../../models/chord_data.dart';
import '../../models/tool_mode.dart';
import '../../models/track_automation_data.dart';
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
  final ScrollController navBarScroll = ScrollController();
  final ScrollController verticalScroll = ScrollController();

  // Legacy scroll controllers - kept for compatibility during transition
  ScrollController get rulerScroll => navBarScroll;
  ScrollController get loopBarScroll => navBarScroll;

  /// Prevent infinite sync loops between scroll controllers.
  bool isSyncingScroll = false;

  /// Whether currently creating a new loop by dragging.
  bool isCreatingLoop = false;

  /// Current hover position in loop bar (in beats), for cursor updates.
  double? loopBarHoverBeat;

  // ============================================
  // GRID AND SNAP SETTINGS
  // ============================================

  /// Grid division (1/16th note = 0.25 beats).
  /// Used when adaptive grid is disabled.
  double gridDivision = 0.25;

  /// Whether snap to grid is enabled.
  bool snapEnabled = true;

  /// Whether adaptive grid is enabled (auto-adjusts based on zoom).
  bool adaptiveGridEnabled = true;

  /// Whether snap triplet mode is enabled.
  bool snapTripletEnabled = false;

  /// Whether quantize triplet mode is enabled.
  bool quantizeTripletEnabled = false;

  /// Quantize division (0 = use current grid, else 4/8/16/32).
  int quantizeDivision = 0;

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

  /// Note ID that should reduce to single selection on tap-up (if no drag occurred).
  /// Used when clicking on already-selected note to allow multi-drag.
  String? pendingNoteTapSelection;

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
  // DRAG ZOOM STATE (Ableton-style click+drag zoom)
  // ============================================

  /// Whether drag zoom is active.
  bool isDragZooming = false;

  /// Starting Y position for drag zoom.
  double? dragZoomStartY;

  /// Starting X position for drag zoom (anchor point for zoom).
  double? dragZoomAnchorX;

  /// pixelsPerBeat at drag zoom start.
  double? dragZoomStartPPB;

  // ============================================
  // VELOCITY LANE STATE
  // ============================================

  /// Whether velocity lane is expanded.
  bool velocityLaneExpanded = false;

  /// Velocity lane height in pixels (resizable).
  double velocityLaneHeight = 80.0;
  static const double velocityLaneMinHeight = 30.0;
  // Max height is calculated dynamically from available layout space

  /// Whether velocity drag is active.
  bool velocityDragActive = false;

  /// ID of note currently being dragged in velocity lane.
  String? velocityDraggedNoteId;

  /// ID of note currently being hovered in velocity lane.
  String? velocityHoveredNoteId;

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
  // CLIP AUTOMATION LANE STATE
  // ============================================

  /// Whether clip automation lane is expanded.
  bool clipAutomationLaneExpanded = false;

  /// Clip automation lane height in pixels (resizable).
  double clipAutomationLaneHeight = 80.0;
  static const double clipAutomationLaneMinHeight = 30.0;

  /// Currently active automation parameter for the clip automation lane.
  AutomationParameter activeClipAutomationParameter = AutomationParameter.volume;

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
  // FOLD VIEW HELPERS
  // ============================================

  /// Get list of MIDI pitches that have notes (sorted descending for display).
  /// Returns all pitches (0-127) if fold is off or no notes exist.
  List<int> get foldedPitches {
    if (!foldViewEnabled || currentClip == null || currentClip!.notes.isEmpty) {
      // Return full range when fold off or empty clip
      return List.generate(
        maxMidiNote - minMidiNote + 1,
        (i) => maxMidiNote - i,
      );
    }

    // Collect unique pitches from notes
    final pitches = currentClip!.notes.map((n) => n.note).toSet().toList();
    pitches.sort((a, b) => b.compareTo(a)); // Sort descending (high notes at top)
    return pitches;
  }

  /// Get the number of visible rows (for canvas height calculation).
  int get visibleRowCount => foldedPitches.length;

  /// Convert a folded row index to MIDI pitch.
  /// Row 0 is the highest pitch shown.
  int rowIndexToMidiNote(int rowIndex) {
    final pitches = foldedPitches;
    if (rowIndex < 0 || rowIndex >= pitches.length) {
      return maxMidiNote - rowIndex; // Fallback to standard mapping
    }
    return pitches[rowIndex];
  }

  /// Convert a MIDI pitch to folded row index.
  /// Returns -1 if pitch is not visible in fold mode.
  int midiNoteToRowIndex(int midiNote) {
    final pitches = foldedPitches;
    final index = pitches.indexOf(midiNote);
    if (index >= 0) return index;
    // If not found in fold mode, return closest row
    if (!foldViewEnabled) {
      return maxMidiNote - midiNote;
    }
    return -1; // Not visible in fold mode
  }

  /// Calculate Y coordinate for a MIDI note (fold-aware).
  double calculateNoteY(int midiNote) {
    if (!foldViewEnabled) {
      return (maxMidiNote - midiNote) * pixelsPerNote;
    }
    final rowIndex = midiNoteToRowIndex(midiNote);
    if (rowIndex < 0) return -pixelsPerNote; // Off-screen if not in fold
    return rowIndex * pixelsPerNote;
  }

  /// Get MIDI note at Y coordinate (fold-aware).
  int getNoteAtY(double y) {
    final rowIndex = (y / pixelsPerNote).floor();
    return rowIndexToMidiNote(rowIndex);
  }

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

  /// Calculate total visible beats.
  /// Extends to fill viewport width + scroll buffer, or furthest note, whichever is greater.
  double calculateTotalBeats({double? viewportWidth, double? pixelsPerBeat}) {
    final loopLength = getLoopLength();

    // Calculate minimum beats needed to fill viewport + scroll buffer
    // Add 16 bars (64 beats in 4/4) beyond viewport for scrolling room
    const scrollBufferBars = 16;
    final scrollBufferBeats = scrollBufferBars * beatsPerBar.toDouble();

    double viewportBeats = loopLength + scrollBufferBeats;
    if (viewportWidth != null && pixelsPerBeat != null && pixelsPerBeat > 0) {
      viewportBeats = (viewportWidth / pixelsPerBeat) + scrollBufferBeats;
    }

    // Also consider furthest note if any exist (plus buffer for drawing new notes)
    double furthestBeat = loopLength;
    if (currentClip != null && currentClip!.notes.isNotEmpty) {
      furthestBeat = currentClip!.notes
          .map((note) => note.startTime + note.duration)
          .reduce((a, b) => a > b ? a : b);
    }
    // Add buffer beyond furthest note for drawing new notes
    furthestBeat += scrollBufferBeats;

    // Take the maximum: viewport + buffer, furthest note + buffer, or loop length + buffer
    final maxBeat = [viewportBeats, furthestBeat, loopLength + scrollBufferBeats]
        .reduce((a, b) => a > b ? a : b);

    // Round up to next bar boundary
    final requiredBars = (maxBeat / beatsPerBar).ceil();
    return requiredBars * beatsPerBar.toDouble();
  }
}

/// Loop marker being dragged in ruler.
enum LoopMarkerDrag {
  start,
  end,
  middle,
}
