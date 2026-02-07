import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Custom painter for sampler waveform with loop region overlay and envelope.
///
/// Features:
/// - Real min/max waveform peaks (same style as timeline WaveformEditorPainter)
/// - Loop region overlay: bright inside markers, dimmed outside
/// - Loop start/end marker lines (vertical, draggable)
/// - Envelope overlay (orange attack→sustain→release)
/// - Center line + time grid (seconds)
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

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || sampleDuration <= 0) return;

    final totalWidth = sampleDuration * pixelsPerSecond;
    final centerY = size.height / 2;

    // Draw time grid (seconds)
    _drawTimeGrid(canvas, size, totalWidth);

    // Draw loop region overlay
    _drawLoopRegion(canvas, size, totalWidth);

    // Draw waveform
    _drawWaveform(canvas, size, totalWidth, centerY);

    // Draw center line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(math.min(totalWidth, size.width), centerY),
      Paint()
        ..color = colors.textMuted.withAlpha(60)
        ..strokeWidth = 0.5,
    );

    // Draw envelope overlay
    _drawEnvelope(canvas, size, totalWidth, centerY);

    // Draw loop markers
    _drawLoopMarkers(canvas, size, totalWidth);
  }

  void _drawTimeGrid(Canvas canvas, Size size, double totalWidth) {
    final gridPaint = Paint()
      ..color = colors.divider.withAlpha(40)
      ..strokeWidth = 0.5;

    // Determine interval based on zoom
    double interval;
    if (pixelsPerSecond > 200) {
      interval = 0.1; // 100ms
    } else if (pixelsPerSecond > 80) {
      interval = 0.25; // 250ms
    } else if (pixelsPerSecond > 40) {
      interval = 0.5; // 500ms
    } else {
      interval = 1.0; // 1s
    }

    final maxX = math.min(totalWidth, size.width * 3); // Don't draw beyond visible
    for (double t = interval; t * pixelsPerSecond < maxX; t += interval) {
      final x = t * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawLoopRegion(Canvas canvas, Size size, double totalWidth) {
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;
    final sampleEndX = math.min(totalWidth, size.width * 3);

    if (loopEnabled) {
      // Dim outside the loop region
      final dimPaint = Paint()..color = Colors.black.withAlpha(80);

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
  }

  void _drawWaveform(Canvas canvas, Size size, double totalWidth, double centerY) {
    if (peaks.isEmpty) return;

    final waveformColor = colors.accent.withAlpha(180);
    final waveformPaint = Paint()
      ..color = waveformColor
      ..style = PaintingStyle.fill;

    // Peaks are alternating min/max pairs
    final peakCount = peaks.length ~/ 2;
    if (peakCount == 0) return;

    final path = Path();
    final step = totalWidth / peakCount;

    // Trace top edge (max values) left to right
    path.moveTo(0, centerY);
    for (int i = 0; i < peakCount; i++) {
      final x = i * step + step / 2;
      final maxVal = peaks[i * 2 + 1].clamp(-1.0, 1.0);
      final topY = centerY - (maxVal * centerY * 0.85);
      path.lineTo(x, topY);
    }

    // Trace bottom edge (min values) right to left
    for (int i = peakCount - 1; i >= 0; i--) {
      final x = i * step + step / 2;
      final minVal = peaks[i * 2].clamp(-1.0, 1.0);
      final bottomY = centerY - (minVal * centerY * 0.85);
      path.lineTo(x, bottomY);
    }

    path.close();
    canvas.drawPath(path, waveformPaint);
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
    return peaks != oldDelegate.peaks ||
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
/// Shows time markings and loop marker handles.
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

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = colors.divider
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Determine tick interval based on zoom level
    double majorInterval;
    int subdivisions;
    if (pixelsPerSecond > 200) {
      majorInterval = 0.5;
      subdivisions = 5; // every 100ms
    } else if (pixelsPerSecond > 80) {
      majorInterval = 1.0;
      subdivisions = 4; // every 250ms
    } else if (pixelsPerSecond > 40) {
      majorInterval = 1.0;
      subdivisions = 2; // every 500ms
    } else {
      majorInterval = 2.0;
      subdivisions = 2; // every 1s
    }

    final subInterval = majorInterval / subdivisions;
    final maxTime = sampleDuration;

    // Draw ticks and labels
    for (double t = 0; t <= maxTime + subInterval; t += subInterval) {
      final x = t * pixelsPerSecond;
      if (x > size.width * 3) break;

      final isMajor = (t / majorInterval - (t / majorInterval).roundToDouble()).abs() < 0.001;

      canvas.drawLine(
        Offset(x, isMajor ? 0 : size.height * 0.6),
        Offset(x, size.height),
        tickPaint,
      );

      if (isMajor) {
        final label = _formatTime(t);
        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 9,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 2, 1));
      }
    }

    // Draw loop region on ruler
    final loopStartX = loopStartSeconds * pixelsPerSecond;
    final loopEndX = loopEndSeconds * pixelsPerSecond;

    final loopColor = loopEnabled
        ? colors.accent
        : const Color(0xFF555555);

    // Loop region bar
    final loopRect = Rect.fromLTWH(
      loopStartX,
      0,
      loopEndX - loopStartX,
      4,
    );
    canvas.drawRect(loopRect, Paint()..color = loopColor);

    // Loop marker handles (small rectangles)
    final handlePaint = Paint()..color = loopColor;
    canvas.drawRect(
      Rect.fromLTWH(loopStartX - 1, 0, 3, size.height * 0.6),
      handlePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(loopEndX - 2, 0, 3, size.height * 0.6),
      handlePaint,
    );
  }

  String _formatTime(double seconds) {
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
