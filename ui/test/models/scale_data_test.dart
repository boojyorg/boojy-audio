import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/scale_data.dart';

void main() {
  group('ScaleType', () {
    test('major scale has correct intervals', () {
      expect(ScaleType.major.displayName, 'Major');
      expect(ScaleType.major.intervals, [0, 2, 4, 5, 7, 9, 11]);
    });

    test('minor scale has correct intervals', () {
      expect(ScaleType.minor.displayName, 'Minor');
      expect(ScaleType.minor.intervals, [0, 2, 3, 5, 7, 8, 10]);
    });

    test('chromatic scale has all 12 semitones', () {
      expect(ScaleType.chromatic.intervals.length, 12);
      expect(ScaleType.chromatic.intervals, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    test('pentatonic scales have 5 notes', () {
      expect(ScaleType.pentatonicMajor.intervals.length, 5);
      expect(ScaleType.pentatonicMinor.intervals.length, 5);
    });

    test('blues scale has 6 notes', () {
      expect(ScaleType.blues.intervals.length, 6);
    });
  });

  group('ScaleRoot', () {
    test('noteNames contains all 12 notes', () {
      expect(ScaleRoot.noteNames.length, 12);
      expect(ScaleRoot.noteNames, ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']);
    });

    test('midiNoteFromName returns correct values', () {
      expect(ScaleRoot.midiNoteFromName('C'), 0);
      expect(ScaleRoot.midiNoteFromName('C#'), 1);
      expect(ScaleRoot.midiNoteFromName('D'), 2);
      expect(ScaleRoot.midiNoteFromName('A'), 9);
      expect(ScaleRoot.midiNoteFromName('B'), 11);
    });

    test('nameFromMidiNote returns correct names', () {
      expect(ScaleRoot.nameFromMidiNote(0), 'C');
      expect(ScaleRoot.nameFromMidiNote(12), 'C'); // C1
      expect(ScaleRoot.nameFromMidiNote(60), 'C'); // Middle C
      expect(ScaleRoot.nameFromMidiNote(69), 'A'); // A4 (440 Hz)
    });

    test('midiNoteFromName and nameFromMidiNote are inverse', () {
      for (var i = 0; i < 12; i++) {
        final name = ScaleRoot.nameFromMidiNote(i);
        expect(ScaleRoot.midiNoteFromName(name), i);
      }
    });
  });

  group('Scale', () {
    group('constructor and properties', () {
      test('creates scale with root and type', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        expect(scale.root, 'C');
        expect(scale.type, ScaleType.major);
        expect(scale.rootMidi, 0);
      });

      test('rootMidi returns correct value for different roots', () {
        const cScale = Scale(root: 'C', type: ScaleType.major);
        const gScale = Scale(root: 'G', type: ScaleType.major);
        const aScale = Scale(root: 'A', type: ScaleType.minor);

        expect(cScale.rootMidi, 0);
        expect(gScale.rootMidi, 7);
        expect(aScale.rootMidi, 9);
      });
    });

    group('containsNote', () {
      test('C major contains correct notes', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        // C Major: C, D, E, F, G, A, B
        expect(scale.containsNote(60), true); // C4
        expect(scale.containsNote(62), true); // D4
        expect(scale.containsNote(64), true); // E4
        expect(scale.containsNote(65), true); // F4
        expect(scale.containsNote(67), true); // G4
        expect(scale.containsNote(69), true); // A4
        expect(scale.containsNote(71), true); // B4

        // Not in C Major
        expect(scale.containsNote(61), false); // C#4
        expect(scale.containsNote(63), false); // D#4
        expect(scale.containsNote(66), false); // F#4
      });

      test('G major contains correct notes', () {
        const scale = Scale(root: 'G', type: ScaleType.major);

        // G Major: G, A, B, C, D, E, F#
        expect(scale.containsNote(67), true); // G4
        expect(scale.containsNote(69), true); // A4
        expect(scale.containsNote(71), true); // B4
        expect(scale.containsNote(60), true); // C4
        expect(scale.containsNote(62), true); // D4
        expect(scale.containsNote(64), true); // E4
        expect(scale.containsNote(66), true); // F#4

        // F natural not in G major
        expect(scale.containsNote(65), false); // F4
      });

      test('works across octaves', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        // All C notes should be in scale
        expect(scale.containsNote(24), true); // C1
        expect(scale.containsNote(36), true); // C2
        expect(scale.containsNote(48), true); // C3
        expect(scale.containsNote(60), true); // C4
        expect(scale.containsNote(72), true); // C5
      });

      test('chromatic scale contains all notes', () {
        const scale = Scale(root: 'C', type: ScaleType.chromatic);

        for (var i = 0; i < 128; i++) {
          expect(scale.containsNote(i), true);
        }
      });
    });

    group('getNotesInRange', () {
      test('returns correct notes for C major in octave', () {
        const scale = Scale(root: 'C', type: ScaleType.major);
        final notes = scale.getNotesInRange(60, 72);

        // C4 to C5: C, D, E, F, G, A, B, C
        expect(notes, [60, 62, 64, 65, 67, 69, 71, 72]);
      });

      test('returns correct notes for A minor pentatonic', () {
        const scale = Scale(root: 'A', type: ScaleType.pentatonicMinor);
        final notes = scale.getNotesInRange(57, 69);

        // A minor pentatonic: A, C, D, E, G (+ A at 69)
        // Range 57-69 includes: A3(57), C4(60), D4(62), E4(64), G4(67), A4(69)
        expect(notes.length, 6);
        expect(notes.contains(57), true); // A3
        expect(notes.contains(60), true); // C4
        expect(notes.contains(62), true); // D4
        expect(notes.contains(64), true); // E4
        expect(notes.contains(67), true); // G4
        expect(notes.contains(69), true); // A4
      });

      test('returns empty list for empty range', () {
        const scale = Scale(root: 'C', type: ScaleType.major);
        final notes = scale.getNotesInRange(61, 61); // Just C#

        expect(notes, isEmpty);
      });
    });

    group('snapToScale', () {
      test('returns same note if already in scale', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        expect(scale.snapToScale(60), 60); // C
        expect(scale.snapToScale(62), 62); // D
        expect(scale.snapToScale(64), 64); // E
      });

      test('snaps to nearest note in scale', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        // C# should snap to C or D (C is closer or equal)
        expect(scale.snapToScale(61), 60); // C# -> C

        // F# is equidistant from F and G, should prefer lower (or could prefer higher)
        final snapped = scale.snapToScale(66);
        expect(snapped == 65 || snapped == 67, true); // F# -> F or G
      });

      test('snaps to note within bounds', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        // Low note
        expect(scale.snapToScale(0), 0); // C-1

        // High note
        expect(scale.snapToScale(127), 127); // G9
      });
    });

    group('getDegree', () {
      test('returns correct degrees for C major', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        expect(scale.getDegree(60), 1); // C = 1st degree (tonic)
        expect(scale.getDegree(62), 2); // D = 2nd degree
        expect(scale.getDegree(64), 3); // E = 3rd degree
        expect(scale.getDegree(65), 4); // F = 4th degree
        expect(scale.getDegree(67), 5); // G = 5th degree
        expect(scale.getDegree(69), 6); // A = 6th degree
        expect(scale.getDegree(71), 7); // B = 7th degree
      });

      test('returns 0 for notes not in scale', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        expect(scale.getDegree(61), 0); // C# not in C major
        expect(scale.getDegree(63), 0); // D# not in C major
      });

      test('works across octaves', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        // All C notes should be 1st degree
        expect(scale.getDegree(24), 1); // C1
        expect(scale.getDegree(36), 1); // C2
        expect(scale.getDegree(48), 1); // C3
        expect(scale.getDegree(60), 1); // C4
      });
    });

    group('isRoot', () {
      test('identifies root notes correctly', () {
        const scale = Scale(root: 'C', type: ScaleType.major);

        expect(scale.isRoot(60), true); // C4
        expect(scale.isRoot(48), true); // C3
        expect(scale.isRoot(72), true); // C5

        expect(scale.isRoot(62), false); // D4
        expect(scale.isRoot(67), false); // G4
      });

      test('works for different root scales', () {
        const gScale = Scale(root: 'G', type: ScaleType.major);

        expect(gScale.isRoot(67), true); // G4
        expect(gScale.isRoot(55), true); // G3
        expect(gScale.isRoot(60), false); // C4
      });
    });

    group('toString', () {
      test('returns readable string', () {
        const cMajor = Scale(root: 'C', type: ScaleType.major);
        const aMinor = Scale(root: 'A', type: ScaleType.minor);
        const gBlues = Scale(root: 'G', type: ScaleType.blues);

        expect(cMajor.toString(), 'C Major');
        expect(aMinor.toString(), 'A Minor');
        expect(gBlues.toString(), 'G Blues');
      });
    });
  });
}
