import 'package:flutter/material.dart';

/// Painter for the Audio Editor waveform display.
/// Renders waveform peaks with grid overlay and loop region dimming.
class WaveformEditorPainter extends CustomPainter {
  /// Waveform peak data (alternating min/max values, normalized -1.0 to 1.0)
  final List<double> peaks;

  /// Pixels per beat for horizontal scaling
  final double pixelsPerBeat;

  /// Total beats to render (includes scroll buffer)
  final double totalBeats;

  /// Audio content duration in beats (for correct waveform scaling)
  final double contentBeats;

  /// Active beats (loop length)
  final double activeBeats;

  /// Whether loop is enabled
  final bool loopEnabled;

  /// Loop start position in beats
  final double loopStart;

  /// Loop end position in beats
  final double loopEnd;

  /// Beats per bar for grid lines
  final int beatsPerBar;

  /// Waveform fill color
  final Color waveformColor;

  /// Grid line color (subdivision lines)
  final Color gridLineColor;

  /// Bar line color (stronger lines at bar boundaries)
  final Color barLineColor;

  /// Whether audio is reversed (flip waveform horizontally)
  final bool reversed;

  /// Visual gain multiplier for normalize preview
  final double normalizeGain;

  WaveformEditorPainter({
    required this.peaks,
    required this.pixelsPerBeat,
    required this.totalBeats,
    required this.contentBeats,
    required this.activeBeats,
    required this.loopEnabled,
    required this.loopStart,
    required this.loopEnd,
    required this.beatsPerBar,
    required this.waveformColor,
    required this.gridLineColor,
    required this.barLineColor,
    this.reversed = false,
    this.normalizeGain = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw grid background
    _drawGrid(canvas, size);

    // 2. Draw waveform
    _drawWaveform(canvas, size);

    // 3. Draw loop region dimming overlay
    if (loopEnabled) {
      _drawLoopOverlay(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridLineColor
      ..strokeWidth = 1.0;

    final barPaint = Paint()
      ..color = barLineColor
      ..strokeWidth = 1.5;

    // Draw vertical grid lines
    const gridDivision = 0.25; // 1/16th note
    final totalGridLines = (totalBeats / gridDivision).ceil();

    for (int i = 0; i <= totalGridLines; i++) {
      final beat = i * gridDivision;
      final x = beat * pixelsPerBeat;

      if (x > size.width) break;

      // Determine line weight based on hierarchy
      final isBar = (beat % beatsPerBar) < 0.001;
      final isBeat = (beat % 1.0) < 0.001;

      if (isBar) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), barPaint);
      } else if (isBeat) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      } else {
        // Subdivision lines (lighter)
        final subPaint = Paint()
          ..color = gridLineColor.withValues(alpha: 0.3)
          ..strokeWidth = 0.5;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), subPaint);
      }
    }

    // Draw horizontal center line
    final centerPaint = Paint()
      ..color = gridLineColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), centerPaint);
  }

  void _drawWaveform(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;

    final waveformPaint = Paint()
      ..color = waveformColor
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final maxAmplitude = size.height / 2 * 0.9; // Leave some padding

    // Calculate how many samples per pixel based on content duration (not total with buffer)
    // The waveform only spans contentBeats, not the full scrollable area
    final contentWidth = contentBeats * pixelsPerBeat;
    final samplesPerPixel = peaks.length / 2 / contentWidth;

    // Draw waveform as filled path
    final path = Path();
    var started = false;

    for (double x = 0; x < size.width; x += 1) {
      // Calculate which peak samples correspond to this x position
      final actualX = reversed ? (size.width - x - 1) : x;
      final sampleIndex = (actualX * samplesPerPixel * 2).floor();

      if (sampleIndex >= peaks.length - 1) continue;

      // Get min/max from peaks (peaks are stored as alternating min/max)
      double minVal = peaks[sampleIndex];
      double maxVal = peaks[sampleIndex + 1];

      // Apply normalize gain for visual preview
      minVal *= normalizeGain;
      maxVal *= normalizeGain;

      // Clamp to valid range
      minVal = minVal.clamp(-1.0, 1.0);
      maxVal = maxVal.clamp(-1.0, 1.0);

      final yMin = centerY - (maxVal * maxAmplitude);

      if (!started) {
        path.moveTo(x, yMin);
        started = true;
      } else {
        path.lineTo(x, yMin);
      }

      // Store for bottom path
    }

    // Draw bottom half (going backwards)
    for (double x = size.width - 1; x >= 0; x -= 1) {
      final actualX = reversed ? (size.width - x - 1) : x;
      final sampleIndex = (actualX * samplesPerPixel * 2).floor();

      if (sampleIndex >= peaks.length - 1) continue;

      double minVal = peaks[sampleIndex];
      minVal *= normalizeGain;
      minVal = minVal.clamp(-1.0, 1.0);

      final yMax = centerY - (minVal * maxAmplitude);
      path.lineTo(x, yMax);
    }

    path.close();
    canvas.drawPath(path, waveformPaint);

    // Draw waveform outline for better visibility
    final outlinePaint = Paint()
      ..color = waveformColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw top outline
    final outlinePath = Path();
    started = false;

    for (double x = 0; x < size.width; x += 1) {
      final actualX = reversed ? (size.width - x - 1) : x;
      final sampleIndex = (actualX * samplesPerPixel * 2).floor();

      if (sampleIndex >= peaks.length - 1) continue;

      double maxVal = peaks[sampleIndex + 1];
      maxVal *= normalizeGain;
      maxVal = maxVal.clamp(-1.0, 1.0);

      final y = centerY - (maxVal * maxAmplitude);

      if (!started) {
        outlinePath.moveTo(x, y);
        started = true;
      } else {
        outlinePath.lineTo(x, y);
      }
    }

    canvas.drawPath(outlinePath, outlinePaint);
  }

  void _drawLoopOverlay(Canvas canvas, Size size) {
    // Dim areas outside the loop region
    final dimPaint = Paint()
      ..color = const Color(0x33000000); // 20% black overlay

    final loopStartX = loopStart * pixelsPerBeat;
    final loopEndX = loopEnd * pixelsPerBeat;

    // Dim before loop
    if (loopStartX > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, loopStartX, size.height),
        dimPaint,
      );
    }

    // Dim after loop
    if (loopEndX < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(loopEndX, 0, size.width - loopEndX, size.height),
        dimPaint,
      );
    }
    // Note: Loop boundary lines are shown in the nav bar above, not here
  }

  @override
  bool shouldRepaint(covariant WaveformEditorPainter oldDelegate) {
    // PERFORMANCE: Use identical() for O(1) reference check on large peak arrays
    // instead of O(n) listEquals on 200K+ elements
    return !identical(peaks, oldDelegate.peaks) ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats ||
        contentBeats != oldDelegate.contentBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        waveformColor != oldDelegate.waveformColor ||
        reversed != oldDelegate.reversed ||
        normalizeGain != oldDelegate.normalizeGain;
  }
}
