import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../painters/unified_nav_bar_painter.dart';

/// Configuration for UnifiedNavBar behavior and state.
class UnifiedNavBarConfig {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final double? insertMarkerPosition;
  final double? playheadPosition; // in beats (null = not shown)

  const UnifiedNavBarConfig({
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.insertMarkerPosition,
    this.playheadPosition,
  });
}

/// Callbacks for UnifiedNavBar interactions.
class UnifiedNavBarCallbacks {
  /// Called when user drags horizontally to scroll timeline.
  /// [delta] is the amount to scroll (negative = scroll left).
  final void Function(double delta)? onHorizontalScroll;

  /// Called when user drags vertically to zoom.
  /// [factor] is the zoom multiplier (> 1 = zoom in).
  /// [anchorBeat] is the beat position to anchor zoom to.
  final void Function(double factor, double anchorBeat)? onZoom;

  /// Called when user clicks to set playhead position.
  final void Function(double beat)? onPlayheadSet;

  /// Called when playhead is dragged.
  final void Function(double beat)? onPlayheadDrag;

  /// Called when loop region is changed (via edge drag).
  final void Function(double start, double end)? onLoopRegionChanged;

  /// Called when loop is toggled on/off.
  final void Function({required bool enabled})? onLoopToggled;

  const UnifiedNavBarCallbacks({
    this.onHorizontalScroll,
    this.onZoom,
    this.onPlayheadSet,
    this.onPlayheadDrag,
    this.onLoopRegionChanged,
    this.onLoopToggled,
  });
}

/// Drag mode for tracking what the user is dragging.
enum _DragMode {
  none,
  loopStart,
  loopEnd,
  playhead,
  navigation, // scroll/zoom
}

/// Unified navigation bar that combines loop region and time ruler.
/// Single row (~24px) with consistent spatial interactions:
/// - Drag horizontally = scroll timeline
/// - Drag vertically = zoom timeline
/// - Click = set playhead
/// - Scroll wheel = scroll timeline
/// - Drag loop edges = resize loop
class UnifiedNavBar extends StatefulWidget {
  final UnifiedNavBarConfig config;
  final UnifiedNavBarCallbacks callbacks;
  final ScrollController scrollController;
  final double height;

  const UnifiedNavBar({
    super.key,
    required this.config,
    required this.callbacks,
    required this.scrollController,
    this.height = 24.0,
  });

  @override
  State<UnifiedNavBar> createState() => _UnifiedNavBarState();
}

class _UnifiedNavBarState extends State<UnifiedNavBar> {
  // Hit zone size for loop edges (in pixels)
  static const double _edgeHitZone = 10.0;

  // Drag state
  _DragMode _dragMode = _DragMode.none;
  double? _dragStartX;
  double? _dragStartY;
  double? _dragStartPixelsPerBeat;

  // Hover state for cursor and edge highlighting
  double? _hoverBeat;
  bool _isHoveringLoopEdge = false;
  bool _isHoveringPlayhead = false;

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.config.totalBeats * widget.config.pixelsPerBeat;

