import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';

/// Compact virtual piano keyboard widget for testing MIDI without physical hardware
/// Displays inline with controls on the left and 21 piano keys (~2 octaves) on the right
class VirtualPiano extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool isEnabled;
  final VoidCallback? onClose;
  final int? selectedTrackId;
  final void Function(int? midiNote)? onNoteHighlight;

  const VirtualPiano({
    super.key,
    required this.audioEngine,
    required this.isEnabled,
    this.onClose,
    this.selectedTrackId,
    this.onNoteHighlight,
  });

  @override
  State<VirtualPiano> createState() => _VirtualPianoState();
}

class _VirtualPianoState extends State<VirtualPiano> with SingleTickerProviderStateMixin {
  // Height constraints
  static const double _minHeight = 56.0;
  static const double _maxHeight = 120.0;
  static const double _defaultHeight = 56.0;

  // Current height (adjustable via drag)
  double _height = _defaultHeight;

  // Current octave (base octave for the keyboard, default C4)
  int _currentOctave = 4;

  // Calculate MIDI offset based on current octave
  int get _octaveOffset => (_currentOctave - 4) * 12;

  // Velocity for note output (1-127)
  int _velocity = 100;

  // Whether keyboard input is enabled
  bool _keyboardEnabled = true;

  // Sustain pedal active (Shift key)
  bool _sustainActive = false;

  // Notes that are being sustained (held by sustain pedal)
  final Set<int> _sustainedNotes = {};

  // Track which notes are currently pressed (by keyboard or mouse)
  final Set<int> _pressedNotes = {};

  // Track which keyboard keys are currently held down (to prevent repeat)
  final Set<LogicalKeyboardKey> _heldKeys = {};

  // Animation controller for slide-in effect
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  // Focus node for keyboard input
  final FocusNode _focusNode = FocusNode();

  // Track focus state for visual indicator
  bool _hasFocus = false;

  // White key keyboard mapping (A-\ keys) -> relative MIDI notes from C
  static final Map<LogicalKeyboardKey, int> _whiteKeyMapping = {
    LogicalKeyboardKey.keyA: 0,   // C
    LogicalKeyboardKey.keyS: 2,   // D
    LogicalKeyboardKey.keyD: 4,   // E
    LogicalKeyboardKey.keyF: 5,   // F
    LogicalKeyboardKey.keyG: 7,   // G
    LogicalKeyboardKey.keyH: 9,   // A
    LogicalKeyboardKey.keyJ: 11,  // B
    LogicalKeyboardKey.keyK: 12,  // C (next octave)
    LogicalKeyboardKey.keyL: 14,  // D
    LogicalKeyboardKey.semicolon: 16,  // E
    LogicalKeyboardKey.quoteSingle: 17,  // F
    LogicalKeyboardKey.backslash: 19,  // G
  };

  // Black key keyboard mapping (W/E/T/Y/U/O/P/]/=) -> relative MIDI notes from C
  static final Map<LogicalKeyboardKey, int> _blackKeyMapping = {
    LogicalKeyboardKey.keyW: 1,   // C#
    LogicalKeyboardKey.keyE: 3,   // D#
    LogicalKeyboardKey.keyT: 6,   // F#
    LogicalKeyboardKey.keyY: 8,   // G#
    LogicalKeyboardKey.keyU: 10,  // A#
    LogicalKeyboardKey.keyO: 13,  // C# (next octave)
    LogicalKeyboardKey.keyP: 15,  // D#
    LogicalKeyboardKey.bracketRight: 18,  // F#
    LogicalKeyboardKey.equal: 20,  // G#
  };

  // Combined keyboard mapping (computed with current octave offset)
  Map<LogicalKeyboardKey, int> get _keyboardMapping {
    final map = <LogicalKeyboardKey, int>{};
    final baseNote = 60 + _octaveOffset; // C4 + offset

    for (final entry in _whiteKeyMapping.entries) {
      map[entry.key] = baseNote + entry.value;
    }
    for (final entry in _blackKeyMapping.entries) {
      map[entry.key] = baseNote + entry.value;
    }

    return map;
  }

