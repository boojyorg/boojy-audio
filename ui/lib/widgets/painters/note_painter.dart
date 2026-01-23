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

  /// Ghost notes from other MIDI tracks (rendered at 30% opacity)
  final List<MidiNoteData> ghostNotes;

  /// Whether to show ghost notes
  final bool showGhostNotes;

  /// Fold mode - when provided, only these pitches are visible (in order)
  /// Used for calculating Y coordinates in fold view
  final List<int>? foldedPitches;

  NotePainter({
    required this.notes,
    this.previewNote,
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.maxMidiNote,
    this.selectionStart,
    this.selectionEnd,
    this.ghostNotes = const [],
    this.showGhostNotes = false,
    this.foldedPitches,
  });

  /// Calculate Y coordinate for a MIDI note (fold-aware)
  double _calculateNoteY(int midiNote) {
    if (foldedPitches == null) {
      return (maxMidiNote - midiNote) * pixelsPerNote;
    }
    final rowIndex = foldedPitches!.indexOf(midiNote);
    if (rowIndex < 0) return -pixelsPerNote; // Off-screen if not in fold
    return rowIndex * pixelsPerNote;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw ghost notes first (behind regular notes)
    if (showGhostNotes) {
      for (final note in ghostNotes) {
        _drawGhostNote(canvas, note);
      }
    }

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

  /// Draw a ghost note (from another track) at 30% opacity
  void _drawGhostNote(Canvas canvas, MidiNoteData note) {
    final x = note.startTime * pixelsPerBeat;
    final y = _calculateNoteY(note.note);
    if (y < 0) return; // Skip notes not visible in fold mode
    final width = note.duration * pixelsPerBeat;
    final height = pixelsPerNote - 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 1, width, height),
      const Radius.circular(4),
    );

    // Ghost note fill - grey at 30% opacity
    final fillPaint = Paint()
      ..color = const Color(0xFF808080).withValues(alpha: 0.3);
    canvas.drawRRect(rect, fillPaint);

    // Ghost note border - subtle
    final borderPaint = Paint()
      ..color = const Color(0xFF606060).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(rect, borderPaint);
  }

  void _drawNote(Canvas canvas, MidiNoteData note,
      {bool isSelected = false, bool isPreview = false}) {
    final x = note.startTime * pixelsPerBeat;
    final y = _calculateNoteY(note.note);
    if (y < 0) return; // Skip notes not visible in fold mode
    final width = note.duration * pixelsPerBeat;
    final height = pixelsPerNote - 2; // Small gap between notes

    // Calculate velocity-based brightness (not transparency)
    // vel 100 = standard cyan, < 100 = darker, > 100 = brighter
    const baseColor = Color(0xFF00BCD4);
    final baseHsl = HSLColor.fromColor(baseColor);
    final baseLightness = baseHsl.lightness; // ~0.42

    double lightness;
    if (note.velocity <= 100) {
      // 0-100: scale from 0.28 (dim) to baseLightness
      lightness = 0.28 + (note.velocity / 100.0) * (baseLightness - 0.28);
    } else {
      // 100-127: scale from baseLightness to 0.54 (brighter)
      final extra = (note.velocity - 100) / 27.0;
      lightness = baseLightness + extra * (0.54 - baseLightness);
    }

    final noteColor = baseHsl.withLightness(lightness).toColor();

    // Note rect - same size for all notes (rounded corners)
    final noteRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 1, width, height),
      const Radius.circular(4),
    );

    // Note fill - velocity-based brightness (no transparency)
    final fillPaint = Paint()
      ..color = isPreview
          ? baseColor.withValues(alpha: 0.5) // Preview: semi-transparent
          : noteColor; // Regular: velocity brightness

    canvas.drawRRect(noteRect, fillPaint);

    // Selected notes get interior white border (2px inset)
    if (isSelected) {
      const borderWidth = 2.0;
      final borderRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x + borderWidth / 2,
          y + 1 + borderWidth / 2,
          width - borderWidth,
          height - borderWidth,
        ),
        const Radius.circular(3),
      );
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth;
      canvas.drawRRect(borderRect, borderPaint);
    }

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

  }

  /// Compare two lists for equality (used for foldedPitches)
  bool _listEquals(List<int>? a, List<int>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(NotePainter oldDelegate) {
    return notes != oldDelegate.notes ||
        previewNote != oldDelegate.previewNote ||
        pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        pixelsPerNote != oldDelegate.pixelsPerNote ||
        selectionStart != oldDelegate.selectionStart ||
        selectionEnd != oldDelegate.selectionEnd ||
        ghostNotes != oldDelegate.ghostNotes ||
        showGhostNotes != oldDelegate.showGhostNotes ||
        !_listEquals(foldedPitches, oldDelegate.foldedPitches);
  }
}
