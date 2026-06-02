import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/tokens.dart';

/// Painter for bar number ruler (displays bar numbers and playhead).
/// Loop rendering is now handled by LoopBarPainter in a separate row.
class BarRulerPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final double playheadPosition; // in beats
  final int beatsPerBar;
  final BoojyColors colors;
  final double textScale;

  BarRulerPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.colors,
    this.playheadPosition = 0.0,
    this.beatsPerBar = 4,
    this.textScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw bar numbers (every beatsPerBar beats)
    final totalBars = (totalBeats / beatsPerBar).ceil();
    for (int bar = 0; bar < totalBars; bar++) {
      final barStartBeat = bar * beatsPerBar.toDouble();
      final x = barStartBeat * pixelsPerBeat;

      // Bar number
      final barNumber = bar + 1; // 1-indexed
      textPainter.text = TextSpan(
        text: '$barNumber',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: BT.fontBody * textScale,
          fontWeight: BT.weightSemiBold,
        ),
      );

      textPainter.layout();
      // Draw bar number at LEFT edge of bar (not centered)
      textPainter.paint(
        canvas,
        Offset(x + 4, 7), // 4px padding from left edge
      );

      // Draw beat ticks
      for (int beat = 0; beat < beatsPerBar; beat++) {
        final beatX = (barStartBeat + beat) * pixelsPerBeat;
        final tickPaint = Paint()
          ..color = colors.hover
          ..strokeWidth = 1;

        canvas.drawLine(
          Offset(beatX, size.height - 5),
          Offset(beatX, size.height),
          tickPaint,
        );
      }
    }

    // Draw playhead triangle (warning/orange)
    if (playheadPosition >= 0 && playheadPosition <= totalBeats) {
      final playheadX = playheadPosition * pixelsPerBeat;

      final trianglePath = Path()
        ..moveTo(playheadX, size.height - 2)
        ..lineTo(playheadX - 8, 0)
        ..lineTo(playheadX + 8, 0)
        ..close();

      final playheadPaint = Paint()
        ..color = colors.warning
        ..style = PaintingStyle.fill;

      canvas.drawPath(trianglePath, playheadPaint);

      // Playhead border for definition
      final borderPaint = Paint()
        ..color = colors.warning.withValues(alpha: 0.7)
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
        beatsPerBar != oldDelegate.beatsPerBar ||
        colors != oldDelegate.colors ||
        textScale != oldDelegate.textScale;
  }
}
