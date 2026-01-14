import 'clip_data.dart';
import 'midi_note_data.dart';

/// Units for clip position and duration.
enum PositionUnit {
  /// Position/duration in seconds (audio clips).
  seconds,

  /// Position/duration in beats (MIDI clips).
  beats,
}

/// Base interface for all timeline clip items.
///
/// This sealed class hierarchy provides a unified interface for operations
/// that apply to both MIDI clips and audio clips, reducing code duplication
/// in gesture handlers and selection operations.
sealed class TimelineClipItem {
  /// Unique clip identifier.
  int get clipId;

  /// Track this clip belongs to.
  int get trackId;

  /// Start position (in positionUnit).
  double get startTime;

  /// Duration (in positionUnit).
  double get duration;

  /// Clip display name.
  String get name;

  /// Unit for position/duration values.
  PositionUnit get positionUnit;

  /// Convert position to pixels given zoom level.
  ///
  /// For audio clips: pixelsPerUnit = pixelsPerSecond
  /// For MIDI clips: pixelsPerUnit = pixelsPerBeat
  double toPixels(double pixelsPerUnit);

  /// Calculate width in pixels given zoom level.
  double widthInPixels(double pixelsPerUnit);

  /// Create a copy at a new position.
  TimelineClipItem copyAtPosition(double newStartTime);

  /// Create a copy with new duration.
  TimelineClipItem copyWithDuration(double newDuration);
}

/// Timeline item wrapper for audio clips.
class AudioClipTimelineItem implements TimelineClipItem {
  final ClipData clip;

  const AudioClipTimelineItem(this.clip);

  @override
  int get clipId => clip.clipId;

  @override
  int get trackId => clip.trackId;

  @override
  double get startTime => clip.startTime;

  @override
  double get duration => clip.duration;

  @override
  String get name => clip.fileName;

  @override
  PositionUnit get positionUnit => PositionUnit.seconds;

  @override
  double toPixels(double pixelsPerUnit) => startTime * pixelsPerUnit;

  @override
  double widthInPixels(double pixelsPerUnit) => duration * pixelsPerUnit;

  @override
  TimelineClipItem copyAtPosition(double newStartTime) {
    return AudioClipTimelineItem(clip.copyWith(startTime: newStartTime));
  }

  @override
  TimelineClipItem copyWithDuration(double newDuration) {
    return AudioClipTimelineItem(clip.copyWith(duration: newDuration));
  }

  /// Access the underlying ClipData.
  ClipData get data => clip;
}

/// Timeline item wrapper for MIDI clips.
class MidiClipTimelineItem implements TimelineClipItem {
  final MidiClipData clip;

  const MidiClipTimelineItem(this.clip);

  @override
  int get clipId => clip.clipId;

  @override
  int get trackId => clip.trackId;

  @override
  double get startTime => clip.startTime;

  @override
  double get duration => clip.duration;

  @override
  String get name => clip.name;

  @override
  PositionUnit get positionUnit => PositionUnit.beats;

  @override
  double toPixels(double pixelsPerUnit) => startTime * pixelsPerUnit;

  @override
  double widthInPixels(double pixelsPerUnit) => duration * pixelsPerUnit;

  @override
  TimelineClipItem copyAtPosition(double newStartTime) {
    return MidiClipTimelineItem(clip.copyWith(startTime: newStartTime));
  }

  @override
  TimelineClipItem copyWithDuration(double newDuration) {
    return MidiClipTimelineItem(clip.copyWith(duration: newDuration));
  }

  /// Access the underlying MidiClipData.
  MidiClipData get data => clip;
}

/// Generic drag state for any timeline item.
///
/// This replaces the duplicate MidiClipDragState and AudioClipDragState
/// with a single generic implementation.
class ClipDragState<T extends TimelineClipItem> {
  /// Item being dragged (null if not dragging).
  T? draggingItem;

  /// Start time of item when drag began.
  double dragStartTime = 0.0;

  /// X position when drag began.
  double dragStartX = 0.0;

  /// Current X position during drag.
  double dragCurrentX = 0.0;

  /// True when modifier key held at drag start (copy mode).
  bool isCopyDrag = false;

  /// True when Shift held (bypasses snap).
  bool snapBypassActive = false;

  /// Whether a drag is currently active.
  bool get isDragging => draggingItem != null;

