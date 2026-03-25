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
/// - Drag to resize (4px grab zone)
/// - 1px centered line at rest, 4px accent bar on hover/drag
/// - Double-click to collapse/expand
/// - Optional [activeNotifier] for synchronized hover with linked dividers
class ResizableDivider extends StatefulWidget {
  final DividerOrientation orientation;
  final Function(double delta) onDrag;
  final VoidCallback onDoubleClick;
  final bool isCollapsed;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final ValueNotifier<bool>? activeNotifier;

  const ResizableDivider({
    super.key,
    required this.orientation,
    required this.onDrag,
    required this.onDoubleClick,
    this.isCollapsed = false,
    this.onDragStart,
    this.onDragEnd,
    this.activeNotifier,
  });

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  static const double _dividerWidth = 4.0;

  bool _isHovered = false;
  bool _isDragging = false;

  void _onNotifierChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.activeNotifier?.addListener(_onNotifierChanged);
  }

  @override
  void didUpdateWidget(ResizableDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeNotifier != widget.activeNotifier) {
      oldWidget.activeNotifier?.removeListener(_onNotifierChanged);
      widget.activeNotifier?.addListener(_onNotifierChanged);
    }
  }

  @override
  void dispose() {
    widget.activeNotifier?.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _setLocalActive(bool hovered, bool dragging) {
    setState(() {
      _isHovered = hovered;
      _isDragging = dragging;
    });
    widget.activeNotifier?.value = hovered || dragging;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isVertical = widget.orientation == DividerOrientation.vertical;
    final isActive = _isHovered || _isDragging || (widget.activeNotifier?.value ?? false);

    return GestureDetector(
      onPanStart: (_) {
        _setLocalActive(_isHovered, true);
        widget.onDragStart?.call();
      },
      onPanUpdate: (details) {
        if (!widget.isCollapsed) {
          final delta = isVertical ? details.delta.dx : details.delta.dy;
          widget.onDrag(delta);
        }
      },
      onPanEnd: (_) {
        _setLocalActive(_isHovered, false);
        widget.onDragEnd?.call();
      },
      onDoubleTap: widget.onDoubleClick,
      child: MouseRegion(
        cursor: isVertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => _setLocalActive(true, _isDragging),
        onExit: (_) => _setLocalActive(false, _isDragging),
        child: Container(
          width: isVertical ? _dividerWidth : double.infinity,
          height: isVertical ? double.infinity : _dividerWidth,
          color: isActive ? colors.accent : colors.dark,
          child: isActive
              ? null
              : Center(
                  child: SizedBox(
                    width: isVertical ? 1.0 : double.infinity,
                    height: isVertical ? double.infinity : 1.0,
                    child: ColoredBox(color: colors.divider),
                  ),
                ),
        ),
      ),
    );
  }
}
