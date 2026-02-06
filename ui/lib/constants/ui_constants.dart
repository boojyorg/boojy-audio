/// Shared UI constants for the DAW timeline, piano roll, and mixer.
///
/// Centralises "magic numbers" that appear in multiple widgets so they
/// can be tuned in one place and referenced by name.
class UIConstants {
  UIConstants._(); // prevent instantiation

  // ============================================
  // TIMELINE CONSTANTS
  // ============================================

  /// Height of the unified navigation / ruler bar (pixels).
  static const double navBarHeight = 24.0;

  /// Height of a clip header row inside timeline clips (pixels).
  static const double clipHeaderHeight = 18.0;

  /// Default height for a track's clip area when no override is stored (pixels).
  static const double defaultClipHeight = 100.0;

  /// Default height for the automation lane when no override is stored (pixels).
  static const double defaultAutomationHeight = 60.0;

  /// Default height for the master track (pixels).
  static const double defaultMasterTrackHeight = 60.0;

  /// Padding subtracted from track height for the clip content area (pixels).
  static const double clipContentPadding = 3.0;

  /// Minimum number of bars rendered in the timeline.
  static const int timelineMinBars = 64;

  /// Beats per bar (standard 4/4 time).
  static const int beatsPerBar = 4;

  /// Minimum beats shown in timeline (timelineMinBars * beatsPerBar).
  static const int timelineMinBeats = timelineMinBars * beatsPerBar;

  // ============================================
  // ZOOM CONSTANTS
  // ============================================

  /// Default horizontal zoom level for the timeline (pixels per beat).
  static const double timelineDefaultPixelsPerBeat = 25.0;

  /// Minimum horizontal zoom level for the timeline (pixels per beat).
  static const double timelineMinZoom = 3.0;

  /// Maximum horizontal zoom level for the timeline (pixels per beat).
  static const double timelineMaxZoom = 500.0;

  /// Zoom step factor for button-based zoom in / zoom out.
  static const double zoomStepFactor = 1.1;

  /// Default view width used before the actual layout width is known.
  static const double defaultViewWidth = 800.0;

  // ============================================
  // TRACK HEIGHT CONSTRAINTS
  // ============================================

  /// Minimum track clip height (pixels).
  static const double trackMinHeight = 40.0;

  /// Maximum track clip height (pixels).
  static const double trackMaxHeight = 400.0;

  /// Standard track height at which the mixer strip is at full scale (pixels).
  static const double trackStandardHeight = 76.0;

  // ============================================
  // GESTURE CONSTANTS
  // ============================================

  /// Width of the resize handle at clip edges (pixels).
  static const double clipResizeHandleWidth = 8.0;

  /// Height of the track resize handle bar (pixels).
  static const double trackResizeHandleHeight = 6.0;

  /// Minimum clip duration in beats for drag-to-create (1 bar).
  static const double minDragCreateDurationBeats = 4.0;

  // ============================================
  // PIANO ROLL CONSTANTS
  // ============================================

  /// Width of the piano keys gutter column (pixels).
  static const double pianoKeysWidth = 80.0;

  /// Resize handle height between velocity lane and grid (pixels).
  static const double laneResizeHandleHeight = 6.0;

  // ============================================
  // MIXER STRIP CONSTANTS
  // ============================================

  /// Fixed width of the dB value display container (pixels).
  static const double dbContainerWidth = 56.0;

  /// Font size for the dB value readout (pixels).
  static const double dbFontSize = 10.0;
}
