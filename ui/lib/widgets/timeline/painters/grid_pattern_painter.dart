import 'package:flutter/material.dart';

/// Painter for grid pattern in track background.
/// Currently empty as grid lines are drawn by the main grid painter.
class GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Empty - grid lines are drawn by the main grid painter
  }

  @override
  bool shouldRepaint(GridPatternPainter oldDelegate) => false;
}
