import 'package:flutter/services.dart' show HardwareKeyboard;
import '../../../models/midi_note_data.dart';
import '../../../models/tool_mode.dart';
import '../../../utils/grid_utils.dart';

/// Configuration for MIDI clip gesture handling.
/// Provides all the callbacks and state needed for gesture handling.
class MidiClipGestureConfig {
  final double pixelsPerBeat;
  final double tempo;
  final ToolMode effectiveToolMode;
  final Function(int clipId, int trackId)? onClipDeleted;
  final Function(MidiClipData clip, double newStartBeats)? onClipCopied;
  final Function(MidiClipData clip)? onClipUpdated;
  final Function(int? clipId, MidiClipData? clip)? onClipSelected;
  final int Function(int dartClipId)? getRustClipId;
  final dynamic audioEngine; // AudioEngine

  const MidiClipGestureConfig({
    required this.pixelsPerBeat,
    required this.tempo,
    required this.effectiveToolMode,
    this.onClipDeleted,
    this.onClipCopied,
    this.onClipUpdated,
    this.onClipSelected,
    this.getRustClipId,
    this.audioEngine,
  });

  /// Get grid snap resolution based on zoom level.
  double getGridSnapResolution() {
    return GridUtils.getTimelineGridResolution(pixelsPerBeat);
  }

  /// Snap a beat value to the grid.
  double snapToGrid(double beats) {
    final snapResolution = getGridSnapResolution();
    return GridUtils.snapToGridRound(beats, snapResolution);
  }
}

/// State tracking for MIDI clip drag operations.
class MidiClipDragState {
  /// ID of clip being dragged (null if not dragging).
  int? draggingClipId;

  /// Start time of clip when drag began.
  double dragStartTime = 0.0;

  /// X position when drag began.
  double dragStartX = 0.0;

  /// Current X position during drag.
  double dragCurrentX = 0.0;

  /// True when Alt/Option held at drag start (copy mode).
  bool isCopyDrag = false;

  /// True when Shift held (bypasses snap).
  bool snapBypassActive = false;

  /// Duration of source clip for stamp copies.
  double stampCopySourceDuration = 0.0;

  /// Number of stamp copies to create.
  int stampCopyCount = 0;

  /// Whether a drag is currently active.
  bool get isDragging => draggingClipId != null;

  /// Reset all drag state.
  void reset() {
    draggingClipId = null;
    dragStartTime = 0.0;
    dragStartX = 0.0;
    dragCurrentX = 0.0;
    isCopyDrag = false;
    snapBypassActive = false;
    stampCopySourceDuration = 0.0;
    stampCopyCount = 0;
  }
}

/// State tracking for MIDI clip resize operations.
class MidiClipResizeState {
  /// ID of clip being resized (null if not resizing).
  int? resizingClipId;

  /// Duration at resize start.
  double startDuration = 0.0;

  /// X position at resize start.
  double startX = 0.0;

  /// Whether a resize is currently active.
  bool get isResizing => resizingClipId != null;

  /// Reset resize state.
  void reset() {
    resizingClipId = null;
    startDuration = 0.0;
    startX = 0.0;
  }
}

/// State tracking for MIDI clip trim operations (left edge).
class MidiClipTrimState {
  /// ID of clip being trimmed (null if not trimming).
  int? trimmingClipId;

  /// Clip start time at trim begin.
  double startTime = 0.0;

  /// Clip duration at trim begin.
  double startDuration = 0.0;

  /// Mouse X at trim begin.
  double startX = 0.0;

  /// Whether a trim is currently active.
  bool get isTrimming => trimmingClipId != null;

  /// Reset trim state.
  void reset() {
    trimmingClipId = null;
    startTime = 0.0;
    startDuration = 0.0;
    startX = 0.0;
  }
}

/// Utility class for MIDI clip gesture calculations.
class MidiClipGestureUtils {
  MidiClipGestureUtils._();

  /// Calculate new position for a clip drag.
  /// Returns the snapped position in beats.
  static double calculateDragPosition({
    required double startTime,
    required double startX,
    required double currentX,
    required double pixelsPerBeat,
    required bool snapEnabled,
    required double snapResolution,
  }) {
    final deltaBeats = (currentX - startX) / pixelsPerBeat;
    var newStartBeats = (startTime + deltaBeats).clamp(0.0, double.infinity);

    if (snapEnabled) {
      newStartBeats = (newStartBeats / snapResolution).round() * snapResolution;
    }

    return newStartBeats;
  }

  /// Calculate stamp copy count for copy drag.
  static int calculateStampCopyCount({
    required double startX,
    required double currentX,
    required double pixelsPerBeat,
    required double sourceDuration,
  }) {
    if (sourceDuration <= 0) return 0;

    final dragDeltaBeats = (currentX - startX) / pixelsPerBeat;
    if (dragDeltaBeats > sourceDuration) {
      return (dragDeltaBeats / sourceDuration).floor();
    }
    return 0;
  }

  /// Calculate new duration for a clip resize.
  static double calculateResizeDuration({
    required double startDuration,
    required double startX,
    required double currentX,
    required double pixelsPerBeat,
    required double snapResolution,
    double minDuration = 1.0,
    double maxDuration = 256.0,
  }) {
    final deltaX = currentX - startX;
    final deltaBeats = deltaX / pixelsPerBeat;
    var newDuration = (startDuration + deltaBeats).clamp(minDuration, maxDuration);

    // Snap to grid
    newDuration = (newDuration / snapResolution).round() * snapResolution;
    return newDuration.clamp(minDuration, maxDuration);
  }

  /// Calculate new start time and duration for left edge trim.
  /// Returns a record with (newStartTime, newDuration).
  static ({double startTime, double duration}) calculateTrimPosition({
    required double originalStartTime,
    required double originalDuration,
    required double startX,
    required double currentX,
    required double pixelsPerBeat,
    required double snapResolution,
    double minDuration = 1.0,
  }) {
    final deltaX = currentX - startX;
    final deltaBeats = deltaX / pixelsPerBeat;

    // Calculate new start time and duration
    var newStartTime = originalStartTime + deltaBeats;
    var newDuration = originalDuration - deltaBeats;

    // Snap start time to grid
    newStartTime = (newStartTime / snapResolution).round() * snapResolution;
    newStartTime = newStartTime.clamp(0.0, originalStartTime + originalDuration - minDuration);

    // Recalculate duration based on snapped start
    newDuration = (originalStartTime + originalDuration) - newStartTime;
    newDuration = newDuration.clamp(minDuration, 256.0);

    return (startTime: newStartTime, duration: newDuration);
  }

  /// Filter and adjust notes after a left edge trim.
  static List<MidiNoteData> adjustNotesForTrim({
    required List<MidiNoteData> notes,
    required double trimOffset,
  }) {
    return notes.where((note) {
      // Keep notes that end after the trim point
      return note.endTime > trimOffset;
    }).map((note) {
      // Adjust note start times relative to new clip start
      final adjustedStart = note.startTime - trimOffset;
      if (adjustedStart < 0) {
        // Note starts before trim point - truncate it
        return note.copyWith(
          startTime: 0,
          duration: note.duration + adjustedStart,
        );
      }
      return note.copyWith(startTime: adjustedStart);
    }).where((note) => note.duration > 0).toList();
  }

  /// Check if shift key is pressed (for snap bypass).
  static bool isShiftPressed() {
    return HardwareKeyboard.instance.isShiftPressed;
  }

  /// Check if Cmd/Ctrl key is pressed (for copy/duplicate).
  static bool isModifierPressed() {
    return HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
  }
}
