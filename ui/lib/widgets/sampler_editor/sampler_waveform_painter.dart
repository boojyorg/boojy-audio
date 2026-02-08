import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Custom painter for sampler waveform with loop region overlay and envelope.
/// Matches the Audio Editor's WaveformEditorPainter visual style.
///
/// Features:
/// - Real min/max waveform peaks with LOD downsampling
/// - Loop region overlay: dimmed outside loop (20% black)
/// - Loop start/end marker lines (vertical, draggable)
/// - Envelope overlay (orange attack→sustain→release)
/// - Hierarchical time grid matching WaveformEditorPainter style
/// - Center line
class SamplerWaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double sampleDuration; // in seconds
  final double pixelsPerSecond;
  final double attackMs;
  final double releaseMs;
  final bool loopEnabled;
  final double loopStartSeconds;
  final double loopEndSeconds;
  final BoojyColors colors;

  SamplerWaveformPainter({
    required this.peaks,
    required this.sampleDuration,
    required this.pixelsPerSecond,
    required this.attackMs,
    required this.releaseMs,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.colors,
  });

  /// Get adaptive grid intervals based on zoom level.
  /// Returns (majorInterval, subInterval) in seconds.
  (double, double) _getGridIntervals() {
    if (pixelsPerSecond > 400) return (0.5, 0.1);
    if (pixelsPerSecond > 200) return (0.5, 0.25);
    if (pixelsPerSecond > 100) return (1.0, 0.25);
    if (pixelsPerSecond > 50) return (1.0, 0.5);
    if (pixelsPerSecond > 25) return (2.0, 1.0);
    return (5.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || sampleDuration <= 0) return;

    final totalWidth = sampleDuration * pixelsPerSecond;
    final centerY = size.height / 2;

    // 1. Draw hierarchical time grid
    _drawTimeGrid(canvas, size, totalWidth);

    // 2. Draw center line
    final centerPaint = Paint()
      ..color = colors.divider.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);

    // 3. Draw loop region overlay
    _drawLoopRegion(canvas, size, totalWidth);

    // 4. Draw waveform (with LOD)
    _drawWaveform(canvas, size, totalWidth, centerY);

    // 5. Draw envelope overlay
    _drawEnvelope(canvas, size, totalWidth, centerY);

    // 6. Draw loop markers
    _drawLoopMarkers(canvas, size, totalWidth);
  }

  void _drawTimeGrid(Canvas canvas, Size size, double totalWidth) {
    final (majorInterval, subInterval) = _getGridIntervals();

    // Major lines (like bar lines in WaveformEditorPainter)
    final majorPaint = Paint()
      ..color = colors.textMuted
      ..strokeWidth = 1.5;

    // Medium lines (like beat lines)
    final mediumPaint = Paint()
      ..color = colors.divider
      ..strokeWidth = 1.0;

    // Subdivision lines (lighter)
    final subPaint = Paint()
      ..color = colors.divider.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final maxX = math.min(totalWidth, size.width * 3);
    for (double t = 0; t <= sampleDuration + subInterval; t += subInterval) {
      final x = t * pixelsPerSecond;
      if (x > maxX) break;

      final isMajor = (t / majorInterval - (t / majorInterval).roundToDouble()).abs() < 0.001;
      // Check if it's a "whole second" line (medium weight)
      final isSecond = (t - t.roundToDouble()).abs() < 0.001;

      if (isMajor) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
      } else if (isSecond) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), mediumPaint);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), subPaint);
      }
    }
  }

  void _drawLoopRegion(Canvas canvas, Size size, double totalWidth) {
    if (!loopEnabled) return;

    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;
    final sampleEndX = math.min(totalWidth, size.width * 3);

    // Dim outside the loop region (20% black, matching WaveformEditorPainter)
    final dimPaint = Paint()..color = const Color(0x33000000);

    // Before loop start
    if (loopStartX > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, loopStartX, size.height),
        dimPaint,
      );
    }

    // After loop end
    if (loopEndX < sampleEndX) {
      canvas.drawRect(
        Rect.fromLTWH(loopEndX, 0, sampleEndX - loopEndX, size.height),
        dimPaint,
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size, double totalWidth, double centerY) {
    if (peaks.isEmpty) return;

    final originalPeakCount = peaks.length ~/ 2;
    if (originalPeakCount == 0) return;

    // LOD: Calculate optimal peak count for visible width
    final targetPeakCount = totalWidth.clamp(100, originalPeakCount.toDouble()).toInt();

    // Downsample if we have more peaks than needed (>2x threshold)
    List<double> renderPeaks;
    if (originalPeakCount > targetPeakCount * 2) {
      final groupSize = originalPeakCount ~/ targetPeakCount;
      renderPeaks = _downsamplePeaks(peaks, groupSize);
    } else {
      renderPeaks = peaks;
    }

    final peakCount = renderPeaks.length ~/ 2;
    if (peakCount == 0) return;

    final step = totalWidth / peakCount;

    // Create closed polygon path for continuous waveform shape
    final path = Path();

    // Start at first peak's top
    double firstMax = renderPeaks[1].clamp(-1.0, 1.0);
    final firstTopY = centerY - (firstMax * centerY * 0.9);
    path.moveTo(step / 2, firstTopY);

    // Trace TOP edge (max values) left to right
    for (int i = 1; i < peakCount; i++) {
      final x = i * step + step / 2;
      double maxVal = renderPeaks[i * 2 + 1].clamp(-1.0, 1.0);
      final topY = centerY - (maxVal * centerY * 0.9);
      path.lineTo(x, topY);
    }

    // Trace BOTTOM edge (min values) right to left
    for (int i = peakCount - 1; i >= 0; i--) {
      final x = i * step + step / 2;
      double minVal = renderPeaks[i * 2].clamp(-1.0, 1.0);
      final bottomY = centerY - (minVal * centerY * 0.9);
      path.lineTo(x, bottomY);
    }

    path.close();

    // Use opaque color for both fill and stroke (matching WaveformEditorPainter)
    final waveColor = colors.accent.withValues(alpha: 0.85);

    // Fill the waveform
    final fillPaint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Add stroke for visual body (dynamic based on zoom)
    double strokeWidth = 0;
    if (step < 1.0) {
      strokeWidth = (1.0 / step).clamp(1.0, 1.5);
    } else {
      strokeWidth = 0.5;
    }

    if (strokeWidth > 0) {
      final strokePaint = Paint()
        ..color = waveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.src;
      canvas.drawPath(path, strokePaint);
    }
  }

  /// Downsample peaks by grouping and taking min/max of each group.
  /// Preserves waveform amplitude while reducing point count.
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

      if (groupMin != double.infinity) {
        result.add(groupMin);
        result.add(groupMax);
      }
    }

    return result;
  }

  void _drawEnvelope(Canvas canvas, Size size, double totalWidth, double centerY) {
    if (sampleDuration <= 0) return;

    final envelopePaint = Paint()
      ..color = colors.warning.withAlpha(60)
      ..style = PaintingStyle.fill;

    final envelopeStrokePaint = Paint()
      ..color = colors.warning.withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final attackSeconds = attackMs / 1000.0;
    final releaseSeconds = releaseMs / 1000.0;
    final attackEndX = attackSeconds * pixelsPerSecond;

    // For envelope display, use sample duration or loop end
    final effectiveEnd = loopEnabled
        ? loopEndSeconds * pixelsPerSecond
        : math.min(sampleDuration * pixelsPerSecond, totalWidth);
    final releaseStartX = effectiveEnd - releaseSeconds * pixelsPerSecond;

    // Envelope curve stroke
    final curve = Path();
    curve.moveTo(0, size.height * 0.15); // Start low (near bottom, inverted for visual)
    curve.lineTo(attackEndX, size.height * 0.05); // Attack up to top
    curve.lineTo(math.max(attackEndX, releaseStartX), size.height * 0.05); // Sustain at top
    curve.lineTo(effectiveEnd, size.height * 0.15); // Release back down

    canvas.drawPath(curve, envelopeStrokePaint);

    // Fill under envelope
    final fillPath = Path.from(curve);
    fillPath.lineTo(effectiveEnd, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, envelopePaint);
  }

  void _drawLoopMarkers(Canvas canvas, Size size, double totalWidth) {
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;

    final markerColor = loopEnabled
        ? colors.accent
        : colors.textMuted.withAlpha(100);

    final markerPaint = Paint()
      ..color = markerColor
      ..strokeWidth = 1.5;

    // Draw loop start line
    canvas.drawLine(
      Offset(loopStartX, 0),
      Offset(loopStartX, size.height),
      markerPaint,
    );

    // Draw loop end line
    canvas.drawLine(
      Offset(loopEndX, 0),
      Offset(loopEndX, size.height),
      markerPaint,
    );

    // Draw small triangles at top of markers
    final trianglePaint = Paint()
      ..color = markerColor
      ..style = PaintingStyle.fill;

    // Start marker triangle (pointing right)
    final startTriangle = Path()
      ..moveTo(loopStartX, 0)
      ..lineTo(loopStartX + 6, 0)
      ..lineTo(loopStartX, 8)
      ..close();
    canvas.drawPath(startTriangle, trianglePaint);

    // End marker triangle (pointing left)
    final endTriangle = Path()
      ..moveTo(loopEndX, 0)
      ..lineTo(loopEndX - 6, 0)
      ..lineTo(loopEndX, 8)
      ..close();
    canvas.drawPath(endTriangle, trianglePaint);
  }

  @override
  bool shouldRepaint(covariant SamplerWaveformPainter oldDelegate) {
    return !identical(peaks, oldDelegate.peaks) ||
        sampleDuration != oldDelegate.sampleDuration ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        attackMs != oldDelegate.attackMs ||
        releaseMs != oldDelegate.releaseMs ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStartSeconds != oldDelegate.loopStartSeconds ||
        loopEndSeconds != oldDelegate.loopEndSeconds;
  }
}

