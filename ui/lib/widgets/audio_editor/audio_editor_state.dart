import 'package:flutter/material.dart';
import '../../models/clip_data.dart';
import '../../models/audio_clip_edit_data.dart';
import '../../services/undo_redo_manager.dart';
import 'audio_editor.dart';

/// Mixin containing all state variables for AudioEditor.
/// This separates state management from UI logic.
mixin AudioEditorStateMixin on State<AudioEditor> {
  // ============================================
  // ZOOM AND VIEW STATE
  // ============================================

  /// Horizontal zoom (pixels per beat).
  double pixelsPerBeat = 80.0;

  /// View width for dynamic zoom limits (captured from LayoutBuilder).
  double viewWidth = 800.0;

  // ============================================
  // SCROLL CONTROLLERS
  // ============================================

  final ScrollController horizontalScroll = ScrollController();
  final ScrollController rulerScroll = ScrollController();
  final ScrollController loopBarScroll = ScrollController();

  /// Prevent infinite sync loops between scroll controllers.
  bool isSyncingScroll = false;

  /// Whether currently creating a new loop by dragging.
  bool isCreatingLoop = false;

  /// Current hover position in loop bar (in beats), for cursor updates.
  double? loopBarHoverBeat;

  // ============================================
  // CLIP STATE
  // ============================================

  /// Current audio clip being edited.
  ClipData? currentClip;

  /// Current edit parameters for the clip.
  AudioClipEditData editData = const AudioClipEditData();

  // ============================================
  // LOOP SETTINGS
  // ============================================

  /// Whether loop is enabled.
  bool loopEnabled = true;

  /// Loop start position in beats.
  double loopStartBeats = 0.0;

  /// Loop end position in beats.
  double loopEndBeats = 4.0;

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
  // TIME SIGNATURE
  // ============================================

  /// Beats per bar.
  int beatsPerBar = 4;

  /// Beat unit (denominator).
  int beatUnit = 4;

  // ============================================
  // UNDO/REDO STATE
  // ============================================

  /// Snapshot of edit data before an action (for undo).
  AudioClipEditData? snapshotBeforeAction;

  /// Global undo/redo manager.
  final UndoRedoManager undoRedoManager = UndoRedoManager();

  // ============================================
  // FOCUS
  // ============================================

  /// Focus node for keyboard events.
  final FocusNode focusNode = FocusNode();

  // ============================================
  // COMPUTED PROPERTIES
  // ============================================

  /// Get the loop length in beats.
  double getLoopLength() {
    return loopEndBeats - loopStartBeats;
  }

  /// Calculate total visible beats (extends beyond loop for scrolling).
  /// Matches Piano Roll behavior: adds 16 bars buffer beyond content.
  double calculateTotalBeats() {
    final loopLength = getLoopLength();

    if (currentClip == null) {
      // Default: 8 bars when no clip loaded
      return 8 * beatsPerBar.toDouble();
    }

    // Calculate based on clip duration in beats
    final clipDurationBeats = editData.lengthBeats;
    final maxBeat = clipDurationBeats > loopLength ? clipDurationBeats : loopLength;

    // Add 16 bars (64 beats at 4/4) buffer for scrolling, matching Piano Roll
    final scrollBufferBeats = 16 * beatsPerBar.toDouble();
    return maxBeat + scrollBufferBeats;
  }

  // ============================================
  // ZOOM CALCULATIONS
  // ============================================

  /// Calculate max pixelsPerBeat (zoom in limit)
  /// 1 sixteenth note (0.25 beats) should fill the view width
  double calculateMaxPixelsPerBeat() {
    return viewWidth / 0.25;
  }

  /// Calculate min pixelsPerBeat (zoom out limit)
  /// Clip length + 4 bars should fit in view
  double calculateMinPixelsPerBeat() {
    final clipLength = getLoopLength();
    final totalBeatsToShow = clipLength + 16.0; // clip + 4 bars (16 beats)
    return viewWidth / totalBeatsToShow;
  }

  // ============================================
  // ZOOM ACTIONS
  // ============================================

  /// Zoom in by 50% (1.5x multiplier)
  void zoomIn() {
    setState(() {
      final maxZoom = calculateMaxPixelsPerBeat();
      final minZoom = calculateMinPixelsPerBeat();
      pixelsPerBeat = (pixelsPerBeat * 1.5).clamp(minZoom, maxZoom);
    });
  }

  /// Zoom out by 50% (divide by 1.5)
  void zoomOut() {
    setState(() {
      final maxZoom = calculateMaxPixelsPerBeat();
      final minZoom = calculateMinPixelsPerBeat();
      pixelsPerBeat = (pixelsPerBeat / 1.5).clamp(minZoom, maxZoom);
    });
  }

  // ============================================
  // SCROLL SYNCHRONIZATION
  // ============================================

  /// Sync ruler scroll from main grid scroll.
  void syncRulerFromGrid() {
    if (isSyncingScroll) return;
    if (!rulerScroll.hasClients || !horizontalScroll.hasClients) return;

    isSyncingScroll = true;
    final max = rulerScroll.position.maxScrollExtent;
    rulerScroll.jumpTo(horizontalScroll.offset.clamp(0.0, max));
    if (loopBarScroll.hasClients) {
      final loopMax = loopBarScroll.position.maxScrollExtent;
      loopBarScroll.jumpTo(horizontalScroll.offset.clamp(0.0, loopMax));
    }
    isSyncingScroll = false;
  }

  /// Sync grid scroll from ruler scroll.
  void syncGridFromRuler() {
    if (isSyncingScroll) return;
    if (!rulerScroll.hasClients || !horizontalScroll.hasClients) return;

    isSyncingScroll = true;
    final max = horizontalScroll.position.maxScrollExtent;
    horizontalScroll.jumpTo(rulerScroll.offset.clamp(0.0, max));
    if (loopBarScroll.hasClients) {
      final loopMax = loopBarScroll.position.maxScrollExtent;
      loopBarScroll.jumpTo(rulerScroll.offset.clamp(0.0, loopMax));
    }
    isSyncingScroll = false;
  }

  /// Sync grid scroll from loop bar scroll.
  void syncGridFromLoopBar() {
    if (isSyncingScroll) return;
    if (!loopBarScroll.hasClients || !horizontalScroll.hasClients) return;

    isSyncingScroll = true;
    final max = horizontalScroll.position.maxScrollExtent;
    horizontalScroll.jumpTo(loopBarScroll.offset.clamp(0.0, max));
    if (rulerScroll.hasClients) {
      final rulerMax = rulerScroll.position.maxScrollExtent;
      rulerScroll.jumpTo(loopBarScroll.offset.clamp(0.0, rulerMax));
    }
    isSyncingScroll = false;
  }

  // ============================================
  // INITIALIZATION AND CLEANUP
  // ============================================

  /// Initialize scroll listeners.
  void initScrollListeners() {
    horizontalScroll.addListener(syncRulerFromGrid);
    rulerScroll.addListener(syncGridFromRuler);
    loopBarScroll.addListener(syncGridFromLoopBar);
  }

  /// Dispose scroll listeners.
  void disposeScrollListeners() {
    horizontalScroll.removeListener(syncRulerFromGrid);
    rulerScroll.removeListener(syncGridFromRuler);
    loopBarScroll.removeListener(syncGridFromLoopBar);
  }

  /// Initialize state from clip data.
  void initFromClip(ClipData? clip) {
    if (clip == null) return;

    currentClip = clip;
    editData = clip.editData ?? const AudioClipEditData();

    // Get BPM and time signature from edit data
    beatsPerBar = editData.beatsPerBar;
    beatUnit = editData.beatUnit;

    // Calculate clip duration in beats from seconds
    // duration (seconds) * (bpm / 60) = beats
    final clipDurationBeats = clip.duration * (editData.bpm / 60.0);

    // If edit data has default loop end (4.0) but clip is longer, use clip duration
    // Otherwise use the saved loop end from edit data
    final savedLoopEnd = editData.loopEndBeats;
    final useClipDuration = savedLoopEnd == 4.0 && clipDurationBeats > 4.0;

    // Sync loop settings
    loopEnabled = editData.loopEnabled;
    loopStartBeats = editData.loopStartBeats;
    loopEndBeats = useClipDuration ? clipDurationBeats : savedLoopEnd;

    // Also update editData.lengthBeats if using clip duration
    if (useClipDuration) {
      editData = editData.copyWith(
        lengthBeats: clipDurationBeats,
        loopEndBeats: clipDurationBeats,
      );
    }
  }

  /// Update clip when widget changes.
  void updateFromClip(ClipData? clip) {
    if (clip == null || clip.clipId == currentClip?.clipId) return;
    initFromClip(clip);
  }
}

/// Loop marker being dragged in ruler.
enum LoopMarkerDrag {
  start,
  end,
  middle,
}
