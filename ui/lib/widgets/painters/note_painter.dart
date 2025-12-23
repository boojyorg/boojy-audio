import 'package:flutter/material.dart';
import '../../models/midi_note_data.dart';

/// Custom painter for MIDI notes in piano roll
class NotePainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final MidiNoteData? previewNote;
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final int maxMidiNote;
  final Offset? selectionStart;
  final Offset? selectionEnd;

  NotePainter({
    required this.notes,
    this.previewNote,
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.maxMidiNote,
    this.selectionStart,
    this.selectionEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw all notes
    for (final note in notes) {
      _drawNote(canvas, note, isSelected: note.isSelected);
    }

    // Draw preview note
    if (previewNote != null) {
      _drawNote(canvas, previewNote!, isPreview: true);
    }

    // Draw selection rectangle
    if (selectionStart != null && selectionEnd != null) {
      final rect = Rect.fromPoints(selectionStart!, selectionEnd!);

      // Fill
      final fillPaint = Paint()
        ..color = const Color(0xFF00BCD4).withValues(alpha: 0.2) // Cyan fill
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);

      // Border
      final borderPaint = Paint()
        ..color = const Color(0xFF00BCD4) // Cyan border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawNote(Canvas canvas, MidiNoteData note,
      {bool isSelected = false, bool isPreview = false}) {
    final x = note.startTime * pixelsPerBeat;
    final y = (maxMidiNote - note.note) * pixelsPerNote;
    final width = note.duration * pixelsPerBeat;
    final height = pixelsPerNote - 2; // Small gap between notes

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 1, width, height),
      const Radius.circular(4), // Slightly rounded corners
    );

    // Note fill - cyan theme
    final fillPaint = Paint()
      ..color = isPreview
          ? const Color(0xFF00BCD4).withValues(alpha: 0.5) // Cyan preview
          : const Color(0xFF00BCD4); // Solid cyan for notes

    canvas.drawRRect(rect, fillPaint);

    // Note border
    final borderPaint = Paint()
      ..color = isSelected
          ? Colors.white // White border when selected (visible on dark bg)
          : const Color(0xFF00838F) // Darker cyan border normally
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.5 : 1.5;

    canvas.drawRRect(rect, borderPaint);

    // Draw note name inside
    if (width > 30) {
      // Only show label if note is wide enough
      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );

      textPainter.text = TextSpan(
        text: note.noteName, // e.g., "G5", "D#4", "C3"
        style: TextStyle(
          color:
              Colors.white.withValues(alpha: 0.9), // White text on cyan background
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );

      textPainter.layout();

      // Position label at left edge with small padding
      final textX = x + 4;
      final textY = y + (height / 2) - (textPainter.height / 2) + 1;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    // Draw resize handles on selected notes (touch-friendly)
    if (isSelected && !isPreview) {
      final handlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      const handleWidth = 6.0;
      final noteRect = Rect.fromLTWH(x, y + 1, width, height);

      // Left handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              noteRect.left - 1, noteRect.top, handleWidth, noteRect.height),
          const Radius.circular(2),
        ),
        handlePaint,
      );

      // Right handle
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(noteRect.right - handleWidth + 1, noteRect.top,
              handleWidth, noteRect.height),
          const Radius.circular(2),
        ),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(NotePainter oldDelegate) {
    return notes != oldDelegate.notes ||
        previewNote != oldDelegate.previewNote ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        pixelsPerNote != oldDelegate.pixelsPerNote ||
        selectionStart != oldDelegate.selectionStart ||
        selectionEnd != oldDelegate.selectionEnd;
  }
}
