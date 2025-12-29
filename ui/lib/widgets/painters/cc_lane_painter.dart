import 'package:flutter/material.dart';
import '../../models/midi_cc_data.dart';

/// Custom painter for MIDI CC automation lane
class CCLanePainter extends CustomPainter {
  final MidiCCLane lane;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;
  final Color lineColor;
  final Color fillColor;
  final Color pointColor;
  final Color selectedPointColor;
  final Color gridLineColor;
  final Color centerLineColor;

  CCLanePainter({
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ccType = lane.ccType;
    final minValue = ccType.minValue;
    final maxValue = ccType.maxValue;
    final range = maxValue - minValue;

    // Draw grid lines (horizontal)
    _drawGridLines(canvas, size, minValue, maxValue);

    // Draw center line for pan and pitch bend
    if (ccType == MidiCCType.pan || ccType == MidiCCType.pitchBend) {
      _drawCenterLine(canvas, size, minValue, maxValue);
    }

    // Get sorted points
    final points = lane.sortedPoints;

    if (points.isEmpty) {
      // Draw default value line
      final centerY = _valueToY(ccType.centerValue, minValue, range, laneHeight);
      final linePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);
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

      // Point circle
      final pointPaint = Paint()
        ..color = point.isSelected ? selectedPointColor : pointColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), point.isSelected ? 6 : 4, pointPaint);

      // Point border
      final borderPaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(x, y), point.isSelected ? 6 : 4, borderPaint);
    }
  }

  void _drawGridLines(Canvas canvas, Size size, int minValue, int maxValue) {
    final gridPaint = Paint()
      ..color = gridLineColor
      ..strokeWidth = 0.5;

    // Draw 5 horizontal grid lines (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = (laneHeight / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawCenterLine(Canvas canvas, Size size, int minValue, int maxValue) {
    final range = maxValue - minValue;
    final centerValue = (minValue + maxValue) ~/ 2;
    final centerY = _valueToY(centerValue, minValue, range, laneHeight);

    final centerPaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);
  }

  double _valueToY(int value, int minValue, int range, double height) {
    // Invert Y so higher values are at top
    final normalized = (value - minValue) / range;
    return height * (1 - normalized);
  }

  @override
  bool shouldRepaint(CCLanePainter oldDelegate) {
    return lane != oldDelegate.lane ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        laneHeight != oldDelegate.laneHeight ||
        totalBeats != oldDelegate.totalBeats ||
        lineColor != oldDelegate.lineColor ||
        fillColor != oldDelegate.fillColor;
  }
}
