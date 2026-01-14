import '../../../services/tool_mode_resolver.dart';
import '../../../utils/grid_utils.dart';

/// State tracking for audio clip drag operations.
class AudioClipDragState {
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
  }
}

/// State tracking for audio clip trim operations.
class AudioClipTrimState {
  /// ID of clip being trimmed (null if not trimming).
  int? trimmingClipId;

  /// Whether trimming left edge (vs right edge).
  bool isTrimmingLeftEdge = false;

  /// Clip start time at trim begin.
  double startTime = 0.0;

  /// Clip duration at trim begin.
  double startDuration = 0.0;

  /// Clip offset at trim begin (for left edge trim).
  double startOffset = 0.0;

  /// Mouse X at trim begin.
  double startX = 0.0;

  /// Whether a trim is currently active.
  bool get isTrimming => trimmingClipId != null;

  /// Reset trim state.
  void reset() {
    trimmingClipId = null;
    isTrimmingLeftEdge = false;
    startTime = 0.0;
    startDuration = 0.0;
    startOffset = 0.0;
    startX = 0.0;
  }
}

/// Utility class for audio clip gesture calculations.
class AudioClipGestureUtils {
  AudioClipGestureUtils._();

  /// Calculate new position for a clip drag.
  /// Returns the snapped position in seconds.
  static double calculateDragPosition({
    required double startTime,
    required double startX,
    required double currentX,
    required double pixelsPerSecond,
    required bool snapEnabled,
    required double pixelsPerBeat,
    required double tempo,
  }) {
    final deltaSeconds = (currentX - startX) / pixelsPerSecond;
    var newStartTime = (startTime + deltaSeconds).clamp(0.0, double.infinity);

    if (snapEnabled) {
      // Snap to beat grid
      final beatsPerSecond = tempo / 60.0;
      final snapResolution = GridUtils.getTimelineGridResolution(pixelsPerBeat);
      final startBeats = newStartTime * beatsPerSecond;
      final snappedBeats = (startBeats / snapResolution).round() * snapResolution;
      newStartTime = snappedBeats / beatsPerSecond;
    }

    return newStartTime;
  }

  /// Calculate new duration for right edge trim.
  static double calculateRightTrimDuration({
    required double startDuration,
    required double startX,
    required double currentX,
    required double pixelsPerSecond,
    required double pixelsPerBeat,
    required double tempo,
    double minDuration = 0.01,
    double? maxDuration,
  }) {
    final deltaSeconds = (currentX - startX) / pixelsPerSecond;
    var newDuration = startDuration + deltaSeconds;

    // Apply max constraint if provided
    if (maxDuration != null) {
      newDuration = newDuration.clamp(minDuration, maxDuration);
    } else {
      newDuration = newDuration.clamp(minDuration, double.infinity);
    }

    // Snap to beat grid
    final beatsPerSecond = tempo / 60.0;
    final snapResolution = GridUtils.getTimelineGridResolution(pixelsPerBeat);
    final durationBeats = newDuration * beatsPerSecond;
    final snappedBeats = (durationBeats / snapResolution).round() * snapResolution;
    newDuration = snappedBeats / beatsPerSecond;

    return newDuration.clamp(minDuration, maxDuration ?? double.infinity);
  }

  /// Calculate new start time, duration, and offset for left edge trim.
  /// Returns a record with (newStartTime, newDuration, newOffset).
  static ({double startTime, double duration, double offset}) calculateLeftTrimPosition({
    required double originalStartTime,
    required double originalDuration,
    required double originalOffset,
    required double startX,
    required double currentX,
    required double pixelsPerSecond,
    required double pixelsPerBeat,
    required double tempo,
    double minDuration = 0.01,
    double? sourceDuration,
  }) {
    final deltaSeconds = (currentX - startX) / pixelsPerSecond;

    // Calculate new values
    var newStartTime = originalStartTime + deltaSeconds;
    var newDuration = originalDuration - deltaSeconds;
    var newOffset = originalOffset + deltaSeconds;

    // Snap start time to beat grid
    final beatsPerSecond = tempo / 60.0;
    final snapResolution = GridUtils.getTimelineGridResolution(pixelsPerBeat);
    final startBeats = newStartTime * beatsPerSecond;
    final snappedBeats = (startBeats / snapResolution).round() * snapResolution;
    newStartTime = snappedBeats / beatsPerSecond;

    // Constrain values
    final maxTrimLeft = originalStartTime + originalDuration - minDuration;
    newStartTime = newStartTime.clamp(0.0, maxTrimLeft);

    // Recalculate duration and offset based on snapped start
    newDuration = (originalStartTime + originalDuration) - newStartTime;
    newOffset = originalOffset + (newStartTime - originalStartTime);

    // Ensure offset doesn't go negative or past source duration
    newOffset = newOffset.clamp(0.0, sourceDuration ?? double.infinity);
    newDuration = newDuration.clamp(minDuration, double.infinity);

    return (startTime: newStartTime, duration: newDuration, offset: newOffset);
  }

  /// Check if shift key is pressed (for snap bypass).
  static bool isShiftPressed() {
    return ModifierKeyState.current().isShiftPressed;
  }

  /// Check if Cmd/Ctrl key is pressed (for copy/duplicate).
  static bool isModifierPressed() {
    return ModifierKeyState.current().isCtrlOrCmd;
  }
}
