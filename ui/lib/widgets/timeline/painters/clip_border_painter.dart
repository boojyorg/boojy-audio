import 'package:flutter/material.dart';

/// Painter for clip border with integrated loop boundary notches.
class ClipBorderPainter extends CustomPainter {
  final Color borderColor;
  final Color trackColor;
  final double borderWidth;
  final double cornerRadius;
  final double headerHeight;
  final List<double> loopBoundaryXPositions;
  final double notchRadius;

  ClipBorderPainter({
    required this.borderColor,
    required this.trackColor,
    required this.borderWidth,
    required this.cornerRadius,
    required this.headerHeight,
    required this.loopBoundaryXPositions,
    this.notchRadius = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildClipPath(size, cornerRadius, notchRadius, loopBoundaryXPositions);

    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);

    // Draw vertical lines at loop boundaries (from header bottom to bottom notch tip)
    if (loopBoundaryXPositions.isNotEmpty) {
      final linePaint = Paint()
        ..color = trackColor.withValues(alpha: 0.25)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      for (final x in loopBoundaryXPositions) {
        canvas.drawLine(
          Offset(x, headerHeight),
          Offset(x, size.height - notchRadius),
          linePaint,
        );
      }
    }
  }

  /// Builds a clip path with rounded corners and notches at loop boundaries.
  /// This is a static method so it can be used by both the painter and the clipper.
  static Path buildClipPath(Size size, double cornerRadius, double notchRadius, List<double> loopBoundaryXPositions) {
    final path = Path();
    final r = cornerRadius;
    final nr = notchRadius;

    // Start at top-left, after corner arc
    path.moveTo(r, 0);

    // Top edge with notches
    for (final notchX in loopBoundaryXPositions) {
      // Line to just before notch
      path.lineTo(notchX - nr, 0);
      // Notch: ╮╭ (curve down-right, then down-left back up)
      path.arcToPoint(
        Offset(notchX, nr),
        radius: Radius.circular(nr),
        clockwise: true,
      );
      path.arcToPoint(
        Offset(notchX + nr, 0),
        radius: Radius.circular(nr),
        clockwise: true,
      );
    }
    // Line to top-right corner
    path.lineTo(size.width - r, 0);

    // Top-right corner
    path.arcToPoint(
      Offset(size.width, r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // Right edge (straight down)
    path.lineTo(size.width, size.height - r);

    // Bottom-right corner
    path.arcToPoint(
      Offset(size.width - r, size.height),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // Bottom edge with notches (in reverse order)
    for (final notchX in loopBoundaryXPositions.reversed) {
      // Line to just after notch
      path.lineTo(notchX + nr, size.height);
      // Notch: ╯╰ (curve up-left, then up-right back down)
      path.arcToPoint(
        Offset(notchX, size.height - nr),
        radius: Radius.circular(nr),
        clockwise: true,
      );
      path.arcToPoint(
        Offset(notchX - nr, size.height),
        radius: Radius.circular(nr),
        clockwise: true,
      );
    }
    // Line to bottom-left corner
    path.lineTo(r, size.height);

    // Bottom-left corner
    path.arcToPoint(
      Offset(0, size.height - r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // Left edge (straight up)
    path.lineTo(0, r);

    // Top-left corner
    path.arcToPoint(
      Offset(r, 0),
      radius: Radius.circular(r),
      clockwise: true,
    );

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(ClipBorderPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        borderWidth != oldDelegate.borderWidth ||
        cornerRadius != oldDelegate.cornerRadius ||
        notchRadius != oldDelegate.notchRadius ||
        !listEquals(loopBoundaryXPositions, oldDelegate.loopBoundaryXPositions);
  }

  /// Compares two lists of doubles for equality.
  static bool listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Clipper for clip content to match the notched border shape.
class ClipPathClipper extends CustomClipper<Path> {
  final double cornerRadius;
  final double notchRadius;
  final List<double> loopBoundaryXPositions;

  ClipPathClipper({
    required this.cornerRadius,
    required this.notchRadius,
    required this.loopBoundaryXPositions,
  });

  @override
  Path getClip(Size size) {
    return ClipBorderPainter.buildClipPath(size, cornerRadius, notchRadius, loopBoundaryXPositions);
  }

  @override
  bool shouldReclip(ClipPathClipper oldClipper) {
    return cornerRadius != oldClipper.cornerRadius ||
        notchRadius != oldClipper.notchRadius ||
        !ClipBorderPainter.listEquals(loopBoundaryXPositions, oldClipper.loopBoundaryXPositions);
  }
}
