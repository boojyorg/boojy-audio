import 'package:flutter/material.dart';

/// Logic Pro-style capsule fader with integrated stereo level meters
/// The level meters are rendered inside the capsule shape, with a draggable handle
class CapsuleFader extends StatelessWidget {
  final double leftLevel; // 0.0 to 1.0
  final double rightLevel; // 0.0 to 1.0
  final double volumeDb; // -60 to +6
  final Function(double)? onVolumeChanged;
  final VoidCallback? onDoubleTap; // Reset to 0 dB

  const CapsuleFader({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    required this.volumeDb,
    this.onVolumeChanged,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTap: onDoubleTap,
          onHorizontalDragUpdate: (details) {
            if (onVolumeChanged == null) return;
            final sliderValue = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final newVolumeDb = _sliderToVolumeDb(sliderValue);
            onVolumeChanged!(newVolumeDb);
          },
          onTapDown: (details) {
            if (onVolumeChanged == null) return;
            final sliderValue = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final newVolumeDb = _sliderToVolumeDb(sliderValue);
            onVolumeChanged!(newVolumeDb);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _CapsuleFaderPainter(
                leftLevel: leftLevel,
                rightLevel: rightLevel,
                volumeSliderValue: _volumeDbToSlider(volumeDb),
              ),
            ),
          ),
        );
      },
    );
  }

  // Boojy volume curve: piecewise linear interpolation
  // Unity at 70%, intuitive midpoint at 50% (-10dB), true silence at 0
  static const List<double> _sliderPoints = [0.01, 0.05, 0.10, 0.30, 0.50, 0.70, 0.85, 1.00];
  static const List<double> _dbPoints = [-60.0, -52.0, -45.0, -24.0, -10.0, 0.0, 3.0, 6.0];

  /// Convert dB to slider value (0.0 to 1.0) using Boojy curve
  double _volumeDbToSlider(double db) {
    if (db <= -60.0) return 0.0;
    if (db >= 6.0) return 1.0;

    // Find segment and interpolate
    for (int i = 0; i < _dbPoints.length - 1; i++) {
      if (db <= _dbPoints[i + 1]) {
        final t = (db - _dbPoints[i]) / (_dbPoints[i + 1] - _dbPoints[i]);
        return _sliderPoints[i] + t * (_sliderPoints[i + 1] - _sliderPoints[i]);
      }
    }
    return 0.7; // fallback to unity
  }

  /// Convert slider value (0.0 to 1.0) to dB using Boojy curve
  double _sliderToVolumeDb(double slider) {
    if (slider <= 0.0) return -60.0; // True silence (treated as -∞)
    if (slider <= 0.01) return -60.0;
    if (slider >= 1.0) return 6.0;

    // Find segment and interpolate
    for (int i = 0; i < _sliderPoints.length - 1; i++) {
      if (slider <= _sliderPoints[i + 1]) {
        final t = (slider - _sliderPoints[i]) / (_sliderPoints[i + 1] - _sliderPoints[i]);
        return _dbPoints[i] + t * (_dbPoints[i + 1] - _dbPoints[i]);
      }
    }
    return 6.0; // fallback to max
  }
}

class _CapsuleFaderPainter extends CustomPainter {
  final double leftLevel;
  final double rightLevel;
  final double volumeSliderValue; // 0.0 to 1.0

  _CapsuleFaderPainter({
    required this.leftLevel,
    required this.rightLevel,
    required this.volumeSliderValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final capsuleRadius = size.height / 2;
    final capsuleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(capsuleRadius),
    );

    // Draw capsule background
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(capsuleRect, bgPaint);

    // Draw capsule border
    final borderPaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(capsuleRect, borderPaint);

    // Clip to capsule shape for meters
    canvas.save();
    canvas.clipRRect(capsuleRect);

    // Calculate meter dimensions
    const meterPadding = 4.0;
    final meterLeft = capsuleRadius + meterPadding;
    final meterRight = size.width - capsuleRadius - meterPadding;
    final meterWidth = meterRight - meterLeft;
    final meterHeight = (size.height - 3 * meterPadding) / 2;

    // Draw left channel meter (top half)
    _drawMeterRow(
      canvas,
      Offset(meterLeft, meterPadding),
      meterWidth,
      meterHeight,
      leftLevel,
    );

    // Draw right channel meter (bottom half)
    _drawMeterRow(
      canvas,
      Offset(meterLeft, meterPadding * 2 + meterHeight),
      meterWidth,
      meterHeight,
      rightLevel,
    );

    canvas.restore();

    // Draw volume handle/thumb
    _drawVolumeHandle(canvas, size);
  }

  void _drawMeterRow(Canvas canvas, Offset offset, double width, double height, double level) {
    // Draw background track (dark)
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx, offset.dy, width, height),
      const Radius.circular(2),
    );
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bgRect, bgPaint);

    // Draw level bar with smooth color gradient
    if (level > 0.01) {
      final levelWidth = width * level;
      final levelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx, offset.dy, levelWidth, height),
        const Radius.circular(2),
      );

      // Smooth gradient: Green → Yellow → Orange → Red
      // Color zones based on dB: -∞ to -12dB green, -12 to -6dB yellow,
      // -6 to 0dB orange→red, above 0dB bright red (clipping)
      // Normalized: -12dB = 0.8, -6dB = 0.9, 0dB = 1.0
      final levelPaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF22c55e), // Green (low levels)
            Color(0xFF22c55e), // Green continues
            Color(0xFFeab308), // Yellow/Amber (-12dB zone)
            Color(0xFFf97316), // Orange (-6dB zone)
            Color(0xFFef4444), // Red (0dB)
            Color(0xFFdc2626), // Bright red (clipping)
          ],
          stops: [0.0, 0.7, 0.8, 0.9, 0.95, 1.0],
        ).createShader(Rect.fromLTWH(offset.dx, offset.dy, width, height));

      canvas.drawRRect(levelRect, levelPaint);
    }
  }

  void _drawVolumeHandle(Canvas canvas, Size size) {
    // Calculate handle position
    final handleRadius = size.height / 2;
    final usableWidth = size.width - handleRadius * 2;
    final handleX = handleRadius + volumeSliderValue * usableWidth;
    final handleY = size.height / 2;

    // Draw semi-transparent grey circle (Logic Pro style - no glow, no indicator)
    final handlePaint = Paint()
      ..color = const Color(0xFF808080).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(handleX, handleY), handleRadius - 1, handlePaint);

    // Draw subtle border
    final borderPaint = Paint()
      ..color = const Color(0xFFAAAAAA).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(handleX, handleY), handleRadius - 1, borderPaint);
  }

  @override
  bool shouldRepaint(_CapsuleFaderPainter oldDelegate) {
    return oldDelegate.leftLevel != leftLevel ||
        oldDelegate.rightLevel != rightLevel ||
        oldDelegate.volumeSliderValue != volumeSliderValue;
  }
}
