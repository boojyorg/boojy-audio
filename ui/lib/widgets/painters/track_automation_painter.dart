import 'package:flutter/material.dart';
import '../../models/track_automation_data.dart';

/// Custom painter for track automation lane (Volume, Pan)
class TrackAutomationPainter extends CustomPainter {
  final TrackAutomationLane lane;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;
  final Color lineColor;
  final Color fillColor;
  final Color pointColor;
  final Color selectedPointColor;
  final Color gridLineColor;
  final Color centerLineColor;
  final String? hoveredPointId;
  final String? draggedPointId;
  final int beatsPerBar;

  TrackAutomationPainter({
    required this.lane,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.totalBeats,
    required this.lineColor,
    required this.fillColor,
    required this.pointColor,
    required this.selectedPointColor,
    required this.gridLineColor,
    this.centerLineColor = const Color(0x40FFFFFF),
    this.hoveredPointId,
    this.draggedPointId,
    this.beatsPerBar = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final param = lane.parameter;
    final minValue = param.minValue;
    final maxValue = param.maxValue;
    final range = maxValue - minValue;

    // Draw grid lines (horizontal)
    _drawGridLines(canvas, size);

    // Draw center line for pan (bipolar parameters)
    if (param.isBipolar) {
      _drawCenterLine(canvas, size, minValue, range);
    }

    // Get sorted points
    final points = lane.sortedPoints;

    if (points.isEmpty) {
      // Draw default value line (dotted)
      final defaultY = _valueToY(param.defaultValue, minValue, range, laneHeight);
      _drawDottedLine(canvas, size, defaultY, lineColor.withValues(alpha: 0.5));
      return;
    }

    // Build path for automation curve
    final path = Path();
    final fillPath = Path();

    // Start from left edge at first point's value
    final firstY = _valueToY(points.first.value, minValue, range, laneHeight);
    path.moveTo(0, firstY);
    fillPath.moveTo(0, laneHeight); // Start fill from bottom
    fillPath.lineTo(0, firstY);

    // Draw line to first point
    final firstX = points.first.time * pixelsPerBeat;
    path.lineTo(firstX, firstY);
    fillPath.lineTo(firstX, firstY);

    // Draw lines between points (linear interpolation)
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      final x1 = p1.time * pixelsPerBeat;
      final y1 = _valueToY(p1.value, minValue, range, laneHeight);
      final x2 = p2.time * pixelsPerBeat;
      final y2 = _valueToY(p2.value, minValue, range, laneHeight);

      // Move to current point (should already be there)
      path.lineTo(x1, y1);
      fillPath.lineTo(x1, y1);

      // Line to next point
      path.lineTo(x2, y2);
      fillPath.lineTo(x2, y2);
    }

    // Extend to right edge at last point's value
    final lastY = _valueToY(points.last.value, minValue, range, laneHeight);
    path.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, lastY);

    // Complete fill path
    fillPath.lineTo(size.width, laneHeight);
    fillPath.close();

    // Draw fill
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Draw points
    for (final point in points) {
      final x = point.time * pixelsPerBeat;
      final y = _valueToY(point.value, minValue, range, laneHeight);

      final isSelected = point.isSelected;
      final isHovered = point.id == hoveredPointId;
      final isDragged = point.id == draggedPointId;

      // Determine point appearance
      double radius;
      Color fill;
      Color border;

      if (isDragged || isSelected) {
        radius = 6.0;
        fill = selectedPointColor;
        border = Colors.white;
      } else if (isHovered) {
        radius = 5.5;
        fill = pointColor;
        border = Colors.white.withValues(alpha: 0.8);
      } else {
        radius = 4.0;
        fill = pointColor;
        border = lineColor;
      }

      // Point circle (fill)
      final pointPaint = Paint()
        ..color = fill
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), radius, pointPaint);

      // Point border
      final borderPaint = Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragged || isSelected ? 2.0 : 1.5;
      canvas.drawCircle(Offset(x, y), radius, borderPaint);
    }
  }

  void _drawGridLines(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridLineColor
      ..strokeWidth = 0.5;

    // Draw 5 horizontal grid lines (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = (laneHeight / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw vertical grid lines matching timeline (bars, beats, subdivisions)
    _drawVerticalGridLines(canvas, size);
  }

  /// Get grid division based on zoom level (matches TimelineGridPainter)
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return beatsPerBar.toDouble(); // Only bars
    if (pixelsPerBeat < 20) return 1.0; // Bars + beats
    if (pixelsPerBeat < 40) return 0.5; // + half beats
    if (pixelsPerBeat < 80) return 0.25; // + quarter beats
    return 0.125; // + eighth beats
  }

  void _drawVerticalGridLines(Canvas canvas, Size size) {
    final gridDivision = _getGridDivision();

    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      // Determine line type based on beat position
      final isBar = (beat % beatsPerBar).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;
      final isHalfBeat = (beat % 0.5).abs() < 0.001;

      Color lineColor;
      double strokeWidth;

      if (isBar) {
        lineColor = const Color(0xFF505050);
        strokeWidth = 2.0;
      } else if (isBeat) {
        lineColor = const Color(0xFF404040);
        strokeWidth = 1.0;
      } else if (isHalfBeat) {
        lineColor = const Color(0xFF363636);
        strokeWidth = 0.5;
      } else {
        lineColor = const Color(0xFF303030);
        strokeWidth = 0.5;
      }

      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = strokeWidth;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawCenterLine(Canvas canvas, Size size, double minValue, double range) {
    final centerValue = (minValue + lane.parameter.maxValue) / 2;
    final centerY = _valueToY(centerValue, minValue, range, laneHeight);

    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);
  }

  void _drawDottedLine(Canvas canvas, Size size, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset((startX + dashWidth).clamp(0, size.width), y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  double _valueToY(double value, double minValue, double range, double height) {
    // Invert Y so higher values are at top
    final normalized = (value - minValue) / range;
    return height * (1 - normalized);
  }

  /// Convert Y position to value
  static double yToValue(
      double y, double laneHeight, double minValue, double maxValue) {
    final range = maxValue - minValue;
    final normalized = 1 - (y / laneHeight);
    return minValue + (normalized * range);
  }

  @override
  bool shouldRepaint(TrackAutomationPainter oldDelegate) {
    return lane != oldDelegate.lane ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        laneHeight != oldDelegate.laneHeight ||
        totalBeats != oldDelegate.totalBeats ||
        lineColor != oldDelegate.lineColor ||
        fillColor != oldDelegate.fillColor ||
        hoveredPointId != oldDelegate.hoveredPointId ||
        draggedPointId != oldDelegate.draggedPointId ||
        beatsPerBar != oldDelegate.beatsPerBar;
  }
}
