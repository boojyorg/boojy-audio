import 'package:flutter/material.dart';
import '../../models/midi_cc_data.dart';
import '../../theme/theme_extension.dart';
import '../painters/cc_lane_painter.dart';

/// CC automation lane widget for the Piano Roll.
/// Displays CC curves and handles point editing.
class PianoRollCCLane extends StatefulWidget {
  final MidiCCLane lane;
  final double pixelsPerBeat;
  final double totalBeats;
  final double laneHeight;
  final ScrollController horizontalScrollController;

  /// Called when CC type is changed via dropdown
  final Function(MidiCCType)? onCCTypeChanged;

  /// Called when a point is added
  final Function(MidiCCPoint)? onPointAdded;

  /// Called when a point is updated (moved)
  final Function(String pointId, MidiCCPoint)? onPointUpdated;

  /// Called when a point is deleted
  final Function(String pointId)? onPointDeleted;

  /// Called when drawing CC values (drag to draw)
  final Function(double time, int value)? onDrawValue;

  /// Called when the lane should be closed
  final VoidCallback? onClose;

  const PianoRollCCLane({
    super.key,
    required this.lane,
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.laneHeight = 80.0,
    required this.horizontalScrollController,
    this.onCCTypeChanged,
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDeleted,
    this.onDrawValue,
    this.onClose,
  });

  @override
  State<PianoRollCCLane> createState() => _PianoRollCCLaneState();
}

class _PianoRollCCLaneState extends State<PianoRollCCLane> {
  String? _draggingPointId;
  bool _isDrawing = false;

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
      child: Row(
        children: [
          // Label area with CC type dropdown
          _buildLabelArea(context),
          // CC curve area (scrolls with note grid)
          Expanded(
            child: SingleChildScrollView(
              controller: widget.horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: _onTapDown,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  size: Size(canvasWidth, widget.laneHeight),
                  painter: CCLanePainter(
                    lane: widget.lane,
                    pixelsPerBeat: widget.pixelsPerBeat,
                    laneHeight: widget.laneHeight,
                    totalBeats: widget.totalBeats,
                    lineColor: _getLineColor(context),
                    fillColor: _getFillColor(context),
                    pointColor: colors.textPrimary,
                    selectedPointColor: colors.accent,
                    gridLineColor: colors.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelArea(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 60,
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // CC type dropdown
          GestureDetector(
            onTap: _showCCTypeMenu,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _getShortCCName(widget.lane.ccType),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 9,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 12,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Close button
          GestureDetector(
            onTap: widget.onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getShortCCName(MidiCCType type) {
    switch (type) {
      case MidiCCType.modWheel:
        return 'Mod';
      case MidiCCType.breath:
        return 'Breath';
      case MidiCCType.volume:
        return 'Vol';
      case MidiCCType.pan:
        return 'Pan';
      case MidiCCType.expression:
        return 'Expr';
      case MidiCCType.sustainPedal:
        return 'Sust';
      case MidiCCType.pitchBend:
        return 'Pitch';
    }
  }

  void _showCCTypeMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<MidiCCType>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy,
        overlay.size.width - buttonPosition.dx - 60,
        0,
      ),
      items: MidiCCType.values.map((type) {
        return PopupMenuItem<MidiCCType>(
          value: type,
          height: 32,
          child: Text(
            type.displayName,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight: type == widget.lane.ccType ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      elevation: 8,
    ).then((value) {
      if (value != null && widget.onCCTypeChanged != null) {
        widget.onCCTypeChanged!(value);
      }
    });
  }

  Color _getLineColor(BuildContext context) {
    // Different colors for different CC types
    switch (widget.lane.ccType) {
      case MidiCCType.modWheel:
        return const Color(0xFF4FC3F7); // Light blue
      case MidiCCType.volume:
        return const Color(0xFF81C784); // Light green
      case MidiCCType.pan:
        return const Color(0xFFFFB74D); // Orange
      case MidiCCType.expression:
        return const Color(0xFFBA68C8); // Purple
      case MidiCCType.sustainPedal:
        return const Color(0xFFE57373); // Red
      case MidiCCType.pitchBend:
        return const Color(0xFFFFD54F); // Yellow
      default:
        return context.colors.accent;
    }
  }

  Color _getFillColor(BuildContext context) {
    return _getLineColor(context).withValues(alpha: 0.2);
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
      final newPoint = MidiCCPoint(
        time: time,
        value: value,
      );
      widget.onPointAdded?.call(newPoint);
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
      widget.onDrawValue?.call(time, value);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final time = details.localPosition.dx / widget.pixelsPerBeat;
    final value = _yToValue(details.localPosition.dy);

    if (_draggingPointId != null) {
      // Update dragged point
      final newPoint = MidiCCPoint(
        id: _draggingPointId,
        time: time.clamp(0.0, widget.totalBeats),
        value: value,
      );
      widget.onPointUpdated?.call(_draggingPointId!, newPoint);
    } else if (_isDrawing) {
      // Draw CC values
      widget.onDrawValue?.call(time.clamp(0.0, widget.totalBeats), value);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _draggingPointId = null;
      _isDrawing = false;
    });
  }

  MidiCCPoint? _findPointAtPosition(Offset position) {
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

  int _yToValue(double y) {
    final ccType = widget.lane.ccType;
    final minValue = ccType.minValue;
    final maxValue = ccType.maxValue;
    final range = maxValue - minValue;

    // Invert Y so higher values are at top
    final normalized = 1 - (y / widget.laneHeight);
    return (minValue + normalized * range).round().clamp(minValue, maxValue);
  }

  double _valueToY(int value) {
    final ccType = widget.lane.ccType;
    final minValue = ccType.minValue;
    final maxValue = ccType.maxValue;
    final range = maxValue - minValue;

    final normalized = (value - minValue) / range;
    return widget.laneHeight * (1 - normalized);
  }
}
