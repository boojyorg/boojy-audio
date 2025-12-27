import 'dart:math' as math;
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

  /// Convert dB to slider value (0.0 to 1.0) using logarithmic scale
  /// 0dB at ~80% position, more resolution near unity
  double _volumeDbToSlider(double db) {
    const maxDb = 6.0;
    const unityDb = 0.0;
    const minDb = -60.0; // Treat as -∞

    if (db >= maxDb) return 1.0;
    if (db <= minDb) return 0.0;

    if (db >= unityDb) {
      // 0dB to +6dB maps to 0.8 to 1.0 (top 20%)
      return 0.8 + (db / maxDb) * 0.2;
    } else {
      // -60dB to 0dB maps to 0.0 to 0.8 (bottom 80%)
      // Use logarithmic curve for natural feel
      final normalizedDb = (db - minDb) / (-minDb); // 0 to 1
      // Apply curve: x^0.4 gives more resolution near unity
      return 0.8 * math.pow(normalizedDb, 0.4);
    }
  }

  /// Convert slider value (0.0 to 1.0) to dB using inverse logarithmic scale
  double _sliderToVolumeDb(double slider) {
    const maxDb = 6.0;
    const minDb = -60.0;

    if (slider >= 1.0) return maxDb;
    if (slider <= 0.0) return minDb;

    if (slider >= 0.8) {
      // Top 20% (0.8 to 1.0) maps to 0dB to +6dB
      return ((slider - 0.8) / 0.2) * maxDb;
    } else {
      // Bottom 80% (0.0 to 0.8) maps to -60dB to 0dB
      final normalizedSlider = slider / 0.8; // 0 to 1
      // Inverse of x^0.4
      final dbNormalized = math.pow(normalizedSlider, 1.0 / 0.4);
      return minDb + dbNormalized * (-minDb);
    }
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
    final meterPadding = 4.0;
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
