import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/clip_automation_data.dart';
import '../../models/tool_mode.dart';
import '../../services/tool_mode_resolver.dart';
import '../../theme/theme_extension.dart';
import '../../utils/grid_utils.dart';
import '../painters/clip_automation_painter.dart';

/// Clip automation lane widget for displaying and editing automation within clips.
/// Supports the 5 tools: draw, select, delete, copy, slice.
class ClipAutomationLaneWidget extends StatefulWidget {
  final ClipAutomationLane lane;
  final double pixelsPerBeat;
  final double clipDurationBeats;
  final double loopLengthBeats;
  final bool canRepeat;
  final double laneHeight;
  final Color trackColor;
  final ToolMode toolMode;

  /// Snap settings
  final bool snapEnabled;
  final double snapResolution;
  final int beatsPerBar;

  /// Called when a point is added
  final Function(ClipAutomationPoint)? onPointAdded;

  /// Called when a point is updated (moved)
  final Function(String pointId, ClipAutomationPoint)? onPointUpdated;

  /// Called when a point is deleted
  final Function(String pointId)? onPointDeleted;

  /// Called when points are selected
  final Function(Set<String> selectedIds)? onSelectionChanged;

  /// Called with preview value during drag (for live value display)
  final Function(double? value)? onPreviewValue;

  const ClipAutomationLaneWidget({
    super.key,
    required this.lane,
    required this.pixelsPerBeat,
    required this.clipDurationBeats,
    required this.loopLengthBeats,
    required this.canRepeat,
    this.laneHeight = 60.0,
    required this.trackColor,
    this.toolMode = ToolMode.draw,
    this.snapEnabled = true,
    this.snapResolution = 1.0,
    this.beatsPerBar = 4,
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDeleted,
    this.onSelectionChanged,
    this.onPreviewValue,
  });

  @override
  State<ClipAutomationLaneWidget> createState() => _ClipAutomationLaneWidgetState();
}

class _ClipAutomationLaneWidgetState extends State<ClipAutomationLaneWidget> {
  String? _draggingPointId;
  String? _hoveredPointId;
  bool _isSelecting = false;
  Offset? _selectionStart;
  Offset? _selectionEnd;
  ClipAutomationPoint? _previewPoint;
  String? _previewPointId;
  Set<String> _selectedPointIds = {};

  /// Effective tool mode (resolves modifier key overrides)
  ToolMode get _effectiveToolMode {
    return ToolModeResolver.resolve(widget.toolMode);
  }

  @override
  void didUpdateWidget(ClipAutomationLaneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear preview when parent lane updates
    if (_previewPoint != null && _previewPointId != null) {
      if (widget.lane != oldWidget.lane) {
        _previewPoint = null;
        _previewPointId = null;
      }
    }
  }

