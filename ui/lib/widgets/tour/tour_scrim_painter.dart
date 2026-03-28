import 'package:flutter/material.dart';

/// CustomPainter that draws a semi-transparent scrim with a spotlight cutout
/// around the tour target widget.
class TourScrimPainter extends CustomPainter {
  final Rect? spotlightRect;
  final double borderRadius;
  final Color scrimColor;
  final Color borderColor;

  TourScrimPainter({
    this.spotlightRect,
    this.borderRadius = 8.0,
    this.scrimColor = const Color(0x99000000), // 60% black
    this.borderColor = const Color(0x8040B3E8), // 50% accent
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (spotlightRect != null) {
      // Cutout path with rounded corners
      final spotlight = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            spotlightRect!,
            Radius.circular(borderRadius),
          ),
        );

      // Combine: full screen minus spotlight
      final scrimPath = Path.combine(
        PathOperation.difference,
        fullScreen,
        spotlight,
      );

      // Draw scrim with cutout
      canvas.drawPath(scrimPath, Paint()..color = scrimColor);

      // Draw accent border around cutout
      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlightRect!, Radius.circular(borderRadius)),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      // No target — full scrim, no cutout
      canvas.drawPath(fullScreen, Paint()..color = scrimColor);
    }
  }

  @override
  bool shouldRepaint(covariant TourScrimPainter oldDelegate) {
    return oldDelegate.spotlightRect != oldDelegate.spotlightRect ||
        oldDelegate.scrimColor != scrimColor;
  }
}
