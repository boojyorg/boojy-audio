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

  /// Get adaptive grid division based on zoom level
  /// Must match UnifiedNavBarPainter._getGridDivision() for alignment
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return beatsPerBar.toDouble(); // Only bars
    if (pixelsPerBeat < 20) return 1.0; // Bars + beats
    if (pixelsPerBeat < 40) return 0.5; // + half beats
    if (pixelsPerBeat < 80) return 0.25; // + quarter beats
    return 0.125; // + eighth beats
  }

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

    // Draw vertical grid lines using adaptive grid division
    final gridDivision = _getGridDivision();

    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;

      if (x > size.width) break;

      // Determine line weight based on hierarchy (use .abs() for floating point safety)
      final isBar = (beat % beatsPerBar).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

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

    final centerY = size.height / 2;

    // Calculate waveform width based on content duration
    final contentWidth = contentBeats * pixelsPerBeat;
    if (contentWidth <= 0) return;

    final originalPeakCount = peaks.length ~/ 2;
    if (originalPeakCount == 0) return;

    // LOD: Calculate optimal peak count for visible width
    // Target ~1 pixel per peak for crisp detail (like Ableton/arrangement view)
    final targetPeakCount = contentWidth.clamp(100, originalPeakCount.toDouble()).toInt();

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

    final step = contentWidth / peakCount;

    // Create closed polygon path for continuous waveform shape
    final path = Path();

    // Handle reversed playback
    int getIndex(int i) => reversed ? (peakCount - 1 - i) : i;

    // Start at first peak's top
    final firstIdx = getIndex(0);
    double firstMax = renderPeaks[firstIdx * 2 + 1] * normalizeGain;
    firstMax = firstMax.clamp(-1.0, 1.0);
    final firstTopY = centerY - (firstMax * centerY * 0.9);
    path.moveTo(step / 2, firstTopY);

    // Trace TOP edge (max values) left to right
    for (int i = 1; i < peakCount; i++) {
      final idx = getIndex(i);
      final x = i * step + step / 2;
      double maxVal = renderPeaks[idx * 2 + 1] * normalizeGain;
      maxVal = maxVal.clamp(-1.0, 1.0);
      final topY = centerY - (maxVal * centerY * 0.9);
      path.lineTo(x, topY);
    }

    // Trace BOTTOM edge (min values) right to left
    for (int i = peakCount - 1; i >= 0; i--) {
      final idx = getIndex(i);
      final x = i * step + step / 2;
      double minVal = renderPeaks[idx * 2] * normalizeGain;
      minVal = minVal.clamp(-1.0, 1.0);
      final bottomY = centerY - (minVal * centerY * 0.9);
      path.lineTo(x, bottomY);
    }

    path.close();

    // Use opaque color for both fill and stroke so they match exactly
    final waveColor = waveformColor.withValues(alpha: 0.85);

    // Fill the waveform
    final fillPaint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Add stroke to give waveform body (dynamic based on zoom)
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

      if (groupMin != double.infinity) {
        result.add(groupMin);
        result.add(groupMax);
      }
    }

    return result;
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
