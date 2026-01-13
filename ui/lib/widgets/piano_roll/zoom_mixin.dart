import 'package:flutter/material.dart';
import '../piano_roll.dart';
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
    final maxZoom = calculateMaxPixelsPerBeat();
    final minZoom = calculateMinPixelsPerBeat();

    // Get current scroll position and viewport center
    final currentScroll = horizontalScroll.offset;
    final viewportCenter = currentScroll + (viewWidth / 2);

    // Calculate the beat at viewport center
    final centerBeat = viewportCenter / pixelsPerBeat;

    // Apply zoom
    final oldPixelsPerBeat = pixelsPerBeat;
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(minZoom, maxZoom);

    if (newPixelsPerBeat == oldPixelsPerBeat) return;

    setState(() {
      pixelsPerBeat = newPixelsPerBeat;
    });

    // Adjust scroll to keep the same beat at viewport center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newCenterX = centerBeat * newPixelsPerBeat;
      final newScroll = (newCenterX - (viewWidth / 2)).clamp(
        0.0,
        horizontalScroll.position.maxScrollExtent,
      );
      horizontalScroll.jumpTo(newScroll);
    });
  }

  /// Zoom at a specific X position (for mouse-based zoom)
  /// [localX] is the X coordinate relative to the grid (not including piano keys)
  /// [factor] > 1 zooms in, < 1 zooms out
  void zoomAtPosition(double localX, double factor) {
    final maxZoom = calculateMaxPixelsPerBeat();
    final minZoom = calculateMinPixelsPerBeat();

    // Get current scroll position
    final currentScroll = horizontalScroll.offset;

    // Calculate the beat at the mouse position
    final mouseX = currentScroll + localX;
    final mouseBeat = mouseX / pixelsPerBeat;

    // Apply zoom
    final oldPixelsPerBeat = pixelsPerBeat;
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(minZoom, maxZoom);

    if (newPixelsPerBeat == oldPixelsPerBeat) return;

    setState(() {
      pixelsPerBeat = newPixelsPerBeat;
    });

    // Adjust scroll to keep the same beat under the mouse
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newMouseX = mouseBeat * newPixelsPerBeat;
      final newScroll = (newMouseX - localX).clamp(
        0.0,
        horizontalScroll.position.maxScrollExtent,
      );
      horizontalScroll.jumpTo(newScroll);
    });
  }

  // ============================================
  // DRAG ZOOM (Ableton-style click+drag)
  // ============================================

  /// Start drag zoom operation
  /// [localX] is the X position relative to the grid where the drag started
  /// [globalY] is the Y position for tracking drag distance
  void startDragZoom(double localX, double globalY) {
    isDragZooming = true;
    dragZoomStartY = globalY;
    dragZoomAnchorX = localX;
    dragZoomStartPPB = pixelsPerBeat;
  }

  /// Update drag zoom based on mouse movement
  /// [globalY] is the current Y position
  void updateDragZoom(double globalY) {
    if (!isDragZooming || dragZoomStartY == null || dragZoomStartPPB == null || dragZoomAnchorX == null) {
      return;
    }

    final maxZoom = calculateMaxPixelsPerBeat();
    final minZoom = calculateMinPixelsPerBeat();

    // Calculate zoom factor based on vertical drag distance
    // Drag up = zoom in, drag down = zoom out
    final deltaY = dragZoomStartY! - globalY;
    // Sensitivity: 200 pixels of drag = 2x zoom change
    final zoomFactor = 1.0 + (deltaY / 200.0);

    // Calculate new pixelsPerBeat
    final newPixelsPerBeat = (dragZoomStartPPB! * zoomFactor).clamp(minZoom, maxZoom);

    if (newPixelsPerBeat == pixelsPerBeat) return;

    // Get current scroll position
    final currentScroll = horizontalScroll.offset;

    // Calculate the beat at the anchor point
    final anchorX = currentScroll + dragZoomAnchorX!;
    final anchorBeat = anchorX / pixelsPerBeat;

    setState(() {
      pixelsPerBeat = newPixelsPerBeat;
    });

    // Adjust scroll to keep the same beat under the anchor point
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final newAnchorX = anchorBeat * newPixelsPerBeat;
      final newScroll = (newAnchorX - dragZoomAnchorX!).clamp(
        0.0,
        horizontalScroll.position.maxScrollExtent,
      );
      horizontalScroll.jumpTo(newScroll);
    });
  }

  /// End drag zoom operation
  void endDragZoom() {
    isDragZooming = false;
    dragZoomStartY = null;
    dragZoomAnchorX = null;
    dragZoomStartPPB = null;
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
