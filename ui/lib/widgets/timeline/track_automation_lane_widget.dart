import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/track_automation_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import '../painters/track_automation_painter.dart';

/// Track automation lane widget for the arrangement timeline.
/// Displays Volume/Pan automation curves and handles point editing.
class TrackAutomationLaneWidget extends StatefulWidget {
  final TrackAutomationLane lane;
  final double pixelsPerBeat;
  final double totalBeats;
  final double laneHeight;
  final ScrollController horizontalScrollController;
  final Color trackColor;

  /// Called when parameter is changed via dropdown
  final Function(AutomationParameter)? onParameterChanged;

  /// Called when a point is added
  final Function(AutomationPoint)? onPointAdded;

  /// Called when a point is updated (moved)
  final Function(String pointId, AutomationPoint)? onPointUpdated;

  /// Called when a point is deleted
  final Function(String pointId)? onPointDeleted;

  /// Called when drawing automation values (drag to draw)
  final Function(double time, double value)? onDrawValue;

  /// Called when lane height changes (resize)
  final Function(double)? onHeightChanged;

  const TrackAutomationLaneWidget({
    super.key,
    required this.lane,
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.laneHeight = 60.0,
    required this.horizontalScrollController,
    required this.trackColor,
    this.onParameterChanged,
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDeleted,
    this.onDrawValue,
    this.onHeightChanged,
  });

  @override
  State<TrackAutomationLaneWidget> createState() =>
      _TrackAutomationLaneWidgetState();
}

class _TrackAutomationLaneWidgetState extends State<TrackAutomationLaneWidget> {
  String? _draggingPointId;
  String? _hoveredPointId;
  bool _isDrawing = false;
  bool _isResizing = false;
  double _resizeStartY = 0.0;
  double _resizeStartHeight = 0.0;

  static const double _footerHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canvasWidth = widget.totalBeats * widget.pixelsPerBeat;
    final canvasHeight = widget.laneHeight - _footerHeight;

    return Container(
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(
          top: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Automation curve area (full width, synced with timeline scroll)
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: widget.horizontalScrollController,
                builder: (context, child) {
                  final scrollOffset =
                      widget.horizontalScrollController.hasClients
                          ? widget.horizontalScrollController.offset
                          : 0.0;
                  return Transform.translate(
                    offset: Offset(-scrollOffset, 0),
                    child: child,
                  );
                },
                child: MouseRegion(
                  cursor: _getCursor(),
                  onHover: _onHover,
                  onExit: (_) => setState(() => _hoveredPointId = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: _onTapDown,
                    onSecondaryTapDown: _onRightClick,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(canvasWidth, canvasHeight),
                        painter: TrackAutomationPainter(
                          lane: widget.lane,
                          pixelsPerBeat: widget.pixelsPerBeat,
                          laneHeight: canvasHeight,
                          totalBeats: widget.totalBeats,
                          lineColor: widget.trackColor,
                          fillColor: widget.trackColor.withValues(alpha: 0.15),
                          pointColor: colors.textPrimary,
                          selectedPointColor: widget.trackColor,
                          gridLineColor: colors.surface,
                          hoveredPointId: _hoveredPointId,
                          draggedPointId: _draggingPointId,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Visible resize footer panel
          _buildResizeFooter(colors),
        ],
      ),
    );
  }

  Widget _buildResizeFooter(BoojyColors colors) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragStart: (details) {
          _isResizing = true;
          _resizeStartY = details.globalPosition.dy;
          _resizeStartHeight = widget.laneHeight;
        },
        onVerticalDragUpdate: (details) {
          if (_isResizing && widget.onHeightChanged != null) {
            // Dragging down = increase height
            final delta = details.globalPosition.dy - _resizeStartY;
            final newHeight = (_resizeStartHeight + delta).clamp(40.0, 200.0);
            widget.onHeightChanged!(newHeight);
          }
        },
        onVerticalDragEnd: (_) => _isResizing = false,
        child: Container(
          height: _footerHeight,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.3),
            border: Border(top: BorderSide(color: colors.surface, width: 1)),
          ),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _getCursor() {
    if (_draggingPointId != null) return SystemMouseCursors.grabbing;
    if (_hoveredPointId != null) return SystemMouseCursors.grab;
    return SystemMouseCursors.precise;
  }