  /// Lane with preview point applied for immediate visual feedback
  ClipAutomationLane get _displayLane {
    if (_previewPoint != null && _previewPointId != null) {
      return widget.lane.updatePoint(_previewPointId!, _previewPoint!);
    }
    return widget.lane;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canvasWidth = widget.clipDurationBeats * widget.pixelsPerBeat;

    return Container(
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.darkest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: colors.surface.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: MouseRegion(
        cursor: _getCursor(),
        onHover: _onHover,
        onExit: (_) => setState(() => _hoveredPointId = null),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: _onTapDown,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Focus(
            onKeyEvent: _onKeyEvent,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(canvasWidth, widget.laneHeight),
                painter: ClipAutomationPainter(
                  lane: _displayLane,
                  pixelsPerBeat: widget.pixelsPerBeat,
                  laneHeight: widget.laneHeight,
                  clipDurationBeats: widget.clipDurationBeats,
                  loopLengthBeats: widget.loopLengthBeats,
                  canRepeat: widget.canRepeat,
                  lineColor: widget.trackColor,
                  fillColor: widget.trackColor.withValues(alpha: 0.15),
                  pointColor: colors.textPrimary,
                  selectedPointColor: widget.trackColor,
                  gridLineColor: colors.surface,
                  hoveredPointId: _hoveredPointId,
                  draggedPointId: _draggingPointId,
                  beatsPerBar: widget.beatsPerBar,
                  selectionStart: _selectionStart,
                  selectionEnd: _selectionEnd,
                  selectedPointIds: _selectedPointIds,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _getCursor() {
    switch (_effectiveToolMode) {
      case ToolMode.draw:
        if (_draggingPointId != null) return SystemMouseCursors.grabbing;
        if (_hoveredPointId != null) return SystemMouseCursors.grab;
        return SystemMouseCursors.precise;
      case ToolMode.select:
        if (_hoveredPointId != null) return SystemMouseCursors.click;
        return SystemMouseCursors.basic;
      case ToolMode.eraser:
        return SystemMouseCursors.forbidden;
      case ToolMode.duplicate:
        if (_hoveredPointId != null) return SystemMouseCursors.copy;
        return SystemMouseCursors.basic;
      case ToolMode.slice:
        return SystemMouseCursors.verticalText;
    }
  }

  void _onHover(PointerHoverEvent event) {
    final point = _findPointAtPosition(event.localPosition);
    final newHoveredId = point?.id;
    if (newHoveredId != _hoveredPointId) {
      setState(() => _hoveredPointId = newHoveredId);
    }
  }

  void _onTapDown(TapDownDetails details) {
    final clickedPoint = _findPointAtPosition(details.localPosition);
    final toolMode = _effectiveToolMode;

    switch (toolMode) {
      case ToolMode.draw:
        if (clickedPoint != null) {
          // Start dragging existing point
          setState(() => _draggingPointId = clickedPoint.id);
        } else {
          // Add new point
          _addPointAtPosition(details.localPosition);
        }
        break;

      case ToolMode.select:
        if (clickedPoint != null) {
          final modifiers = ModifierKeyState.current();
          if (modifiers.isShiftPressed) {
            // Toggle selection
            setState(() {
              if (_selectedPointIds.contains(clickedPoint.id)) {
                _selectedPointIds.remove(clickedPoint.id);
              } else {
                _selectedPointIds.add(clickedPoint.id);
              }
            });
          } else {
            // Select only this point
            setState(() {
              _selectedPointIds = {clickedPoint.id};
            });
          }
          widget.onSelectionChanged?.call(_selectedPointIds);
        } else {
          // Clear selection
          setState(() => _selectedPointIds.clear());
          widget.onSelectionChanged?.call(_selectedPointIds);
        }
        break;

      case ToolMode.eraser:
        // Click on point to delete it
        if (clickedPoint != null) {
          widget.onPointDeleted?.call(clickedPoint.id);
          // Also remove from local selection
          setState(() {
            _selectedPointIds.remove(clickedPoint.id);
          });
        }
        break;

      case ToolMode.duplicate:
        if (clickedPoint != null) {
          _duplicatePoint(clickedPoint, details.localPosition);
        }
        break;

      case ToolMode.slice:
        if (clickedPoint != null) {
          _sliceAtPoint(clickedPoint, details.localPosition);
        }
        break;
    }
  }

  void _onPanStart(DragStartDetails details) {
    final clickedPoint = _findPointAtPosition(details.localPosition);
    final toolMode = _effectiveToolMode;
    final modifiers = ModifierKeyState.current();

    // Shift+drag always starts box selection (like piano roll)
    if (modifiers.isShiftPressed && clickedPoint == null) {
      setState(() {
        _isSelecting = true;
        _selectionStart = details.localPosition;
        _selectionEnd = details.localPosition;
      });
      return;
    }

    if (toolMode == ToolMode.draw && clickedPoint != null) {
      setState(() => _draggingPointId = clickedPoint.id);
    } else if (toolMode == ToolMode.select) {
      if (clickedPoint != null && _selectedPointIds.contains(clickedPoint.id)) {
        // Start dragging selected points
        setState(() => _draggingPointId = clickedPoint.id);
      } else if (clickedPoint == null) {
        // Start box selection only on empty space
        setState(() {
          _isSelecting = true;
          _selectionStart = details.localPosition;
          _selectionEnd = details.localPosition;
        });
      } else {
        // Clicked on unselected point - select it and prepare to drag
        setState(() {
          _selectedPointIds = {clickedPoint.id};
          _draggingPointId = clickedPoint.id;
        });
        widget.onSelectionChanged?.call(_selectedPointIds);
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggingPointId != null) {
      _updateDraggedPoint(details.localPosition);
    } else if (_isSelecting) {
      // Update box selection (works with Shift+drag in any mode OR Select tool)
      setState(() => _selectionEnd = details.localPosition);
      _updateBoxSelection();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _draggingPointId = null;
      _isSelecting = false;
      _selectionStart = null;
      _selectionEnd = null;
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Delete selected points with Delete or Backspace
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _deleteSelectedPoints();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _addPointAtPosition(Offset position) {
    double time = position.dx / widget.pixelsPerBeat;
    time = _snapTime(time);
    final value = _yToValue(position.dy);

    final param = widget.lane.parameter;
    final newPoint = ClipAutomationPoint(
      time: time.clamp(0.0, widget.loopLengthBeats),
      value: value.clamp(param.minValue, param.maxValue),
    );
    widget.onPointAdded?.call(newPoint);
  }

  void _updateDraggedPoint(Offset position) {
    if (_draggingPointId == null) return;

    double time = position.dx / widget.pixelsPerBeat;
    time = _snapTime(time);
    final value = _yToValue(position.dy);

    final param = widget.lane.parameter;
    final newPoint = ClipAutomationPoint(
      id: _draggingPointId,
      time: time.clamp(0.0, widget.loopLengthBeats),
      value: value.clamp(param.minValue, param.maxValue),
    );

    setState(() {
      _previewPoint = newPoint;
      _previewPointId = _draggingPointId;
    });

    widget.onPreviewValue?.call(newPoint.value);
    widget.onPointUpdated?.call(_draggingPointId!, newPoint);
  }

  void _updateBoxSelection() {
    if (_selectionStart == null || _selectionEnd == null) return;

    final minX = _selectionStart!.dx < _selectionEnd!.dx
        ? _selectionStart!.dx
        : _selectionEnd!.dx;
    final maxX = _selectionStart!.dx > _selectionEnd!.dx
        ? _selectionStart!.dx
        : _selectionEnd!.dx;
    final minY = _selectionStart!.dy < _selectionEnd!.dy
        ? _selectionStart!.dy
        : _selectionEnd!.dy;
    final maxY = _selectionStart!.dy > _selectionEnd!.dy
        ? _selectionStart!.dy
        : _selectionEnd!.dy;

    final newSelection = <String>{};
    for (final point in widget.lane.points) {
      final x = point.time * widget.pixelsPerBeat;
      final y = _valueToY(point.value);
      if (x >= minX && x <= maxX && y >= minY && y <= maxY) {
        newSelection.add(point.id);
      }
    }

    if (newSelection != _selectedPointIds) {
      setState(() => _selectedPointIds = newSelection);
      widget.onSelectionChanged?.call(_selectedPointIds);
    }
  }

  void _deleteSelectedPoints() {
    for (final pointId in _selectedPointIds) {
      widget.onPointDeleted?.call(pointId);
    }
    setState(() => _selectedPointIds.clear());
    widget.onSelectionChanged?.call(_selectedPointIds);
  }

  void _duplicatePoint(ClipAutomationPoint point, Offset position) {
    double time = position.dx / widget.pixelsPerBeat;
    time = _snapTime(time);

    // Create duplicate slightly offset in time
    final offset = widget.snapResolution > 0 ? widget.snapResolution : 0.25;
    final newPoint = ClipAutomationPoint(
      time: (point.time + offset).clamp(0.0, widget.loopLengthBeats),
      value: point.value,
    );
    widget.onPointAdded?.call(newPoint);
  }

  void _sliceAtPoint(ClipAutomationPoint point, Offset position) {
    // Slice creates a new point at the click position on the automation curve
    double time = position.dx / widget.pixelsPerBeat;
    time = _snapTime(time);
    final value = widget.lane.getValueAtTime(time);

    final param = widget.lane.parameter;
    final newPoint = ClipAutomationPoint(
      time: time.clamp(0.0, widget.loopLengthBeats),
      value: value.clamp(param.minValue, param.maxValue),
    );
    widget.onPointAdded?.call(newPoint);
  }

  ClipAutomationPoint? _findPointAtPosition(Offset position) {
    const hitRadius = 10.0;

    for (final point in _displayLane.points) {
      final pointX = point.time * widget.pixelsPerBeat;
      final pointY = _valueToY(point.value);

      final distance = (Offset(pointX, pointY) - position).distance;
      if (distance <= hitRadius) {
        return point;
      }
    }
    return null;
  }

  double _snapTime(double time) {
    final isShiftPressed = ModifierKeyState.current().isShiftPressed;
    if (widget.snapEnabled && !isShiftPressed && widget.snapResolution > 0) {
      return GridUtils.snapToGridRound(time, widget.snapResolution);
    }
    return time;
  }

  double _yToValue(double y) {
    final param = widget.lane.parameter;
    final range = param.maxValue - param.minValue;
    final normalized = 1 - (y / widget.laneHeight);
    return param.minValue + normalized * range;
  }

  double _valueToY(double value) {
    final param = widget.lane.parameter;
    final range = param.maxValue - param.minValue;
    final normalized = (value - param.minValue) / range;
    return widget.laneHeight * (1 - normalized);
  }
}
