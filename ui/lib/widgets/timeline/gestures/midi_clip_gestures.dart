import '../../../models/midi_note_data.dart';

/// MIDI clip gesture helpers that are still in use.
///
/// This file used to hold a full set of drag/resize/trim state classes and
/// calculators for an alternative gesture path that was never wired up; those
/// were removed as dead code. Only [adjustNotesForTrim] remains — it is used by
/// `clip_overlap_handler.dart` when a clip's start is trimmed by overlap
/// resolution.
class MidiClipGestureUtils {
  MidiClipGestureUtils._();

  /// Filter and adjust notes after a left-edge trim.
  ///
  /// Drops notes that end before the trim point, shifts the rest so they are
  /// relative to the new clip start, truncates a note straddling the trim
  /// point, and drops any note left with non-positive duration.
  static List<MidiNoteData> adjustNotesForTrim({
    required List<MidiNoteData> notes,
    required double trimOffset,
  }) {
    return notes
        .where((note) {
          // Keep notes that end after the trim point
          return note.endTime > trimOffset;
        })
        .map((note) {
          // Adjust note start times relative to new clip start
          final adjustedStart = note.startTime - trimOffset;
          if (adjustedStart < 0) {
            // Note starts before trim point - truncate it
            return note.copyWith(
              startTime: 0,
              duration: note.duration + adjustedStart,
            );
          }
          return note.copyWith(startTime: adjustedStart);
        })
        .where((note) => note.duration > 0)
        .toList();
  }
}
