import 'package:flutter/material.dart';

/// Painter for timeline grid lines (beat-based with zoom-dependent visibility)
class TimelineGridPainter extends CustomPainter {
  final double pixelsPerBeat;

  TimelineGridPainter({
    required this.pixelsPerBeat,
  });

  /// Get the smallest grid subdivision to show based on zoom level
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return 4.0;     // Only bars (every 4 beats)
    if (pixelsPerBeat < 20) return 1.0;     // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;     // + half beats
    if (pixelsPerBeat < 80) return 0.25;    // + quarter beats
    return 0.125;                            // + eighth beats
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Beat-based measurements (tempo-independent)
    final gridDivision = _getGridDivision();

    // Calculate total beats to draw (extend to fill width)
    final totalBeats = (size.width / pixelsPerBeat).ceil() + 4;

    final paint = Paint()..style = PaintingStyle.stroke;

    // Draw grid lines based on beat subdivisions
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      // Determine line style based on beat position
      final isBar = (beat % 4.0).abs() < 0.001;  // Every 4 beats = bar
      final isBeat = (beat % 1.0).abs() < 0.001; // Whole beats
      final isHalfBeat = (beat % 0.5).abs() < 0.001; // Half beats

      if (isBar) {
        // Bar lines - thickest and brightest
        paint.color = const Color(0xFF505050);
        paint.strokeWidth = 2.0;
      } else if (isBeat) {
        // Beat lines - medium
        paint.color = const Color(0xFF404040);
        paint.strokeWidth = 1.0;
      } else if (isHalfBeat) {
        // Half beat lines - thin
        paint.color = const Color(0xFF363636);
        paint.strokeWidth = 0.5;
      } else {
        // Subdivision lines - thinnest
        paint.color = const Color(0xFF303030);
        paint.strokeWidth = 0.5;
      }

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(TimelineGridPainter oldDelegate) {
    return oldDelegate.pixelsPerBeat != pixelsPerBeat;
  }
}
