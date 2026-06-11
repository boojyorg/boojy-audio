import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Paints the filled equilateral "▲" that doubles as the "A" in the Boojy Audio
/// wordmark. Kept code-drawn (not part of the raster text assets) so it stays
/// theme-aware — the top bar tints it with the accent, or [error] red when the
/// engine fails to start.
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

/// The brand text is raster art (the lettering is not Inter, so it can't be
/// faithfully reproduced with Text). Black originals were exported from the
/// design source; the *_white.png twins are script-recolored copies
/// (near-black → white) that keep the grey i/j tittles and the amber "o"
/// untouched. Picks per theme: light text on a dark theme → the white asset.
/// [mark] is 'boojy' or 'udio'. Shared with the top bar's logo.
String boojyTextAsset(BuildContext context, String mark) {
  final light = context.colors.textPrimary.computeLuminance() > 0.5;
  return 'assets/images/${mark}_text_${light ? 'white' : 'black'}.png';
}

// Proportions measured from the brand lockup (boojy_audio_text_Audio_v2.png,
// which contains the udio art at 1:1): triangle 268×239 sits bottom-aligned
// with the letters, 18px gap; the trimmed udio asset is 670×266 with the
// letters 241 tall (the i-tittle accounts for the top 25px).
const double _kTriW = 268, _kTriH = 239, _kGap = 18;
const double _kUdioH = 266;

/// The "▲udio" wordmark: a brand-accent code-drawn triangle ("A") + the brand
/// "udio" raster art.
///
/// [fontSize] keeps the old Inter-based sizing anchor (24 → the top bar's
/// 22×19 triangle) so existing call sites keep their visual size. To dim the
/// whole mark (e.g. the settings footer), wrap it in [Opacity] — raster text
/// can't take an arbitrary colour the way the old [Text] could.
class BoojyWordmark extends StatelessWidget {
  const BoojyWordmark({
    super.key,
    required this.triangleColor,
    this.fontSize = 24,
  });

  /// Colour of the "▲" (the "A"). Pass the brand accent, or [error] to signal
  /// a failed engine, exactly as the top bar does.
  final Color triangleColor;

  /// Nominal size; the triangle scales as fontSize 24 → 19px tall, matching
  /// the pre-raster lockup, and the udio art scales with the triangle.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final triHeight = fontSize * (19.05 / 24);
    final triWidth = triHeight * (_kTriW / _kTriH);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CustomPaint(
          size: Size(triWidth, triHeight),
          painter: BoojyTrianglePainter(triangleColor),
        ),
        SizedBox(width: triHeight * (_kGap / _kTriH)),
        Image.asset(
          boojyTextAsset(context, 'udio'),
          height: triHeight * (_kUdioH / _kTriH),
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}

/// The stacked "Boojy / ▲udio" brand lockup, shown on the start screen and
/// the crash-recovery dialog; [scale] shrinks the whole lockup proportionally.
///
/// "Boojy" is the brand raster art (amber "o", grey j-tittle baked in); the
/// "▲udio" line reuses [BoojyWordmark]. Both pick black/white text per theme,
/// so the lettering can't vanish against dark modals the way the original
/// dark-only PNGs did (H13).
class BoojyWordmarkLockup extends StatelessWidget {
  const BoojyWordmarkLockup({super.key, this.scale = 1.0});

  /// Multiplies every dimension (1.0 = the 46px/32px start-screen lockup).
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nudged right so the B's stem optically aligns with the ▲'s left
        // slope below it (Tyr-tuned).
        Padding(
          padding: EdgeInsets.only(left: 4 * scale),
          child: Image.asset(
            boojyTextAsset(context, 'boojy'),
            height: 47 * scale,
            filterQuality: FilterQuality.medium,
          ),
        ),
        SizedBox(height: 6 * scale),
        BoojyWordmark(
          triangleColor: context.colors.accent,
          fontSize: 40 * scale,
        ),
      ],
    );
  }
}
