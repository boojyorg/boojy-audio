import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../theme/theme_extension.dart';
import '../../painters/unified_nav_bar_painter.dart';
import 'anchored_zoom.dart';

/// Configuration for UnifiedNavBar behavior and state.
class UnifiedNavBarConfig {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final double? insertMarkerPosition;
  final double? playheadPosition; // in beats (null = not shown)
  final bool punchInEnabled;
  final bool punchOutEnabled;
  final bool isPlaying;
  final int beatsPerBar;

  const UnifiedNavBarConfig({
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.insertMarkerPosition,
    this.playheadPosition,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.isPlaying = false,
    this.beatsPerBar = 4,
  });
}

/// Callbacks for UnifiedNavBar interactions.
class UnifiedNavBarCallbacks {
  /// Called when the scroll wheel moves over the ruler.
  /// [delta] is the amount to scroll (negative = scroll left).
  final void Function(double delta)? onHorizontalScroll;

  /// Called on every pointer move of a navigation drag on the ruler.
  ///
  /// The beat grabbed at drag start must stay under the pointer for the
  /// whole gesture: hold [anchorBeat] at [anchorViewportX] pixels from the
  /// left edge of the ruler viewport after multiplying the zoom by [factor]
  /// (> 1 = zoom in; exactly 1 for a purely horizontal move). Horizontal
  /// travel therefore scrolls and vertical travel zooms, as one continuous
  /// gesture. See `anchoredScrollOffset` / `applyZoomScroll`.
  final void Function(double factor, double anchorBeat, double anchorViewportX)?
  onZoom;

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
  // Larger hit zone for playhead (easier to grab)
  static const double _playheadHitZone = 15.0;

  // Drag state
  _DragMode _dragMode = _DragMode.none;

  // Navigation drag: the beat under the pointer at pan start and where it
  // sat in the viewport. Each move reports the incremental zoom ratio for the
  // vertical travel since the previous move plus the pointer's current
  // viewport x, so the consumer keeps that beat under the pointer throughout.
  double? _navAnchorBeat;
  double? _navStartViewportX;
  double? _navStartGlobalX;
  double? _navLastGlobalY;

