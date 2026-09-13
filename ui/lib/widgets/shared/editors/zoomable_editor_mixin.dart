import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'anchored_zoom.dart';

/// Mixin providing horizontal zoom functionality for the arrangement.
///
/// Subclasses must provide:
/// - [horizontalScrollController] for scroll management
/// - [pixelsPerBeat] getter/setter for zoom level (the setter must rebuild)
/// - [viewWidth] for calculating zoom limits
/// - [contentWidthAt] so scroll can be corrected in the same frame as zoom
///
/// Features:
/// - Cmd/Ctrl + scroll wheel zoom
/// - Zoom in/out actions with viewport center anchor
/// - Zoom at specific position (for mouse-based zoom)
/// - Ruler drag zoom (see [handleNavBarZoom])
/// - Configurable zoom limits (min/max pixelsPerBeat)
///
/// The maths (drag ratio, anchored offset, same-frame scroll) is shared with
/// the piano roll and audio editor through `anchored_zoom.dart`.
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

  /// Width of the scrollable content at a given zoom, so the scroll
  /// controllers can be told their post-zoom extent before the viewport
  /// lays out (see [applyZoomScroll]).
  double contentWidthAt(double pixelsPerBeat);

  /// Every controller that must move with [horizontalScrollController]
  /// (a mirrored ruler, for instance). Defaults to the main one only.
  List<ScrollController> get zoomLinkedScrollControllers => [
    horizontalScrollController,
  ];

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
  double get minZoom => 3.0;
  double get maxZoom => 500.0;

  // ============================================
  // ZOOM ACTIONS
  // ============================================

  /// Zoom centered on the viewport center.
  void _zoomAtViewportCenter(double factor) {
    final currentScroll = horizontalScrollController.hasClients
        ? horizontalScrollController.offset
        : 0.0;
    final centerX = viewWidth / 2;
    zoomAnchored(
      factor: factor,
      anchorBeat: (currentScroll + centerX) / pixelsPerBeat,
      anchorViewportX: centerX,
    );
  }

  /// Zoom at a specific X position (for mouse-based zoom).
  /// [localX] is the X coordinate relative to the viewport.
  /// [factor] > 1 zooms in, < 1 zooms out.
  void zoomAtPosition(double localX, double factor) {
    final currentScroll = horizontalScrollController.hasClients
        ? horizontalScrollController.offset
        : 0.0;
    zoomAnchored(
      factor: factor,
      anchorBeat: (currentScroll + localX) / pixelsPerBeat,
      anchorViewportX: localX,
    );
  }

  /// Ruler drag from [UnifiedNavBarCallbacks.onZoom]: hold [anchorBeat]
  /// under the pointer at [anchorViewportX] while the zoom changes by
  /// [factor]. A factor of exactly 1 is a pure scroll.
  void handleNavBarZoom(
    double factor,
    double anchorBeat,
    double anchorViewportX,
  ) {
    zoomAnchored(
      factor: factor,
      anchorBeat: anchorBeat,
      anchorViewportX: anchorViewportX,
    );
  }

  /// The one zoom path: multiply the zoom by [factor] (clamped to the
  /// editor's limits) and scroll so [anchorBeat] sits at [anchorViewportX],
  /// both in the same frame.
  void zoomAnchored({
    required double factor,
    required double anchorBeat,
    required double anchorViewportX,
  }) {
    final newPixelsPerBeat = (pixelsPerBeat * factor).clamp(
      calculateMinZoom(),
      calculateMaxZoom(),
    );
    final offset = anchoredScrollOffset(
      anchorBeat: anchorBeat,
      anchorViewportX: anchorViewportX,
      pixelsPerBeat: newPixelsPerBeat,
    );
    if (newPixelsPerBeat == pixelsPerBeat &&
        horizontalScrollController.hasClients &&
        offset == horizontalScrollController.offset) {
      return;
    }
    pixelsPerBeat = newPixelsPerBeat;
    applyZoomScroll(
      controllers: zoomLinkedScrollControllers,
      offset: offset,
      contentWidth: contentWidthAt(newPixelsPerBeat),
    );
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
      final isModifierPressed =
          HardwareKeyboard.instance.isMetaPressed ||
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

  /// Cmd/Ctrl + wheel anywhere in the editor: zoom about the viewport
  /// centre (the pointer position is not known here).
  void handlePointerSignalSimple(PointerSignalEvent event) {
    handlePointerSignal(event);
  }
}
