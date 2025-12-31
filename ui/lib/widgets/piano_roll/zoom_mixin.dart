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
  /// Clip length + 4 bars should fit in view
  double calculateMinPixelsPerBeat() {
    final clipLength = getLoopLength();
    final totalBeatsToShow = clipLength + 16.0; // clip + 4 bars (16 beats)
    // pixelsPerBeat = viewWidth / totalBeatsToShow
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
  // SNAP TOGGLE
  // ============================================

  /// Toggle grid snap on/off
  void toggleSnap() {
    setState(() {
      snapEnabled = !snapEnabled;
    });
  }
}
