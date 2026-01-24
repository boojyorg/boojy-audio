import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/clip_automation_data.dart';
import '../../models/track_automation_data.dart';
import '../../models/tool_mode.dart';
import '../../services/tool_mode_resolver.dart';
import '../../theme/theme_extension.dart';
import '../../utils/grid_utils.dart';
import '../painters/clip_automation_painter.dart';

/// Clip automation lane widget for the Piano Roll.
/// Displays automation curves for clip-based automation and handles point editing.
class PianoRollClipAutomationLane extends StatefulWidget {
  final ClipAutomationLane lane;
  final double pixelsPerBeat;
  final double loopLengthBeats;
  final bool canRepeat;
  final double clipDurationBeats;
  final double laneHeight;
  final Color trackColor;
  final ToolMode toolMode;
  final ScrollController horizontalScrollController;

  /// Snap settings
  final bool snapEnabled;
  final double snapResolution;
  final int beatsPerBar;

  /// Called when automation parameter is changed via dropdown
  final Function(AutomationParameter)? onParameterChanged;

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

  /// Called when the lane should be closed
  final VoidCallback? onClose;

  const PianoRollClipAutomationLane({
    super.key,
    required this.lane,
    required this.pixelsPerBeat,
    required this.loopLengthBeats,
    required this.canRepeat,
    required this.clipDurationBeats,
    this.laneHeight = 80.0,
    required this.trackColor,
    this.toolMode = ToolMode.draw,
    required this.horizontalScrollController,
    this.snapEnabled = true,
    this.snapResolution = 0.25,
    this.beatsPerBar = 4,
    this.onParameterChanged,
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDeleted,
    this.onSelectionChanged,
    this.onPreviewValue,
    this.onClose,
  });

  @override
  State<PianoRollClipAutomationLane> createState() =>
      _PianoRollClipAutomationLaneState();
}

