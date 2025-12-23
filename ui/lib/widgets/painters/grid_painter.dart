import 'package:flutter/material.dart';

/// Custom painter for piano roll grid background
class GridPainter extends CustomPainter {
  final double pixelsPerBeat;
  final double pixelsPerNote;
  final double gridDivision;
  final int maxMidiNote;
  final double totalBeats;
  final double activeBeats; // Active region boundary

  GridPainter({
    required this.pixelsPerBeat,
    required this.pixelsPerNote,
    required this.gridDivision,
    required this.maxMidiNote,
    required this.totalBeats,
    required this.activeBeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // STEP 1: Draw backgrounds FIRST (so vertical lines can be drawn on top)
    for (int note = 0; note <= maxMidiNote; note++) {
      final y = (maxMidiNote - note) * pixelsPerNote;
      final isBlackKey = _isBlackKey(note);

      // Draw background color (dark theme to match DAW UI)
      final bgPaint = Paint()
        ..color = isBlackKey ? const Color(0xFF242424) : const Color(0xFF363636);

      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, pixelsPerNote),
        bgPaint,
      );

      // Draw horizontal separator line
      final linePaint = Paint()
        ..color = const Color(0xFF333333) // Subtle dark line
        ..strokeWidth = 0.5;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // STEP 2: Draw vertical grid lines ON TOP (so they're visible)
    // Dark theme grid colors
    final subdivisionPaint = Paint()
      ..color = const Color(0xFF404040) // Dark grey for 16th note lines
      ..strokeWidth = 1.0;

    final beatPaint = Paint()
      ..color = const Color(0xFF505050) // Medium grey for beats
      ..strokeWidth = 1.5;

    final barPaint = Paint()
      ..color = const Color(0xFF606060) // Lighter grey for bars
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

  @override
  bool shouldRepaint(GridPainter oldDelegate) {
    return pixelsPerBeat != oldDelegate.pixelsPerBeat ||
        pixelsPerNote != oldDelegate.pixelsPerNote ||
        gridDivision != oldDelegate.gridDivision ||
        totalBeats != oldDelegate.totalBeats ||
        activeBeats != oldDelegate.activeBeats;
  }
}
