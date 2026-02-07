import 'package:flutter/material.dart';

/// Painter for the dedicated loop bar row.
/// Renders a solid bar for the loop/punch region with 4-mode color scheme:
///   - Loop only (no punch): orange
///   - Loop + punch: solid red
///   - Punch only (no loop): faded red
///   - Neither: grey hint text
class LoopBarPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final bool punchInEnabled;
  final bool punchOutEnabled;

  LoopBarPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Full background - darker for non-loop areas
    final darkBgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkBgPaint);

    final hasPunch = punchInEnabled || punchOutEnabled;

    if (!loopEnabled && !hasPunch) {
      // Mode 1: No loop, no punch — show hint text
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
    final loopRect = Rect.fromLTWH(loopStartX, 0, loopWidth, size.height);

    // Determine bar colors based on mode
    Color fillColor;
    Color borderColor;

    if (hasPunch && loopEnabled) {
      // Mode 3: Loop + Punch — solid red
      fillColor = const Color(0xFFAA2222);
      borderColor = const Color(0xFFCC3333);
    } else if (hasPunch) {
      // Mode 4: Punch only (no loop) — faded red
      fillColor = const Color(0x66AA2222);
      borderColor = const Color(0x88CC3333);
    } else {
      // Mode 2: Loop only (no punch) — orange
      fillColor = const Color(0xFFB36800);
      borderColor = const Color(0xFFFF9800);
    }

    // Fill bar
    final centerPaint = Paint()..color = fillColor;
    canvas.drawRect(loopRect, centerPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(loopRect, borderPaint);
  }

  @override
  bool shouldRepaint(LoopBarPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd ||
        punchInEnabled != oldDelegate.punchInEnabled ||
        punchOutEnabled != oldDelegate.punchOutEnabled;
  }
}
