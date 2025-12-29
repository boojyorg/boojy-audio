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

  GridPainter({
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.gridDivision,
    required this.maxMidiNote,
    this.minMidiNote = 0,
    required this.totalBeats,
    required this.activeBeats,
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    // STEP 1: Draw backgrounds FIRST (so vertical lines can be drawn on top)
    for (int note = minMidiNote; note <= maxMidiNote; note++) {
      final y = (maxMidiNote - note) * pixelsPerNote;
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

    // Vertical lines (beats and bars)
    for (double beat = 0; beat <= totalBeats; beat += gridDivision) {
      final x = beat * pixelsPerBeat;
      final isBar = (beat % 4.0) == 0.0; // 4/4 time
      final isBeat = (beat % 1.0) == 0.0;

      final paint = isBar ? barPaint : (isBeat ? beatPaint : subdivisionPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Note: Grey shaded overlay removed per user preference
    // Orange loop end marker is drawn by _buildLoopEndMarker widget
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

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        pixelsPerNote != oldDelegate.pixelsPerNote ||
        gridDivision != oldDelegate.gridDivision ||
        totalBeats != oldDelegate.totalBeats ||
        activeBeats != oldDelegate.activeBeats ||
        blackKeyBackground != oldDelegate.blackKeyBackground ||
        whiteKeyBackground != oldDelegate.whiteKeyBackground ||
        separatorLine != oldDelegate.separatorLine ||
        subdivisionGridLine != oldDelegate.subdivisionGridLine ||
        beatGridLine != oldDelegate.beatGridLine ||
        barGridLine != oldDelegate.barGridLine ||
        scaleHighlightEnabled != oldDelegate.scaleHighlightEnabled ||
        scaleRootMidi != oldDelegate.scaleRootMidi ||
        scaleIntervals != oldDelegate.scaleIntervals ||
        minMidiNote != oldDelegate.minMidiNote;
  }
}
