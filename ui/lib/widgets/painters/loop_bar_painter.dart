import 'package:flutter/material.dart';

/// Painter for the dedicated loop bar row.
/// Renders the loop region with draggable markers in Ableton style.
class LoopBarPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;

  LoopBarPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background - slightly darker than bar ruler
    final bgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw subtle beat markers for reference
    final beatMarkPaint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..strokeWidth = 1;

    final totalBars = (totalBeats / 4).ceil();
    for (int bar = 0; bar < totalBars; bar++) {
      final x = bar * 4.0 * pixelsPerBeat;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), beatMarkPaint);
    }

    if (!loopEnabled) {
      // Draw hint text when no loop
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'Drag to create loop',
          style: TextStyle(
            color: Color(0xFF505050),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(10, (size.height - textPainter.height) / 2),
      );
      return;
    }

    final loopStartX = loopStart * pixelsPerBeat;
    final loopEndX = loopEnd * pixelsPerBeat;
    final loopWidth = loopEndX - loopStartX;

    // Loop region background
    final loopBgPaint = Paint()..color = const Color(0x50FF9800);
    canvas.drawRect(
      Rect.fromLTWH(loopStartX, 2, loopWidth, size.height - 4),
      loopBgPaint,
    );

    // Loop region border
    final loopBorderPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTWH(loopStartX, 2, loopWidth, size.height - 4),
      loopBorderPaint,
    );

    // Start handle - triangle pointing right ▶
    final handlePaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.fill;

    final startTriangle = Path()
      ..moveTo(loopStartX + 2, 4)
      ..lineTo(loopStartX + 10, size.height / 2)
      ..lineTo(loopStartX + 2, size.height - 4)
      ..close();
    canvas.drawPath(startTriangle, handlePaint);

    // End handle - triangle pointing left ◀
    final endTriangle = Path()
      ..moveTo(loopEndX - 2, 4)
      ..lineTo(loopEndX - 10, size.height / 2)
      ..lineTo(loopEndX - 2, size.height - 4)
      ..close();
    canvas.drawPath(endTriangle, handlePaint);

    // Center bar connecting the markers (like ◀══════▶)
    final barPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..strokeWidth = 2;

    if (loopWidth > 24) {
      canvas.drawLine(
        Offset(loopStartX + 12, size.height / 2),
        Offset(loopEndX - 12, size.height / 2),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(LoopBarPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd;
  }
}
