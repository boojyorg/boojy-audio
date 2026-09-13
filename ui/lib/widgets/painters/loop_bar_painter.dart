import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Painter for the dedicated loop bar row.
/// Renders a solid amber bar for the loop region, or a grey hint when loop is
/// off.
class LoopBarPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final BoojyColors colors;
  final double textScale;

  LoopBarPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.colors,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.textScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Full background - darker for non-loop areas
    final darkBgPaint = Paint()..color = colors.editor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkBgPaint);

    if (!loopEnabled) {
      // Loop off — show hint text
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

    // Loop on — muted amber (dim warning)
    final fillColor = colors.warning.withValues(alpha: 0.35);
    final borderColor = colors.warning.withValues(alpha: 0.78);

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
        colors != oldDelegate.colors ||
        textScale != oldDelegate.textScale;
  }
}
