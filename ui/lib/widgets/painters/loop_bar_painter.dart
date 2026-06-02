import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

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
  final BoojyColors colors;
  final double textScale;

  LoopBarPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.colors,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.textScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Full background - darker for non-loop areas
    final darkBgPaint = Paint()..color = colors.editor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkBgPaint);

    final hasPunch = punchInEnabled || punchOutEnabled;

    if (!loopEnabled && !hasPunch) {
      // Mode 1: No loop, no punch — show hint text
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Drag to create loop',
          style: TextStyle(color: colors.textMuted, fontSize: 10 * textScale),
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
      // Mode 3: Loop + Punch — solid red (lit recordActive)
      fillColor = colors.recordActive;
      borderColor = colors.recordActive.withValues(alpha: 0.8);
    } else if (hasPunch) {
      // Mode 4: Punch only (no loop) — faded red (dim recordActive)
      fillColor = colors.recordActive.withValues(alpha: 0.4);
      borderColor = colors.recordActive.withValues(alpha: 0.53);
    } else {
      // Mode 2: Loop only (no punch) — muted amber (dim warning)
      fillColor = colors.warning.withValues(alpha: 0.35);
      borderColor = colors.warning.withValues(alpha: 0.78);
    }

    // Fill bar
    final centerPaint = Paint()..color = fillColor;
    canvas.drawRect(loopRect, centerPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
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
        punchOutEnabled != oldDelegate.punchOutEnabled ||
        colors != oldDelegate.colors ||
        textScale != oldDelegate.textScale;
  }
}
