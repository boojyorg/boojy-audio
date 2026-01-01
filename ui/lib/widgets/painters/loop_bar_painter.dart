import 'package:flutter/material.dart';

/// Painter for the dedicated loop bar row.
/// Renders a simple solid bar for the loop region.
/// Non-loop areas are darker (~70% brightness).
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
    // Full background - darker for non-loop areas
    final darkBgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkBgPaint);

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

    // Loop region - solid colored bar (full height, slight padding)
    final loopPaint = Paint()..color = const Color(0xFFFF9800);
    canvas.drawRect(
      Rect.fromLTWH(loopStartX, 4, loopWidth, size.height - 8),
      loopPaint,
    );
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
