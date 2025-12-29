import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// A clickable time display showing bar.beat.tick format.
/// Each segment (bar, beat, tick) is individually clickable to edit.
/// Used for loop start and loop length in the Piano Roll toolbar.
class LoopTimeDisplay extends StatefulWidget {
  /// Value in beats (quarter notes)
  final double beats;

  /// Label shown above the display (e.g., "Start", "Length")
  final String label;

  /// Called when value changes
  final Function(double)? onChanged;

  /// Beats per bar (default 4 for 4/4 time)
  final int beatsPerBar;

  /// Ticks per beat (standard MIDI resolution)
  final int ticksPerBeat;

  const LoopTimeDisplay({
    super.key,
    required this.beats,
    required this.label,
    this.onChanged,
    this.beatsPerBar = 4,
    this.ticksPerBeat = 960,
  });

  @override
  State<LoopTimeDisplay> createState() => _LoopTimeDisplayState();
}

class _LoopTimeDisplayState extends State<LoopTimeDisplay> {
  bool _isEditing = false;
  int _editingSegment = -1; // 0=bar, 1=beat, 2=tick
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

  /// Convert beats to bar.beat.tick tuple
  (int bar, int beat, int tick) _beatsToBarBeatTick(double beats) {
    final totalTicks = (beats * widget.ticksPerBeat).round();
    final ticksPerBar = widget.beatsPerBar * widget.ticksPerBeat;

    final bar = (totalTicks ~/ ticksPerBar) + 1; // 1-indexed
    final remainingTicks = totalTicks % ticksPerBar;
    final beat = (remainingTicks ~/ widget.ticksPerBeat) + 1; // 1-indexed
    final tick = remainingTicks % widget.ticksPerBeat;

    return (bar, beat, tick);
  }

  /// Convert bar.beat.tick tuple back to beats
  double _barBeatTickToBeats(int bar, int beat, int tick) {
    final ticksPerBar = widget.beatsPerBar * widget.ticksPerBeat;
    final totalTicks = ((bar - 1) * ticksPerBar) +
        ((beat - 1) * widget.ticksPerBeat) +
        tick;
    return totalTicks / widget.ticksPerBeat;
  }

  void _startEditing(int segment) {
    final (bar, beat, tick) = _beatsToBarBeatTick(widget.beats);
    String initialValue;
    switch (segment) {
      case 0:
        initialValue = bar.toString();
        break;
      case 1:
        initialValue = beat.toString();
        break;
      case 2:
        initialValue = tick.toString();
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
      final (bar, beat, tick) = _beatsToBarBeatTick(widget.beats);

      int newBar = bar;
      int newBeat = beat;
      int newTick = tick;

      switch (_editingSegment) {
        case 0:
          newBar = newValue.clamp(1, 999);
          break;
        case 1:
          newBeat = newValue.clamp(1, widget.beatsPerBar);
          break;
        case 2:
          newTick = newValue.clamp(0, widget.ticksPerBeat - 1);
          break;
      }

      final newBeats = _barBeatTickToBeats(newBar, newBeat, newTick);
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
    final (bar, beat, tick) = _beatsToBarBeatTick(widget.beats);
    int newBar = bar;
    int newBeat = beat;
    int newTick = tick;

    final direction = delta > 0 ? -1 : 1; // Scroll up = increase

    switch (segment) {
      case 0:
        newBar = (bar + direction).clamp(1, 999);
        break;
      case 1:
        newBeat = (beat + direction).clamp(1, widget.beatsPerBar);
        break;
      case 2:
        newTick = (tick + direction * 10).clamp(0, widget.ticksPerBeat - 1);
        break;
    }

    final newBeats = _barBeatTickToBeats(newBar, newBeat, newTick);
    widget.onChanged?.call(newBeats);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bar, beat, tick) = _beatsToBarBeatTick(widget.beats);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Text(
          widget.label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        // Time display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSegment(0, bar.toString(), colors),
              _buildDot(colors),
              _buildSegment(1, beat.toString(), colors),
              _buildDot(colors),
              _buildSegment(2, tick.toString().padLeft(3, '0'), colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegment(int segment, String value, BoojyColors colors) {
    final isEditing = _isEditing && _editingSegment == segment;

    if (isEditing) {
      return SizedBox(
        width: segment == 2 ? 30 : 20,
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
              LengthLimitingTextInputFormatter(segment == 2 ? 3 : 3),
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
