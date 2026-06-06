import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/theme_extension.dart';

/// Capsule-style slider matching track mixer fader appearance.
/// Has a pill-shaped track with a circular handle.
class CapsuleSlider extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final Function(double)? onChanged;
  final VoidCallback? onDoubleTap;

  /// Fired once when an edit gesture begins (drag-start, or tap-down for a
  /// click). Lets callers coalesce a whole drag into a single undo step by
  /// snapshotting the pre-gesture value here.
  final VoidCallback? onChangeStart;

  /// Fired once when an edit gesture ends (drag-end/cancel, or tap-up). Note:
  /// when a tap turns into a drag the recognizer fires onTapCancel (handled
  /// silently) followed by onHorizontalDragStart, so a drag stays one gesture.
  final VoidCallback? onChangeEnd;

  const CapsuleSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.onDoubleTap,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTap: onDoubleTap,
          onHorizontalDragStart: (_) => onChangeStart?.call(),
          onHorizontalDragUpdate: (details) {
            if (onChanged == null) return;
            final sliderValue =
                (details.localPosition.dx / constraints.maxWidth).clamp(
                  0.0,
                  1.0,
                );
            onChanged!(sliderValue);
          },
          onHorizontalDragEnd: (_) => onChangeEnd?.call(),
          onHorizontalDragCancel: () => onChangeEnd?.call(),
          onTapDown: (details) {
            if (onChanged == null) return;
            onChangeStart?.call();
            final sliderValue =
                (details.localPosition.dx / constraints.maxWidth).clamp(
                  0.0,
                  1.0,
                );
            onChanged!(sliderValue);
          },
          onTapUp: (_) => onChangeEnd?.call(),
          // A tap that becomes a drag cancels here; the drag-start that follows
          // re-opens the same gesture, so we deliberately do NOT end it.
          onTapCancel: () {},
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: CapsulePainter(
                sliderValue: value,
                colors: context.colors,
              ),
            ),
          ),
        );
      },
    );
  }
}

class CapsulePainter extends CustomPainter {
  final double sliderValue; // 0.0 to 1.0
  final BoojyColors colors;

  CapsulePainter({required this.sliderValue, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final capsuleRadius = size.height / 2;
    final capsuleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(capsuleRadius),
    );

    // Draw capsule background
    final bgPaint = Paint()
      ..color = colors.darkest
      ..style = PaintingStyle.fill;
    canvas.drawRRect(capsuleRect, bgPaint);

    // Draw capsule border
    final borderPaint = Paint()
      ..color = colors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(capsuleRect, borderPaint);

    // Draw handle/thumb
    final handleRadius = size.height / 2 - 1;
    final usableWidth = size.width - handleRadius * 2;
    final handleX = handleRadius + sliderValue * usableWidth;
    final handleY = size.height / 2;

    // Draw semi-transparent grey circle (Logic Pro style)
    final handlePaint = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(handleX, handleY), handleRadius, handlePaint);

    // Draw subtle border on handle
    final handleBorderPaint = Paint()
      ..color = colors.textSecondary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
      Offset(handleX, handleY),
      handleRadius,
      handleBorderPaint,
    );
  }

  @override
  bool shouldRepaint(CapsulePainter oldDelegate) {
    return oldDelegate.sliderValue != sliderValue ||
        oldDelegate.colors != colors;
  }
}
