import 'package:flutter/material.dart';

/// Configuration for InteractiveGutter behavior.
class InteractiveGutterConfig {
  /// Width of the gutter.
  final double width;

  /// Number of items in the gutter.
  final int itemCount;

  /// Current scroll offset (for calculating visible items).
  final double scrollOffset;

  /// Whether audition/tap is enabled.
  final bool tapEnabled;

  const InteractiveGutterConfig({
    required this.width,
    required this.itemCount,
    this.scrollOffset = 0.0,
    this.tapEnabled = true,
  });
}

/// Callbacks for InteractiveGutter interactions.
class InteractiveGutterCallbacks {
  /// Called when user drags vertically to scroll.
  /// [delta] is the amount to scroll (positive = scroll down).
  final void Function(double delta)? onVerticalScroll;

  /// Called when user releases drag with velocity (for momentum scrolling).
  /// [velocity] is pixels per second in vertical direction.
  final void Function(double velocity)? onVerticalFling;

  /// Called when user drags horizontally to zoom item height.
  /// [factor] is the zoom multiplier (> 1 = zoom in, items get taller).
  final void Function(double factor)? onItemHeightZoom;

  /// Called when user taps an item.
  /// [index] is the item index (e.g., MIDI note number for piano keys).
  final void Function(int index)? onItemTap;

  /// Called when user releases tap on an item (for note-off).
  final void Function(int index)? onItemTapUp;

  const InteractiveGutterCallbacks({
    this.onVerticalScroll,
    this.onVerticalFling,
    this.onItemHeightZoom,
    this.onItemTap,
    this.onItemTapUp,
  });
}

/// Interactive gutter widget for spatial navigation.
/// Used for Piano Roll key gutter and Arrangement track headers.
///
/// Gesture mapping:
/// - Drag up/down = scroll items (octaves for piano, tracks for arrangement)
/// - Drag left/right = zoom item height
/// - Click = tap item (audition note / select track)
///
/// Cursor: resizeUpDown (indicates vertical scroll/zoom capability)
class InteractiveGutter extends StatefulWidget {
  final InteractiveGutterConfig config;
  final InteractiveGutterCallbacks callbacks;

  /// Builder for individual items.
  /// [index] is the item index, [height] is the current item height.
  final Widget Function(int index, double height) itemBuilder;

  /// Current height per item (used for rendering).
  final double itemHeight;

  /// Scroll controller for the gutter content.
  final ScrollController scrollController;

  const InteractiveGutter({
    super.key,
    required this.config,
    required this.callbacks,
    required this.itemBuilder,
    required this.itemHeight,
    required this.scrollController,
  });

  @override
  State<InteractiveGutter> createState() => _InteractiveGutterState();
}

class _InteractiveGutterState extends State<InteractiveGutter> {
  // Drag state
  bool _isDragging = false;
  double? _dragStartX;
  double? _dragStartY;
  int? _tappedItemIndex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.config.width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Use AnimatedBuilder + Stack/Positioned to sync with scroll controller
    // WITHOUT attaching the controller to a scroll view (avoids multiple attachment error)
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;

        return ClipRect(
          child: AnimatedBuilder(
            animation: widget.scrollController,
            builder: (context, _) {
              final scrollOffset = widget.scrollController.hasClients
                  ? widget.scrollController.offset
                  : 0.0;

              // Calculate visible range with buffer
              final firstVisibleIndex = (scrollOffset / widget.itemHeight).floor();
              final visibleCount = (viewportHeight / widget.itemHeight).ceil() + 2;
              final startIndex = (firstVisibleIndex - 1).clamp(0, widget.config.itemCount);
              final endIndex = (firstVisibleIndex + visibleCount).clamp(0, widget.config.itemCount);

              // Build positioned items using Stack to avoid overflow
              final positionedItems = <Widget>[];
              for (var i = startIndex; i < endIndex; i++) {
                final top = i * widget.itemHeight - scrollOffset;
                positionedItems.add(Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  height: widget.itemHeight,
                  child: widget.itemBuilder(i, widget.itemHeight),
                ));
              }

              return SizedBox(
                height: viewportHeight,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: positionedItems,
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ============================================
  // TAP HANDLING (Click to audition/select)
  // ============================================

  void _handleTapDown(TapDownDetails details) {
    if (!widget.config.tapEnabled) return;

    final itemIndex = _getItemIndexAtY(details.localPosition.dy);
    if (itemIndex != null) {
      _tappedItemIndex = itemIndex;
      widget.callbacks.onItemTap?.call(itemIndex);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_tappedItemIndex != null) {
      widget.callbacks.onItemTapUp?.call(_tappedItemIndex!);
      _tappedItemIndex = null;
    }
  }

  void _handleTapCancel() {
    if (_tappedItemIndex != null) {
      widget.callbacks.onItemTapUp?.call(_tappedItemIndex!);
      _tappedItemIndex = null;
    }
  }

  int? _getItemIndexAtY(double y) {
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final adjustedY = y + scrollOffset;
    final index = (adjustedY / widget.itemHeight).floor();

    // No inversion - index 0 is at top (high notes via foldedPitches)
    final itemIndex = index;

    if (itemIndex >= 0 && itemIndex < widget.config.itemCount) {
      return itemIndex;
    }
    return null;
  }

  // ============================================
  // PAN HANDLING (Drag for scroll/zoom)
  // ============================================

  void _handlePanStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartX = details.globalPosition.dx;
    _dragStartY = details.globalPosition.dy;

    // Cancel any tap in progress
    if (_tappedItemIndex != null) {
      widget.callbacks.onItemTapUp?.call(_tappedItemIndex!);
      _tappedItemIndex = null;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _dragStartX == null || _dragStartY == null) return;

    final deltaX = details.delta.dx;
    final deltaY = details.delta.dy;

    // Vertical drag = scroll (drag up = scroll up to see higher notes)
    if (deltaY.abs() > 0.5) {
      widget.callbacks.onVerticalScroll?.call(deltaY);
    }

    // Horizontal drag = zoom item height
    // Drag right = zoom in (items get taller)
    // Drag left = zoom out (items get shorter)
    if (deltaX.abs() > 0.5) {
      // Sensitivity: 100px drag = ~1.5x zoom change
      final factor = 1.0 + (deltaX / 200.0);
      widget.callbacks.onItemHeightZoom?.call(factor);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    _isDragging = false;
    _dragStartX = null;
    _dragStartY = null;

    // Apply momentum/fling if there's significant vertical velocity
    final velocityY = details.velocity.pixelsPerSecond.dy;
    if (velocityY.abs() > 50) {
      widget.callbacks.onVerticalFling?.call(velocityY);
    }
  }
}
