/// Chord types with their interval patterns (semitones from root)
enum ChordType {
  major('Maj', [0, 4, 7]),
  minor('Min', [0, 3, 7]),
  dominant7('7', [0, 4, 7, 10]),
  major7('Maj7', [0, 4, 7, 11]),
  minor7('Min7', [0, 3, 7, 10]),
  diminished('Dim', [0, 3, 6]),
  augmented('Aug', [0, 4, 8]),
  sus2('Sus2', [0, 2, 7]),
  sus4('Sus4', [0, 5, 7]),
  diminished7('Dim7', [0, 3, 6, 9]),
  add9('Add9', [0, 4, 7, 14]),
  sixth('6', [0, 4, 7, 9]),
  minor6('Min6', [0, 3, 7, 9]);

  final String displayName;
  final List<int> intervals;

  const ChordType(this.displayName, this.intervals);

  /// Get the number of notes in this chord
  int get noteCount => intervals.length;

  /// Get maximum inversion index (0-based)
  int get maxInversion => intervals.length - 1;
}

/// Note names for chord roots
enum ChordRoot {
  c(0, 'C'),
  cSharp(1, 'C#'),
  d(2, 'D'),
  dSharp(3, 'D#'),
  e(4, 'E'),
  f(5, 'F'),
  fSharp(6, 'F#'),
  g(7, 'G'),
  gSharp(8, 'G#'),
  a(9, 'A'),
  aSharp(10, 'A#'),
  b(11, 'B');

  final int semitone; // 0-11
  final String displayName;

  const ChordRoot(this.semitone, this.displayName);

  /// Get MIDI note number for this root at a given octave (0-10)
  int midiNoteAt(int octave) => semitone + (octave + 1) * 12;
}

/// A chord configuration ready to be placed
class ChordConfiguration {
  final ChordRoot root;
  final ChordType type;
  final int inversion; // 0 = root position, 1 = first inversion, etc.
  final int octave; // Base octave (0-10)

  const ChordConfiguration({
    required this.root,
    required this.type,
    this.inversion = 0,
    this.octave = 4,
  });

  /// Get the MIDI note numbers for this chord
  List<int> get midiNotes {
    final baseNote = root.midiNoteAt(octave);
    final intervals = type.intervals;

    // Apply inversion by moving lower notes up an octave
    final List<int> notes = intervals.map((i) => baseNote + i).toList();

    // Apply inversion
    for (int i = 0; i < inversion && i < notes.length; i++) {
      // Move the lowest note up an octave
      notes.sort();
      notes[0] += 12;
    }

    notes.sort();
    return notes;
  }

  /// Get display name (e.g., "C Maj", "F# Min7")
  String get displayName => '${root.displayName} ${type.displayName}';

  /// Get full display name with inversion (e.g., "C Maj (1st inv)")
  String get fullDisplayName {
    if (inversion == 0) return displayName;
    final invNames = ['', '1st', '2nd', '3rd'];
    final invName = inversion < invNames.length ? invNames[inversion] : '${inversion}th';
    return '$displayName ($invName inv)';
  }

  ChordConfiguration copyWith({
    ChordRoot? root,
    ChordType? type,
    int? inversion,
    int? octave,
  }) {
    return ChordConfiguration(
      root: root ?? this.root,
      type: type ?? this.type,
      inversion: inversion ?? this.inversion,
      octave: octave ?? this.octave,
    );
  }
}
