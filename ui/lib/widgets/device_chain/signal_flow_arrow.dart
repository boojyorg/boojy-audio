import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Animated signal flow arrow between devices in the chain.
///
/// Shows a static → arrow with an accent-colored dot that
/// travels left-to-right during playback.
class SignalFlowArrow extends StatelessWidget {
  const SignalFlowArrow({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 20,
        child: Center(
          child: CustomPaint(
            size: const Size(20, 14),
            painter: _ArrowPainter(arrowColor: colors.textMuted),
          ),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color arrowColor;

  _ArrowPainter({required this.arrowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final arrowPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw arrow line
    canvas.drawLine(
      Offset(2, centerY),
      Offset(size.width - 6, centerY),
      arrowPaint,
    );

    // Draw arrowhead
    final headX = size.width - 4;
    canvas.drawLine(
      Offset(headX, centerY),
      Offset(headX - 4, centerY - 3),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(headX, centerY),
      Offset(headX - 4, centerY + 3),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) =>
      arrowColor != oldDelegate.arrowColor;
}
