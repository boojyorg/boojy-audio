import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Logic Pro-style minimal pan knob
/// - Thin circular ring base (no fill)
/// - Arc indicator from 12 o'clock
/// - Orange arc for left pan, red arc for right pan
/// - Value text centered inside (empty at center)
class PanKnob extends StatelessWidget {
  final double pan; // -1.0 to 1.0
  final Function(double)? onChanged;
  final double size;

  const PanKnob({
    super.key,
    required this.pan,
    this.onChanged,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (onChanged == null) return;
          // Drag up = pan right, drag down = pan left
          // Sensitivity: 200px drag = full range
          final delta = -details.delta.dy / 200.0;
          final newPan = (pan + delta).clamp(-1.0, 1.0);
          onChanged!(newPan);
        },
        onDoubleTap: () {
          // Reset to center on double-tap
          onChanged?.call(0.0);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: CustomPaint(
            size: Size(size, size),
            painter: _PanKnobPainter(pan: pan),
          ),
        ),
      ),
    );
  }
}

class _PanKnobPainter extends CustomPainter {
  final double pan; // -1.0 to 1.0

  _PanKnobPainter({required this.pan});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Reduce padding to make arc fill more of the space (was -2, now -1)
    final radius = size.width / 2 - 1;

    // Arc angles
    const activeStartAngle = 135 * math.pi / 180; // 7 o'clock position
    const activeSweepAngle = 270 * math.pi / 180; // 270° sweep to 5 o'clock
    const bottomStartAngle = 45 * math.pi / 180; // 5 o'clock position
    const bottomSweepAngle = 90 * math.pi / 180; // 90° sweep to 7 o'clock

    // 1. Draw darker bottom arc (5 o'clock to 7 o'clock) - inactive zone
    final bottomArcPaint = Paint()
      ..color = const Color(0xFF3A3A3A) // Darker grey for inactive zone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      bottomStartAngle,
      bottomSweepAngle,
      false,
      bottomArcPaint,
    );

    // 2. Draw grey active zone arc (7 o'clock to 5 o'clock)
    final baseArcPaint = Paint()
      ..color = const Color(0xFF5A5A5A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      activeStartAngle,
      activeSweepAngle,
      false,
      baseArcPaint,
    );

    // 3. Draw colored position arc (only if not centered)
    if (pan.abs() > 0.02) {
      // Orange for left, red for right
      final arcColor = pan < 0
          ? const Color(0xFFFF9800) // Orange for left
          : const Color(0xFFF44336); // Red for right

      final positionArcPaint = Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      // Arc from 12 o'clock position (-90° in radians)
      // pan -1.0 = -135° sweep (counter-clockwise to 7 o'clock)
      // pan +1.0 = +135° sweep (clockwise to 5 o'clock)
      final panSweepAngle = pan * 135 * math.pi / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // Start at 12 o'clock
        panSweepAngle,
        false,
        positionArcPaint,
      );
    }

    // 4. Draw centered value text (empty if centered)
    if (pan.abs() > 0.02) {
      final label = pan < 0
          ? 'L${(pan.abs() * 50).round()}'
          : 'R${(pan * 50).round()}';

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: const Color(0xFFE0E0E0),
            fontSize: size.width * 0.34, // Larger text (was 0.28)
            fontWeight: FontWeight.w600, // Bolder (was w500)
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        center - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_PanKnobPainter oldDelegate) {
    return oldDelegate.pan != pan;
  }
}
