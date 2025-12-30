import 'package:flutter/material.dart';

/// Orientation of the resizable divider
enum DividerOrientation {
  vertical,   // Left-right resize (vertical line)
  horizontal, // Up-down resize (horizontal line)
}

/// A subtle draggable divider that allows resizing panels
///
/// Features:
/// - Drag to resize (8px hit area)
/// - 1px grey line idle, 3px accent line on hover/drag
/// - Double-click to collapse/expand
/// - Custom cursor on hover for discoverability
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
  // Hit area size (8px invisible grab zone)
  static const double _hitAreaSize = 8.0;

  // Colors
  static const Color _idleColor = Color(0xFF505050); // Grey idle
  static const Color _activeColor = Color(0xFF38BDF8); // Accent on hover/drag

  // State for visual feedback
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.orientation == DividerOrientation.vertical;

    // Line width: 1px idle, 3px on hover/drag
    final lineWidth = (_isHovered || _isDragging) ? 3.0 : 1.0;
    final lineColor = (_isHovered || _isDragging) ? _activeColor : _idleColor;

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
          // Invisible hit area for dragging
          width: isVertical ? _hitAreaSize : double.infinity,
          height: isVertical ? double.infinity : _hitAreaSize,
          color: Colors.transparent,
          child: Center(
            // Visible line centered within hit area
            child: Container(
              width: isVertical ? lineWidth : double.infinity,
              height: isVertical ? double.infinity : lineWidth,
              color: lineColor,
            ),
          ),
        ),
      ),
    );
  }
}
