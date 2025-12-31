// Scale definitions for the Piano Roll.
// Each scale is defined by its interval pattern (semitones from root).

/// Available scale types with their semitone intervals
enum ScaleType {
  major('Major', [0, 2, 4, 5, 7, 9, 11]),
  minor('Minor', [0, 2, 3, 5, 7, 8, 10]),
  dorian('Dorian', [0, 2, 3, 5, 7, 9, 10]),
  phrygian('Phrygian', [0, 1, 3, 5, 7, 8, 10]),
  lydian('Lydian', [0, 2, 4, 6, 7, 9, 11]),
  mixolydian('Mixolydian', [0, 2, 4, 5, 7, 9, 10]),
  harmonicMinor('Harmonic Minor', [0, 2, 3, 5, 7, 8, 11]),
  pentatonicMajor('Pentatonic Major', [0, 2, 4, 7, 9]),
  pentatonicMinor('Pentatonic Minor', [0, 3, 5, 7, 10]),
  blues('Blues', [0, 3, 5, 6, 7, 10]),
  chromatic('Chromatic', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);

  final String displayName;
  final List<int> intervals;

  const ScaleType(this.displayName, this.intervals);
}

/// Note names for scale root selection
class ScaleRoot {
  static const List<String> noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  /// Get MIDI note number for a root note name (in octave 0)
  static int midiNoteFromName(String name) {
    return noteNames.indexOf(name);
  }

  /// Get note name from MIDI note number
  static String nameFromMidiNote(int midiNote) {
    return noteNames[midiNote % 12];
  }
}

/// Scale helper class for checking notes against a scale
class Scale {
  final String root;
  final ScaleType type;

  const Scale({
    required this.root,
    required this.type,
  });

  /// Get the root note as a MIDI note number (0-11)
  int get rootMidi => ScaleRoot.midiNoteFromName(root);

  /// Check if a MIDI note is in this scale
  bool containsNote(int midiNote) {
    final noteInOctave = (midiNote - rootMidi) % 12;
    // Handle negative modulo
    final normalized = noteInOctave < 0 ? noteInOctave + 12 : noteInOctave;
    return type.intervals.contains(normalized);
  }

  /// Get all MIDI notes in this scale within a range
  List<int> getNotesInRange(int minNote, int maxNote) {
    final notes = <int>[];
    for (int note = minNote; note <= maxNote; note++) {
      if (containsNote(note)) {
        notes.add(note);
      }
    }
    return notes;
  }

  /// Snap a MIDI note to the nearest note in this scale
  int snapToScale(int midiNote) {
    if (containsNote(midiNote)) return midiNote;

    // Find nearest note in scale
    int below = midiNote;
    int above = midiNote;

    while (!containsNote(below) && below >= 0) {
      below--;
    }
    while (!containsNote(above) && above <= 127) {
      above++;
    }

    // Return the closest one
    if (below < 0) return above;
    if (above > 127) return below;

    return (midiNote - below <= above - midiNote) ? below : above;
  }

  /// Get the degree of a note in this scale (1-based, 0 if not in scale)
  int getDegree(int midiNote) {
    if (!containsNote(midiNote)) return 0;

    final noteInOctave = (midiNote - rootMidi) % 12;
    final normalized = noteInOctave < 0 ? noteInOctave + 12 : noteInOctave;
    return type.intervals.indexOf(normalized) + 1;
  }

  /// Check if a note is the root of the scale
  bool isRoot(int midiNote) {
    return (midiNote % 12) == rootMidi;
  }

  @override
  String toString() => '$root ${type.displayName}';
}