    return SizedBox(
      height: widget.height,
      width: totalWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTapUp,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Listener(
          onPointerSignal: _handlePointerSignal,
          child: MouseRegion(
            cursor: _getCurrentCursor(),
            onHover: _handleHover,
            onExit: (_) => setState(() {
              _hoverBeat = null;
              _isHoveringLoopEdge = false;
              _isHoveringPlayhead = false;
            }),
            child: CustomPaint(
              size: Size(totalWidth, widget.height),
              painter: UnifiedNavBarPainter(
                pixelsPerBeat: widget.config.pixelsPerBeat,
                totalBeats: widget.config.totalBeats,
                loopEnabled: widget.config.loopEnabled,
                loopStart: widget.config.loopStart,
                loopEnd: widget.config.loopEnd,
                insertMarkerPosition: widget.config.insertMarkerPosition,
                playheadPosition: widget.config.playheadPosition,
                hoverBeat: _isHoveringLoopEdge ? _hoverBeat : null,
                isHoveringPlayhead: _isHoveringPlayhead,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // COORDINATE HELPERS
  // ============================================

  double _beatAtX(double x) {
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    return (x + scrollOffset) / widget.config.pixelsPerBeat;
  }

  double _xAtBeat(double beat) {
    return beat * widget.config.pixelsPerBeat;
  }

  bool _isNearLoopStart(double beat) {
    if (!widget.config.loopEnabled) return false;
    final loopStartX = _xAtBeat(widget.config.loopStart);
    final beatX = _xAtBeat(beat);
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    return (beatX - loopStartX + scrollOffset).abs() < _edgeHitZone;
  }

  bool _isNearLoopEnd(double beat) {
    if (!widget.config.loopEnabled) return false;
    final loopEndX = _xAtBeat(widget.config.loopEnd);
    final beatX = _xAtBeat(beat);
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    return (beatX - loopEndX + scrollOffset).abs() < _edgeHitZone;
  }

  bool _isNearPlayhead(double beat) {
    if (widget.config.playheadPosition == null) return false;
    final playheadX = _xAtBeat(widget.config.playheadPosition!);
    final beatX = _xAtBeat(beat);
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    return (beatX - playheadX + scrollOffset).abs() < _edgeHitZone;
  }

  // ============================================
  // CURSOR
  // ============================================

  MouseCursor _getCurrentCursor() {
    if (_dragMode != _DragMode.none) {
      if (_dragMode == _DragMode.loopStart || _dragMode == _DragMode.loopEnd) {
        return SystemMouseCursors.resizeLeftRight;
      }
      if (_dragMode == _DragMode.playhead) {
        return SystemMouseCursors.resizeColumn;
      }
      return SystemMouseCursors.grabbing;
    }

    if (_isHoveringLoopEdge) {
      return SystemMouseCursors.resizeLeftRight;
    }

    if (_isHoveringPlayhead) {
      return SystemMouseCursors.resizeColumn;
    }

    return SystemMouseCursors.grab;
  }

  // ============================================
  // HOVER HANDLING
  // ============================================

  void _handleHover(PointerHoverEvent event) {
    final beat = _beatAtX(event.localPosition.dx);
    final nearStart = _isNearLoopStart(beat);
    final nearEnd = _isNearLoopEnd(beat);
    final nearPlayhead = _isNearPlayhead(beat);

    setState(() {
      _hoverBeat = beat;
      _isHoveringLoopEdge = nearStart || nearEnd;
      _isHoveringPlayhead = nearPlayhead;
    });
  }

  // ============================================
  // TAP HANDLING (Click to set playhead)
  // ============================================

  void _handleTapUp(TapUpDetails details) {
    final beat = _beatAtX(details.localPosition.dx);
    widget.callbacks.onPlayheadSet?.call(beat);
  }

  // ============================================
  // PAN HANDLING (Drag for scroll/zoom/loop resize)
  // ============================================

  void _handlePanStart(DragStartDetails details) {
    final beat = _beatAtX(details.localPosition.dx);

    // Check if on playhead first (highest priority for dragging)
    if (_isNearPlayhead(beat)) {
      _dragMode = _DragMode.playhead;
    }
    // Check if on loop edge
    else if (_isNearLoopStart(beat)) {
      _dragMode = _DragMode.loopStart;
    } else if (_isNearLoopEnd(beat)) {
      _dragMode = _DragMode.loopEnd;
    } else {
      // Navigation mode
      _dragMode = _DragMode.navigation;
      _dragStartX = details.globalPosition.dx;
      _dragStartY = details.globalPosition.dy;
      _dragStartPixelsPerBeat = widget.config.pixelsPerBeat;
    }

    setState(() {});
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    switch (_dragMode) {
      case _DragMode.loopStart:
        _handleLoopStartDrag(details);
        break;
      case _DragMode.loopEnd:
        _handleLoopEndDrag(details);
        break;
      case _DragMode.playhead:
        _handlePlayheadDrag(details);
        break;
      case _DragMode.navigation:
        _handleNavigationDrag(details);
        break;
      case _DragMode.none:
        break;
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _dragMode = _DragMode.none;
      _dragStartX = null;
      _dragStartY = null;
      _dragStartPixelsPerBeat = null;
    });
  }

  void _handleLoopStartDrag(DragUpdateDetails details) {
    final beat = _beatAtX(details.localPosition.dx);
    // Clamp to valid range (0 to loopEnd - 1 beat)
    final newStart = beat.clamp(0.0, widget.config.loopEnd - 1.0);
    // Snap to grid (quarter beats)
    final snappedStart = (newStart * 4).round() / 4;
    widget.callbacks.onLoopRegionChanged?.call(
      snappedStart,
      widget.config.loopEnd,
    );
  }

  void _handleLoopEndDrag(DragUpdateDetails details) {
    final beat = _beatAtX(details.localPosition.dx);
    // Clamp to valid range (loopStart + 1 beat to totalBeats)
    final newEnd = beat.clamp(widget.config.loopStart + 1.0, widget.config.totalBeats);
    // Snap to grid (quarter beats)
    final snappedEnd = (newEnd * 4).round() / 4;
    widget.callbacks.onLoopRegionChanged?.call(
      widget.config.loopStart,
      snappedEnd,
    );
  }

  void _handlePlayheadDrag(DragUpdateDetails details) {
    final beat = _beatAtX(details.localPosition.dx);
    // Clamp to valid range (0 to totalBeats)
    final newPosition = beat.clamp(0.0, widget.config.totalBeats);
    // Snap to grid (quarter beats)
    final snappedPosition = (newPosition * 4).round() / 4;
    widget.callbacks.onPlayheadDrag?.call(snappedPosition);
  }

  void _handleNavigationDrag(DragUpdateDetails details) {
    if (_dragStartX == null || _dragStartY == null) return;

    final deltaX = details.globalPosition.dx - _dragStartX!;
    final deltaY = details.globalPosition.dy - _dragStartY!;

    // Horizontal drag = scroll (opposite direction - drag right = scroll left)
    if (deltaX.abs() > 2) {
      widget.callbacks.onHorizontalScroll?.call(-deltaX);
      // Reset start position for continuous scrolling
      _dragStartX = details.globalPosition.dx;
    }

    // Vertical drag = zoom (drag up = zoom in, drag down = zoom out)
    if (deltaY.abs() > 2 && _dragStartPixelsPerBeat != null) {
      // Sensitivity: 100px drag = 1.5x zoom change
      final factor = 1.0 - (deltaY / 200.0);
      final anchorBeat = _beatAtX(details.localPosition.dx);
      widget.callbacks.onZoom?.call(factor, anchorBeat);
      // Reset start position for continuous zooming
      _dragStartY = details.globalPosition.dy;
    }
  }

  // ============================================
  // SCROLL WHEEL (Scroll timeline horizontally)
  // ============================================

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // Scroll wheel = horizontal scroll (no modifier needed)
      // Convert vertical scroll delta to horizontal scroll
      final scrollDelta = event.scrollDelta.dy;
      widget.callbacks.onHorizontalScroll?.call(scrollDelta);
    }
  }
}
