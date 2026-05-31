import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// Paints the filled equilateral "▲" that doubles as the "A" in the Boojy Audio
/// wordmark. Shared so the top bar, start screen, and settings footer all draw
/// the identical mark — no raster asset, theme-aware via [color].
class BoojyTrianglePainter extends CustomPainter {
  const BoojyTrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(size.width / 2, 0) // apex (top centre)
      ..lineTo(size.width, size.height) // bottom right
      ..lineTo(0, size.height) // bottom left
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BoojyTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The "▲udio" wordmark: a brand-accent triangle ("A") + "udio" in the UI font.
///
/// This is the single source of truth for the treatment shown in the top bar's
/// logo. Reused in the start screen and the settings footer so they can't drift
/// from a stale raster/SVG asset again. Triangle and gap scale with [fontSize].
class BoojyWordmark extends StatelessWidget {
  const BoojyWordmark({
    super.key,
    required this.triangleColor,
    required this.textColor,
    this.fontSize = 24,
  });

  /// Colour of the "▲" (the "A"). Pass the brand accent, or [error] to signal a
  /// failed engine, exactly as the top bar does.
  final Color triangleColor;

  /// Colour of the "udio" text.
  final Color textColor;

  /// Size of the "udio" text; the triangle and gap scale proportionally to keep
  /// the same proportions as the 24px top-bar lockup.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Match the top bar's 24px → Size(22, 19.05) triangle (equilateral, so
    // height = base * √3/2 ≈ base * 0.866) and 2px gap.
    final triWidth = fontSize * (22 / 24);
    final triHeight = triWidth * (19.05 / 22);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(triWidth, triHeight),
          painter: BoojyTrianglePainter(triangleColor),
        ),
        SizedBox(width: fontSize * (2 / 24)),
        Text(
          'udio',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: BT.weightSemiBold,
            color: textColor,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
