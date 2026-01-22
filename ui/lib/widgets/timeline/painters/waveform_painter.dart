import 'package:flutter/material.dart';

/// Painter for audio waveform visualization with LOD (Level of Detail) support.
/// Downsamples peaks when zoomed out for performance, preserves detail when zoomed in.
/// Supports looped/tiled rendering when clipWidth > loopWidth.
/// Supports offset-aware rendering for non-destructive trimming.
class WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Color color;
  final double visualGain;

  /// Width of one loop iteration in pixels (for looped clips).
  /// If null or >= clipWidth, no looping/tiling occurs.
  final double? loopWidth;

  /// Full content duration in seconds (for calculating peak density).
  /// This is the duration that the peaks array represents.
  final double? contentDuration;

  /// Start offset in seconds (for left-edge trimming).
  /// Determines which portion of peaks to start rendering from.
  final double startOffset;

  /// Visible duration in seconds (how much of the content is displayed).
  /// When clip is trimmed, this is less than contentDuration.
  /// If null, displays from startOffset to end of content.
  final double? visibleDuration;

  WaveformPainter({
    required this.peaks,
    required this.color,
    this.visualGain = 1.0,
    this.loopWidth,
    this.contentDuration,
    this.startOffset = 0.0,
    this.visibleDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final centerY = size.height / 2;

    // Calculate effective loop width (one iteration of the waveform)
    final effectiveLoopWidth = (loopWidth != null && loopWidth! > 0 && loopWidth! < size.width)
        ? loopWidth!
        : size.width;

    // Calculate number of loop iterations needed to fill the clip
    final loopCount = (size.width / effectiveLoopWidth).ceil();

    // Render waveform for each loop iteration
    for (int loop = 0; loop < loopCount; loop++) {
      final loopStartX = loop * effectiveLoopWidth;
      final loopEndX = (loopStartX + effectiveLoopWidth).clamp(0.0, size.width);
      final thisLoopWidth = loopEndX - loopStartX;

      if (thisLoopWidth <= 0) break;

      // Save canvas state and clip to this loop region
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(loopStartX, 0, thisLoopWidth, size.height));

      _paintSingleWaveform(canvas, Size(effectiveLoopWidth, size.height), loopStartX, centerY);

      canvas.restore();
    }

    // Center line for visual continuity through silent parts (spans full clip)
    final centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerLinePaint);
  }

  /// Paint a single waveform iteration at the given offset
  void _paintSingleWaveform(Canvas canvas, Size size, double offsetX, double centerY) {
    final originalPeakCount = peaks.length ~/ 2;
    if (originalPeakCount == 0) return;

    // Determine which peaks to render based on offset
    List<double> visiblePeaks;
    final double effectiveWidth = size.width;

    if (contentDuration != null && contentDuration! > 0) {
      // Calculate peak indices for the visible portion
      final peaksPerSecond = originalPeakCount / contentDuration!;
      final startPeakIndex = (startOffset * peaksPerSecond).floor().clamp(0, originalPeakCount);

      // Calculate end peak index based on visibleDuration (if specified)
      int endPeakIndex = originalPeakCount;
      if (visibleDuration != null && visibleDuration! > 0) {
        final endOffset = startOffset + visibleDuration!;
        endPeakIndex = (endOffset * peaksPerSecond).ceil().clamp(0, originalPeakCount);
      }

      // Extract peaks for the visible portion
      if (startPeakIndex < endPeakIndex) {
        visiblePeaks = peaks.sublist(startPeakIndex * 2, endPeakIndex * 2);
      } else {
        visiblePeaks = [];
      }
    } else {
      visiblePeaks = peaks;
    }

    final visiblePeakCount = visiblePeaks.length ~/ 2;
    if (visiblePeakCount == 0) return;

    // LOD: Calculate optimal peak count for visible width
    // Target ~1 pixel per peak for crisp detail (like Ableton)
    final targetPeakCount = effectiveWidth.clamp(100, visiblePeakCount.toDouble()).toInt();

    // Downsample if we have more peaks than needed (>2x threshold for smoother transitions)
    List<double> renderPeaks;
    if (visiblePeakCount > targetPeakCount * 2) {
      final groupSize = visiblePeakCount ~/ targetPeakCount;
      renderPeaks = _downsamplePeaks(visiblePeaks, groupSize);
    } else {
      renderPeaks = visiblePeaks;
    }

    final peakCount = renderPeaks.length ~/ 2;
    if (peakCount == 0) return;

    // Calculate step size - this determines how much horizontal space each peak gets
    // For trimmed clips, we want consistent scale so waveform doesn't squeeze
    double step;
    if (contentDuration != null && contentDuration! > 0) {
      // Calculate pixels per second based on full content
      // size.width / visibleDuration gives pixelsPerSecond
      // We want the same density regardless of trim
      final pixelsPerPeak = effectiveWidth / peakCount;
      step = pixelsPerPeak;
    } else {
      step = effectiveWidth / peakCount;
    }

    // Create closed polygon path for continuous waveform shape
    final path = Path();

    // Start at first peak's top (apply visual gain)
    final firstMax = (renderPeaks[1] * visualGain).clamp(-1.0, 1.0);
    final firstTopY = centerY - (firstMax * centerY);
    path.moveTo(offsetX + step / 2, firstTopY);

    // Trace TOP edge (max values) left to right
    for (int i = 2; i < renderPeaks.length; i += 2) {
      final x = offsetX + (i ~/ 2) * step + step / 2;
      final max = (renderPeaks[i + 1] * visualGain).clamp(-1.0, 1.0);
      final topY = centerY - (max * centerY);
      path.lineTo(x, topY);
    }

    // Trace BOTTOM edge (min values) right to left
    for (int i = renderPeaks.length - 2; i >= 0; i -= 2) {
      final x = offsetX + (i ~/ 2) * step + step / 2;
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
        visualGain != oldDelegate.visualGain ||
        loopWidth != oldDelegate.loopWidth ||
        contentDuration != oldDelegate.contentDuration ||
        startOffset != oldDelegate.startOffset ||
        visibleDuration != oldDelegate.visibleDuration;
  }
}
