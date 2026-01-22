import 'package:flutter/material.dart';

/// Painter for audio waveform visualization with LOD (Level of Detail) support.
/// Downsamples peaks when zoomed out for performance, preserves detail when zoomed in.
class WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Color color;
  final double visualGain;

  WaveformPainter({
    required this.peaks,
    required this.color,
    this.visualGain = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final centerY = size.height / 2;
    final originalPeakCount = peaks.length ~/ 2;
    if (originalPeakCount == 0) return;

    // LOD: Calculate optimal peak count for visible width
    // Target ~1 pixel per peak for crisp detail (like Ableton)
    final targetPeakCount = size.width.clamp(100, originalPeakCount.toDouble()).toInt();

    // Downsample if we have more peaks than needed (>2x threshold for smoother transitions)
    List<double> renderPeaks;
    if (originalPeakCount > targetPeakCount * 2) {
      final groupSize = originalPeakCount ~/ targetPeakCount;
      renderPeaks = _downsamplePeaks(peaks, groupSize);
    } else {
      renderPeaks = peaks;
    }

    final peakCount = renderPeaks.length ~/ 2;
    if (peakCount == 0) return;

    final step = size.width / peakCount;

    // Create closed polygon path for continuous waveform shape
    final path = Path();

    // Start at first peak's top (apply visual gain)
    final firstMax = (renderPeaks[1] * visualGain).clamp(-1.0, 1.0);
    final firstTopY = centerY - (firstMax * centerY);
    path.moveTo(step / 2, firstTopY);

    // Trace TOP edge (max values) left to right
    for (int i = 2; i < renderPeaks.length; i += 2) {
      final x = (i ~/ 2) * step + step / 2;
      final max = (renderPeaks[i + 1] * visualGain).clamp(-1.0, 1.0);
      final topY = centerY - (max * centerY);
      path.lineTo(x, topY);
    }

    // Trace BOTTOM edge (min values) right to left
    for (int i = renderPeaks.length - 2; i >= 0; i -= 2) {
      final x = (i ~/ 2) * step + step / 2;
      final min = (renderPeaks[i] * visualGain).clamp(-1.0, 1.0);
      final bottomY = centerY - (min * centerY);
      path.lineTo(x, bottomY);
    }

    path.close();

    // Use opaque color for both fill and stroke so they match exactly
    final waveformColor = color.withValues(alpha: 0.85);

    // Fill the waveform
    final fillPaint = Paint()
      ..color = waveformColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Add stroke to give waveform body
    double strokeWidth = 0;
    if (step < 1.0) {
      // Zoomed out: scale stroke to compensate for sub-pixel peaks
      strokeWidth = (1.0 / step).clamp(1.0, 1.5);
    } else {
      // Normal/zoomed in: minimum stroke for visual continuity
      strokeWidth = 0.5;
    }

    if (strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = waveformColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.src;
      canvas.drawPath(path, strokePaint);
    }

    // Center line for visual continuity through silent parts
    final centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerLinePaint);
  }

  /// Downsample peaks by grouping and taking min/max of each group.
  /// This preserves waveform amplitude while reducing point count.
  List<double> _downsamplePeaks(List<double> peaks, int groupSize) {
    if (groupSize <= 1) return peaks;

    final result = <double>[];
    final pairCount = peaks.length ~/ 2;

    for (int i = 0; i < pairCount; i += groupSize) {
      double groupMin = double.infinity;
      double groupMax = double.negativeInfinity;

      final end = (i + groupSize).clamp(0, pairCount);
      for (int j = i; j < end; j++) {
        final min = peaks[j * 2];
        final max = peaks[j * 2 + 1];
        if (min < groupMin) groupMin = min;
        if (max > groupMax) groupMax = max;
      }

      result.add(groupMin);
      result.add(groupMax);
    }

    return result;
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // O(1) reference checks - downsampling happens fresh each paint
    return !identical(peaks, oldDelegate.peaks) ||
        color != oldDelegate.color ||
        visualGain != oldDelegate.visualGain;
  }
}
