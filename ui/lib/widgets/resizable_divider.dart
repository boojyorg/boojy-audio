import 'package:flutter/material.dart';

/// Orientation of the resizable divider
enum DividerOrientation {
  vertical,   // Left-right resize (vertical line)
  horizontal, // Up-down resize (horizontal line)
}

/// A draggable divider that allows resizing panels
///
/// Features:
/// - Drag to resize
/// - Double-click to collapse/expand
/// - Hover highlight for discoverability
/// - Custom cursor on hover
class ResizableDivider extends StatefulWidget {
  final DividerOrientation orientation;
  final Function(double delta) onDrag;
  final VoidCallback onDoubleClick;
  final bool isCollapsed;

  const ResizableDivider({
    super.key,
    required this.orientation,
    required this.onDrag,
    required this.onDoubleClick,
    this.isCollapsed = false,
  });

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  bool _isHovered = false;
  bool _isDragging = false;

  // Touch-friendly hit area (20px) while keeping visual line thin
  static const double _hitAreaSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.orientation == DividerOrientation.vertical;
    final isActive = _isHovered || _isDragging;

    // Visual line dimensions
    final lineWidth = isVertical ? (isActive ? 3.0 : 1.0) : double.infinity;
    final lineHeight = isVertical ? double.infinity : (isActive ? 3.0 : 1.0);

    // Line color based on state
    final lineColor = _isDragging
        ? const Color(0xFF00BCD4) // Cyan when dragging
        : _isHovered
            ? const Color(0xFF00838F) // Dim cyan on hover
            : const Color(0xFF363636); // Dark grey default

    return GestureDetector(
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanUpdate: (details) {
        if (!widget.isCollapsed) {
          final delta = isVertical ? details.delta.dx : details.delta.dy;
          widget.onDrag(delta);
        }
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      onDoubleTap: widget.onDoubleClick,
      child: MouseRegion(
        cursor: isVertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          // Large invisible hit area for touch
          width: isVertical ? _hitAreaSize : double.infinity,
          height: isVertical ? double.infinity : _hitAreaSize,
          color: Colors.transparent,
          child: Center(
            // Thin visible line centered within hit area
            child: Container(
              width: lineWidth,
              height: lineHeight,
              color: lineColor,
            ),
          ),
        ),
      ),
    );
  }
}