  // Where the pointer went down. A pan is only recognised after the pointer
  // has travelled the gesture slop, so the anchor is taken from the press
  // itself (the beat the user aimed at) and the swallowed travel is folded
  // into the first update rather than lost.
  Offset? _downLocal;
  Offset? _downGlobal;

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
        onPanDown: _handlePanDown,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            // Consume the scroll event to prevent bubbling to parent
            if (event is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (event) => _handlePointerSignal(event),
              );
            }
          },
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
                beatsPerBar: widget.config.beatsPerBar,
                loopEnabled: widget.config.loopEnabled,
                loopStart: widget.config.loopStart,
                loopEnd: widget.config.loopEnd,
                insertMarkerPosition: widget.config.insertMarkerPosition,
                playheadPosition: widget.config.playheadPosition,
                hoverBeat: _isHoveringLoopEdge ? _hoverBeat : null,
                isHoveringPlayhead: _isHoveringPlayhead,
                isPlaying: widget.config.isPlaying,
                punchInEnabled: widget.config.punchInEnabled,
                punchOutEnabled: widget.config.punchOutEnabled,
                colors: context.colors,
                textScale: MediaQuery.textScalerOf(context).scale(1.0),
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

  double get _scrollOffset =>
      widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;

  /// Beat at a pointer x. The ruler is laid out at full content width INSIDE
  /// the horizontal scroll view (see [ScrollableNavBar]), so gesture and hover
  /// positions arrive in content space already: never add the scroll offset
  /// here. Doing so put every click, hover and zoom anchor `offset / ppb`
  /// beats too far right whenever the ruler was scrolled past bar 1.
  double _beatAtX(double x) => x / widget.config.pixelsPerBeat;

  double _xAtBeat(double beat) {
    return beat * widget.config.pixelsPerBeat;
  }

  bool _isNearLoopStart(double beat) {
    // Bar is always visible, so edges are always interactive
    return (_xAtBeat(beat) - _xAtBeat(widget.config.loopStart)).abs() <
        _edgeHitZone;
  }

  bool _isNearLoopEnd(double beat) {
    // Bar is always visible, so edges are always interactive
    return (_xAtBeat(beat) - _xAtBeat(widget.config.loopEnd)).abs() <
        _edgeHitZone;
  }

  bool _isNearPlayhead(double beat) {
    if (widget.config.playheadPosition == null) return false;
    // Compare beat positions directly (both are in the same coordinate space)
    final playheadBeat = widget.config.playheadPosition!;
    final distanceInBeats = (beat - playheadBeat).abs();
    final distanceInPixels = distanceInBeats * widget.config.pixelsPerBeat;
    return distanceInPixels < _playheadHitZone;
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
    // Don't set playhead when tapping directly on it (allow drag instead)
    if (!_isNearPlayhead(beat)) {
      widget.callbacks.onPlayheadSet?.call(beat);
    }
  }

  // ============================================
  // PAN HANDLING (Drag for scroll/zoom/loop resize)
  // ============================================

  void _handlePanDown(DragDownDetails details) {
    _downLocal = details.localPosition;
    _downGlobal = details.globalPosition;
  }

  void _handlePanStart(DragStartDetails details) {
    final local = _downLocal ?? details.localPosition;
    final global = _downGlobal ?? details.globalPosition;
    final beat = _beatAtX(local.dx);

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
      // Navigation mode: grab the beat under the pointer.
      _dragMode = _DragMode.navigation;
      _navAnchorBeat = beat;
      _navStartViewportX = local.dx - _scrollOffset;
      _navStartGlobalX = global.dx;
      _navLastGlobalY = global.dy;
      // Apply the travel between the press and recognition straight away.
      _emitNavigation(details.globalPosition);
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
      _navAnchorBeat = null;
      _navStartViewportX = null;
      _navStartGlobalX = null;
      _navLastGlobalY = null;
      _downLocal = null;
      _downGlobal = null;
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
    final newEnd = beat.clamp(
      widget.config.loopStart + 1.0,
      widget.config.totalBeats,
    );
    // Snap to grid (quarter beats)
    final snappedEnd = (newEnd * 4).round() / 4;
    widget.callbacks.onLoopRegionChanged?.call(
      widget.config.loopStart,
      snappedEnd,
    );
  }

  void _handlePlayheadDrag(DragUpdateDetails details) {
    final beat = _beatAtX(details.localPosition.dx);
    // Clamp to valid range (0 to totalBeats), no snapping for precise scrubbing
    final newPosition = beat.clamp(0.0, widget.config.totalBeats);
    widget.callbacks.onPlayheadDrag?.call(newPosition);
  }

  void _handleNavigationDrag(DragUpdateDetails details) =>
      _emitNavigation(details.globalPosition);

  void _emitNavigation(Offset globalPosition) {
    final anchorBeat = _navAnchorBeat;
    final startViewportX = _navStartViewportX;
    final startGlobalX = _navStartGlobalX;
    final lastGlobalY = _navLastGlobalY;
    if (anchorBeat == null ||
        startViewportX == null ||
        startGlobalX == null ||
        lastGlobalY == null) {
      return;
    }

    // Vertical travel since the previous move → incremental zoom ratio. No
    // dead zone: a 1px move is a 1px move, and the ratios multiply, so the
    // gesture is smooth and a round trip returns to the starting zoom.
    final deltaY = globalPosition.dy - lastGlobalY;
    _navLastGlobalY = globalPosition.dy;
    final factor = rulerDragZoomFactor(deltaY);

    // Pointer x in the viewport, tracked from the press by global travel:
    // the ruler itself moves under the pointer as the consumer scrolls, so
    // its local x is not a stable reference during the drag.
    final viewportX = startViewportX + (globalPosition.dx - startGlobalX);

    widget.callbacks.onZoom?.call(factor, anchorBeat, viewportX);
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