  // Key labels for display (key character only, note name computed dynamically)
  static const Map<int, String> _keyLabels = {
    // White keys (relative position)
    0: 'A', 2: 'S', 4: 'D', 5: 'F', 7: 'G', 9: 'H', 11: 'J',
    12: 'K', 14: 'L', 16: ';', 17: "'", 19: '\\',
    // Black keys
    1: 'W', 3: 'E', 6: 'T', 8: 'Y', 10: 'U',
    13: 'O', 15: 'P', 18: ']', 20: '=',
  };

  // Note names (without octave number)
  static const List<String> _noteNamesInOctave = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  String _getNoteNameWithoutOctave(int midiNote) {
    final noteIndex = midiNote % 12;
    return _noteNamesInOctave[noteIndex];
  }

  @override
  void initState() {
    super.initState();

    // Listen to focus changes
    _focusNode.addListener(() {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    });

    // Setup slide animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    // Start animation
    _animationController.forward();

    // Request focus when enabled
    if (widget.isEnabled) {
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(VirtualPiano oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Request focus when enabled
    if (widget.isEnabled && !oldWidget.isEnabled) {
      _focusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _decreaseOctave() {
    if (_currentOctave > -1) {
      setState(() {
        _currentOctave--;
      });
    }
  }

  void _increaseOctave() {
    if (_currentOctave < 9) {
      setState(() {
        _currentOctave++;
      });
    }
  }

  void _onKeyEvent(KeyEvent event) {
    if (!widget.isEnabled || widget.audioEngine == null) return;

    final key = event.logicalKey;

    // Handle Shift key for sustain
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      if (event is KeyDownEvent) {
        setState(() {
          _sustainActive = true;
        });
      } else if (event is KeyUpEvent) {
        _releaseSustainedNotes();
      }
      return;
    }

    // Handle octave change keys (Z/X)
    if (key == LogicalKeyboardKey.keyZ) {
      if (event is KeyDownEvent && !_heldKeys.contains(key)) {
        _heldKeys.add(key);
        _decreaseOctave();
      } else if (event is KeyUpEvent) {
        _heldKeys.remove(key);
      }
      return;
    }
    if (key == LogicalKeyboardKey.keyX) {
      if (event is KeyDownEvent && !_heldKeys.contains(key)) {
        _heldKeys.add(key);
        _increaseOctave();
      } else if (event is KeyUpEvent) {
        _heldKeys.remove(key);
      }
      return;
    }

    // Skip if keyboard input is disabled
    if (!_keyboardEnabled) return;

    // Handle piano keys
    final midiNote = _keyboardMapping[key];
    if (midiNote == null) return;

    // Clamp to valid MIDI range
    if (midiNote < 0 || midiNote > 127) return;

    if (event is KeyDownEvent) {
      // Prevent repeated key-down events
      if (_heldKeys.contains(key)) return;
      _heldKeys.add(key);

      // Trigger note on
      _noteOn(midiNote);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);

      // Trigger note off (if not sustained)
      _noteOff(midiNote);
    }
  }

  void _releaseSustainedNotes() {
    setState(() {
      _sustainActive = false;
      // Release all sustained notes that aren't currently pressed
      for (final note in _sustainedNotes.toList()) {
        if (!_pressedNotes.contains(note)) {
          _sendNoteOff(note);
        }
      }
      _sustainedNotes.clear();
    });
    widget.onNoteHighlight?.call(null);
  }

  void _noteOn(int midiNote) {
    if (_pressedNotes.contains(midiNote)) return;

    setState(() {
      _pressedNotes.add(midiNote);
      if (_sustainActive) {
        _sustainedNotes.add(midiNote);
      }
    });

    // Send MIDI note on to selected track's instrument
    if (widget.selectedTrackId != null) {
      try {
        widget.audioEngine?.sendTrackMidiNoteOn(widget.selectedTrackId!, midiNote, _velocity);
      } catch (e) {
        // FFI call - ignore MIDI send errors silently
      }
    }

    // Notify for piano roll highlighting
    widget.onNoteHighlight?.call(midiNote);
  }

  void _noteOff(int midiNote) {
    setState(() {
      _pressedNotes.remove(midiNote);
    });

    // If sustain is active and this note is sustained, don't send note off
    if (_sustainActive && _sustainedNotes.contains(midiNote)) {
      return;
    }

    _sendNoteOff(midiNote);

    // Clear highlight if no notes are pressed
    if (_pressedNotes.isEmpty && _sustainedNotes.isEmpty) {
      widget.onNoteHighlight?.call(null);
    }
  }

  void _sendNoteOff(int midiNote) {
    // Send MIDI note off to selected track's instrument
    if (widget.selectedTrackId != null) {
      try {
        widget.audioEngine?.sendTrackMidiNoteOff(widget.selectedTrackId!, midiNote, 0);
      } catch (e) {
        // FFI call - ignore MIDI send errors silently
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.isEnabled,
          onKeyEvent: (node, event) {
            final key = event.logicalKey;

            // Always handle sustain and octave keys
            if (key == LogicalKeyboardKey.shiftLeft ||
                key == LogicalKeyboardKey.shiftRight ||
                key == LogicalKeyboardKey.keyZ ||
                key == LogicalKeyboardKey.keyX) {
              _onKeyEvent(event);
              return KeyEventResult.handled;
            }

            // Handle piano keys only if keyboard is enabled
            if (_keyboardEnabled && _keyboardMapping.containsKey(key)) {
              _onKeyEvent(event);
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Resize handle at top
              _buildResizeHandle(),
              // Main piano content
              Container(
                height: _height,
                decoration: BoxDecoration(
                  color: context.colors.darkest,
                ),
                child: Row(
                  children: [
                    // Controls section
                    _buildControls(),

                    // Divider
                    Container(
                      width: 1,
                      color: context.colors.elevated,
                    ),

                    // Piano keyboard
                    Expanded(
                      child: _buildKeyboard(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            // Drag up = increase height (negative delta.dy)
            _height = (_height - details.delta.dy).clamp(_minHeight, _maxHeight);
          });
        },
        child: Container(
          height: 6,
          decoration: BoxDecoration(
            color: context.colors.standard,
            border: Border(
              top: BorderSide(
                color: _hasFocus ? context.colors.accent : context.colors.elevated,
                width: _hasFocus ? 2 : 1,
              ),
            ),
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 3,
              decoration: BoxDecoration(
                color: context.colors.textMuted,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Octave down button
          _buildControlButton(
            label: 'Oct -',
            sublabel: 'Z',
            onPressed: _currentOctave > -1 ? _decreaseOctave : null,
          ),

          const SizedBox(width: 4),

          // Octave up button
          _buildControlButton(
            label: 'Oct +',
            sublabel: 'X',
            onPressed: _currentOctave < 9 ? _increaseOctave : null,
          ),

          const SizedBox(width: 8),

          // Velocity knob
          _buildVelocityKnob(),

          const SizedBox(width: 8),

          // Keyboard toggle
          _buildKeyboardToggle(),

          const SizedBox(width: 8),

          // Current octave display
          _buildOctaveDisplay(),

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required String label,
    required String sublabel,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isEnabled ? context.colors.dark : context.colors.dark.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: context.colors.elevated,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? context.colors.textPrimary : context.colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVelocityKnob() {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _velocity = (_velocity - details.delta.dy.round()).clamp(1, 127);
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.dark,
              border: Border.all(
                color: context.colors.accent,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                'Vel',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$_velocity',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _keyboardEnabled = !_keyboardEnabled;
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: _keyboardEnabled ? context.colors.accent.withValues(alpha: 0.2) : context.colors.dark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _keyboardEnabled ? context.colors.accent : context.colors.elevated,
            width: 1,
          ),
        ),
        child: Icon(
          Icons.keyboard,
          size: 18,
          color: _keyboardEnabled ? context.colors.accent : context.colors.textMuted,
        ),
      ),
    );
  }

  Widget _buildOctaveDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.dark,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: context.colors.elevated,
          width: 1,
        ),
      ),
      child: Text(
        'C$_currentOctave',
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildKeyboard() {
    // 21 keys: 12 white keys + positions for black keys
    // Pattern: C C# D D# E F F# G G# A A# B C C# D D# E F F# G G#
    // We display 12 white keys and 9 black keys (21 total positions, ~2 octaves)

    final baseNote = 60 + _octaveOffset; // C of current octave

    // White keys: C D E F G A B C D E F G (12 white keys)
    final whiteNotes = <int>[
      baseNote,      // C
      baseNote + 2,  // D
      baseNote + 4,  // E
      baseNote + 5,  // F
      baseNote + 7,  // G
      baseNote + 9,  // A
      baseNote + 11, // B
      baseNote + 12, // C (next octave)
      baseNote + 14, // D
      baseNote + 16, // E
      baseNote + 17, // F
      baseNote + 19, // G
    ];

    // Black keys with their positions (between white keys)
    // Position is the index of the white key after which this black key appears
    final blackKeys = <Map<String, int>>[
      {'note': baseNote + 1, 'afterWhiteIndex': 0},   // C#
      {'note': baseNote + 3, 'afterWhiteIndex': 1},   // D#
      {'note': baseNote + 6, 'afterWhiteIndex': 3},   // F#
      {'note': baseNote + 8, 'afterWhiteIndex': 4},   // G#
      {'note': baseNote + 10, 'afterWhiteIndex': 5},  // A#
      {'note': baseNote + 13, 'afterWhiteIndex': 7},  // C# (next octave)
      {'note': baseNote + 15, 'afterWhiteIndex': 8},  // D#
      {'note': baseNote + 18, 'afterWhiteIndex': 10}, // F#
      {'note': baseNote + 20, 'afterWhiteIndex': 11}, // G#
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final whiteKeyWidth = constraints.maxWidth / whiteNotes.length;
          final blackKeyWidth = whiteKeyWidth * 0.6;

          return Stack(
            children: [
              // White keys layer
              Row(
                children: whiteNotes.map((note) {
                  final relativeNote = (note - baseNote) % 24;
                  return _buildWhiteKey(note, relativeNote);
                }).toList(),
              ),
              // Black keys layer
              ...blackKeys.map((blackKey) {
                final note = blackKey['note']!;
                final afterIndex = blackKey['afterWhiteIndex']!;
                final left = (afterIndex + 0.7) * whiteKeyWidth;
                final relativeNote = (note - baseNote) % 24;

                return Positioned(
                  left: left,
                  top: 0,
                  child: _buildBlackKey(note, relativeNote, blackKeyWidth),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteKey(int midiNote, int relativeNote) {
    final isPressed = _pressedNotes.contains(midiNote) || _sustainedNotes.contains(midiNote);
    final keyLabel = _keyLabels[relativeNote] ?? '';
    final noteName = _getNoteNameWithoutOctave(midiNote);
    final isValidNote = midiNote >= 0 && midiNote <= 127;

    return Expanded(
      child: GestureDetector(
        onTapDown: isValidNote ? (_) => _noteOn(midiNote) : null,
        onTapUp: isValidNote ? (_) => _noteOff(midiNote) : null,
        onTapCancel: isValidNote ? () => _noteOff(midiNote) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isPressed
                ? context.colors.accent
                : (isValidNote ? context.colors.textPrimary : context.colors.surface),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isPressed ? context.colors.accent : context.colors.surface,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '$noteName/$keyLabel',
              style: TextStyle(
                color: isPressed
                    ? context.colors.textPrimary
                    : context.colors.darkest,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlackKey(int midiNote, int relativeNote, double width) {
    final isPressed = _pressedNotes.contains(midiNote) || _sustainedNotes.contains(midiNote);
    final keyLabel = _keyLabels[relativeNote] ?? '';
    final noteName = _getNoteNameWithoutOctave(midiNote);
    final isValidNote = midiNote >= 0 && midiNote <= 127;

    return GestureDetector(
      onTapDown: isValidNote ? (_) => _noteOn(midiNote) : null,
      onTapUp: isValidNote ? (_) => _noteOff(midiNote) : null,
      onTapCancel: isValidNote ? () => _noteOff(midiNote) : null,
      child: Container(
        width: width,
        height: 28,
        decoration: BoxDecoration(
          color: isPressed
              ? context.colors.accent
              : (isValidNote ? context.colors.darkest : context.colors.dark),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isPressed ? context.colors.accent : context.colors.surface,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            '$noteName/$keyLabel',
            style: TextStyle(
              color: isPressed
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
