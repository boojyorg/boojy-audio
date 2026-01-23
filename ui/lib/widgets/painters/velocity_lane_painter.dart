import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';

/// Painter for velocity editing lane (Ableton-style)
/// Each note's velocity indicator uses brightness matching the note color in piano roll.
class VelocityLanePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;
  final String? draggedNoteId;

  VelocityLanePainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.totalBeats,
    this.draggedNoteId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final bgPaint = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw horizontal grid lines at 25%, 50%, 75%, 100%
    final gridPaint = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;

    for (var i = 1; i <= 4; i++) {
      final y = size.height * (1 - i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw vertical bar lines (every 4 beats)
    final barPaint = Paint()
      ..color = const Color(0xFF404040)
      ..strokeWidth = 1;

    for (double beat = 0; beat <= totalBeats; beat += 4) {
      final x = beat * pixelsPerBeat;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), barPaint);
    }

    // Draw velocity indicators for each note
    // Style: vertical line (velocity height) + horizontal line (note duration) + circle at corner
    // Color varies by velocity brightness (matching note_painter.dart)
    const circleRadius = 3.5;

    // Base color for velocity calculation (same as notes)
    const baseColor = Color(0xFF00BCD4);
    final baseHsl = HSLColor.fromColor(baseColor);
    final baseLightness = baseHsl.lightness; // ~0.42

    for (final note in notes) {
      final x = note.startTime * pixelsPerBeat;
      final width = (note.duration * pixelsPerBeat).clamp(4.0, double.infinity);
      final barHeight = (note.velocity / 127) * laneHeight;
      final y = laneHeight - barHeight;

      // Calculate velocity-based brightness (matching note_painter.dart)
      double lightness;
      if (note.velocity <= 100) {
        // 0-100: scale from 0.28 (dim) to baseLightness
        lightness = 0.28 + (note.velocity / 100.0) * (baseLightness - 0.28);
      } else {
        // 100-127: scale from baseLightness to 0.54 (brighter)
        final extra = (note.velocity - 100) / 27.0;
        lightness = baseLightness + extra * (0.54 - baseLightness);
      }
      final velocityColor = baseHsl.withLightness(lightness).toColor();

      // Check if highlighted (selected or being dragged)
      final isHighlighted = note.isSelected || note.id == draggedNoteId;

      // Derive border color - white if highlighted, else darker velocity color
      final borderColor = isHighlighted
          ? Colors.white
          : HSLColor.fromColor(velocityColor)
              .withLightness((lightness * 0.7).clamp(0.0, 1.0))
              .toColor();

      final linePaint = Paint()
        ..color = velocityColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final horizontalLinePaint = Paint()
        ..color = isHighlighted ? Colors.white : velocityColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final circleFillPaint = Paint()
        ..color = velocityColor
        ..style = PaintingStyle.fill;

      final circleBorderPaint = Paint()
        ..color = borderColor
        ..strokeWidth = isHighlighted ? 1.5 : 1.0
        ..style = PaintingStyle.stroke;

      // Draw vertical line (from bottom to velocity height)
      canvas.drawLine(
        Offset(x + 1, laneHeight),
        Offset(x + 1, y),
        linePaint,
      );

      // Draw horizontal line at top (note duration)
      canvas.drawLine(
        Offset(x + 1, y),
        Offset(x + width - 1, y),
        horizontalLinePaint,
      );

      // Draw circle at top-left corner
      final circleCenter = Offset(x + 1, y);
      canvas.drawCircle(circleCenter, circleRadius, circleFillPaint);
      canvas.drawCircle(circleCenter, circleRadius, circleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(VelocityLanePainter oldDelegate) {
    return notes != oldDelegate.notes ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        laneHeight != oldDelegate.laneHeight ||
        totalBeats != oldDelegate.totalBeats ||
        draggedNoteId != oldDelegate.draggedNoteId;
  }
}
