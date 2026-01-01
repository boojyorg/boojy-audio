import '../../../models/scale_data.dart';

/// Utility class for piano roll coordinate calculations.
/// Converts between beat positions, MIDI notes, and pixel coordinates.
class PianoRollCoordinates {
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final int maxMidiNote;
  final int minMidiNote;

  const PianoRollCoordinates({
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    this.maxMidiNote = 127,
    this.minMidiNote = 0,
  });

  /// Calculate Y coordinate for a MIDI note.
  /// Higher notes = lower Y coordinate (inverted).
  double calculateNoteY(int midiNote) {
    return (maxMidiNote - midiNote) * pixelsPerNote;
  }

  /// Calculate X coordinate for a beat position.
  double calculateBeatX(double beat) {
    return beat * pixelsPerBeat;
  }

  /// Get MIDI note at a Y coordinate.
  int getNoteAtY(double y) {
    final rawNote = maxMidiNote - (y / pixelsPerNote).floor();
    return rawNote.clamp(minMidiNote, maxMidiNote);
  }

  /// Get beat position at an X coordinate.
  double getBeatAtX(double x) {
    return x / pixelsPerBeat;
  }

  /// Snap a beat position to a grid.
  double snapToGrid(double beat, double gridDivision, {bool snapEnabled = true}) {
    if (!snapEnabled) return beat;
    return (beat / gridDivision).floor() * gridDivision;
  }

  /// Returns the adaptive grid division based on zoom level.
  /// Target: 20-40px per grid cell.
  static double getAdaptiveGridDivision(double pixelsPerBeat) {
    // Grid divisions in beats (smallest to largest)
    // 1/128, 1/64, 1/32, 1/16, 1/8, 1/4, 1/2, 1 beat, 2 beats, 4 beats (1 bar), 8 beats, 16 beats
    const divisions = [
      0.03125, // 1/128
      0.0625, // 1/64
      0.125, // 1/32
      0.25, // 1/16
      0.5, // 1/8
      1.0, // 1/4
      2.0, // 1/2
      4.0, // 1 bar
      8.0, // 2 bars
      16.0, // 4 bars
    ];

    // Find first division where cell width is >= 20px
    for (final div in divisions) {
      final cellWidth = div * pixelsPerBeat;
      if (cellWidth >= 20 && cellWidth <= 40) {
        return div;
      }
    }

    // If no exact match, find first that's >= 20px
    for (final div in divisions) {
      if (div * pixelsPerBeat >= 20) {
        return div;
      }
    }

    // Fallback to largest division
    return divisions.last;
  }

  /// Convert grid division (beats) to display label.
  static String gridDivisionToLabel(double division, {bool triplet = false}) {
    final suffix = triplet ? 'T' : '';
    if (division >= 16.0) return '4 Bar$suffix';
    if (division >= 8.0) return '2 Bar$suffix';
    if (division >= 4.0) return '1 Bar$suffix';
    if (division >= 2.0) return '1/2$suffix';
    if (division >= 1.0) return '1/4$suffix';
    if (division >= 0.5) return '1/8$suffix';
    if (division >= 0.25) return '1/16$suffix';
    if (division >= 0.125) return '1/32$suffix';
    if (division >= 0.0625) return '1/64$suffix';
    return '1/128$suffix';
  }

  /// Calculate max pixelsPerBeat (zoom in limit).
  /// 1 sixteenth note (0.25 beats) should fill the view width.
  static double calculateMaxPixelsPerBeat(double viewWidth) {
    return viewWidth / 0.25;
  }

  /// Calculate min pixelsPerBeat (zoom out limit).
  /// Clip length + 4 bars should fit in view.
  static double calculateMinPixelsPerBeat(double viewWidth, double clipLength) {
    final totalBeatsToShow = clipLength + 16.0; // clip + 4 bars (16 beats)
    return viewWidth / totalBeatsToShow;
  }

  /// Create a copy with updated values.
  PianoRollCoordinates copyWith({
    double? pixelsPerBeat,
    double? pixelsPerNote,
    int? maxMidiNote,
    int? minMidiNote,
  }) {
    return PianoRollCoordinates(
      pixelsPerBeat: pixelsPerBeat ?? this.pixelsPerBeat,
      pixelsPerNote: pixelsPerNote ?? this.pixelsPerNote,
      maxMidiNote: maxMidiNote ?? this.maxMidiNote,
      minMidiNote: minMidiNote ?? this.minMidiNote,
    );
  }
}

/// Utility class for scale-related operations.
class ScaleUtils {
  /// Snap a MIDI note to the nearest note in the given scale.
  static int snapNoteToScale(int midiNote, Scale scale) {
    if (scale.containsNote(midiNote)) return midiNote;

    // Find nearest note in scale
    int below = midiNote;
    int above = midiNote;

    while (!scale.containsNote(below) && below >= 0) {
      below--;
    }
    while (!scale.containsNote(above) && above <= 127) {
      above++;
    }

    // Return the closest one
    if (below < 0) return above;
    if (above > 127) return below;

    return (midiNote - below <= above - midiNote) ? below : above;
  }
}

/// Note name utility functions.
class NoteNameUtils {
  static const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  /// Get the name of a MIDI note (e.g., "C4", "F#5").
  static String getNoteName(int midiNote) {
    final octave = (midiNote ~/ 12) - 1;
    final noteName = _noteNames[midiNote % 12];
    return '$noteName$octave';
  }

  /// Check if a MIDI note is a black key.
  static bool isBlackKey(int midiNote) {
    final noteInOctave = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(noteInOctave); // C#, D#, F#, G#, A#
  }

  /// Check if a MIDI note is C.
  static bool isC(int midiNote) {
    return midiNote % 12 == 0;
  }
}
