import 'package:flutter/material.dart';
import '../../models/clip_automation_data.dart';

/// Custom painter for clip-level automation curves.
/// Similar to TrackAutomationPainter but designed for clip-based automation
/// with loop repetition support.
class ClipAutomationPainter extends CustomPainter {
  final ClipAutomationLane lane;
  final double pixelsPerBeat;
  final double laneHeight;
  final double clipDurationBeats;
  final double loopLengthBeats;
  final bool canRepeat;
  final Color lineColor;
  final Color fillColor;
  final Color pointColor;
  final Color selectedPointColor;
  final Color gridLineColor;
  final Color ghostColor;
  final String? hoveredPointId;
  final String? draggedPointId;
  final int beatsPerBar;
  final Offset? selectionStart;
  final Offset? selectionEnd;
  final Set<String> selectedPointIds;

  ClipAutomationPainter({
    required this.lane,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.clipDurationBeats,
    required this.loopLengthBeats,
    required this.canRepeat,
    required this.lineColor,
    required this.fillColor,
    required this.pointColor,
    required this.selectedPointColor,
    required this.gridLineColor,
    this.ghostColor = const Color(0x40FFFFFF),
    this.hoveredPointId,
    this.draggedPointId,
    this.beatsPerBar = 4,
    this.selectionStart,
    this.selectionEnd,
    this.selectedPointIds = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGridLines(canvas, size);
    _drawAutomationCurve(canvas, size);
    _drawSelectionRectangle(canvas);
    _drawPoints(canvas, size);
  }

  void _drawSelectionRectangle(Canvas canvas) {
    if (selectionStart == null || selectionEnd == null) return;

    final rect = Rect.fromPoints(selectionStart!, selectionEnd!);

    // Fill
    final fillPaint = Paint()
      ..color = const Color(0xFF00BCD4).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = const Color(0xFF00BCD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, borderPaint);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridLineColor
      ..strokeWidth = 0.5;

    // Horizontal grid lines (25%, 50%, 75%)
    for (final frac in [0.25, 0.5, 0.75]) {
      final y = laneHeight * (1 - frac);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines (bars/beats based on zoom)
    final beatStep = _calculateBeatStep();
    for (double beat = 0; beat <= clipDurationBeats; beat += beatStep) {
      final x = beat * pixelsPerBeat;
      final isBarLine = (beat % beatsPerBar).abs() < 0.001;
      gridPaint.strokeWidth = isBarLine ? 1.0 : 0.5;
      gridPaint.color = isBarLine ? gridLineColor : gridLineColor.withValues(alpha: 0.5);
      canvas.drawLine(Offset(x, 0), Offset(x, laneHeight), gridPaint);
    }
  }

  double _calculateBeatStep() {
    // Adjust grid density based on zoom level
    if (pixelsPerBeat < 10) return beatsPerBar.toDouble();
    if (pixelsPerBeat < 25) return 1.0;
    if (pixelsPerBeat < 50) return 0.5;
    return 0.25;
  }

  void _drawAutomationCurve(Canvas canvas, Size size) {
    if (!lane.hasAutomation) {
      _drawDefaultLine(canvas, size);
      return;
    }

    final sorted = lane.sortedPoints;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // Draw first iteration (editable)
    _drawCurveIteration(canvas, sorted, 0, loopLengthBeats, linePaint, fillPaint, false);

    // Draw ghost iterations if looping
    if (canRepeat && clipDurationBeats > loopLengthBeats) {
      final ghostLinePaint = Paint()
        ..color = ghostColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final ghostFillPaint = Paint()
        ..color = ghostColor.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      double offset = loopLengthBeats;
      while (offset < clipDurationBeats) {
        _drawCurveIteration(canvas, sorted, offset, loopLengthBeats, ghostLinePaint, ghostFillPaint, true);
        offset += loopLengthBeats;
      }
    }
  }

  void _drawCurveIteration(
    Canvas canvas,
    List<ClipAutomationPoint> points,
    double offsetBeats,
    double lengthBeats,
    Paint linePaint,
    Paint fillPaint,
    bool isGhost,
  ) {
    if (points.isEmpty) return;

    final path = Path();
    final fillPath = Path();

    // Start from left edge, holding first point's value
    final startX = offsetBeats * pixelsPerBeat;
    final startY = _valueToY(points.first.value);
    path.moveTo(startX, startY);
    fillPath.moveTo(startX, laneHeight);
    fillPath.lineTo(startX, startY);

    // Draw lines to each point
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      // Only draw if within this iteration's bounds
      if (point.time > lengthBeats) break;

      final x = (offsetBeats + point.time) * pixelsPerBeat;
      final y = _valueToY(point.value);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    // Extend to end of iteration, holding last point's value
    final endX = (offsetBeats + lengthBeats).clamp(0.0, clipDurationBeats) * pixelsPerBeat;
    final endY = _valueToY(points.last.value);
    path.lineTo(endX, endY);
    fillPath.lineTo(endX, endY);
    fillPath.lineTo(endX, laneHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  void _drawDefaultLine(Canvas canvas, Size size) {
    final defaultY = _valueToY(lane.parameter.defaultValue);
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed line for default value
    const dashWidth = 4.0;
    const gapWidth = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, defaultY),
        Offset((x + dashWidth).clamp(0, size.width), defaultY),
        paint,
      );
      x += dashWidth + gapWidth;
    }
  }

  void _drawPoints(Canvas canvas, Size size) {
    for (final point in lane.points) {
      // Only draw points within the first loop iteration
      if (point.time > loopLengthBeats) continue;

      final x = point.time * pixelsPerBeat;
      final y = _valueToY(point.value);

      final isHovered = point.id == hoveredPointId;
      final isDragged = point.id == draggedPointId;
      final isSelected = selectedPointIds.contains(point.id);

      // Point size: normal=4, hovered=5.5, selected/dragged=6
      double radius = 4.0;
      if (isHovered) radius = 5.5;
      if (isSelected || isDragged) radius = 6.0;

      // Point color
      Color color = pointColor;
      if (isSelected || isDragged) color = selectedPointColor;

      // Draw point
      final pointPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), radius, pointPaint);

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset(x, y), radius, borderPaint);
    }
  }

  double _valueToY(double value) {
    final param = lane.parameter;
    final normalized = (value - param.minValue) / (param.maxValue - param.minValue);
    return laneHeight * (1 - normalized);
  }

  @override
  bool shouldRepaint(covariant ClipAutomationPainter oldDelegate) {
    return lane != oldDelegate.lane ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        laneHeight != oldDelegate.laneHeight ||
        clipDurationBeats != oldDelegate.clipDurationBeats ||
        loopLengthBeats != oldDelegate.loopLengthBeats ||
        canRepeat != oldDelegate.canRepeat ||
        lineColor != oldDelegate.lineColor ||
        hoveredPointId != oldDelegate.hoveredPointId ||
        draggedPointId != oldDelegate.draggedPointId ||
        selectionStart != oldDelegate.selectionStart ||
        selectionEnd != oldDelegate.selectionEnd ||
        !_setEquals(selectedPointIds, oldDelegate.selectedPointIds);
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
