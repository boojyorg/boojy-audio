import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/midi_note_data.dart';

void main() {
  group('MidiNoteData', () {
    group('constructor', () {
      test('creates note with required parameters', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );

        expect(note.note, 60);
        expect(note.velocity, 100);
        expect(note.startTime, 0.0);
        expect(note.duration, 1.0);
        expect(note.isSelected, false);
        expect(note.id, isNotEmpty);
      });

      test('creates note with custom id', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'custom_id',
        );

        expect(note.id, 'custom_id');
      });

      test('generates unique ids for different notes', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );
        final note2 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );

        expect(note1.id, isNot(note2.id));
      });
    });

    group('endTime', () {
      test('calculates end time correctly', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 2.0,
          duration: 1.5,
        );

        expect(note.endTime, 3.5);
      });
    });

    group('noteName', () {
      test('returns C4 for MIDI note 60', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );

        expect(note.noteName, 'C4');
      });

      test('returns correct note names for various MIDI notes', () {
        expect(
          MidiNoteData(note: 0, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'C-1',
        );
        expect(
          MidiNoteData(note: 21, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'A0',
        );
        expect(
          MidiNoteData(note: 69, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'A4',
        );
        expect(
          MidiNoteData(note: 127, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'G9',
        );
      });

      test('returns sharp note names correctly', () {
        expect(
          MidiNoteData(note: 61, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'C#4',
        );
        expect(
          MidiNoteData(note: 70, velocity: 100, startTime: 0, duration: 1)
              .noteName,
          'A#4',
        );
      });
    });

    group('velocityColor', () {
      test('returns darker color for low velocity', () {
        final lowVelNote = MidiNoteData(
          note: 60,
          velocity: 1,
          startTime: 0.0,
          duration: 1.0,
        );
        final highVelNote = MidiNoteData(
          note: 60,
          velocity: 127,
          startTime: 0.0,
          duration: 1.0,
        );

        // Higher velocity should be brighter (higher luminance)
        final lowLuminance = lowVelNote.velocityColor.computeLuminance();
        final highLuminance = highVelNote.velocityColor.computeLuminance();

        expect(highLuminance, greaterThan(lowLuminance));
      });

      test('returns valid color for all velocity ranges', () {
        for (var vel = 0; vel <= 127; vel++) {
          final note = MidiNoteData(
            note: 60,
            velocity: vel,
            startTime: 0.0,
            duration: 1.0,
          );
          final color = note.velocityColor;

          expect(color.a, greaterThanOrEqualTo(0));
          expect(color.a, lessThanOrEqualTo(1));
          expect(color.r, greaterThanOrEqualTo(0));
          expect(color.r, lessThanOrEqualTo(1));
          expect(color.g, greaterThanOrEqualTo(0));
          expect(color.g, lessThanOrEqualTo(1));
          expect(color.b, greaterThanOrEqualTo(0));
          expect(color.b, lessThanOrEqualTo(1));
        }
      });
    });

    group('startTimeInSeconds', () {
      test('converts beats to seconds at 120 BPM', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 4.0, // 4 beats
          duration: 1.0,
        );

        // At 120 BPM: 4 beats = 2 seconds
        expect(note.startTimeInSeconds(120.0), 2.0);
      });

      test('converts beats to seconds at 60 BPM', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 2.0, // 2 beats
          duration: 1.0,
        );

        // At 60 BPM: 2 beats = 2 seconds
        expect(note.startTimeInSeconds(60.0), 2.0);
      });
    });

    group('durationInSeconds', () {
      test('converts duration to seconds at 120 BPM', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 2.0, // 2 beats
        );

        // At 120 BPM: 2 beats = 1 second
        expect(note.durationInSeconds(120.0), 1.0);
      });
    });

    group('contains', () {
      test('returns true for point inside note', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note.contains(1.5, 60), true);
        expect(note.contains(2.0, 60), true);
      });

      test('returns false for wrong pitch', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note.contains(1.5, 61), false);
      });

      test('returns false for time outside note', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note.contains(0.5, 60), false);
        expect(note.contains(3.5, 60), false);
      });

      test('returns true at boundaries', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note.contains(1.0, 60), true); // Start
        expect(note.contains(3.0, 60), true); // End
      });
    });

    group('overlaps', () {
      test('returns true for overlapping notes on same pitch', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 2.0,
        );
        final note2 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note1.overlaps(note2), true);
        expect(note2.overlaps(note1), true);
      });

      test('returns false for different pitches', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 2.0,
        );
        final note2 = MidiNoteData(
          note: 61,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        expect(note1.overlaps(note2), false);
      });

      test('returns false for non-overlapping notes', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );
        final note2 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 2.0,
          duration: 1.0,
        );

        expect(note1.overlaps(note2), false);
      });

      test('returns false for adjacent notes (touching)', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );
        final note2 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 1.0,
        );

        expect(note1.overlaps(note2), false);
      });
    });

    group('copyWith', () {
      test('copies with no changes', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
          isSelected: true,
          id: 'test_id',
        );
        final copy = note.copyWith();

        expect(copy.note, 60);
        expect(copy.velocity, 100);
        expect(copy.startTime, 1.0);
        expect(copy.duration, 2.0);
        expect(copy.isSelected, true);
        expect(copy.id, 'test_id');
      });

      test('copies with specific changes', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );
        final copy = note.copyWith(
          note: 72,
          velocity: 80,
          isSelected: true,
        );

        expect(copy.note, 72);
        expect(copy.velocity, 80);
        expect(copy.startTime, 1.0); // Unchanged
        expect(copy.duration, 2.0); // Unchanged
        expect(copy.isSelected, true);
      });
    });

    group('snapToGrid', () {
      test('snaps start time to grid', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.3,
          duration: 1.0,
        );

        final snapped = note.snapToGrid(0.5);
        expect(snapped.startTime, 1.5);
      });

      test('snaps to nearest grid point', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.2,
          duration: 1.0,
        );

        final snapped = note.snapToGrid(0.5);
        expect(snapped.startTime, 1.0);
      });
    });

    group('quantize', () {
      test('quantizes both start time and duration', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.3,
          duration: 0.7,
        );

        final quantized = note.quantize(0.5);
        expect(quantized.startTime, 1.5);
        expect(quantized.duration, 0.5);
      });

      test('ensures minimum duration of one grid unit', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 0.1,
        );

        final quantized = note.quantize(0.5);
        expect(quantized.duration, 0.5);
      });
    });

    group('equality', () {
      test('notes with same id are equal', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'same_id',
        );
        final note2 = MidiNoteData(
          note: 72, // Different pitch
          velocity: 50, // Different velocity
          startTime: 5.0, // Different start
          duration: 2.0, // Different duration
          id: 'same_id',
        );

        expect(note1 == note2, true);
        expect(note1.hashCode, note2.hashCode);
      });

      test('notes with different ids are not equal', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'id1',
        );
        final note2 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'id2',
        );

        expect(note1 == note2, false);
      });
    });

    group('toString', () {
      test('returns readable string representation', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 1.0,
          duration: 2.0,
        );

        final str = note.toString();
        expect(str, contains('60'));
        expect(str, contains('C4'));
        expect(str, contains('100'));
        expect(str, contains('1.0'));
        expect(str, contains('2.0'));
      });
    });
  });

  group('MidiClipData', () {
    group('constructor', () {
      test('creates clip with required parameters', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
        );

        expect(clip.clipId, 1);
        expect(clip.trackId, 2);
        expect(clip.startTime, 0.0);
        expect(clip.duration, 4.0);
        expect(clip.loopLength, 4.0); // Defaults to duration
        expect(clip.loopCount, 1);
        expect(clip.notes, isEmpty);
        expect(clip.name, 'MIDI Clip');
        expect(clip.isMuted, false);
        expect(clip.isLooping, false);
      });

      test('creates clip with custom loopLength', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 8.0,
          loopLength: 4.0,
        );

        expect(clip.duration, 8.0);
        expect(clip.loopLength, 4.0);
      });
    });

    group('totalDuration and endTime', () {
      test('calculates total duration with loops', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          loopCount: 3,
        );

        expect(clip.totalDuration, 12.0);
        expect(clip.endTime, 12.0);
      });

      test('calculates endTime with start offset', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 2.0,
          duration: 4.0,
          loopCount: 2,
        );

        expect(clip.endTime, 10.0); // 2 + (4 * 2)
      });
    });

    group('addNote', () {
      test('adds note to clip', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
        );
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );

        final updatedClip = clip.addNote(note);

        expect(updatedClip.notes.length, 1);
        expect(updatedClip.notes.first, note);
        expect(clip.notes, isEmpty); // Original unchanged
      });
    });

    group('removeNote', () {
      test('removes note by id', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'note_to_remove',
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note],
        );

        final updatedClip = clip.removeNote('note_to_remove');

        expect(updatedClip.notes, isEmpty);
      });

      test('does nothing if note id not found', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'existing_note',
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note],
        );

        final updatedClip = clip.removeNote('non_existent');

        expect(updatedClip.notes.length, 1);
      });
    });

    group('updateNote', () {
      test('updates existing note', () {
        final note = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          id: 'note_id',
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note],
        );
        final updatedNote = note.copyWith(velocity: 50);

        final updatedClip = clip.updateNote('note_id', updatedNote);

        expect(updatedClip.notes.first.velocity, 50);
      });
    });

    group('selectedNotes', () {
      test('returns only selected notes', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          isSelected: true,
        );
        final note2 = MidiNoteData(
          note: 64,
          velocity: 100,
          startTime: 1.0,
          duration: 1.0,
          isSelected: false,
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note1, note2],
        );

        expect(clip.selectedNotes.length, 1);
        expect(clip.selectedNotes.first.note, 60);
      });
    });

    group('selectNotesInRect', () {
      test('selects notes within rectangle', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
        );
        final note2 = MidiNoteData(
          note: 72,
          velocity: 100,
          startTime: 2.0,
          duration: 1.0,
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note1, note2],
        );

        // Select rectangle: beats 0-2, notes 55-65
        final selected = clip.selectNotesInRect(0.0, 2.0, 55, 65);

        expect(selected.notes[0].isSelected, true);
        expect(selected.notes[1].isSelected, false);
      });
    });

    group('clearSelection', () {
      test('clears all note selections', () {
        final note1 = MidiNoteData(
          note: 60,
          velocity: 100,
          startTime: 0.0,
          duration: 1.0,
          isSelected: true,
        );
        final note2 = MidiNoteData(
          note: 64,
          velocity: 100,
          startTime: 1.0,
          duration: 1.0,
          isSelected: true,
        );
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          notes: [note1, note2],
        );

        final cleared = clip.clearSelection();

        expect(cleared.notes.every((n) => !n.isSelected), true);
      });
    });

    group('copyWith', () {
      test('copies with specific changes', () {
        final clip = MidiClipData(
          clipId: 1,
          trackId: 2,
          startTime: 0.0,
          duration: 4.0,
          name: 'Original',
        );

        final copy = clip.copyWith(
          name: 'Updated',
          isMuted: true,
        );

        expect(copy.clipId, 1);
        expect(copy.name, 'Updated');
        expect(copy.isMuted, true);
        expect(copy.duration, 4.0);
      });
    });
  });
}
