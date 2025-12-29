import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// A clickable time signature display showing numerator/denominator format.
/// Each segment is individually clickable to edit.
/// Format: [4] / [4]
class TimeSignatureDisplay extends StatefulWidget {
  /// Beats per bar (numerator, e.g., 4 in 4/4)
  final int beatsPerBar;

  /// Beat unit (denominator, e.g., 4 in 4/4)
  final int beatUnit;

  /// Called when beats per bar changes
  final Function(int)? onBeatsPerBarChanged;

  /// Called when beat unit changes
  final Function(int)? onBeatUnitChanged;

  const TimeSignatureDisplay({
    super.key,
    required this.beatsPerBar,
    required this.beatUnit,
    this.onBeatsPerBarChanged,
    this.onBeatUnitChanged,
  });

  @override
  State<TimeSignatureDisplay> createState() => _TimeSignatureDisplayState();
}

class _TimeSignatureDisplayState extends State<TimeSignatureDisplay> {
  bool _isEditing = false;
  int _editingSegment = -1; // 0=numerator, 1=denominator
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

  void _startEditing(int segment) {
    String initialValue;
    switch (segment) {
      case 0:
        initialValue = widget.beatsPerBar.toString();
        break;
      case 1:
        initialValue = widget.beatUnit.toString();
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
    if (newValue != null) {
      switch (_editingSegment) {
        case 0:
          // Numerator: 1-99
          final clamped = newValue.clamp(1, 99);
          widget.onBeatsPerBarChanged?.call(clamped);
          break;
        case 1:
          // Denominator: 1-16
          final clamped = newValue.clamp(1, 16);
          widget.onBeatUnitChanged?.call(clamped);
          break;
      }
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
        final nextSegment = (_editingSegment + 1) % 2;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startEditing(nextSegment);
        });
      }
    }
  }

  /// Increment/decrement segment with scroll
  void _handleScroll(int segment, double delta) {
    final direction = delta > 0 ? -1 : 1; // Scroll up = increase

    switch (segment) {
      case 0:
        // Numerator: 1-99
        final newValue = (widget.beatsPerBar + direction).clamp(1, 99);
        widget.onBeatsPerBarChanged?.call(newValue);
        break;
      case 1:
        // Denominator: 1-16
        final newValue = (widget.beatUnit + direction).clamp(1, 16);
        widget.onBeatUnitChanged?.call(newValue);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSegment(0, widget.beatsPerBar.toString(), colors),
        _buildSlash(colors),
        _buildSegment(1, widget.beatUnit.toString(), colors),
      ],
    );
  }

  Widget _buildSegment(int segment, String value, BoojyColors colors) {
    final isEditing = _isEditing && _editingSegment == segment;

    if (isEditing) {
      return SizedBox(
        width: 20,
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
              LengthLimitingTextInputFormatter(2),
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

  Widget _buildSlash(BoojyColors colors) {
    return Text(
      '/',
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
  }
}
