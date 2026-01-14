import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/services.dart' show HardwareKeyboard;

/// Mixin providing horizontal zoom functionality for editors (Piano Roll, Timeline).
///
/// Subclasses must provide:
/// - [horizontalScrollController] for scroll management
/// - [pixelsPerBeat] getter/setter for zoom level
/// - [viewWidth] for calculating zoom limits
///
/// Features:
/// - Cmd/Ctrl + scroll wheel zoom
/// - Zoom in/out actions with viewport center anchor
/// - Zoom at specific position (for mouse-based zoom)
/// - Ableton-style drag zoom (click and drag up/down)
/// - Configurable zoom limits (min/max pixelsPerBeat)
///
/// Usage:
/// ```dart
/// class _MyEditorState extends State<MyEditor> with ZoomableEditorMixin {
///   @override
///   ScrollController get horizontalScrollController => _scrollController;
///
///   @override
///   double get pixelsPerBeat => _pixelsPerBeat;
///   @override
///   set pixelsPerBeat(double value) => setState(() => _pixelsPerBeat = value);
///
///   @override
///   double get viewWidth => _viewWidth;
///
///   @override
///   double calculateMinZoom() => viewWidth / totalBeatsToShow;
///   @override
///   double calculateMaxZoom() => viewWidth / 0.25; // 1 sixteenth fills view
///
///   // In build:
///   Listener(
///     onPointerSignal: handlePointerSignal,
///     child: ...
///   )
/// }
/// ```
mixin ZoomableEditorMixin<T extends StatefulWidget> on State<T> {
  // ============================================
  // ABSTRACT PROPERTIES (must be overridden)
  // ============================================

  /// Scroll controller for horizontal scrolling.
  ScrollController get horizontalScrollController;

  /// Current zoom level (pixels per beat).
  double get pixelsPerBeat;
  set pixelsPerBeat(double value);

  /// View width for calculating zoom limits.
  double get viewWidth;

  // ============================================
  // ZOOM LIMITS (override to customize)
  // ============================================

  /// Calculate minimum pixelsPerBeat (max zoom out).
  /// Default: allow zooming to see 200 beats.
  double calculateMinZoom() => viewWidth / 200.0;

  /// Calculate maximum pixelsPerBeat (max zoom in).
  /// Default: 1 sixteenth note (0.25 beats) fills view width.
  double calculateMaxZoom() => viewWidth / 0.25;

  /// Default zoom limits (for simpler editors).
  double get minZoom => 10.0;
  double get maxZoom => 500.0;

  // ============================================
  // DRAG ZOOM STATE
  // ============================================

  /// Whether drag zoom is currently active.
  bool _isDragZooming = false;
  bool get isDragZooming => _isDragZooming;

  /// Starting Y position for drag zoom.
  double? _dragZoomStartY;

  /// Starting X position (anchor point for zoom).
  double? _dragZoomAnchorX;

  /// pixelsPerBeat at drag zoom start.
  double? _dragZoomStartPPB;

  // ============================================
  // ZOOM ACTIONS
  // ============================================

  /// Zoom in by 50% (1.5x multiplier), centered on viewport center.
  void zoomIn() {
    _zoomAtViewportCenter(1.5);
  }

  /// Zoom out by 50% (divide by 1.5), centered on viewport center.
  void zoomOut() {
    _zoomAtViewportCenter(1 / 1.5);
  }

  /// Zoom centered on the viewport center.
  void _zoomAtViewportCenter(double factor) {
    final maxZ = calculateMaxZoom();
    final minZ = calculateMinZoom();

    // Get current scroll position and viewport center
    final currentScroll = horizontalScrollController.offset;
    final viewportCenter = currentScroll + (viewWidth / 2);

    // Calculate the beat at viewport center
    final centerBeat = viewportCenter / pixelsPerBeat;

    // Apply zoom
    final oldPixelsPerBeat = pixelsPerBeat;
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(minZ, maxZ);

    if (newPixelsPerBeat == oldPixelsPerBeat) return;

    pixelsPerBeat = newPixelsPerBeat;

    // Adjust scroll to keep the same beat at viewport center
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!horizontalScrollController.hasClients) return;
      final newCenterX = centerBeat * newPixelsPerBeat;
      final newScroll = (newCenterX - (viewWidth / 2)).clamp(
        0.0,
        horizontalScrollController.position.maxScrollExtent,
      );
      horizontalScrollController.jumpTo(newScroll);
    });
  }

  /// Zoom at a specific X position (for mouse-based zoom).
  /// [localX] is the X coordinate relative to the scrollable content.
  /// [factor] > 1 zooms in, < 1 zooms out.
  void zoomAtPosition(double localX, double factor) {
    final maxZ = calculateMaxZoom();
    final minZ = calculateMinZoom();

    // Get current scroll position
    final currentScroll = horizontalScrollController.offset;

    // Calculate the beat at the mouse position
    final mouseX = currentScroll + localX;
    final mouseBeat = mouseX / pixelsPerBeat;

    // Apply zoom
    final oldPixelsPerBeat = pixelsPerBeat;
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(minZ, maxZ);

    if (newPixelsPerBeat == oldPixelsPerBeat) return;

    pixelsPerBeat = newPixelsPerBeat;

    // Adjust scroll to keep the same beat under the mouse
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!horizontalScrollController.hasClients) return;
      final newMouseX = mouseBeat * newPixelsPerBeat;
      final newScroll = (newMouseX - localX).clamp(
        0.0,
        horizontalScrollController.position.maxScrollExtent,
      );
      horizontalScrollController.jumpTo(newScroll);
    });
  }

  // ============================================
  // SCROLL WHEEL ZOOM
  // ============================================

  /// Handle pointer signal for Cmd/Ctrl + scroll wheel zoom.
  /// Call this from Listener.onPointerSignal in your build method.
  ///
  /// [localX] is the X coordinate where the scroll occurred (for anchor point).
  /// If null, zooms at viewport center.
  void handlePointerSignal(PointerSignalEvent event, {double? localX}) {
    if (event is PointerScrollEvent) {
      // Check for Cmd (Mac) or Ctrl (Windows/Linux) modifier
      final isModifierPressed = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;

      if (isModifierPressed) {
        final scrollDelta = event.scrollDelta.dy;
        final factor = scrollDelta < 0 ? 1.1 : (1 / 1.1);

        if (localX != null) {
          zoomAtPosition(localX, factor);
        } else {
          _zoomAtViewportCenter(factor);
        }
      }
    }
  }

  /// Simplified zoom handler that uses fixed clamp values.
  /// Useful for editors that don't need dynamic zoom limits.
  void handlePointerSignalSimple(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isModifierPressed = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;

      if (isModifierPressed) {
        final scrollDelta = event.scrollDelta.dy;
        final oldValue = pixelsPerBeat;
        final newValue = scrollDelta < 0
            ? (pixelsPerBeat * 1.1).clamp(minZoom, maxZoom)
            : (pixelsPerBeat / 1.1).clamp(minZoom, maxZoom);
        // Only rebuild if value actually changed
        if (newValue != oldValue) {
          pixelsPerBeat = newValue;
        }
      }
    }
  }

  // ============================================
  // DRAG ZOOM (Ableton-style click+drag)
  // ============================================

  /// Start drag zoom operation.
  /// [localX] is the X position relative to scrollable content where the drag started.
  /// [globalY] is the Y position for tracking drag distance.
  void startDragZoom(double localX, double globalY) {
    _isDragZooming = true;
    _dragZoomStartY = globalY;
    _dragZoomAnchorX = localX;
    _dragZoomStartPPB = pixelsPerBeat;
  }

  /// Update drag zoom based on mouse movement.
  /// [globalY] is the current Y position.
  void updateDragZoom(double globalY) {
    if (!_isDragZooming ||
        _dragZoomStartY == null ||
        _dragZoomStartPPB == null ||
        _dragZoomAnchorX == null) {
      return;
    }

    final maxZ = calculateMaxZoom();
    final minZ = calculateMinZoom();

    // Calculate zoom factor based on vertical drag distance
    // Drag up = zoom in, drag down = zoom out
    final deltaY = _dragZoomStartY! - globalY;
    // Sensitivity: 200 pixels of drag = 2x zoom change
    final zoomFactor = 1.0 + (deltaY / 200.0);

    // Calculate new pixelsPerBeat
    final newPixelsPerBeat = (_dragZoomStartPPB! * zoomFactor).clamp(minZ, maxZ);

    if (newPixelsPerBeat == pixelsPerBeat) return;

    // Get current scroll position
    final currentScroll = horizontalScrollController.offset;

    // Calculate the beat at the anchor point
    final anchorX = currentScroll + _dragZoomAnchorX!;
    final anchorBeat = anchorX / pixelsPerBeat;

    pixelsPerBeat = newPixelsPerBeat;

    // Adjust scroll to keep the same beat under the anchor point
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!horizontalScrollController.hasClients) return;
      final newAnchorX = anchorBeat * newPixelsPerBeat;
      final newScroll = (newAnchorX - _dragZoomAnchorX!).clamp(
        0.0,
        horizontalScrollController.position.maxScrollExtent,
      );
      horizontalScrollController.jumpTo(newScroll);
    });
  }

  /// End drag zoom operation.
  void endDragZoom() {
    _isDragZooming = false;
    _dragZoomStartY = null;
    _dragZoomAnchorX = null;
    _dragZoomStartPPB = null;
  }
}
