import 'package:flutter/material.dart';
import '../piano_roll.dart';
import '../shared/editors/anchored_zoom.dart';
import 'piano_roll_state.dart';

/// Mixin containing zoom and snap functionality for PianoRoll.
/// Handles zoom in/out and grid snapping.
mixin ZoomMixin on State<PianoRoll>, PianoRollStateMixin {
  // ============================================
  // ZOOM CALCULATIONS
  // ============================================

  /// Calculate max pixelsPerBeat (zoom in limit)
  /// 1 sixteenth note (0.25 beats) should fill the view width
  double calculateMaxPixelsPerBeat() {
    // 1 sixteenth = 0.25 beats should fill viewWidth
    // pixelsPerBeat = viewWidth / 0.25
    return viewWidth / 0.25;
  }

  /// Calculate min pixelsPerBeat (zoom out limit)
  /// Allow zooming out to see clip + 16 bars (matches scroll buffer)
  double calculateMinPixelsPerBeat() {
    final clipLength = getLoopLength();
    // Match the scroll buffer: 16 bars beyond clip
    final scrollBufferBeats = 16 * beatsPerBar.toDouble();
    final totalBeatsToShow = clipLength + scrollBufferBeats;
    // pixelsPerBeat = viewWidth / totalBeatsToShow
    return viewWidth / totalBeatsToShow;
  }

  // ============================================
  // ZOOM ACTIONS
  // ============================================

  /// Zoom in by 50% (1.5x multiplier), centered on viewport center
  void zoomIn() {
    _zoomAtViewportCenter(1.5);
  }

  /// Zoom out by 50% (divide by 1.5), centered on viewport center
  void zoomOut() {
    _zoomAtViewportCenter(1 / 1.5);
  }

  /// Zoom centered on the viewport center
  void _zoomAtViewportCenter(double factor) {
    final currentScroll = horizontalScroll.hasClients
        ? horizontalScroll.offset
        : 0.0;
    final centerX = viewWidth / 2;
    zoomAnchored(
      factor: factor,
      anchorBeat: (currentScroll + centerX) / pixelsPerBeat,
      anchorViewportX: centerX,
    );
  }

  /// Zoom at a specific X position (for mouse-based zoom)
  /// [localX] is the X coordinate relative to the grid (not including piano keys)
  /// [factor] > 1 zooms in, < 1 zooms out
  void zoomAtPosition(double localX, double factor) {
    final currentScroll = horizontalScroll.hasClients
        ? horizontalScroll.offset
        : 0.0;
    zoomAnchored(
      factor: factor,
      anchorBeat: (currentScroll + localX) / pixelsPerBeat,
      anchorViewportX: localX,
    );
  }

  /// The one zoom path for the piano roll: multiply the zoom by [factor]
  /// (clamped) and scroll the grid and its ruler so [anchorBeat] sits at
  /// [anchorViewportX], in the same frame. Shares its maths with the
  /// arrangement and the audio editor (`anchored_zoom.dart`).
  void zoomAnchored({
    required double factor,
    required double anchorBeat,
    required double anchorViewportX,
  }) {
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(
      calculateMinPixelsPerBeat(),
      calculateMaxPixelsPerBeat(),
    );
    final offset = anchoredScrollOffset(
      anchorBeat: anchorBeat,
      anchorViewportX: anchorViewportX,
      pixelsPerBeat: newPixelsPerBeat,
    );
    if (newPixelsPerBeat == pixelsPerBeat &&
        horizontalScroll.hasClients &&
        offset == horizontalScroll.offset) {
      return;
    }
    setState(() {
      pixelsPerBeat = newPixelsPerBeat;
    });
    final totalBeats = calculateTotalBeats(
      viewportWidth: viewWidth,
      pixelsPerBeat: newPixelsPerBeat,
    );
    applyZoomScroll(
      controllers: [horizontalScroll, navBarScroll],
      offset: offset,
      contentWidth: totalBeats * newPixelsPerBeat,
    );
  }

  // ============================================
  // DRAG ZOOM (middle-mouse drag on the grid)
  // ============================================

  /// Start drag zoom operation
  /// [localX] is the X position relative to the grid where the drag started
  /// [globalY] is the Y position for tracking drag distance
  void startDragZoom(double localX, double globalY) {
    isDragZooming = true;
    dragZoomStartY = globalY;
    dragZoomAnchorX = localX;
    final currentScroll = horizontalScroll.hasClients
        ? horizontalScroll.offset
        : 0.0;
    dragZoomAnchorBeat = (currentScroll + localX) / pixelsPerBeat;
  }

  /// Update drag zoom based on mouse movement
  /// [globalY] is the current Y position
  void updateDragZoom(double globalY) {
    final lastY = dragZoomStartY;
    final anchorX = dragZoomAnchorX;
    final anchorBeat = dragZoomAnchorBeat;
    if (!isDragZooming ||
        lastY == null ||
        anchorX == null ||
        anchorBeat == null) {
      return;
    }
    // Same ratio-per-pixel and direction as the ruler drag (down = in), and
    // the beat grabbed at the start stays under the pointer.
    dragZoomStartY = globalY;
    zoomAnchored(
      factor: rulerDragZoomFactor(globalY - lastY),
      anchorBeat: anchorBeat,
      anchorViewportX: anchorX,
    );
  }

  /// End drag zoom operation
  void endDragZoom() {
    isDragZooming = false;
    dragZoomStartY = null;
    dragZoomAnchorX = null;
    dragZoomAnchorBeat = null;
  }

  // ============================================
  // SNAP TOGGLE
  // ============================================

  /// Toggle grid snap on/off
  void toggleSnap() {
    setState(() {
      snapEnabled = !snapEnabled;
    });
  }
}
