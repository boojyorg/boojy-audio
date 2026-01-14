import '../../../utils/grid_utils.dart';

/// Utility class for timeline coordinate calculations.
/// Converts between beat positions, time positions, and pixel coordinates.
class TimelineCoordinates {
  final double pixelsPerBeat;
  final double tempo;

  const TimelineCoordinates({
    required this.pixelsPerBeat,
    required this.tempo,
  });

  /// Get pixels per second (derived from pixelsPerBeat and tempo).
  /// Used for time-based positioning (audio clips, playhead).
  double get pixelsPerSecond {
    final beatsPerSecond = tempo / 60.0;
    return pixelsPerBeat * beatsPerSecond;
  }

  /// Calculate timeline position in seconds from X coordinate.
  double calculateTimelinePosition(double x, double scrollOffset) {
    final totalX = x + scrollOffset;
    return totalX / pixelsPerSecond;
  }

  /// Calculate beat position from X coordinate.
  double calculateBeatPosition(double x, double scrollOffset) {
    final totalX = x + scrollOffset;
    return totalX / pixelsPerBeat;
  }

  /// Calculate X coordinate from beat position.
  double calculateXFromBeat(double beat, double scrollOffset) {
    return (beat * pixelsPerBeat) - scrollOffset;
  }

  /// Calculate X coordinate from time in seconds.
  double calculateXFromTime(double seconds, double scrollOffset) {
    return (seconds * pixelsPerSecond) - scrollOffset;
  }

  /// Get grid snap resolution in beats based on zoom level.
  /// Matches TimelineGridPainter._getGridDivision for consistent snapping.
  double getGridSnapResolution() {
    return GridUtils.getTimelineGridResolution(pixelsPerBeat);
  }

  /// Snap a beat value to the current grid resolution.
  double snapToGrid(double beats) {
    final snapResolution = getGridSnapResolution();
    return GridUtils.snapToGridRound(beats, snapResolution);
  }

  /// Snap a beat value to bar boundaries.
  double snapToBar(double beats) {
    return (beats / 4.0).floor() * 4.0;
  }

  /// Convert beats to seconds.
  double beatsToSeconds(double beats) {
    return beats * 60.0 / tempo;
  }

  /// Convert seconds to beats.
  double secondsToBeats(double seconds) {
    return seconds * tempo / 60.0;
  }

  /// Create a copy with updated values.
  TimelineCoordinates copyWith({
    double? pixelsPerBeat,
    double? tempo,
  }) {
    return TimelineCoordinates(
      pixelsPerBeat: pixelsPerBeat ?? this.pixelsPerBeat,
      tempo: tempo ?? this.tempo,
    );
  }
}

/// Utility class for track height calculations.
class TrackHeightUtils {
  /// Default track height in pixels.
  static const double defaultTrackHeight = 60.0;

  /// Minimum track height in pixels.
  static const double minTrackHeight = 40.0;

  /// Maximum track height in pixels.
  static const double maxTrackHeight = 200.0;

  /// Get the height for a specific track.
  static double getTrackHeight(Map<int, double> trackHeights, int trackId) {
    return trackHeights[trackId] ?? defaultTrackHeight;
  }

  /// Calculate total height of all tracks.
  static double calculateTotalHeight(List<int> trackIds, Map<int, double> trackHeights) {
    double total = 0.0;
    for (final trackId in trackIds) {
      total += getTrackHeight(trackHeights, trackId);
    }
    return total;
  }

  /// Calculate Y offset for a specific track.
  static double calculateTrackYOffset(List<int> trackIds, int targetTrackId, Map<int, double> trackHeights) {
    double offset = 0.0;
    for (final trackId in trackIds) {
      if (trackId == targetTrackId) break;
      offset += getTrackHeight(trackHeights, trackId);
    }
    return offset;
  }
}
