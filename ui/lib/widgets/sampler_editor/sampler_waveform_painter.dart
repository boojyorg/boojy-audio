import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Custom painter for sampler waveform display.
/// Matches the Audio Editor's WaveformEditorPainter visual style:
/// Grid → Waveform → Loop dimming (no envelope, no loop markers).
class SamplerWaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double sampleDuration; // in seconds
  final double pixelsPerSecond;
  final bool loopEnabled;
  final double loopStartSeconds;
  final double loopEndSeconds;
  final BoojyColors colors;
  final double originalBpm;
  final int beatsPerBar;

  SamplerWaveformPainter({
    required this.peaks,
    required this.sampleDuration,
    required this.pixelsPerSecond,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.colors,
    this.originalBpm = 120.0,
    this.beatsPerBar = 4,
  });

  double get _pixelsPerBeat => pixelsPerSecond * (60.0 / originalBpm);

  /// Adaptive grid division in beats — matches UnifiedNavBarPainter
  double _getGridDivision() {
    final ppb = _pixelsPerBeat;
    if (ppb < 10) return beatsPerBar.toDouble();
    if (ppb < 20) return 1.0;
    if (ppb < 40) return 0.5;
    if (ppb < 80) return 0.25;
    return 0.125;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || sampleDuration <= 0) return;

    final totalWidth = sampleDuration * pixelsPerSecond;
    final centerY = size.height / 2;

    // 1. Draw grid (includes center line, matching Audio Editor)
    _drawTimeGrid(canvas, size, totalWidth);

    // 2. Draw waveform
    _drawWaveform(canvas, size, totalWidth, centerY);

    // 3. Draw loop dimming overlay
    if (loopEnabled) {
      _drawLoopRegion(canvas, size, totalWidth);
    }
  }

  void _drawTimeGrid(Canvas canvas, Size size, double totalWidth) {
    final ppb = _pixelsPerBeat;
    final totalBeats = sampleDuration * (originalBpm / 60.0);
    final gridDivision = _getGridDivision();

    // Bar lines (matching WaveformEditorPainter)
    final barPaint = Paint()
      ..color = colors.textMuted
      ..strokeWidth = 1.5;

    // Beat lines
    final gridPaint = Paint()
      ..color = colors.divider
      ..strokeWidth = 1.0;

    // Subdivision lines (lighter)
    final subPaint = Paint()
      ..color = colors.divider.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * ppb;
      if (x > size.width) break;

      final isBar = (beat % beatsPerBar).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

      if (isBar) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), barPaint);
      } else if (isBeat) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), subPaint);
      }
    }

    // Draw horizontal center line (inside grid, matching Audio Editor)
    final centerPaint = Paint()
      ..color = colors.divider.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);
  }

  void _drawLoopRegion(Canvas canvas, Size size, double totalWidth) {
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;

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
    if (loopEndX < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(loopEndX, 0, size.width - loopEndX, size.height),
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

  @override
  bool shouldRepaint(covariant SamplerWaveformPainter oldDelegate) {
    return !identical(peaks, oldDelegate.peaks) ||
        sampleDuration != oldDelegate.sampleDuration ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStartSeconds != oldDelegate.loopStartSeconds ||
        loopEndSeconds != oldDelegate.loopEndSeconds ||
        originalBpm != oldDelegate.originalBpm ||
        beatsPerBar != oldDelegate.beatsPerBar;
  }
}

/// Beat-based ruler painter for the sampler editor.
/// Matches UnifiedNavBarPainter: 24px height, dark background,
/// full-height loop region bar, bar/beat/subdivision labels.
class SamplerRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double sampleDuration;
  final bool loopEnabled;
  final double loopStartSeconds;
  final double loopEndSeconds;
  final BoojyColors colors;
  final double originalBpm;
  final int beatsPerBar;
  final double? hoverSeconds; // For loop edge hover feedback

  SamplerRulerPainter({
    required this.pixelsPerSecond,
    required this.sampleDuration,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.colors,
    this.originalBpm = 120.0,
    this.beatsPerBar = 4,
    this.hoverSeconds,
  });

  double get _pixelsPerBeat => pixelsPerSecond * (60.0 / originalBpm);

  /// Adaptive grid division — matches UnifiedNavBarPainter
  double _getGridDivision() {
    final ppb = _pixelsPerBeat;
    if (ppb < 10) return beatsPerBar.toDouble();
    if (ppb < 20) return 1.0;
    if (ppb < 40) return 0.5;
    if (ppb < 80) return 0.25;
    return 0.125;
  }

  /// Bar number display interval — matches UnifiedNavBarPainter
  int _getBarNumberInterval() {
    final ppb = _pixelsPerBeat;
    if (ppb < 1.75) return 8;
    if (ppb < 3.5) return 4;
    if (ppb < 7) return 2;
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark background
    final bgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Draw loop region (full-height colored bar)
    _drawLoopRegion(canvas, size);

    // 3. Draw grid lines and bar/beat numbers
    _drawGridAndNumbers(canvas, size);
  }

  void _drawLoopRegion(Canvas canvas, Size size) {
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;
    final loopWidth = loopEndX - loopStartX;

    if (loopWidth <= 0) return;

    final loopRect = Rect.fromLTWH(loopStartX, 0, loopWidth, size.height);

    // Colors matching UnifiedNavBarPainter (no punch-in for sampler)
    Color fillColor;
    Color borderColor;

    if (loopEnabled) {
      fillColor = const Color(0xFFB36800);
      borderColor = const Color(0xFFFF9800);
    } else {
      fillColor = const Color(0xFF333333);
      borderColor = const Color(0xFF555555);
    }

    final fillPaint = Paint()..color = fillColor;
    canvas.drawRect(loopRect, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(loopRect, borderPaint);

    // Edge highlighting on hover (matching UnifiedNavBarPainter)
    if (hoverSeconds != null) {
      final hoverX = hoverSeconds! * pixelsPerSecond;
      const edgeHitZone = 10.0;
      const hoverColor = Color(0xFFFFB74D);

      if ((hoverX - loopStartX).abs() < edgeHitZone) {
        final highlightPaint = Paint()
          ..color = hoverColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawLine(
          Offset(loopStartX, 0),
          Offset(loopStartX, size.height),
          highlightPaint,
        );
      } else if ((hoverX - loopEndX).abs() < edgeHitZone) {
        final highlightPaint = Paint()
          ..color = hoverColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawLine(
          Offset(loopEndX, 0),
          Offset(loopEndX, size.height),
          highlightPaint,
        );
      }
    }
  }

  void _drawGridAndNumbers(Canvas canvas, Size size) {
    final ppb = _pixelsPerBeat;
    final totalBeats = sampleDuration * (originalBpm / 60.0);
    final gridDivision = _getGridDivision();
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;

    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * ppb;
      if (x > size.width) break;

      final isBar = (beat % beatsPerBar).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

      if (isBar) {
        // Bar tick — taller
        final tickPaint = Paint()
          ..color = const Color(0xFF707070)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(x, size.height - 6),
          Offset(x, size.height),
          tickPaint,
        );

        // Bar number
        final barNumber = (beat / beatsPerBar).floor() + 1;
        final barInterval = _getBarNumberInterval();
        if (barNumber % barInterval == 1 || barInterval == 1) {
          final textX = x + 4;
          final isOverLoop = loopEnabled && textX >= loopStartX && textX < loopEndX;
          textPainter.text = TextSpan(
            text: '$barNumber',
            style: TextStyle(
              color: isOverLoop ? const Color(0xFFFFFFFF) : const Color(0xFFE0E0E0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(textX, 2));
        }
      } else if (isBeat) {
        // Beat tick — medium
        final tickPaint = Paint()
          ..color = const Color(0xFF505050)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height),
          tickPaint,
        );

        // Beat label (e.g., "1.2", "1.3")
        if (ppb >= 30) {
          final barNumber = (beat / beatsPerBar).floor() + 1;
          final beatInBar = (beat % beatsPerBar).floor() + 1;

          if (beatInBar > 1) {
            final subdivisionsVisible = ppb >= 100;

            if (subdivisionsVisible) {
              final textX = x + 4;
              final isOverLoop = loopEnabled && textX >= loopStartX && textX < loopEndX;
              textPainter.text = TextSpan(
                text: '$barNumber.$beatInBar',
                style: TextStyle(
                  color: isOverLoop ? const Color(0xFFFFFFFF) : const Color(0xFFE0E0E0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              );
              textPainter.layout();
              textPainter.paint(canvas, Offset(textX, 2));
            } else {
              final textX = x + 2;
              final isOverLoop = loopEnabled && textX >= loopStartX && textX < loopEndX;
              textPainter.text = TextSpan(
                text: '$barNumber.$beatInBar',
                style: TextStyle(
                  color: isOverLoop ? const Color(0xFFFFFFFF) : const Color(0xFF808080),
                  fontSize: 9,
                ),
              );
              textPainter.layout();
              textPainter.paint(canvas, Offset(textX, 3));
            }
          }
        }
      } else {
        // Subdivision tick — short
        final tickPaint = Paint()
          ..color = const Color(0xFF404040)
          ..strokeWidth = 0.5;
        canvas.drawLine(
          Offset(x, size.height - 2),
          Offset(x, size.height),
          tickPaint,
        );

        // Progressive subdivision labels (bar.beat.sub)
        if (ppb >= 100) {
          final beatFraction = beat % 1.0;
          final isHalfBeat = (beatFraction - 0.5).abs() < 0.01;
          final isQuarterBeat = (beatFraction - 0.25).abs() < 0.01 ||
                                (beatFraction - 0.75).abs() < 0.01;

          final shouldShow = isHalfBeat || (isQuarterBeat && ppb >= 200);

          if (shouldShow) {
            final barNumber = (beat / beatsPerBar).floor() + 1;
            final beatInBar = (beat % beatsPerBar).floor() + 1;
            final subInBeat = (beatFraction * 4).round() + 1;

            final textX = x + 2;
            final isOverLoop = loopEnabled && textX >= loopStartX && textX < loopEndX;

            textPainter.text = TextSpan(
              text: '$barNumber.$beatInBar.$subInBeat',
              style: TextStyle(
                color: isOverLoop ? const Color(0xFFFFFFFF) : const Color(0xFF808080),
                fontSize: 9,
              ),
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(textX, 3));
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SamplerRulerPainter oldDelegate) {
    return pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        sampleDuration != oldDelegate.sampleDuration ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStartSeconds != oldDelegate.loopStartSeconds ||
        loopEndSeconds != oldDelegate.loopEndSeconds ||
        originalBpm != oldDelegate.originalBpm ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        hoverSeconds != oldDelegate.hoverSeconds;
  }
}
