import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';

/// Painter for velocity editing lane (Ableton-style)
class VelocityLanePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;
  final Color noteColor;

  VelocityLanePainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.totalBeats,
    this.noteColor = const Color(0xFF00BCD4), // Cyan to match notes
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
    const circleRadius = 3.5;

    // Derive darker border color from note color
    final borderColor = HSLColor.fromColor(noteColor)
        .withLightness((HSLColor.fromColor(noteColor).lightness * 0.7).clamp(0.0, 1.0))
        .toColor();

    final linePaint = Paint()
      ..color = noteColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final circleFillPaint = Paint()
      ..color = noteColor
      ..style = PaintingStyle.fill;

    final circleBorderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final note in notes) {
      final x = note.startTime * pixelsPerBeat;
      final width = (note.duration * pixelsPerBeat).clamp(4.0, double.infinity);
      final barHeight = (note.velocity / 127) * laneHeight;
      final y = laneHeight - barHeight;

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
        linePaint,
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
        noteColor != oldDelegate.noteColor;
  }
}
