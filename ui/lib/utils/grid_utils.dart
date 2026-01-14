/// Shared utility functions for grid snapping and division calculations.
/// Used by piano roll, timeline, and audio editor for consistent grid behavior.
class GridUtils {
  /// Snap a beat position to the grid using floor (for placing at grid start).
  /// Use this for creating new notes/clips where you want them placed at the
  /// nearest grid line before the click position.
  static double snapToGridFloor(double beat, double gridDivision) {
    return (beat / gridDivision).floor() * gridDivision;
  }

  /// Snap a beat position to the grid using round (for snapping to nearest).
  /// Use this for dragging/moving where you want to snap to the closest grid line.
  static double snapToGridRound(double beat, double gridDivision) {
    return (beat / gridDivision).round() * gridDivision;
  }

  /// Get adaptive grid division based on zoom level (pixels per beat).
  /// Returns a grid division that maintains comfortable visual spacing.
  /// Target: 20-40px per grid cell.
  static double getAdaptiveGridDivision(double pixelsPerBeat) {
    // Grid divisions in beats (smallest to largest)
    const divisions = [
      0.03125, // 1/128
      0.0625, // 1/64
      0.125, // 1/32
      0.25, // 1/16
      0.5, // 1/8
      1.0, // 1/4
      2.0, // 1/2
      4.0, // 1 bar
      8.0, // 2 bars
      16.0, // 4 bars
    ];

    // Find first division where cell width is >= 20px and <= 40px
    for (final div in divisions) {
      final cellWidth = div * pixelsPerBeat;
      if (cellWidth >= 20 && cellWidth <= 40) {
        return div;
      }
    }

    // If no exact match, find first that's >= 20px
    for (final div in divisions) {
      if (div * pixelsPerBeat >= 20) {
        return div;
      }
    }

    // Fallback to largest division
    return divisions.last;
  }

  /// Get grid snap resolution for timeline-style zoom levels.
  /// Uses simpler thresholds optimized for arrangement view.
  static double getTimelineGridResolution(double pixelsPerBeat) {
    if (pixelsPerBeat < 10) return 4.0; // Snap to bars
    if (pixelsPerBeat < 20) return 1.0; // Snap to beats
    if (pixelsPerBeat < 40) return 0.5; // 1/8th notes
    if (pixelsPerBeat < 80) return 0.25; // 1/16th notes
    return 0.125; // 1/32nd notes
  }

  /// Apply triplet modifier to a grid division.
  /// Triplets divide each beat into 3 instead of 4, so multiply by 2/3.
  static double applyTripletModifier(double gridDivision) {
    return gridDivision * 2 / 3;
  }

  /// Convert grid division (beats) to display label.
  static String gridDivisionToLabel(double division, {bool triplet = false}) {
    final suffix = triplet ? 'T' : '';
    if (division >= 16.0) return '4 Bar$suffix';
    if (division >= 8.0) return '2 Bar$suffix';
    if (division >= 4.0) return '1 Bar$suffix';
    if (division >= 2.0) return '1/2$suffix';
    if (division >= 1.0) return '1/4$suffix';
    if (division >= 0.5) return '1/8$suffix';
    if (division >= 0.25) return '1/16$suffix';
    if (division >= 0.125) return '1/32$suffix';
    if (division >= 0.0625) return '1/64$suffix';
    return '1/128$suffix';
  }
}
