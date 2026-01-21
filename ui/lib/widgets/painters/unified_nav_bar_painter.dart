import 'package:flutter/material.dart';

/// Painter for the unified navigation bar that combines loop region and bar numbers.
/// Single row (~24px) that handles both loop visualization and time display.
class UnifiedNavBarPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double totalBeats;
  final bool loopEnabled;
  final double loopStart;
  final double loopEnd;
  final double? insertMarkerPosition;
  final double? playheadPosition; // in beats (null = not shown)
  final double? hoverBeat; // For loop edge hover feedback
  final bool isHoveringPlayhead; // For expanded hover state
  final int beatsPerBar;

  UnifiedNavBarPainter({
    required this.pixelsPerBeat,
    required this.totalBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.insertMarkerPosition,
    this.playheadPosition,
    this.hoverBeat,
    this.isHoveringPlayhead = false,
    this.beatsPerBar = 4,
  });

  /// Get adaptive grid division based on zoom level
  /// Must match TimelineGridPainter._getGridDivision() for alignment
  double _getGridDivision() {
    if (pixelsPerBeat < 10) return beatsPerBar.toDouble();   // Only bars
    if (pixelsPerBeat < 20) return 1.0;   // Bars + beats
    if (pixelsPerBeat < 40) return 0.5;   // + half beats
    if (pixelsPerBeat < 80) return 0.25;  // + quarter beats
    return 0.125;                          // + eighth beats
  }

  /// Get bar number display interval based on zoom level
  /// At low zoom, show fewer bar numbers to prevent overlap
  int _getBarNumberInterval() {
    if (pixelsPerBeat < 1.75) return 8;   // Show every 8 bars
    if (pixelsPerBeat < 3.5) return 4;    // Show every 4 bars
    if (pixelsPerBeat < 7) return 2;      // Show every 2 bars
    return 1;                              // Show every bar
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw dark background
    final darkBgPaint = Paint()..color = const Color(0xFF1A1A1A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkBgPaint);

    // 2. Draw loop region (if enabled)
    if (loopEnabled) {
      _drawLoopRegion(canvas, size);
    }

    // 3. Draw grid lines and bar numbers
    _drawGridAndNumbers(canvas, size);

    // 4. Draw insert marker (if set)
    if (insertMarkerPosition != null) {
      _drawInsertMarker(canvas, size, insertMarkerPosition!);
    }

    // 5. Draw playhead (if set)
    if (playheadPosition != null) {
      _drawPlayhead(canvas, size);
    }
  }

  void _drawLoopRegion(Canvas canvas, Size size) {
    final loopStartX = loopStart * pixelsPerBeat;
    final loopEndX = loopEnd * pixelsPerBeat;
    final loopWidth = loopEndX - loopStartX;

    if (loopWidth <= 0) return;

    final loopRect = Rect.fromLTWH(loopStartX, 0, loopWidth, size.height);

    // Fill with darker orange
    final fillPaint = Paint()..color = const Color(0xFFB36800);
    canvas.drawRect(loopRect, fillPaint);

    // Draw bright orange border
    final borderPaint = Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(loopRect, borderPaint);

    // Highlight edges on hover (if within 10px of an edge)
    if (hoverBeat != null) {
      final hoverX = hoverBeat! * pixelsPerBeat;
      const edgeHitZone = 10.0;

      // Check if hovering near start edge
      if ((hoverX - loopStartX).abs() < edgeHitZone) {
        final highlightPaint = Paint()
          ..color = const Color(0xFFFFB74D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
        canvas.drawLine(
          Offset(loopStartX, 0),
          Offset(loopStartX, size.height),
          highlightPaint,
        );
      }
      // Check if hovering near end edge
      else if ((hoverX - loopEndX).abs() < edgeHitZone) {
        final highlightPaint = Paint()
          ..color = const Color(0xFFFFB74D)
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
    final gridDivision = _getGridDivision();
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    // Draw grid lines and numbers
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      if (x > size.width) break;

      final isBar = (beat % beatsPerBar).abs() < 0.001;
      final isBeat = (beat % 1.0).abs() < 0.001;

      // Draw tick lines at bottom (adjusted for 24px height)
      if (isBar) {
        // Bar line - taller tick
        final tickPaint = Paint()
          ..color = const Color(0xFF707070)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(x, size.height - 6),
          Offset(x, size.height),
          tickPaint,
        );

        // Bar number (y-offset adjusted for 24px)
        // Only show at interval to prevent overlap when zoomed out
        final barNumber = (beat / beatsPerBar).floor() + 1;
        final barInterval = _getBarNumberInterval();
        if (barNumber % barInterval == 1 || barInterval == 1) {
          textPainter.text = TextSpan(
            text: '$barNumber',
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x + 4, 2));
        }
      } else if (isBeat) {
        // Beat tick - medium height
        final tickPaint = Paint()
          ..color = const Color(0xFF505050)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height),
          tickPaint,
        );

        // Show beat number when zoomed in (e.g., 1.2, 1.3, 1.4)
        // Beat 1 is skipped since bar number is already shown
        // Same size as bar numbers for visual consistency
        if (pixelsPerBeat >= 30) {
          final barNumber = (beat / beatsPerBar).floor() + 1;
          final beatInBar = (beat % beatsPerBar).floor() + 1;

          if (beatInBar > 1) {
            final textX = x + 4;
            final loopStartX = loopStart * pixelsPerBeat;
            final loopEndX = loopEnd * pixelsPerBeat;
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
          }
        }
      } else {
        // Subdivision tick - short
        final tickPaint = Paint()
          ..color = const Color(0xFF404040)
          ..strokeWidth = 0.5;
        canvas.drawLine(
          Offset(x, size.height - 2),
          Offset(x, size.height),
          tickPaint,
        );

        // Show 16th note subdivision labels when very zoomed in
        // Only show at quarter-beat positions (0.25, 0.5, 0.75)
        // Format: 1.1.2, 1.1.3, 1.1.4 (bar.beat.subdivision)
        // Same size as bar/beat labels for visual consistency
        if (pixelsPerBeat >= 100) {
          final beatFraction = beat % 1.0;
          // Check if this is a quarter-beat position (16th note)
          final isQuarterBeat = (beatFraction - 0.25).abs() < 0.01 ||
                                (beatFraction - 0.5).abs() < 0.01 ||
                                (beatFraction - 0.75).abs() < 0.01;

          if (isQuarterBeat) {
            final barNumber = (beat / beatsPerBar).floor() + 1;
            final beatInBar = (beat % beatsPerBar).floor() + 1;
            final subInBeat = (beatFraction * 4).round() + 1; // 1-indexed: .25→2, .5→3, .75→4

            final textX = x + 4;
            final loopStartX = loopStart * pixelsPerBeat;
            final loopEndX = loopEnd * pixelsPerBeat;
            final isOverLoop = loopEnabled && textX >= loopStartX && textX < loopEndX;

            textPainter.text = TextSpan(
              text: '$barNumber.$beatInBar.$subInBeat',
              style: TextStyle(
                color: isOverLoop ? const Color(0xFFFFFFFF) : const Color(0xFFE0E0E0),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(textX, 2));
          }
        }
      }
    }
  }

  void _drawInsertMarker(Canvas canvas, Size size, double beat) {
    final x = beat * pixelsPerBeat;

    // Vertical line
    final linePaint = Paint()
      ..color = const Color(0xFF4FC3F7) // Light blue
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Small diamond at top
    final diamondPath = Path()
      ..moveTo(x, 4)
      ..lineTo(x - 4, 0)
      ..lineTo(x, -4)
      ..lineTo(x + 4, 0)
      ..close();

    final diamondPaint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..style = PaintingStyle.fill;
    canvas.drawPath(diamondPath, diamondPaint);
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    if (playheadPosition == null) return;

    final x = playheadPosition! * pixelsPerBeat;
    const playheadColor = Color(0xFF3B82F6); // Blue

    // Head radius: 5px default, 6px on hover
    final headRadius = isHoveringPlayhead ? 6.0 : 5.0;
    const lineWidth = 2.0;

    // Draw vertical line (full height, through circle center)
    final linePaint = Paint()
      ..color = playheadColor
      ..strokeWidth = lineWidth;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Draw solid circle head at top
    final circlePaint = Paint()
      ..color = playheadColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, headRadius + 2), headRadius, circlePaint);

    // Add glow effect on hover
    if (isHoveringPlayhead) {
      final glowPaint = Paint()
        ..color = playheadColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, headRadius + 2), headRadius + 3, glowPaint);
      // Redraw circle on top of glow
      canvas.drawCircle(Offset(x, headRadius + 2), headRadius, circlePaint);
    }
  }

  @override
  bool shouldRepaint(UnifiedNavBarPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        totalBeats != oldDelegate.totalBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd ||
        insertMarkerPosition != oldDelegate.insertMarkerPosition ||
        playheadPosition != oldDelegate.playheadPosition ||
        hoverBeat != oldDelegate.hoverBeat ||
        isHoveringPlayhead != oldDelegate.isHoveringPlayhead ||
        beatsPerBar != oldDelegate.beatsPerBar;
  }
}
