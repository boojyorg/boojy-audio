import 'package:flutter/material.dart';
import '../theme/theme_extension.dart';

/// Orientation of the resizable divider
enum DividerOrientation {
  vertical,   // Left-right resize (vertical line)
  horizontal, // Up-down resize (horizontal line)
}

/// A subtle draggable divider that allows resizing panels
///
/// Features:
/// - Drag to resize (8px hit area for easy grabbing)
/// - 4px visible colored strip centered within hit area
/// - Divider color idle, accent color on hover/drag
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
  // Visible divider strip width
  static const double _dividerWidth = 4.0;

  // State for visual feedback
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isVertical = widget.orientation == DividerOrientation.vertical;
    final isActive = _isHovered || _isDragging;
    final dividerColor = isActive ? colors.accent : colors.divider;

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
            // 4px visible divider strip
            child: Container(
              width: isVertical ? _dividerWidth : double.infinity,
              height: isVertical ? double.infinity : _dividerWidth,
              color: dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
