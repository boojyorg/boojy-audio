import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// A clickable time display showing bar.beat.subdivision format.
/// Each segment (bar, beat, sub) is individually clickable to edit.
/// Used for loop start and loop length in the Piano Roll toolbar.
///
/// Format: bar.beat.sub where sub is 1-4 (sixteenth notes within a beat)
class LoopTimeDisplay extends StatefulWidget {
  /// Value in beats (quarter notes)
  final double beats;

  /// Label shown above the display (e.g., "Start", "Length")
  final String label;

  /// Called when value changes
  final Function(double)? onChanged;

  /// Beats per bar (default 4 for 4/4 time)
  final int beatsPerBar;

  /// Subdivisions per beat (default 4 for sixteenth notes)
  final int subsPerBeat;

  const LoopTimeDisplay({
    super.key,
    required this.beats,
    required this.label,
    this.onChanged,
    this.beatsPerBar = 4,
    this.subsPerBeat = 4, // 4 sixteenths per beat
  });

  @override
  State<LoopTimeDisplay> createState() => _LoopTimeDisplayState();
}

class _LoopTimeDisplayState extends State<LoopTimeDisplay> {
  bool _isEditing = false;
  int _editingSegment = -1; // 0=bar, 1=beat, 2=sub
  late TextEditingController _editController;
  late FocusNode _editFocusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
    _editFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.removeListener(_onFocusChange);
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_editFocusNode.hasFocus && _isEditing) {
      _commitEdit();
    }
  }

  /// Convert beats to bar.beat.sub tuple (all 1-indexed)
  /// sub = sixteenth note subdivision within the beat (1-4)
  (int bar, int beat, int sub) _beatsToBarBeatSub(double beats) {
    final totalSubs = (beats * widget.subsPerBeat).round();
    final subsPerBar = widget.beatsPerBar * widget.subsPerBeat;

    final bar = (totalSubs ~/ subsPerBar) + 1; // 1-indexed
    final remainingSubs = totalSubs % subsPerBar;
    final beat = (remainingSubs ~/ widget.subsPerBeat) + 1; // 1-indexed
    final sub = (remainingSubs % widget.subsPerBeat) + 1; // 1-indexed (1-4)

    return (bar, beat, sub);
  }

  /// Convert bar.beat.sub tuple back to beats (all 1-indexed input)
  double _barBeatSubToBeats(int bar, int beat, int sub) {
    final subsPerBar = widget.beatsPerBar * widget.subsPerBeat;
    final totalSubs = ((bar - 1) * subsPerBar) +
        ((beat - 1) * widget.subsPerBeat) +
        (sub - 1); // sub is 1-indexed
    return totalSubs / widget.subsPerBeat;
  }

  void _startEditing(int segment) {
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);
    String initialValue;
    switch (segment) {
      case 0:
        initialValue = bar.toString();
        break;
      case 1:
        initialValue = beat.toString();
        break;
      case 2:
        initialValue = sub.toString();
        break;
      default:
        return;
    }

    setState(() {
      _isEditing = true;
      _editingSegment = segment;
      _editController.text = initialValue;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _commitEdit() {
    if (!_isEditing) return;

    final newValue = int.tryParse(_editController.text);
    if (newValue != null && widget.onChanged != null) {
      final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);

      int newBar = bar;
      int newBeat = beat;
      int newSub = sub;

      switch (_editingSegment) {
        case 0:
          newBar = newValue.clamp(1, 999);
          break;
        case 1:
          newBeat = newValue.clamp(1, widget.beatsPerBar);
          break;
        case 2:
          newSub = newValue.clamp(1, widget.subsPerBeat); // 1-4 for sixteenths
          break;
      }

      final newBeats = _barBeatSubToBeats(newBar, newBeat, newSub);
      widget.onChanged!(newBeats);
    }

    setState(() {
      _isEditing = false;
      _editingSegment = -1;
    });
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _commitEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _isEditing = false;
          _editingSegment = -1;
        });
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        // Move to next segment
        _commitEdit();
        final nextSegment = (_editingSegment + 1) % 3;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startEditing(nextSegment);
        });
      }
    }
  }

  /// Increment/decrement segment with scroll
  void _handleScroll(int segment, double delta) {
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);
    int newBar = bar;
    int newBeat = beat;
    int newSub = sub;

    final direction = delta > 0 ? -1 : 1; // Scroll up = increase

    switch (segment) {
      case 0:
        newBar = (bar + direction).clamp(1, 999);
        break;
      case 1:
        newBeat = (beat + direction).clamp(1, widget.beatsPerBar);
        break;
      case 2:
        newSub = (sub + direction).clamp(1, widget.subsPerBeat); // 1-4 for sixteenths
        break;
    }

    final newBeats = _barBeatSubToBeats(newBar, newBeat, newSub);
    widget.onChanged?.call(newBeats);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bar, beat, sub) = _beatsToBarBeatSub(widget.beats);

    // Single row with 3 clickable/editable segments
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSegment(0, bar.toString(), colors),
        _buildDot(colors),
        _buildSegment(1, beat.toString(), colors),
        _buildDot(colors),
        _buildSegment(2, sub.toString(), colors),
      ],
    );
  }

  Widget _buildSegment(int segment, String value, BoojyColors colors) {
    final isEditing = _isEditing && _editingSegment == segment;

    if (isEditing) {
      return SizedBox(
        width: 20, // All segments are single digit now
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _handleKey,
          child: TextField(
            controller: _editController,
            focusNode: _editFocusNode,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(segment == 0 ? 3 : 1), // bar can be 3 digits, beat/sub are 1 digit
            ],
            onSubmitted: (_) => _commitEdit(),
          ),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(segment, event.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        onTap: () => _startEditing(segment),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(BoojyColors colors) {
    return Text(
      '.',
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
  }
}
