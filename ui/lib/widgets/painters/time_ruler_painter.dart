import 'package:flutter/material.dart';

/// Painter for the time ruler (bar numbers with beat subdivisions)
class TimeRulerPainter extends CustomPainter {
  final double pixelsPerBeat;
  final bool loopPlaybackEnabled;
  final double loopStartBeats;
  final double loopEndBeats;

  // Loop region color (orange per spec #F97316)
  static const Color loopRegionColor = Color(0xFFF97316);

  TimeRulerPainter({
    required this.pixelsPerBeat,
    this.loopPlaybackEnabled = false,
    this.loopStartBeats = 0.0,
    this.loopEndBeats = 4.0,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    return 0.25;                             // + quarter beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw loop region first (behind everything else)
    if (loopPlaybackEnabled && loopEndBeats > loopStartBeats) {
      final loopStartX = loopStartBeats * pixelsPerBeat;
      final loopEndX = loopEndBeats * pixelsPerBeat;

      // Draw loop region background
      final loopPaint = Paint()
        ..color = loopRegionColor.withValues(alpha: 0.2);
      canvas.drawRect(
        Rect.fromLTRB(loopStartX, 0, loopEndX, size.height),
        loopPaint,
      );

      // Draw loop region top bar (thicker, more visible)
      final loopBarPaint = Paint()
        ..color = loopRegionColor
        ..strokeWidth = 3;
      canvas.drawLine(
        Offset(loopStartX, 2),
        Offset(loopEndX, 2),
        loopBarPaint,
      );

      // Draw loop start bracket
      final bracketPaint = Paint()
        ..color = loopRegionColor
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(loopStartX, 0),
        Offset(loopStartX, size.height),
        bracketPaint,
      );
      // Left bracket top corner
      canvas.drawLine(
        Offset(loopStartX, 2),
        Offset(loopStartX + 8, 2),
        bracketPaint,
      );

      // Draw loop end bracket
      canvas.drawLine(
        Offset(loopEndX, 0),
        Offset(loopEndX, size.height),
        bracketPaint,
      );
      // Right bracket top corner
      canvas.drawLine(
        Offset(loopEndX - 8, 2),
        Offset(loopEndX, 2),
        bracketPaint,
      );
    }

    // Beat-based measurements (tempo-independent)
    final gridDivision = _getGridDivision();

    // Calculate total beats to draw
    final totalBeats = (size.width / pixelsPerBeat).ceil() + 4;

    final paint = Paint()
      ..color = const Color(0xFF3a3a3a)
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    // Draw markers based on beat subdivisions
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      // Determine tick style based on beat position
      final isBar = (beat % 4.0).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

      double tickHeight;
      if (isBar) {
        tickHeight = 15.0;
        paint.strokeWidth = 1.5;
      } else if (isBeat) {
        tickHeight = 10.0;
        paint.strokeWidth = 1.0;
      } else {
        tickHeight = 6.0;
        paint.strokeWidth = 0.5;
      }

      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        paint,
      );

      // Draw bar numbers at bar lines
      if (isBar) {
        final barNumber = (beat / 4.0).round() + 1; // Bars are 1-indexed

        textPainter.text = TextSpan(
          text: '$barNumber',
          style: const TextStyle(
            color: Color(0xFF9E9E9E),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );

        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 2),
        );
      } else if (isBeat && pixelsPerBeat >= 30) {
        // Show beat subdivisions (1.2, 1.3, 1.4) when zoomed in enough
        final barNumber = (beat / 4.0).floor() + 1;
        final beatInBar = ((beat % 4.0) + 1).round();

        if (beatInBar > 1) {
          textPainter.text = TextSpan(
            text: '$barNumber.$beatInBar',
            style: const TextStyle(
              color: Color(0xFF707070),
              fontSize: 9,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          );

          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(x - textPainter.width / 2, 4),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return oldDelegate.pixelsPerBeat != pixelsPerBeat ||
        oldDelegate.loopPlaybackEnabled != loopPlaybackEnabled ||
        oldDelegate.loopStartBeats != loopStartBeats ||
        oldDelegate.loopEndBeats != loopEndBeats;
  }
}
