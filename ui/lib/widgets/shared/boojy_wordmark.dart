import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
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

/// The stacked "Boojy / ▲udio" brand lockup.
///
/// Rebuilt in code rather than served from PNGs: the old `boojy-logo.png` /
/// `boojy_audio_text.png` baked the lettering in near-black, so it disappeared
/// against dark modals. "Boojy" is white with the brand amber dot for the
/// second "o"; "▲udio" reuses [BoojyWordmark] — the same treatment as the live
/// top-bar logo — so the two can never drift. Shown on the start screen and
/// the crash-recovery dialog; [scale] shrinks the whole lockup proportionally.
class BoojyWordmarkLockup extends StatelessWidget {
  const BoojyWordmarkLockup({super.key, this.scale = 1.0});

  /// Multiplies every dimension (1.0 = the 46px/32px start-screen lockup).
  final double scale;

  // The warm amber of the logo dot (sampled from the original asset). Not a
  // theme token — it's a fixed brand colour, like the accent blue.
  static const Color _brandAmber = Color(0xFFFBB034);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 46 * scale,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: -1 * scale,
              height: 1.0,
            ),
            children: [
              const TextSpan(text: 'Bo'),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 1.5 * scale),
                  child: Container(
                    width: 24 * scale,
                    height: 24 * scale,
                    decoration: const BoxDecoration(
                      color: _brandAmber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const TextSpan(text: 'jy'),
            ],
          ),
        ),
        SizedBox(height: 6 * scale),
        BoojyWordmark(
          triangleColor: colors.accent,
          textColor: colors.textPrimary,
          fontSize: 32 * scale,
        ),
      ],
    );
  }
}
