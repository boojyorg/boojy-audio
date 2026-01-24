import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/track_automation_data.dart';
import '../../services/tool_mode_resolver.dart';
import '../../theme/theme_extension.dart';
import '../../utils/grid_utils.dart';
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

  /// Snap settings
  final bool snapEnabled;
  final double snapResolution;
  final int beatsPerBar;

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

  /// Called with preview value during drag (for live value display)
  final Function(double? value)? onPreviewValue;

  const TrackAutomationLaneWidget({
    super.key,
    required this.lane,
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.laneHeight = 60.0,
    required this.horizontalScrollController,
    required this.trackColor,
    this.snapEnabled = true,
    this.snapResolution = 1.0,
    this.beatsPerBar = 4,
    this.onParameterChanged,
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDeleted,
    this.onDrawValue,
    this.onHeightChanged,
    this.onPreviewValue,
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
  AutomationPoint? _previewPoint; // Local preview during drag for real-time updates
  String? _previewPointId; // ID of point being previewed (persists after drag ends)

  @override
  void didUpdateWidget(TrackAutomationLaneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear preview when parent lane updates (callback propagated)
    if (_previewPoint != null && _previewPointId != null) {
      // Check if the lane now contains the updated point
      if (widget.lane != oldWidget.lane) {
        _previewPoint = null;
        _previewPointId = null;
      }
    }
  }

  /// Lane with preview point applied (for immediate visual feedback)
  TrackAutomationLane get _displayLane {
    if (_previewPoint != null && _previewPointId != null) {
      return widget.lane.updatePoint(_previewPointId!, _previewPoint!);
    }
    return widget.lane;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canvasWidth = widget.totalBeats * widget.pixelsPerBeat;

    return Container(
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(
          top: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Stack(
        children: [
          // Automation curve area (full width, synced with timeline scroll)
          ClipRect(
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
                      size: Size(canvasWidth, widget.laneHeight),
                      painter: TrackAutomationPainter(
                        lane: _displayLane, // Use preview lane for real-time updates
                        pixelsPerBeat: widget.pixelsPerBeat,
                        laneHeight: widget.laneHeight,
                        totalBeats: widget.totalBeats,
                        lineColor: widget.trackColor,
                        fillColor: widget.trackColor.withValues(alpha: 0.15),
                        pointColor: colors.textPrimary,
                        selectedPointColor: widget.trackColor,
                        gridLineColor: colors.surface,
                        hoveredPointId: _hoveredPointId,
                        draggedPointId: _draggingPointId,
                        beatsPerBar: widget.beatsPerBar,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Resize handle at top (invisible 6px strip)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onVerticalDragStart: (details) {
                  _isResizing = true;
                  _resizeStartY = details.globalPosition.dy;
                  _resizeStartHeight = widget.laneHeight;
                },
                onVerticalDragUpdate: (details) {
                  if (_isResizing && widget.onHeightChanged != null) {
                    // Dragging up = increase height (negative delta)
                    final delta = _resizeStartY - details.globalPosition.dy;
                    final newHeight = (_resizeStartHeight + delta).clamp(40.0, 200.0);
                    widget.onHeightChanged!(newHeight);
                  }
                },
                onVerticalDragEnd: (_) => _isResizing = false,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ],
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
    double time = details.localPosition.dx / widget.pixelsPerBeat;
    final value = _yToValue(details.localPosition.dy);

    // Check if clicking on existing point
    final clickedPoint = _findPointAtPosition(details.localPosition);

    if (clickedPoint != null) {
      // Start dragging existing point
      setState(() {
        _draggingPointId = clickedPoint.id;
      });
    } else {
      // Add new point (snap time if enabled)
      time = _snapTime(time);
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

      // Draw initial point (snap if enabled)
      double time = details.localPosition.dx / widget.pixelsPerBeat;
      time = _snapTime(time);
      final value = _yToValue(details.localPosition.dy);
      widget.onDrawValue?.call(time.clamp(0.0, widget.totalBeats), value);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    double time = details.localPosition.dx / widget.pixelsPerBeat;
    final value = _yToValue(details.localPosition.dy);
    final param = widget.lane.parameter;

    if (_draggingPointId != null) {
      // Snap time if enabled (Shift bypasses snap)
      time = _snapTime(time);

      // Create preview point for immediate visual feedback
      final newPoint = AutomationPoint(
        id: _draggingPointId,
        time: time.clamp(0.0, widget.totalBeats),
        value: value.clamp(param.minValue, param.maxValue),
      );

      // Local setState for immediate repaint (like velocity lane)
      setState(() {
        _previewPoint = newPoint;
        _previewPointId = _draggingPointId; // Track which point is being previewed
      });

      // Notify parent of preview value (for live value display)
      widget.onPreviewValue?.call(newPoint.value);

      // Callback for persistence
      widget.onPointUpdated?.call(_draggingPointId!, newPoint);
    } else if (_isDrawing) {
      // Draw automation values (time already snapped above)
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
      // Don't clear _previewPoint here - keep showing preview until
      // didUpdateWidget detects the parent lane has been updated
    });
    // Don't clear preview value - keep showing the dragged-to value when paused
    // Preview will be cleared when playback starts (handled in DAWScreen)
  }

  AutomationPoint? _findPointAtPosition(Offset position) {
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

  double get _canvasHeight => widget.laneHeight;

  /// Snap time to grid if snap is enabled (Shift key bypasses snap)
  double _snapTime(double time) {
    final isShiftPressed = ModifierKeyState.current().isShiftPressed;
    if (widget.snapEnabled && !isShiftPressed && widget.snapResolution > 0) {
      return GridUtils.snapToGridRound(time, widget.snapResolution);
    }
    return time;
  }

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
