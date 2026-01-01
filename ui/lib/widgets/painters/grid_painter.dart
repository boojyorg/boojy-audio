import 'package:flutter/material.dart';

/// Custom painter for piano roll grid background
class GridPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final double gridDivision;
  final int maxMidiNote;
  final int minMidiNote;
  final double totalBeats;
  final double activeBeats; // Active region boundary

  // Loop region parameters
  final bool loopEnabled;
  final double loopStart; // Loop start in beats
  final double loopEnd; // Loop end in beats

  // Time signature
  final int beatsPerBar; // e.g., 4 for 4/4, 3 for 3/4, 6 for 6/8

  // Triplet mode (3 lines per beat instead of 4)
  final bool tripletEnabled;

  // Theme-aware colors (passed from widget with BuildContext)
  final Color blackKeyBackground;
  final Color whiteKeyBackground;
  final Color separatorLine;
  final Color subdivisionGridLine;
  final Color beatGridLine;
  final Color barGridLine;

  // Scale highlighting
  final bool scaleHighlightEnabled;
  final int scaleRootMidi; // 0-11 (C=0, C#=1, etc.)
  final List<int> scaleIntervals; // e.g., [0, 2, 4, 5, 7, 9, 11] for major
  final Color outOfScaleOverlay;

  // Fold mode - when provided, only these pitches are rendered (in order)
  final List<int>? foldedPitches;

  GridPainter({
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.gridDivision,
    required this.maxMidiNote,
    this.minMidiNote = 0,
    required this.totalBeats,
    required this.activeBeats,
    this.loopEnabled = false,
    this.loopStart = 0.0,
    this.loopEnd = 4.0,
    this.beatsPerBar = 4, // Default to 4/4 time
    this.tripletEnabled = false,
    required this.blackKeyBackground,
    required this.whiteKeyBackground,
    required this.separatorLine,
    required this.subdivisionGridLine,
    required this.beatGridLine,
    required this.barGridLine,
    this.scaleHighlightEnabled = false,
    this.scaleRootMidi = 0,
    this.scaleIntervals = const [0, 2, 4, 5, 7, 9, 11], // Major scale default
    this.outOfScaleOverlay = const Color(0x40000000), // Semi-transparent black
    this.foldedPitches,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // STEP 1: Draw backgrounds FIRST (so vertical lines can be drawn on top)
    // Use foldedPitches if provided (fold mode), otherwise iterate over full range
    final pitchesToRender = foldedPitches ??
        List.generate(maxMidiNote - minMidiNote + 1, (i) => maxMidiNote - i);

    for (int rowIndex = 0; rowIndex < pitchesToRender.length; rowIndex++) {
      final note = pitchesToRender[rowIndex];
      final y = rowIndex * pixelsPerNote;
      final isBlackKey = _isBlackKey(note);

      // Draw background color (theme-aware)
      final bgPaint = Paint()
        ..color = isBlackKey ? blackKeyBackground : whiteKeyBackground;

      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, pixelsPerNote),
        bgPaint,
      );

      // Draw scale highlight overlay (dim out-of-scale notes)
      if (scaleHighlightEnabled && !_isInScale(note)) {
        final overlayPaint = Paint()..color = outOfScaleOverlay;
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, pixelsPerNote),
          overlayPaint,
        );
      }

      // Draw horizontal separator line
      final linePaint = Paint()
        ..color = separatorLine
        ..strokeWidth = 0.5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // STEP 2: Draw vertical grid lines ON TOP (so they're visible)
    // Theme-aware grid colors
    final subdivisionPaint = Paint()
      ..color = subdivisionGridLine
      ..strokeWidth = 1.0;

    final beatPaint = Paint()
      ..color = beatGridLine
      ..strokeWidth = 1.5;

    final barPaint = Paint()
      ..color = barGridLine
      ..strokeWidth = 2.5;

    // Calculate effective grid step
    // For triplets, the gridDivision is already 2/3 of normal,
    // so we just use it as-is
    final gridStep = gridDivision;

    // Vertical lines (beats and bars)
    for (double beat = 0; beat <= totalBeats; beat += gridStep) {
      final x = beat * pixelsPerBeat;

      // Check if this is a bar line (uses time signature)
      final isBar = _isApproximately(beat % beatsPerBar, 0.0);
      // Check if this is a beat line
      final isBeat = _isApproximately(beat % 1.0, 0.0);

      final paint = isBar ? barPaint : (isBeat ? beatPaint : subdivisionPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // STEP 3: Draw loop region dimming overlay (20% darker outside loop)
    if (loopEnabled) {
      final dimPaint = Paint()..color = const Color(0x33000000); // 20% black overlay

      final loopStartX = loopStart * pixelsPerBeat;
      final loopEndX = loopEnd * pixelsPerBeat;

      // Dim area before loop start
      if (loopStartX > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, loopStartX, size.height),
          dimPaint,
        );
      }

      // Dim area after loop end
      if (loopEndX < size.width) {
        canvas.drawRect(
          Rect.fromLTWH(loopEndX, 0, size.width - loopEndX, size.height),
          dimPaint,
        );
      }
    }
  }

  bool _isBlackKey(int midiNote) {
    final noteInOctave = midiNote % 12;
    return [1, 3, 6, 8, 10].contains(noteInOctave);
  }

  /// Check if a MIDI note is in the current scale
  bool _isInScale(int midiNote) {
    final noteInOctave = (midiNote - scaleRootMidi) % 12;
    // Handle negative modulo
    final normalized = noteInOctave < 0 ? noteInOctave + 12 : noteInOctave;
    return scaleIntervals.contains(normalized);
  }

  /// Check if two doubles are approximately equal (handles triplet rounding)
  bool _isApproximately(double a, double b, [double epsilon = 0.001]) {
    return (a - b).abs() < epsilon;
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
  bool shouldRepaint(GridPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        pixelsPerNote != oldDelegate.pixelsPerNote ||
        gridDivision != oldDelegate.gridDivision ||
        totalBeats != oldDelegate.totalBeats ||
        activeBeats != oldDelegate.activeBeats ||
        loopEnabled != oldDelegate.loopEnabled ||
        loopStart != oldDelegate.loopStart ||
        loopEnd != oldDelegate.loopEnd ||
        beatsPerBar != oldDelegate.beatsPerBar ||
        tripletEnabled != oldDelegate.tripletEnabled ||
        blackKeyBackground != oldDelegate.blackKeyBackground ||
        whiteKeyBackground != oldDelegate.whiteKeyBackground ||
        separatorLine != oldDelegate.separatorLine ||
        subdivisionGridLine != oldDelegate.subdivisionGridLine ||
        beatGridLine != oldDelegate.beatGridLine ||
        barGridLine != oldDelegate.barGridLine ||
        scaleHighlightEnabled != oldDelegate.scaleHighlightEnabled ||
        scaleRootMidi != oldDelegate.scaleRootMidi ||
        !_listEquals(foldedPitches, oldDelegate.foldedPitches) ||
        scaleIntervals != oldDelegate.scaleIntervals ||
        minMidiNote != oldDelegate.minMidiNote;
  }
}
