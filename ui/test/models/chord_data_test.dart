import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/chord_data.dart';

void main() {
  group('ChordType', () {
    group('intervals', () {
      test('major has correct intervals', () {
        expect(ChordType.major.intervals, [0, 4, 7]);
      });

      test('minor has correct intervals', () {
        expect(ChordType.minor.intervals, [0, 3, 7]);
      });

      test('dominant7 has correct intervals', () {
        expect(ChordType.dominant7.intervals, [0, 4, 7, 10]);
      });

      test('major7 has correct intervals', () {
        expect(ChordType.major7.intervals, [0, 4, 7, 11]);
      });

      test('minor7 has correct intervals', () {
        expect(ChordType.minor7.intervals, [0, 3, 7, 10]);
      });

      test('diminished has correct intervals', () {
        expect(ChordType.diminished.intervals, [0, 3, 6]);
      });

      test('augmented has correct intervals', () {
        expect(ChordType.augmented.intervals, [0, 4, 8]);
      });

      test('sus2 has correct intervals', () {
        expect(ChordType.sus2.intervals, [0, 2, 7]);
      });

      test('sus4 has correct intervals', () {
        expect(ChordType.sus4.intervals, [0, 5, 7]);
      });

      test('diminished7 has correct intervals', () {
        expect(ChordType.diminished7.intervals, [0, 3, 6, 9]);
      });

      test('add9 has correct intervals', () {
        expect(ChordType.add9.intervals, [0, 4, 7, 14]);
      });

      test('sixth has correct intervals', () {
        expect(ChordType.sixth.intervals, [0, 4, 7, 9]);
      });

      test('minor6 has correct intervals', () {
        expect(ChordType.minor6.intervals, [0, 3, 7, 9]);
      });
    });

    group('displayName', () {
      test('major displays as Maj', () {
        expect(ChordType.major.displayName, 'Maj');
      });

      test('minor displays as Min', () {
        expect(ChordType.minor.displayName, 'Min');
      });

      test('dominant7 displays as 7', () {
        expect(ChordType.dominant7.displayName, '7');
      });

      test('major7 displays as Maj7', () {
        expect(ChordType.major7.displayName, 'Maj7');
      });

      test('diminished displays as Dim', () {
        expect(ChordType.diminished.displayName, 'Dim');
      });

      test('augmented displays as Aug', () {
        expect(ChordType.augmented.displayName, 'Aug');
      });
    });

    group('noteCount', () {
      test('triads have 3 notes', () {
        expect(ChordType.major.noteCount, 3);
        expect(ChordType.minor.noteCount, 3);
        expect(ChordType.diminished.noteCount, 3);
        expect(ChordType.augmented.noteCount, 3);
        expect(ChordType.sus2.noteCount, 3);
        expect(ChordType.sus4.noteCount, 3);
      });

      test('seventh chords have 4 notes', () {
        expect(ChordType.dominant7.noteCount, 4);
        expect(ChordType.major7.noteCount, 4);
        expect(ChordType.minor7.noteCount, 4);
        expect(ChordType.diminished7.noteCount, 4);
        expect(ChordType.add9.noteCount, 4);
        expect(ChordType.sixth.noteCount, 4);
        expect(ChordType.minor6.noteCount, 4);
      });
    });

    group('maxInversion', () {
      test('triads have max inversion 2', () {
        expect(ChordType.major.maxInversion, 2);
        expect(ChordType.minor.maxInversion, 2);
      });

      test('seventh chords have max inversion 3', () {
        expect(ChordType.dominant7.maxInversion, 3);
        expect(ChordType.major7.maxInversion, 3);
      });
    });
  });

  group('ChordRoot', () {
    group('semitone values', () {
      test('C is 0', () {
        expect(ChordRoot.c.semitone, 0);
      });

      test('C# is 1', () {
        expect(ChordRoot.cSharp.semitone, 1);
      });

      test('D is 2', () {
        expect(ChordRoot.d.semitone, 2);
      });

      test('all roots have correct semitones', () {
        expect(ChordRoot.c.semitone, 0);
        expect(ChordRoot.cSharp.semitone, 1);
        expect(ChordRoot.d.semitone, 2);
        expect(ChordRoot.dSharp.semitone, 3);
        expect(ChordRoot.e.semitone, 4);
        expect(ChordRoot.f.semitone, 5);
        expect(ChordRoot.fSharp.semitone, 6);
        expect(ChordRoot.g.semitone, 7);
        expect(ChordRoot.gSharp.semitone, 8);
        expect(ChordRoot.a.semitone, 9);
        expect(ChordRoot.aSharp.semitone, 10);
        expect(ChordRoot.b.semitone, 11);
      });
    });

    group('displayName', () {
      test('C displays as C', () {
        expect(ChordRoot.c.displayName, 'C');
      });

      test('sharp notes display correctly', () {
        expect(ChordRoot.cSharp.displayName, 'C#');
        expect(ChordRoot.dSharp.displayName, 'D#');
        expect(ChordRoot.fSharp.displayName, 'F#');
        expect(ChordRoot.gSharp.displayName, 'G#');
        expect(ChordRoot.aSharp.displayName, 'A#');
      });
    });

    group('midiNoteAt', () {
      test('C at octave 4 is MIDI 60', () {
        expect(ChordRoot.c.midiNoteAt(4), 60);
      });

      test('A at octave 4 is MIDI 69', () {
        expect(ChordRoot.a.midiNoteAt(4), 69);
      });

      test('C at octave 0 is MIDI 12', () {
        expect(ChordRoot.c.midiNoteAt(0), 12);
      });

      test('C at octave 5 is MIDI 72', () {
        expect(ChordRoot.c.midiNoteAt(5), 72);
      });

      test('all roots at octave 4', () {
        expect(ChordRoot.c.midiNoteAt(4), 60);
        expect(ChordRoot.cSharp.midiNoteAt(4), 61);
        expect(ChordRoot.d.midiNoteAt(4), 62);
        expect(ChordRoot.dSharp.midiNoteAt(4), 63);
        expect(ChordRoot.e.midiNoteAt(4), 64);
        expect(ChordRoot.f.midiNoteAt(4), 65);
        expect(ChordRoot.fSharp.midiNoteAt(4), 66);
        expect(ChordRoot.g.midiNoteAt(4), 67);
        expect(ChordRoot.gSharp.midiNoteAt(4), 68);
        expect(ChordRoot.a.midiNoteAt(4), 69);
        expect(ChordRoot.aSharp.midiNoteAt(4), 70);
        expect(ChordRoot.b.midiNoteAt(4), 71);
      });
    });
  });

  group('ChordConfiguration', () {
    group('constructor', () {
      test('creates with required fields', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        expect(chord.root, ChordRoot.c);
        expect(chord.type, ChordType.major);
      });

      test('uses default inversion 0', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        expect(chord.inversion, 0);
      });

      test('uses default octave 4', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        expect(chord.octave, 4);
      });

      test('creates with all fields', () {
        final chord = ChordConfiguration(
          root: ChordRoot.fSharp,
          type: ChordType.minor7,
          inversion: 2,
          octave: 5,
        );

        expect(chord.root, ChordRoot.fSharp);
        expect(chord.type, ChordType.minor7);
        expect(chord.inversion, 2);
        expect(chord.octave, 5);
      });
    });

    group('midiNotes', () {
      test('C major root position at octave 4', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 64, 67]); // C4, E4, G4
      });

      test('C minor root position at octave 4', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.minor,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 63, 67]); // C4, Eb4, G4
      });

      test('G major at octave 4', () {
        final chord = ChordConfiguration(
          root: ChordRoot.g,
          type: ChordType.major,
          octave: 4,
        );

        expect(chord.midiNotes, [67, 71, 74]); // G4, B4, D5
      });

      test('C7 at octave 4', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.dominant7,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 64, 67, 70]); // C4, E4, G4, Bb4
      });

      test('C major first inversion', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 1,
          octave: 4,
        );

        // First inversion: E4, G4, C5
        expect(chord.midiNotes, [64, 67, 72]);
      });

      test('C major second inversion', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 2,
          octave: 4,
        );

        // Second inversion: G4, C5, E5
        expect(chord.midiNotes, [67, 72, 76]);
      });

      test('C7 first inversion', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.dominant7,
          inversion: 1,
          octave: 4,
        );

        // C7 first inversion: E4, G4, Bb4, C5
        expect(chord.midiNotes, [64, 67, 70, 72]);
      });

      test('different octaves', () {
        final chordOctave3 = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 3,
        );

        final chordOctave5 = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 5,
        );

        expect(chordOctave3.midiNotes, [48, 52, 55]); // C3, E3, G3
        expect(chordOctave5.midiNotes, [72, 76, 79]); // C5, E5, G5
      });

      test('augmented chord', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.augmented,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 64, 68]); // C4, E4, G#4
      });

      test('diminished chord', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.diminished,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 63, 66]); // C4, Eb4, Gb4
      });

      test('sus2 chord', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.sus2,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 62, 67]); // C4, D4, G4
      });

      test('sus4 chord', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.sus4,
          octave: 4,
        );

        expect(chord.midiNotes, [60, 65, 67]); // C4, F4, G4
      });
    });

    group('displayName', () {
      test('C major displays as C Maj', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        expect(chord.displayName, 'C Maj');
      });

      test('F# minor7 displays as F# Min7', () {
        final chord = ChordConfiguration(
          root: ChordRoot.fSharp,
          type: ChordType.minor7,
        );

        expect(chord.displayName, 'F# Min7');
      });

      test('G dominant7 displays as G 7', () {
        final chord = ChordConfiguration(
          root: ChordRoot.g,
          type: ChordType.dominant7,
        );

        expect(chord.displayName, 'G 7');
      });
    });

    group('fullDisplayName', () {
      test('root position shows only chord name', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 0,
        );

        expect(chord.fullDisplayName, 'C Maj');
      });

      test('first inversion shows 1st inv', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 1,
        );

        expect(chord.fullDisplayName, 'C Maj (1st inv)');
      });

      test('second inversion shows 2nd inv', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 2,
        );

        expect(chord.fullDisplayName, 'C Maj (2nd inv)');
      });

      test('third inversion shows 3rd inv', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.dominant7,
          inversion: 3,
        );

        expect(chord.fullDisplayName, 'C 7 (3rd inv)');
      });

      test('higher inversions show nth inv', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 4,
        );

        expect(chord.fullDisplayName, 'C Maj (4th inv)');
      });
    });

    group('copyWith', () {
      test('copies all fields when none specified', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 1,
          octave: 5,
        );

        final copy = original.copyWith();

        expect(copy.root, original.root);
        expect(copy.type, original.type);
        expect(copy.inversion, original.inversion);
        expect(copy.octave, original.octave);
      });

      test('updates root only', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        final copy = original.copyWith(root: ChordRoot.g);

        expect(copy.root, ChordRoot.g);
        expect(copy.type, ChordType.major);
      });

      test('updates type only', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
        );

        final copy = original.copyWith(type: ChordType.minor);

        expect(copy.root, ChordRoot.c);
        expect(copy.type, ChordType.minor);
      });

      test('updates inversion only', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 0,
        );

        final copy = original.copyWith(inversion: 2);

        expect(copy.inversion, 2);
      });

      test('updates octave only', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 4,
        );

        final copy = original.copyWith(octave: 6);

        expect(copy.octave, 6);
      });

      test('updates multiple fields', () {
        final original = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          inversion: 0,
          octave: 4,
        );

        final copy = original.copyWith(
          root: ChordRoot.f,
          type: ChordType.minor7,
          inversion: 1,
          octave: 5,
        );

        expect(copy.root, ChordRoot.f);
        expect(copy.type, ChordType.minor7);
        expect(copy.inversion, 1);
        expect(copy.octave, 5);
      });
    });

    group('edge cases', () {
      test('handles low octave', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 0,
        );

        expect(chord.midiNotes, [12, 16, 19]);
      });

      test('handles high octave', () {
        final chord = ChordConfiguration(
          root: ChordRoot.c,
          type: ChordType.major,
          octave: 8,
        );

        expect(chord.midiNotes, [108, 112, 115]);
      });

      test('all 12 roots work correctly', () {
        for (final root in ChordRoot.values) {
          final chord = ChordConfiguration(
            root: root,
            type: ChordType.major,
            octave: 4,
          );

          expect(chord.midiNotes.length, 3);
          expect(chord.midiNotes[0], root.midiNoteAt(4));
        }
      });

      test('all chord types work correctly', () {
        for (final type in ChordType.values) {
          final chord = ChordConfiguration(
            root: ChordRoot.c,
            type: type,
            octave: 4,
          );

          expect(chord.midiNotes.length, type.noteCount);
        }
      });
    });
  });
}
