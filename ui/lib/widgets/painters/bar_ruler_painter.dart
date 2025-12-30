import 'package:flutter/material.dart';

/// Painter for bar number ruler (FL Studio style)
class BarRulerPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final double playheadPosition; // in beats

  // Loop region parameters
  final bool loopEnabled;
  final double loopStart; // Loop start in beats
  final double loopEnd; // Loop end in beats

  BarRulerPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.playheadPosition,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw bar numbers (every 4 beats)
    final totalBars = (totalBeats / 4).ceil();
    for (int bar = 0; bar < totalBars; bar++) {
      final barStartBeat = bar * 4.0;
      final x = barStartBeat * pixelsPerBeat;

      // Bar number
      final barNumber = bar + 1; // 1-indexed
      textPainter.text = TextSpan(
        text: "$barNumber",
        style: const TextStyle(
          color: Color(0xFFE0E0E0), // Light text on dark background
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

      textPainter.layout();
      // Draw bar number at LEFT edge of bar (not centered)
      textPainter.paint(
        canvas,
        Offset(x + 4, 7), // 4px padding from left edge
      );

      // Draw beat ticks
      for (int beat = 0; beat < 4; beat++) {
        final beatX = (barStartBeat + beat) * pixelsPerBeat;
        final tickPaint = Paint()
          ..color = const Color(0xFF606060) // Dark grey ticks
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(beatX, size.height - 5),
          Offset(beatX, size.height),
          tickPaint,
        );
      }
    }

    // Draw loop region highlight in ruler
    if (loopEnabled) {
      final loopStartX = loopStart * pixelsPerBeat;
      final loopEndX = loopEnd * pixelsPerBeat;

      // Loop region background highlight (subtle orange tint)
      final loopRegionPaint = Paint()
        ..color = const Color(0x30FF9800); // 20% orange

      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopEndX - loopStartX, size.height),
        loopRegionPaint,
      );

      // Start marker bracket
      final startMarkerPaint = Paint()
        ..color = const Color(0xFFFF9800) // Orange
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      // Draw [ shape for start marker
      final startPath = Path()
        ..moveTo(loopStartX + 6, 2)
        ..lineTo(loopStartX + 2, 2)
        ..lineTo(loopStartX + 2, size.height - 2)
        ..lineTo(loopStartX + 6, size.height - 2);
      canvas.drawPath(startPath, startMarkerPaint);

      // End marker bracket
      // Draw ] shape for end marker
      final endPath = Path()
        ..moveTo(loopEndX - 6, 2)
        ..lineTo(loopEndX - 2, 2)
        ..lineTo(loopEndX - 2, size.height - 2)
        ..lineTo(loopEndX - 6, size.height - 2);
      canvas.drawPath(endPath, startMarkerPaint);
    }

    // Draw playhead triangle (orange)
    if (playheadPosition >= 0 && playheadPosition <= totalBeats) {
      final playheadX = playheadPosition * pixelsPerBeat;

      final trianglePath = Path()
        ..moveTo(playheadX, size.height - 2)
        ..lineTo(playheadX - 8, 0)
        ..lineTo(playheadX + 8, 0)
        ..close();

      final playheadPaint = Paint()
        ..color = const Color(0xFFFF9800) // Orange
        ..style = PaintingStyle.fill;

      canvas.drawPath(trianglePath, playheadPaint);

      // Playhead border for definition
      final borderPaint = Paint()
        ..color = const Color(0xFFE65100) // Darker orange border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawPath(trianglePath, borderPaint);
    }
  }

  @override
  bool shouldRepaint(BarRulerPainter oldDelegate) {
    return playheadPosition != oldDelegate.playheadPosition ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd;
  }
}
