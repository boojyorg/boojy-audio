import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'dart:math' as math;
import '../../../models/midi_note_data.dart';

/// Painter for mini MIDI clip preview with dynamic height based on note range.
///
/// Height formula:
/// - Range 1-8 semitones: height = range x 12.5% of content area
/// - Range 9+: Full height (100%), notes compress to fit
class MidiClipPainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double clipDuration; // Total clip duration in beats (arrangement length)
  final double loopLength; // Loop length in beats
  final double contentStartOffset; // Which beat of content to start from (Piano Roll Start field)
  final Color trackColor;

  MidiClipPainter({
    required this.notes,
    required this.clipDuration,
    required this.loopLength,
    required this.trackColor,
    this.contentStartOffset = 0.0,
  });

  /// Get lighter shade of track color for notes
  Color _getLighterColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.85)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || clipDuration == 0) return;

    // Filter notes that are visible (within loopLength, accounting for contentStartOffset)
    final visibleNotes = notes.where((n) {
      final relativeStart = n.startTime - contentStartOffset;
      // Include notes that are within the loop boundary
      return relativeStart < loopLength && relativeStart + n.duration > 0;
    }).toList();

    if (visibleNotes.isEmpty) return;

    // Find note range for vertical scaling (using visible notes only)
    final minNote = visibleNotes.map((n) => n.note).reduce(math.min);
    final maxNote = visibleNotes.map((n) => n.note).reduce(math.max);
    final noteRange = maxNote - minNote + 1;

    // Calculate dynamic height based on note range
    // Range 1-8: 12.5% per semitone, Range 9+: full height with compression
    final double heightPercentage;
    final double noteSlotHeight;

    if (noteRange <= 8) {
      heightPercentage = noteRange * 0.125;
      noteSlotHeight = size.height * 0.125;
    } else {
      heightPercentage = 1.0;
      noteSlotHeight = size.height / noteRange;
    }

    final usedHeight = size.height * heightPercentage;
    final topOffset = size.height - usedHeight; // Anchor notes to bottom

    // Calculate pixels per beat from actual content area width
    final pixelsPerBeat = size.width / clipDuration;

    // Use lighter shade of track color for notes
    final noteColor = _getLighterColor(trackColor);
    final notePaint = Paint()
      ..color = noteColor
      ..style = PaintingStyle.fill;

    // Calculate number of loop iterations to draw
    // Notes repeat every loopLength beats until clipDuration is reached
    final numLoops = loopLength > 0 ? (clipDuration / loopLength).ceil() : 1;

    // Draw notes for each loop iteration
    for (int loop = 0; loop < numLoops; loop++) {
      final loopOffsetBeats = loop * loopLength;

      for (final note in visibleNotes) {
        // Shift note position by contentStartOffset
        final noteRelativeStart = note.startTime - contentStartOffset;
        final noteDurationBeats = note.duration;

        // Skip notes that start before the content offset (for first loop)
        if (noteRelativeStart < 0 && loop == 0) continue;

        // Skip notes that are beyond loopLength
        if (noteRelativeStart >= loopLength) continue;

        // Calculate absolute position in the clip
        final noteAbsoluteStart = loopOffsetBeats + math.max(0.0, noteRelativeStart);

        // Skip notes that start beyond the clip duration
        if (noteAbsoluteStart >= clipDuration) continue;

        // Handle notes that start before contentStartOffset but extend past it
        double x;
        double width;
        if (noteRelativeStart < 0 && loop == 0) {
          // Note starts before offset - clip the beginning
          x = loopOffsetBeats * pixelsPerBeat;
          width = (noteDurationBeats + noteRelativeStart) * pixelsPerBeat;
        } else {
          x = noteAbsoluteStart * pixelsPerBeat;
          width = noteDurationBeats * pixelsPerBeat;
        }

        // Truncate width if note extends beyond loop boundary or clip duration
        final noteEndBeats = noteAbsoluteStart + noteDurationBeats;
        final loopEndBeats = loopOffsetBeats + loopLength;
        final maxEndBeats = math.min(loopEndBeats, clipDuration);
        if (noteEndBeats > maxEndBeats) {
          width = (maxEndBeats - noteAbsoluteStart) * pixelsPerBeat;
        }

        // Calculate Y position based on note's position in range
        final notePosition = note.note - minNote;
        final y = topOffset + (usedHeight - (notePosition + 1) * noteSlotHeight);
        final height = noteSlotHeight - 1; // 1px gap between notes

        // Skip notes that would start beyond the clip
        if (x >= size.width) continue;

        // Clip width to not exceed the clip boundary
        if (x + width > size.width) {
          width = size.width - x;
        }

        // Skip if width is too small
        if (width <= 0) continue;

        // Draw note rectangle with slight rounding
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, math.max(width, 2.0), math.max(height, 2.0)),
          const Radius.circular(2),
        );

        canvas.drawRRect(rect, notePaint);
      }
    }
  }

  @override
  bool shouldRepaint(MidiClipPainter oldDelegate) {
    return !listEquals(notes, oldDelegate.notes) ||
           clipDuration != oldDelegate.clipDuration ||
           loopLength != oldDelegate.loopLength ||
           contentStartOffset != oldDelegate.contentStartOffset ||
           trackColor != oldDelegate.trackColor;
  }
}
