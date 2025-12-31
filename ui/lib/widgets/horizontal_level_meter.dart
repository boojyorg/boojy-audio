import 'package:flutter/material.dart';

/// Horizontal stereo level meter with volume slider overlaid
/// Ableton-style: meter shows signal level, slider thumb adjusts volume
class HorizontalLevelMeter extends StatelessWidget {
  final double leftLevel; // 0.0 to 1.0
  final double rightLevel; // 0.0 to 1.0
  final double volumeDb; // -inf to +6
  final Function(double)? onVolumeChanged;

  const HorizontalLevelMeter({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    required this.volumeDb,
    this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Simplified meter - dB label shown in parent widget's top row
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
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
              painter: _MeterPainter(
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

  /// Convert dB to slider value (0.0 to 1.0)
  /// Using logarithmic scale: -60dB to +6dB
  double _volumeDbToSlider(double db) {
    const minDb = -60.0;
    const maxDb = 6.0;
    if (db <= minDb) return 0.0;
    if (db >= maxDb) return 1.0;
    return (db - minDb) / (maxDb - minDb);
  }

  /// Convert slider value (0.0 to 1.0) to dB
  double _sliderToVolumeDb(double slider) {
    const minDb = -60.0;
    const maxDb = 6.0;
    return minDb + slider * (maxDb - minDb);
  }
}

class _MeterPainter extends CustomPainter {
  final double leftLevel;
  final double rightLevel;
  final double volumeSliderValue; // 0.0 to 1.0

  static const int segmentCount = 20;
  static const double segmentGap = 2;

  _MeterPainter({
    required this.leftLevel,
    required this.rightLevel,
    required this.volumeSliderValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final meterHeight = (size.height - 8) / 2; // Two rows with gap
    final segmentWidth = (size.width - (segmentCount - 1) * segmentGap) / segmentCount;

    // Draw left channel (top)
    _drawMeterRow(canvas, const Offset(0, 2), segmentWidth, meterHeight - 2, leftLevel);

    // Draw right channel (bottom)
    _drawMeterRow(canvas, Offset(0, meterHeight + 6), segmentWidth, meterHeight - 2, rightLevel);

    // Draw volume slider thumb
    _drawVolumeThumb(canvas, size);
  }

  void _drawMeterRow(Canvas canvas, Offset offset, double segmentWidth, double height, double level) {
    for (int i = 0; i < segmentCount; i++) {
      final threshold = (i + 1) / segmentCount;
      final isLit = level >= threshold;

      // Color based on segment position
      Color color;
      if (i < 12) {
        // Green (60%)
        color = isLit ? const Color(0xFF4CAF50) : const Color(0xFF2E5A32);
      } else if (i < 16) {
        // Yellow (60-80%)
        color = isLit ? const Color(0xFFFFC107) : const Color(0xFF5A4A1F);
      } else {
        // Red (80-100%)
        color = isLit ? const Color(0xFFFF5722) : const Color(0xFF5A2A1A);
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          offset.dx + i * (segmentWidth + segmentGap),
          offset.dy,
          segmentWidth,
          height,
        ),
        const Radius.circular(2),
      );

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rect, paint);
    }
  }

  void _drawVolumeThumb(Canvas canvas, Size size) {
    final thumbX = volumeSliderValue * size.width;
    final thumbY = size.height / 2;

    // Vertical line
    final linePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(thumbX, 0),
      Offset(thumbX, size.height),
      linePaint,
    );

    // Thumb circle
    final thumbPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, thumbY), 6, thumbPaint);

    // Thumb border
    final borderPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(thumbX, thumbY), 6, borderPaint);
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) {
    return oldDelegate.leftLevel != leftLevel ||
        oldDelegate.rightLevel != rightLevel ||
        oldDelegate.volumeSliderValue != volumeSliderValue;
  }
}
