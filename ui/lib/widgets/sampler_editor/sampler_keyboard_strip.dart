import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// Slim piano strip at the bottom of the Sampler editor for auditioning the
/// loaded sample — the GarageBand Quick Sampler signature. Click (or click and
/// glide) to hear the sample pitched; the root note key is tinted accent.
///
/// Range is C1 (24) to C7 (96), stretched to the available width.
class SamplerKeyboardStrip extends StatefulWidget {
  static const double height = 44.0;

  final int rootNote;
  final bool enabled;
  final void Function(int note) onNoteOn;
  final void Function(int note) onNoteOff;

  const SamplerKeyboardStrip({
    super.key,
    required this.rootNote,
    required this.onNoteOn,
    required this.onNoteOff,
    this.enabled = true,
  });

  @override
  State<SamplerKeyboardStrip> createState() => _SamplerKeyboardStripState();
}

class _SamplerKeyboardStripState extends State<SamplerKeyboardStrip> {
  static const int _lowNote = 24; // C1
  static const int _highNote = 96; // C7

  int? _activeNote;

  @override
  void dispose() {
    _releaseActiveNote();
    super.dispose();
  }

  void _releaseActiveNote() {
    final note = _activeNote;
    if (note != null) {
      widget.onNoteOff(note);
      _activeNote = null;
    }
  }

  void _pressNoteAt(Offset localPosition, Size size) {
    if (!widget.enabled) return;
    final note = _KeyboardGeometry(
      size,
      _lowNote,
      _highNote,
    ).noteAt(localPosition);
    if (note == null || note == _activeNote) return;
    _releaseActiveNote();
    widget.onNoteOn(note);
    setState(() => _activeNote = note);
  }

  void _release() {
    if (_activeNote == null) return;
    _releaseActiveNote();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: SamplerKeyboardStrip.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return MouseRegion(
            cursor: widget.enabled
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: Listener(
              onPointerDown: (e) => _pressNoteAt(e.localPosition, size),
              onPointerMove: (e) {
                // Glide: sliding across keys retriggers like a real keyboard.
                if (_activeNote != null) _pressNoteAt(e.localPosition, size);
              },
              onPointerUp: (_) => _release(),
              onPointerCancel: (_) => _release(),
              child: CustomPaint(
                size: size,
                painter: _KeyboardStripPainter(
                  colors: colors,
                  rootNote: widget.rootNote,
                  activeNote: _activeNote,
                  enabled: widget.enabled,
                  lowNote: _lowNote,
                  highNote: _highNote,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shared key layout math for painting and hit-testing.
class _KeyboardGeometry {
  final Size size;
  final int lowNote;
  final int highNote;

  _KeyboardGeometry(this.size, this.lowNote, this.highNote);

  static bool isBlack(int note) => const [1, 3, 6, 8, 10].contains(note % 12);

  List<int> get whiteNotes => [
    for (int n = lowNote; n <= highNote; n++)
      if (!isBlack(n)) n,
  ];

  double get whiteKeyWidth => size.width / whiteNotes.length;

  double get blackKeyHeight => size.height * 0.62;

  double get blackKeyWidth => whiteKeyWidth * 0.62;

  /// Left edge X of a white key (counts white keys below it).
  double whiteKeyX(int note) {
    int index = 0;
    for (int n = lowNote; n < note; n++) {
      if (!isBlack(n)) index++;
    }
    return index * whiteKeyWidth;
  }

  /// Center X of a black key (sits on the boundary after its lower white
  /// neighbour).
  double blackKeyCenterX(int note) {
    assert(isBlack(note));
    return whiteKeyX(note - 1) + whiteKeyWidth;
  }

  Rect blackKeyRect(int note) {
    final cx = blackKeyCenterX(note);
    return Rect.fromLTWH(
      cx - blackKeyWidth / 2,
      0,
      blackKeyWidth,
      blackKeyHeight,
    );
  }

  int? noteAt(Offset position) {
    if (position.dx < 0 ||
        position.dx >= size.width ||
        position.dy < 0 ||
        position.dy >= size.height) {
      return null;
    }

    // Black keys sit on top, so test them first.
    if (position.dy < blackKeyHeight) {
      for (int n = lowNote; n <= highNote; n++) {
        if (isBlack(n) && blackKeyRect(n).contains(position)) return n;
      }
    }

    final whiteIndex = (position.dx / whiteKeyWidth).floor().clamp(
      0,
      whiteNotes.length - 1,
    );
    return whiteNotes[whiteIndex];
  }
}

class _KeyboardStripPainter extends CustomPainter {
  final BoojyColors colors;
  final int rootNote;
  final int? activeNote;
  final bool enabled;
  final int lowNote;
  final int highNote;

  _KeyboardStripPainter({
    required this.colors,
    required this.rootNote,
    required this.activeNote,
    required this.enabled,
    required this.lowNote,
    required this.highNote,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geo = _KeyboardGeometry(size, lowNote, highNote);
    final whiteFill = enabled
        ? colors.textPrimary
        : colors.textPrimary.withValues(alpha: 0.35);
    final blackFill = enabled
        ? colors.darkest
        : colors.darkest.withValues(alpha: 0.5);
    final borderPaint = Paint()
      ..color = colors.dark
      ..strokeWidth = 1.0;

    // White keys.
    for (final note in geo.whiteNotes) {
      final rect = Rect.fromLTWH(
        geo.whiteKeyX(note),
        0,
        geo.whiteKeyWidth,
        size.height,
      );
      Color fill = whiteFill;
      if (note == rootNote) fill = colors.accent;
      if (note == activeNote) fill = colors.selectionBorder;
      canvas.drawRect(rect, Paint()..color = fill);
      canvas.drawLine(rect.topRight, rect.bottomRight, borderPaint);
    }

    // Black keys on top.
    for (int n = lowNote; n <= highNote; n++) {
      if (!_KeyboardGeometry.isBlack(n)) continue;
      final rect = geo.blackKeyRect(n);
      Color fill = blackFill;
      if (n == rootNote) fill = colors.accent;
      if (n == activeNote) fill = colors.selectionBorder;
      canvas.drawRect(rect, Paint()..color = fill);
    }

    // Top border separating strip from the waveform.
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = colors.divider
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _KeyboardStripPainter oldDelegate) {
    return rootNote != oldDelegate.rootNote ||
        activeNote != oldDelegate.activeNote ||
        enabled != oldDelegate.enabled ||
        colors != oldDelegate.colors;
  }
}
