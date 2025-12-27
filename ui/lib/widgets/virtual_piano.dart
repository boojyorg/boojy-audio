import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';

/// Virtual piano keyboard widget for testing MIDI without physical hardware
class VirtualPiano extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool isEnabled;
  final VoidCallback? onClose;
  final int? selectedTrackId;

  const VirtualPiano({
    super.key,
    required this.audioEngine,
    required this.isEnabled,
    this.onClose,
    this.selectedTrackId,
  });

  @override
  State<VirtualPiano> createState() => _VirtualPianoState();
}

class _VirtualPianoState extends State<VirtualPiano> with SingleTickerProviderStateMixin {
  // Keyboard mapping: key -> MIDI note number
  final Map<LogicalKeyboardKey, int> _keyboardMapping = {
    // Bottom row - White keys (C4-E5)
    LogicalKeyboardKey.keyZ: 60,  // C4
    LogicalKeyboardKey.keyX: 62,  // D4
    LogicalKeyboardKey.keyC: 64,  // E4
    LogicalKeyboardKey.keyV: 65,  // F4
    LogicalKeyboardKey.keyB: 67,  // G4
    LogicalKeyboardKey.keyN: 69,  // A4
    LogicalKeyboardKey.keyM: 71,  // B4
    LogicalKeyboardKey.comma: 72,  // C5
    LogicalKeyboardKey.period: 74,  // D5
    LogicalKeyboardKey.slash: 76,  // E5
    // Bottom row - Black keys (sharps)
    LogicalKeyboardKey.keyS: 61,  // C#4
    LogicalKeyboardKey.keyD: 63,  // D#4
    LogicalKeyboardKey.keyG: 66,  // F#4
    LogicalKeyboardKey.keyH: 68,  // G#4
    LogicalKeyboardKey.keyJ: 70,  // A#4
    LogicalKeyboardKey.keyL: 73,  // C#5
    LogicalKeyboardKey.semicolon: 75,  // D#5
    // Top row - White keys (C5-E6)
    LogicalKeyboardKey.keyW: 72,  // C5
    LogicalKeyboardKey.keyE: 74,  // D5
    LogicalKeyboardKey.keyR: 76,  // E5
    LogicalKeyboardKey.keyT: 77,  // F5
    LogicalKeyboardKey.keyY: 79,  // G5
    LogicalKeyboardKey.keyU: 81,  // A5
    LogicalKeyboardKey.keyI: 83,  // B5
    LogicalKeyboardKey.keyO: 84,  // C6
    LogicalKeyboardKey.keyP: 86,  // D6
    LogicalKeyboardKey.bracketLeft: 88,  // E6
    // Top row - Black keys (sharps)
    LogicalKeyboardKey.digit3: 73,  // C#5
    LogicalKeyboardKey.digit4: 75,  // D#5
    LogicalKeyboardKey.digit6: 78,  // F#5
    LogicalKeyboardKey.digit7: 80,  // G#5
    LogicalKeyboardKey.digit8: 82,  // A#5
    LogicalKeyboardKey.digit0: 85,  // C#6
    LogicalKeyboardKey.minus: 87,  // D#6
  };

  // Note names for display (sharp notation)
  final Map<int, String> _noteNames = {
    // White keys
    60: 'C4', 62: 'D4', 64: 'E4', 65: 'F4', 67: 'G4', 69: 'A4', 71: 'B4',
    72: 'C5', 74: 'D5', 76: 'E5', 77: 'F5', 79: 'G5', 81: 'A5', 83: 'B5',
    84: 'C6', 86: 'D6', 88: 'E6',
    // Black keys (sharps)
    61: 'C#4', 63: 'D#4', 66: 'F#4', 68: 'G#4', 70: 'A#4',
    73: 'C#5', 75: 'D#5', 78: 'F#5', 80: 'G#5', 82: 'A#5',
    85: 'C#6', 87: 'D#6',
  };

  // Flat notation for black keys (to display above sharp)
  final Map<int, String> _flatNames = {
    61: 'Db4', 63: 'Eb4', 66: 'Gb4', 68: 'Ab4', 70: 'Bb4',
    73: 'Db5', 75: 'Eb5', 78: 'Gb5', 80: 'Ab5', 82: 'Bb5',
    85: 'Db6', 87: 'Eb6',
  };