  /// Get the clip ID of the item being dragged.
  int? get draggingClipId => draggingItem?.clipId;

  /// Reset all drag state.
  void reset() {
    draggingItem = null;
    dragStartTime = 0.0;
    dragStartX = 0.0;
    dragCurrentX = 0.0;
    isCopyDrag = false;
    snapBypassActive = false;
  }

  /// Start a drag operation.
  void startDrag({
    required T item,
    required double startX,
    bool copyMode = false,
  }) {
    draggingItem = item;
    dragStartTime = item.startTime;
    dragStartX = startX;
    dragCurrentX = startX;
    isCopyDrag = copyMode;
    snapBypassActive = false;
  }

  /// Update drag position.
  void updateDrag(double currentX, {bool bypassSnap = false}) {
    dragCurrentX = currentX;
    snapBypassActive = bypassSnap;
  }

  /// Calculate new position for the dragged item.
  ///
  /// [pixelsPerUnit] is pixels per beat (MIDI) or pixels per second (audio).
  /// [snapResolution] is the grid resolution for snapping.
  double calculateNewPosition({
    required double pixelsPerUnit,
    required double snapResolution,
    bool applySnap = true,
  }) {
    final deltaUnits = (dragCurrentX - dragStartX) / pixelsPerUnit;
    var newPosition = (dragStartTime + deltaUnits).clamp(0.0, double.infinity);

    if (applySnap && !snapBypassActive) {
      newPosition = (newPosition / snapResolution).round() * snapResolution;
    }

    return newPosition;
  }
}

/// Generic trim state for any timeline item.
class ClipTrimState<T extends TimelineClipItem> {
  /// Item being trimmed (null if not trimming).
  T? trimmingItem;

  /// Whether trimming left edge (vs right edge).
  bool isTrimmingLeftEdge = false;

  /// Item start time at trim begin.
  double startTime = 0.0;

  /// Item duration at trim begin.
  double startDuration = 0.0;

  /// Mouse X at trim begin.
  double startX = 0.0;

  /// Whether a trim is currently active.
  bool get isTrimming => trimmingItem != null;

  /// Get the clip ID of the item being trimmed.
  int? get trimmingClipId => trimmingItem?.clipId;

  /// Reset trim state.
  void reset() {
    trimmingItem = null;
    isTrimmingLeftEdge = false;
    startTime = 0.0;
    startDuration = 0.0;
    startX = 0.0;
  }

  /// Start a trim operation.
  void startTrim({
    required T item,
    required double mouseX,
    required bool leftEdge,
  }) {
    trimmingItem = item;
    isTrimmingLeftEdge = leftEdge;
    startTime = item.startTime;
    startDuration = item.duration;
    startX = mouseX;
  }

  /// Calculate new duration for right edge trim.
  double calculateRightTrimDuration({
    required double currentX,
    required double pixelsPerUnit,
    required double snapResolution,
    double minDuration = 0.01,
    double? maxDuration,
  }) {
    final deltaUnits = (currentX - startX) / pixelsPerUnit;
    var newDuration = startDuration + deltaUnits;

    // Apply constraints
    final max = maxDuration ?? double.infinity;
    newDuration = newDuration.clamp(minDuration, max);

    // Snap to grid
    newDuration = (newDuration / snapResolution).round() * snapResolution;
    return newDuration.clamp(minDuration, max);
  }

  /// Calculate new start time and duration for left edge trim.
  /// Returns a record with (newStartTime, newDuration).
  ({double startTime, double duration}) calculateLeftTrimPosition({
    required double currentX,
    required double pixelsPerUnit,
    required double snapResolution,
    double minDuration = 0.01,
  }) {
    final deltaUnits = (currentX - startX) / pixelsPerUnit;

    // Calculate new values
    var newStartTime = startTime + deltaUnits;
    var newDuration = startDuration - deltaUnits;

    // Snap start time to grid
    newStartTime = (newStartTime / snapResolution).round() * snapResolution;

    // Constrain to valid range
    final maxTrimLeft = startTime + startDuration - minDuration;
    newStartTime = newStartTime.clamp(0.0, maxTrimLeft);

    // Recalculate duration based on snapped start
    newDuration = (startTime + startDuration) - newStartTime;
    newDuration = newDuration.clamp(minDuration, double.infinity);

    return (startTime: newStartTime, duration: newDuration);
  }
}