class _PianoRollClipAutomationLaneState
    extends State<PianoRollClipAutomationLane> {
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
  void didUpdateWidget(PianoRollClipAutomationLane oldWidget) {
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
    debugPrint('[AutomationLane] BUILD METHOD CALLED - laneHeight=${widget.laneHeight}, clipDurationBeats=${widget.clipDurationBeats}');
    final colors = context.colors;
    final canvasWidth = widget.clipDurationBeats * widget.pixelsPerBeat;

    // Wrap entire widget with Listener at top level to trace ALL pointer events
    return Listener(
      onPointerDown: (event) {
        debugPrint('[AutomationLane] TOP-LEVEL Listener onPointerDown: ${event.localPosition}');
      },
      child: Container(
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(
          top: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Label area with parameter dropdown
          _buildLabelArea(context),
          // Automation curve area (synced with note grid scroll)
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: widget.horizontalScrollController,
                builder: (context, _) {
                  final scrollOffset =
                      widget.horizontalScrollController.hasClients
                          ? widget.horizontalScrollController.offset
                          : 0.0;
                  // NOTE: CustomPaint must be inside the builder (not child param)
                  // so that setState() triggers a rebuild of the painter with
                  // updated selectionStart, selectionEnd, selectedPointIds.
                  debugPrint('[AutomationLane] BUILD: scrollOffset=$scrollOffset, laneHeight=${widget.laneHeight}');
                  return Transform.translate(
                    offset: Offset(-scrollOffset, 0),
                    child: Listener(
                      onPointerDown: (event) {
                        debugPrint('[AutomationLane] LISTENER onPointerDown: ${event.localPosition}');
                      },
                      child: MouseRegion(
                        cursor: _getCursor(),
                        onHover: (event) {
                          debugPrint('[AutomationLane] HOVER: ${event.localPosition}');
                          _onHover(event);
                        },
                        onExit: (_) => setState(() => _hoveredPointId = null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapDown: (details) {
                            debugPrint('[AutomationLane] GestureDetector onTapDown: ${details.localPosition}');
                            _onTapDown(details);
                          },
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
                                  fillColor:
                                      widget.trackColor.withValues(alpha: 0.15),
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
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),  // Close Listener child
    );
  }

  Widget _buildLabelArea(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 80,
      height: widget.laneHeight,
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          right: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Automation label at top
          Text(
            'Automation',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // Parameter dropdown
          GestureDetector(
            onTap: _showParameterMenu,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getShortParameterName(widget.lane.parameter),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(width: 2),
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
          const SizedBox(height: 8),
          // Current value display
          Text(
            _formatCurrentValue(),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getShortParameterName(AutomationParameter param) {
    switch (param) {
      case AutomationParameter.volume:
        return 'Vol';
      case AutomationParameter.pan:
        return 'Pan';
    }
  }

  String _formatCurrentValue() {
    final param = widget.lane.parameter;
    double value;

    // Show preview value if dragging, otherwise show default
    if (_previewPoint != null) {
      value = _previewPoint!.value;
    } else if (widget.lane.points.isNotEmpty) {
      value = widget.lane.points.last.value;
    } else {
      value = param.defaultValue;
    }

    switch (param) {
      case AutomationParameter.volume:
        final db = VolumeConversion.normalizedToDb(value);
        if (db <= -60) return '-inf dB';
        return '${db.toStringAsFixed(1)} dB';
      case AutomationParameter.pan:
        // Pan is stored as -1 to 1, convert to display
        final pan = value;
        if (pan.abs() < 0.01) return 'C';
        if (pan < 0) return '${(pan.abs() * 100).round()}L';
        return '${(pan * 100).round()}R';
    }
  }

  void _showParameterMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonPosition =
        button.localToGlobal(Offset.zero, ancestor: overlay);

    showMenu<AutomationParameter>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonPosition.dx,
        buttonPosition.dy,
        overlay.size.width - buttonPosition.dx - 60,
        0,
      ),
      items: [
        AutomationParameter.volume,
        AutomationParameter.pan,
      ].map((param) {
        return PopupMenuItem<AutomationParameter>(
          value: param,
          height: 32,
          child: Text(
            param.displayName,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11,
              fontWeight:
                  param == widget.lane.parameter ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
      elevation: 8,
    ).then((value) {
      if (value != null && widget.onParameterChanged != null) {
        widget.onParameterChanged!(value);
      }
    });
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

    // DEBUG: Trace what's happening with tool mode and hit detection
    debugPrint('[AutomationLane] _onTapDown: toolMode=$toolMode, clickedPoint=${clickedPoint?.id}, localPos=${details.localPosition}');
    debugPrint('[AutomationLane] Points in lane: ${_displayLane.points.length}');
    for (final p in _displayLane.points) {
      final px = p.time * widget.pixelsPerBeat;
      final py = _valueToY(p.value);
      debugPrint('[AutomationLane]   Point ${p.id}: time=${p.time}, value=${p.value}, screenPos=($px, $py)');
    }

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
        debugPrint('[AutomationLane] ERASER: clickedPoint=${clickedPoint?.id}');
        if (clickedPoint != null) {
          debugPrint('[AutomationLane] ERASER: Calling onPointDeleted for ${clickedPoint.id}');
          widget.onPointDeleted?.call(clickedPoint.id);
          // Also remove from local selection
          setState(() {
            _selectedPointIds.remove(clickedPoint.id);
          });
        } else {
          debugPrint('[AutomationLane] ERASER: No point found at click position!');
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
      if (clickedPoint != null &&
          _selectedPointIds.contains(clickedPoint.id)) {
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
    // Clear preview
    _previewPoint = null;
    _previewPointId = null;
    widget.onPreviewValue?.call(null);
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

    // Flutter's Transform.translate ALREADY adjusts localPosition to content space
    // DO NOT add scrollOffset - that causes double-transformation!
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