  // Key labels for each MIDI note
  final Map<int, String> _keyLabels = {
    // White keys
    60: 'Z', 62: 'X', 64: 'C', 65: 'V', 67: 'B', 69: 'N', 71: 'M',
    72: ',/W', 74: './E', 76: '//R', 77: 'T', 79: 'Y', 81: 'U', 83: 'I',
    84: 'O', 86: 'P', 88: '[',
    // Black keys
    61: 'S', 63: 'D', 66: 'G', 68: 'H', 70: 'J', 73: 'L/3', 75: ';/4',
    78: '6', 80: '7', 82: '8', 85: '0', 87: '-',
  };

  // Track which notes are currently pressed
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

  @override
  void initState() {
    super.initState();

    // Listen to focus changes
    _focusNode.addListener(() {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
      print('🎹 [VirtualPiano] Focus changed: $_hasFocus');
    });

    // Setup slide animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    // Start animation
    _animationController.forward();

    // Request focus when enabled - use multiple attempts to ensure focus
    if (widget.isEnabled) {
      // Immediate request
      _focusNode.requestFocus();

      // Post-frame request
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        print('🎹 [VirtualPiano] Focus requested in initState');
      });

      // Delayed request after animation
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _focusNode.requestFocus();
          print('🎹 [VirtualPiano] Focus requested after animation');
        }
      });
    }
  }

  @override
  void didUpdateWidget(VirtualPiano oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Request focus when enabled
    if (widget.isEnabled && !oldWidget.isEnabled) {
      _focusNode.requestFocus();
      print('🎹 [VirtualPiano] Focus requested in didUpdateWidget');

      // Also request after a delay to ensure it sticks
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

  void _onKeyEvent(KeyEvent event) {
    if (!widget.isEnabled || widget.audioEngine == null) return;

    final key = event.logicalKey;
    final midiNote = _keyboardMapping[key];

    if (midiNote == null) return;

    if (event is KeyDownEvent) {
      // Prevent repeated key-down events
      if (_heldKeys.contains(key)) return;
      _heldKeys.add(key);

      // Trigger note on
      _noteOn(midiNote);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);

      // Trigger note off
      _noteOff(midiNote);
    }
  }

  void _noteOn(int midiNote) {
    if (_pressedNotes.contains(midiNote)) return;

    setState(() {
      _pressedNotes.add(midiNote);
    });

    // Send MIDI note on to selected track's instrument with velocity 100 (forte)
    if (widget.selectedTrackId != null) {
      try {
        widget.audioEngine?.sendTrackMidiNoteOn(widget.selectedTrackId!, midiNote, 100);
      } catch (e) {
        print('Error playing note on track ${widget.selectedTrackId}: $e');
      }
    }
    // If no track selected, piano is silent (do nothing)
  }

  void _noteOff(int midiNote) {
    setState(() {
      _pressedNotes.remove(midiNote);
    });

    // Send MIDI note off to selected track's instrument
    if (widget.selectedTrackId != null) {
      try {
        widget.audioEngine?.sendTrackMidiNoteOff(widget.selectedTrackId!, midiNote, 0);
      } catch (e) {
        print('Error stopping note on track ${widget.selectedTrackId}: $e');
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
          // Request focus when piano is tapped
          _focusNode.requestFocus();
          print('🎹 [VirtualPiano] Focus requested');
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.isEnabled,
          onKeyEvent: (node, event) {
            // Only handle keys that are mapped to piano notes
            if (_keyboardMapping.containsKey(event.logicalKey)) {
              print('🎹 [VirtualPiano] Handling piano key: ${event.logicalKey}');
              _onKeyEvent(event);
              return KeyEventResult.handled;
            }
            // Let other keys propagate to other widgets (for text input, etc.)
            return KeyEventResult.ignored;
          },
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              border: Border(
                top: BorderSide(
                  color: _hasFocus ? const Color(0xFF4CAF50) : Colors.grey[800]!,
                  width: _hasFocus ? 3 : 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
                if (_hasFocus)
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
              ],
            ),
            child: Column(
              children: [
                // Header with controls
                _buildHeader(),

                // Piano keyboard
                Expanded(
                  child: _buildKeyboard(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.piano,
            color: Color(0xFF4CAF50),
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text(
            'Virtual Piano Keyboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),

          // Close button
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            color: Colors.grey[400],
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onClose,
            tooltip: 'Hide Piano',
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    // White keys: C4 to E6
    final whiteNotes = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84, 86, 88];

    // Black keys with their positions (as a fraction between white keys)
    // Pattern: C, C#, D, D#, E, F, F#, G, G#, A, A#, B
    // Black keys come after: C(0), D(1), F(3), G(4), A(5), C(7), D(8), F(10), G(11), A(12), C(14), D(15)
    final blackKeys = [
      {'note': 61, 'afterWhiteIndex': 0},  // C#4 after C4
      {'note': 63, 'afterWhiteIndex': 1},  // D#4 after D4
      {'note': 66, 'afterWhiteIndex': 3},  // F#4 after F4
      {'note': 68, 'afterWhiteIndex': 4},  // G#4 after G4
      {'note': 70, 'afterWhiteIndex': 5},  // A#4 after A4
      {'note': 73, 'afterWhiteIndex': 7},  // C#5 after C5
      {'note': 75, 'afterWhiteIndex': 8},  // D#5 after D5
      {'note': 78, 'afterWhiteIndex': 10}, // F#5 after F5
      {'note': 80, 'afterWhiteIndex': 11}, // G#5 after G5
      {'note': 82, 'afterWhiteIndex': 12}, // A#5 after A5
      {'note': 85, 'afterWhiteIndex': 14}, // C#6 after C6
      {'note': 87, 'afterWhiteIndex': 15}, // D#6 after D6
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final whiteKeyWidth = constraints.maxWidth / whiteNotes.length;

          return Stack(
            children: [
              // White keys layer
              Row(
                children: whiteNotes.map((note) => _buildWhiteKey(note)).toList(),
              ),
              // Black keys layer
              ...blackKeys.map((blackKey) {
                final note = blackKey['note'] as int;
                final afterIndex = blackKey['afterWhiteIndex'] as int;
                final left = (afterIndex + 0.7) * whiteKeyWidth; // Position between white keys

                return Positioned(
                  left: left,
                  top: 0,
                  child: _buildBlackKey(note, whiteKeyWidth * 0.6),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWhiteKey(int midiNote) {
    final isPressed = _pressedNotes.contains(midiNote);
    final label = _keyLabels[midiNote] ?? '';
    final noteName = _noteNames[midiNote] ?? '';

    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => _noteOn(midiNote),
        onTapUp: (_) => _noteOff(midiNote),
        onTapCancel: () => _noteOff(midiNote),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isPressed ? const Color(0xFF4CAF50) : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isPressed ? const Color(0xFF4CAF50) : const Color(0xFF404040),
              width: 2,
            ),
            boxShadow: isPressed
                ? [
                    BoxShadow(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Note name at top
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  noteName,
                  style: TextStyle(
                    color: isPressed ? Colors.white : Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const Spacer(),

              // Keyboard key label at bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isPressed ? Colors.white : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlackKey(int midiNote, double width) {
    final isPressed = _pressedNotes.contains(midiNote);
    final label = _keyLabels[midiNote] ?? '';
    final noteName = _noteNames[midiNote] ?? '';  // Sharp notation
    final flatName = _flatNames[midiNote] ?? '';  // Flat notation

    return GestureDetector(
      onTapDown: (_) => _noteOn(midiNote),
      onTapUp: (_) => _noteOff(midiNote),
      onTapCancel: () => _noteOff(midiNote),
      child: Container(
        width: width,
        height: 100, // Shorter than white keys
        decoration: BoxDecoration(
          color: isPressed ? const Color(0xFF9C27B0) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isPressed ? const Color(0xFF9C27B0) : const Color(0xFF404040),
            width: 2,
          ),
          boxShadow: isPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFF9C27B0).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Flat notation at top (smaller)
            Text(
              flatName,
              style: TextStyle(
                color: isPressed ? Colors.white : const Color(0xFF808080),
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Sharp notation in middle (main label)
            Text(
              noteName,
              style: TextStyle(
                color: isPressed ? Colors.white : const Color(0xFFA0A0A0),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),

            // Keyboard key label at bottom
            Text(
              label,
              style: TextStyle(
                color: isPressed ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