  void _onHover(PointerHoverEvent event) {
    final point = _findPointAtPosition(event.localPosition);
    final newHoveredId = point?.id;
    if (newHoveredId != _hoveredPointId) {
      setState(() {
        _hoveredPointId = newHoveredId;
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    final time = details.localPosition.dx / widget.pixelsPerBeat;
    final value = _yToValue(details.localPosition.dy);

    // Check if clicking on existing point
    final clickedPoint = _findPointAtPosition(details.localPosition);

    if (clickedPoint != null) {
      // Start dragging existing point
      setState(() {
        _draggingPointId = clickedPoint.id;
      });
    } else {
      // Add new point
      final param = widget.lane.parameter;
      final newPoint = AutomationPoint(
        time: time.clamp(0.0, widget.totalBeats),
        value: value.clamp(param.minValue, param.maxValue),
      );
      widget.onPointAdded?.call(newPoint);
    }
  }

  void _onRightClick(TapDownDetails details) {
    // Delete point on right-click
    final clickedPoint = _findPointAtPosition(details.localPosition);
    if (clickedPoint != null) {
      widget.onPointDeleted?.call(clickedPoint.id);
    }
  }

  void _onPanStart(DragStartDetails details) {
    final clickedPoint = _findPointAtPosition(details.localPosition);

    if (clickedPoint != null) {
      setState(() {
        _draggingPointId = clickedPoint.id;
      });
    } else {
      // Start drawing mode
      setState(() {
        _isDrawing = true;
      });

      // Draw initial point
      final time = details.localPosition.dx / widget.pixelsPerBeat;
      final value = _yToValue(details.localPosition.dy);
      widget.onDrawValue?.call(time.clamp(0.0, widget.totalBeats), value);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final time = details.localPosition.dx / widget.pixelsPerBeat;
    final value = _yToValue(details.localPosition.dy);
    final param = widget.lane.parameter;

    if (_draggingPointId != null) {
      // Update dragged point
      final newPoint = AutomationPoint(
        id: _draggingPointId,
        time: time.clamp(0.0, widget.totalBeats),
        value: value.clamp(param.minValue, param.maxValue),
      );
      widget.onPointUpdated?.call(_draggingPointId!, newPoint);
    } else if (_isDrawing) {
      // Draw automation values
      widget.onDrawValue?.call(
        time.clamp(0.0, widget.totalBeats),
        value.clamp(param.minValue, param.maxValue),
      );
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _draggingPointId = null;
      _isDrawing = false;
    });
  }

  AutomationPoint? _findPointAtPosition(Offset position) {
    const hitRadius = 10.0;

    for (final point in widget.lane.points) {
      final pointX = point.time * widget.pixelsPerBeat;
      final pointY = _valueToY(point.value);

      final distance = (Offset(pointX, pointY) - position).distance;
      if (distance <= hitRadius) {
        return point;
      }
    }
    return null;
  }

  double get _canvasHeight => widget.laneHeight - _footerHeight;

  double _yToValue(double y) {
    final param = widget.lane.parameter;
    final minValue = param.minValue;
    final maxValue = param.maxValue;
    final range = maxValue - minValue;

    // Invert Y so higher values are at top
    final normalized = 1 - (y / _canvasHeight);
    return minValue + normalized * range;
  }

  double _valueToY(double value) {
    final param = widget.lane.parameter;
    final minValue = param.minValue;
    final maxValue = param.maxValue;
    final range = maxValue - minValue;

    final normalized = (value - minValue) / range;
    return _canvasHeight * (1 - normalized);
  }
}
