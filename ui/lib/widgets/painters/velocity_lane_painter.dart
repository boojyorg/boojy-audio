import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';

/// Painter for velocity editing lane (Ableton-style)
class VelocityLanePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double pixelsPerBeat;
  final double laneHeight;
  final double totalBeats;

  VelocityLanePainter({
    required this.notes,
    required this.pixelsPerBeat,
    required this.laneHeight,
    required this.totalBeats,
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

    // Draw velocity bars for each note
    final barFillPaint = Paint()
      ..color = const Color(0xFF00BCD4) // Cyan to match notes
      ..style = PaintingStyle.fill;

    final barBorderPaint = Paint()
      ..color = const Color(0xFF00838F) // Darker cyan border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final note in notes) {
      final x = note.startTime * pixelsPerBeat;
      final width = (note.duration * pixelsPerBeat).clamp(4.0, double.infinity);
      final barHeight = (note.velocity / 127) * laneHeight;
      final y = laneHeight - barHeight;

      // Draw velocity bar
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y, width - 2, barHeight),
        const Radius.circular(2),
      );

      canvas.drawRRect(barRect, barFillPaint);
      canvas.drawRRect(barRect, barBorderPaint);

      // Draw velocity value text for wider notes
      if (width > 25) {
        final textPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );

        textPainter.text = TextSpan(
          text: '${note.velocity}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        );

        textPainter.layout();
        final textX = x + (width - textPainter.width) / 2;
        final textY = y + 2;

        if (barHeight > 14) {
          textPainter.paint(canvas, Offset(textX, textY));
        }
      }
    }
  }

  @override
  bool shouldRepaint(VelocityLanePainter oldDelegate) {
    return notes != oldDelegate.notes ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        laneHeight != oldDelegate.laneHeight ||
        totalBeats != oldDelegate.totalBeats;
  }
}