/// Painter for the seconds-based ruler in the sampler editor.
/// Styled to match UnifiedNavBar (24px height, dark background,
/// hierarchical tick marks at bottom, time labels at top).
class SamplerRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double sampleDuration;
  final bool loopEnabled;
  final double loopStartSeconds;
  final double loopEndSeconds;
  final BoojyColors colors;

  SamplerRulerPainter({
    required this.pixelsPerSecond,
    required this.sampleDuration,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.colors,
  });

  /// Get adaptive intervals based on zoom level.
  /// Returns (majorInterval, subdivisions).
  (double, int) _getIntervals() {
    if (pixelsPerSecond > 400) return (0.5, 5);
    if (pixelsPerSecond > 200) return (0.5, 5);
    if (pixelsPerSecond > 100) return (1.0, 4);
    if (pixelsPerSecond > 50) return (1.0, 2);
    if (pixelsPerSecond > 25) return (2.0, 2);
    return (5.0, 5);
  }

  /// Determine label display interval for avoiding text overlap.
  double _getLabelInterval(double majorInterval) {
    final majorPixels = majorInterval * pixelsPerSecond;
    if (majorPixels >= 60) return majorInterval;
    return majorInterval * 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark background (matching UnifiedNavBar: 0xFF1A1A1A)
    final bgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Draw loop region bar at top
    _drawLoopRegion(canvas, size);

    // 3. Draw tick marks and time labels
    _drawTicksAndLabels(canvas, size);
  }

  void _drawLoopRegion(Canvas canvas, Size size) {
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;

    if (loopEnabled) {
      // Filled loop region bar (matching UnifiedNavBar orange style)
      final fillPaint = Paint()..color = const Color(0xFFB36800);
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopEndX - loopStartX, 4),
        fillPaint,
      );
      // Border
      final borderPaint = Paint()
        ..color = const Color(0xFFFF9800)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopEndX - loopStartX, 4),
        borderPaint,
      );
    } else {
      // Grey when inactive
      final fillPaint = Paint()..color = const Color(0xFF333333);
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopEndX - loopStartX, 4),
        fillPaint,
      );
      final borderPaint = Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(
        Rect.fromLTWH(loopStartX, 0, loopEndX - loopStartX, 4),
        borderPaint,
      );
    }
  }

  void _drawTicksAndLabels(Canvas canvas, Size size) {
    final (majorInterval, subdivisions) = _getIntervals();
    final subInterval = majorInterval / subdivisions;
    final labelInterval = _getLabelInterval(majorInterval);

    // Tick paints (matching UnifiedNavBar hierarchy — painted from bottom)
    final majorTickPaint = Paint()
      ..color = const Color(0xFF707070)
      ..strokeWidth = 1.5;
    final mediumTickPaint = Paint()
      ..color = const Color(0xFF505050)
      ..strokeWidth = 1.0;
    final subTickPaint = Paint()
      ..color = const Color(0xFF404040)
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (double t = 0; t <= sampleDuration + subInterval; t += subInterval) {
      final x = t * pixelsPerSecond;
      if (x > size.width * 3) break;

      final isMajor = (t / majorInterval - (t / majorInterval).roundToDouble()).abs() < 0.001;
      final isSecond = (t - t.roundToDouble()).abs() < 0.001;

      if (isMajor) {
        // Major tick: 6px from bottom
        canvas.drawLine(
          Offset(x, size.height - 6),
          Offset(x, size.height),
          majorTickPaint,
        );

        // Time label (only at label intervals to avoid overlap)
        final isLabelTick = (t / labelInterval - (t / labelInterval).roundToDouble()).abs() < 0.001;
        if (isLabelTick) {
          textPainter.text = TextSpan(
            text: _formatTime(t),
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x + 4, 5));
        }
      } else if (isSecond) {
        // Whole-second tick: 4px from bottom
        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height),
          mediumTickPaint,
        );
      } else {
        // Subdivision tick: 2px from bottom
        canvas.drawLine(
          Offset(x, size.height - 2),
          Offset(x, size.height),
          subTickPaint,
        );
      }
    }
  }

  String _formatTime(double seconds) {
    if (seconds < 0.001) return '0s';
    if (seconds < 1.0) {
      return '${(seconds * 1000).round()}ms';
    } else if (seconds < 10.0) {
      return '${seconds.toStringAsFixed(1)}s';
    } else {
      return '${seconds.toStringAsFixed(0)}s';
    }
  }

  @override
  bool shouldRepaint(covariant SamplerRulerPainter oldDelegate) {
    return pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        sampleDuration != oldDelegate.sampleDuration ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStartSeconds != oldDelegate.loopStartSeconds ||
        loopEndSeconds != oldDelegate.loopEndSeconds;
  }
}
