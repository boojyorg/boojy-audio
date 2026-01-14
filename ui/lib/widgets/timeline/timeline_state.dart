import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../models/tool_mode.dart';
import '../../utils/grid_utils.dart';
import '../shared/editors/zoomable_editor_mixin.dart';
import '../timeline_view.dart';

/// Mixin containing all state variables for TimelineView.
/// This separates state management from UI logic.
mixin TimelineViewStateMixin on State<TimelineView> implements ZoomableEditorMixin<TimelineView> {
  // ============================================
  // SCROLL AND ZOOM STATE
  // ============================================

  /// Scroll controller for horizontal scrolling.
  final ScrollController scrollController = ScrollController();

  /// Horizontal zoom (pixels per beat).
  double _pixelsPerBeat = 25.0;

  /// View width for zoom calculations (updated from MediaQuery).
  double _viewWidth = 800.0;

  // ZoomableEditorMixin interface implementation
  @override
  ScrollController get horizontalScrollController => scrollController;

  @override
  double get pixelsPerBeat => _pixelsPerBeat;
  @override
  set pixelsPerBeat(double value) {
    if (value != _pixelsPerBeat) {
      setState(() => _pixelsPerBeat = value);
    }
  }

  @override
  double get viewWidth => _viewWidth;
  set viewWidth(double value) => _viewWidth = value;

  @override
  double get minZoom => 10.0;
  @override
  double get maxZoom => 500.0;

  @override
  double calculateMinZoom() => minZoom;
  @override
  double calculateMaxZoom() => maxZoom;

  // ============================================
  // TRACK STATE
  // ============================================

  /// List of tracks in the timeline.
  List<TimelineTrackData> tracks = [];

  /// Timer for refreshing track data.
  Timer? refreshTimer;

  // ============================================
  // CLIP MANAGEMENT STATE
  // ============================================

  /// List of audio clips.
  final List<ClipData> clips = [];

  /// Preview clip for drag-and-drop.
  PreviewClip? previewClip;

  /// Track ID being hovered during drag.
  int? dragHoveredTrackId;

  /// Whether an audio file is being dragged over empty space.
  bool isAudioFileDraggingOverEmpty = false;

  // ============================================
  // AUDIO CLIP DRAG STATE
  // ============================================

  /// ID of audio clip being dragged.
  int? draggingClipId;

  /// Start time of clip when drag began.
  double dragStartTime = 0.0;

  /// X position when drag began.
  double dragStartX = 0.0;

  /// Current X position during drag.
  double dragCurrentX = 0.0;

  // ============================================
  // MIDI CLIP DRAG STATE
  // ============================================

  /// ID of MIDI clip being dragged.
  int? draggingMidiClipId;

  /// Start time of MIDI clip when drag began.
  double midiDragStartTime = 0.0;

  /// X position when MIDI drag began.
  double midiDragStartX = 0.0;

  /// Current X position during MIDI drag.
  double midiDragCurrentX = 0.0;

  // ============================================
  // SNAP AND COPY STATE
  // ============================================

  /// True when Alt/Option held during drag (bypasses snap).
  bool snapBypassActive = false;

  /// True when Alt held at drag start (copy mode).
  bool isCopyDrag = false;

  // ============================================
  // STAMP COPY STATE
  // ============================================

  /// Duration of source clip for stamp copy.
  double stampCopySourceDuration = 0.0;

  /// Number of stamp copies to create.
  int stampCopyCount = 0;

  // ============================================
  // MIDI CLIP RESIZE STATE
  // ============================================

  /// ID of MIDI clip being resized (right edge).
  int? resizingMidiClipId;

  /// Duration at resize start.
  double resizeStartDuration = 0.0;

  /// X position at resize start.
  double resizeStartX = 0.0;

  // ============================================
  // MIDI CLIP TRIM STATE (LEFT EDGE)
  // ============================================

  /// ID of MIDI clip being trimmed.
  int? trimmingMidiClipId;

  /// Clip start time at trim begin.
  double trimStartTime = 0.0;

  /// Clip duration at trim begin.
  double trimStartDuration = 0.0;

  /// Mouse X at trim begin.
  double trimStartX = 0.0;

  // ============================================
  // AUDIO CLIP SELECTION STATE
  // ============================================

  /// Single selected audio clip (deprecated - use multi-select).
  int? selectedAudioClipId;

  // ============================================
  // MULTI-SELECTION STATE
  // ============================================

  /// Set of selected MIDI clip IDs.
  final Set<int> selectedMidiClipIds = {};

  /// Set of selected audio clip IDs.
  final Set<int> selectedAudioClipIds = {};

  // ============================================
  // BOX SELECTION STATE (Marquee Selection)
  // ============================================

  /// Whether box selection is currently active.
  bool isBoxSelecting = false;

  /// Starting position of box selection (in local coordinates relative to gesture).
  Offset? boxSelectionStart;

  /// Current/end position of box selection (in local coordinates relative to gesture).
  Offset? boxSelectionEnd;

  /// Scroll offset when box selection started (for proper coordinate calculation).
  double boxSelectionScrollOffset = 0.0;

  /// Y offset of the track where selection started (for proper vertical positioning).
  double boxSelectionTrackYOffset = 0.0;

  // ============================================
  // AUDIO CLIP TRIM STATE
  // ============================================

  /// ID of audio clip being trimmed.
  int? trimmingAudioClipId;

  /// Whether trimming left edge.
  bool isTrimmingLeftEdge = false;

  /// Clip start time at audio trim begin.
  double audioTrimStartTime = 0.0;

  /// Clip duration at audio trim begin.
  double audioTrimStartDuration = 0.0;

  /// Clip offset at audio trim begin.
  double audioTrimStartOffset = 0.0;

  /// Mouse X at audio trim begin.
  double audioTrimStartX = 0.0;

  // ============================================
  // DRAG-TO-CREATE STATE
  // ============================================

  /// Whether dragging to create new clip.
  bool isDraggingNewClip = false;

  /// Start position of new clip in beats.
  double newClipStartBeats = 0.0;

  /// End position of new clip in beats.
  double newClipEndBeats = 0.0;

  /// Track ID for new clip (null = create new track).
  int? newClipTrackId;

  // ============================================
  // ERASER MODE STATE
  // ============================================

  /// Whether eraser mode is active.
  bool isErasing = false;

  /// Set of erased audio clip IDs.
  final Set<int> erasedAudioClipIds = {};

  /// Set of erased MIDI clip IDs.
  final Set<int> erasedMidiClipIds = {};

  // ============================================
  // SPLIT PREVIEW STATE
  // ============================================

  /// ID of audio clip showing split preview.
  int? splitPreviewAudioClipId;

  /// ID of MIDI clip showing split preview.
  int? splitPreviewMidiClipId;

  /// Beat position for split preview.
  double splitPreviewBeatPosition = 0.0;

  // ============================================
  // INSERT MARKER STATE
  // ============================================

  /// Insert marker position in beats (null = not visible).
  double? insertMarkerBeats;

  // ============================================
  // TOOL MODE STATE
  // ============================================

  /// Temporary tool mode when holding modifier keys (Alt, Cmd/Ctrl).
  /// When non-null, overrides widget.toolMode temporarily.
  ToolMode? tempToolMode;

  /// Current cursor for the timeline (updated based on tool mode).
  MouseCursor currentCursor = SystemMouseCursors.basic;

  /// Get effective tool mode (temp overrides permanent).
  ToolMode get effectiveToolMode => tempToolMode ?? widget.toolMode;

  /// Update temporary tool mode and cursor based on currently held modifier keys.
  /// Shift = Select, Alt = Eraser, Cmd/Ctrl = Duplicate, otherwise null.
  void updateTempToolMode() {
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    setState(() {
      if (isAltPressed) {
        tempToolMode = ToolMode.eraser; // Alt = Eraser
        currentCursor = SystemMouseCursors.forbidden;
      } else if (isCtrlOrCmd) {
        tempToolMode = ToolMode.duplicate; // Cmd/Ctrl = Duplicate
        currentCursor = SystemMouseCursors.copy;
      } else if (isShiftPressed) {
        tempToolMode = ToolMode.select; // Shift = Select
        currentCursor = SystemMouseCursors.basic;
      } else {
        tempToolMode = null; // Back to selected tool
        // Update cursor based on the actual tool mode
        currentCursor = _getCursorForToolMode(widget.toolMode);
      }
    });
  }

  /// Get cursor for a given tool mode.
  MouseCursor _getCursorForToolMode(ToolMode tool) {
    switch (tool) {
      case ToolMode.draw:
        return SystemMouseCursors.precise;
      case ToolMode.select:
        return SystemMouseCursors.basic;
      case ToolMode.eraser:
        return SystemMouseCursors.forbidden;
      case ToolMode.duplicate:
        return SystemMouseCursors.copy;
      case ToolMode.slice:
        return SystemMouseCursors.verticalText;
    }
  }

  // ============================================
  // CLIPBOARD STATE
  // ============================================

  /// Clipboard for MIDI clip copy/paste.
  MidiClipData? clipboardMidiClip;

  // ============================================
  // COMPUTED PROPERTIES
  // ============================================

  /// Get pixels per second (derived from pixelsPerBeat and tempo).
  double get pixelsPerSecond {
    final beatsPerSecond = widget.tempo / 60.0;
    return pixelsPerBeat * beatsPerSecond;
  }

  /// Get grid snap resolution in beats based on zoom level.
  double getGridSnapResolution() {
    return GridUtils.getTimelineGridResolution(pixelsPerBeat);
  }

  /// Snap a beat value to the current grid resolution.
  double snapToGrid(double beats) {
    final snapResolution = getGridSnapResolution();
    return GridUtils.snapToGridRound(beats, snapResolution);
  }

  /// Calculate timeline position in seconds from X coordinate.
  double calculateTimelinePosition(Offset localPosition) {
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / pixelsPerSecond;
  }

  /// Calculate beat position from X coordinate.
  double calculateBeatPosition(Offset localPosition) {
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final totalX = localPosition.dx + scrollOffset;
    return totalX / pixelsPerBeat;
  }

  // ============================================
  // PUBLIC GETTERS/SETTERS FOR PERSISTENCE
  // ============================================

  /// Get current scroll offset.
  double get scrollOffset => scrollController.offset;

  /// Set scroll offset.
  void setScrollOffset(double offset) {
    if (scrollController.hasClients) {
      scrollController.jumpTo(offset);
    }
  }

  /// Set pixels per beat (zoom level).
  void setPixelsPerBeat(double zoom) {
    pixelsPerBeat = zoom; // Uses setter which calls setState
  }
}
