import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';

/// A draggable pitch display showing semitones and cents in format: [+0 st. 0 ct]
/// Each segment (semitones, cents) is individually draggable and editable.
///
/// Features:
/// - Drag up/down to increment/decrement (3px per unit)
/// - Scroll wheel support
/// - Double-click to type exact value
/// - Cents overflow to semitones (e.g., +51 ct → +1 st, +1 ct)
class DraggablePitchDisplay extends StatefulWidget {
  /// Transpose in semitones (-48 to +48)
  final int semitones;

  /// Fine pitch in cents (-50 to +50)
  final int cents;

  /// Called when semitones change
  final Function(int)? onSemitonesChanged;

  /// Called when cents change
  final Function(int)? onCentsChanged;

  const DraggablePitchDisplay({
    super.key,
    required this.semitones,
    required this.cents,
    this.onSemitonesChanged,
    this.onCentsChanged,
  });

  @override
  State<DraggablePitchDisplay> createState() => _DraggablePitchDisplayState();
}

class _DraggablePitchDisplayState extends State<DraggablePitchDisplay> {
  bool _isEditing = false;
  int _editingSegment = -1; // 0=semitones, 1=cents
  bool _isFirstKeystroke = true;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;

  // Drag accumulators
  double _semitonesDragAccumulator = 0.0;
  double _centsDragAccumulator = 0.0;

  static const int minSemitones = -48;
  static const int maxSemitones = 48;
  static const int minCents = -50;
  static const int maxCents = 50;

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
        initialValue = widget.semitones.toString();
        break;
      case 1:
        initialValue = widget.cents.toString();
        break;
      default:
        return;
    }

    setState(() {
      _isEditing = true;
      _editingSegment = segment;
      _isFirstKeystroke = true;
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

    final text = _editController.text;
    if (text.isNotEmpty) {
      final newValue = int.tryParse(text);
      if (newValue != null) {
        _applyValue(newValue);
      }
    }

    setState(() {
      _isEditing = false;
      _editingSegment = -1;
      _isFirstKeystroke = true;
    });
  }

  void _applyValue(int newValue) {
    switch (_editingSegment) {
      case 0: // Semitones
        final clamped = newValue.clamp(minSemitones, maxSemitones);
        widget.onSemitonesChanged?.call(clamped);
        break;
      case 1: // Cents
        _applyPitchWithOverflow(widget.semitones, newValue);
        break;
    }
  }

  /// Apply pitch change with overflow from cents to semitones
  void _applyPitchWithOverflow(int semitones, int cents) {
    // Calculate overflow
    int newSemitones = semitones;
    int newCents = cents;

    // Overflow cents to semitones
    while (newCents > maxCents) {
      newCents -= 100;
      newSemitones += 1;
    }
    while (newCents < minCents) {
      newCents += 100;
      newSemitones -= 1;
    }

    // Clamp semitones
    newSemitones = newSemitones.clamp(minSemitones, maxSemitones);

    // If we hit semitone limits, clamp cents too
    if (newSemitones == maxSemitones && newCents > 0) {
      newCents = 0;
    }
    if (newSemitones == minSemitones && newCents < 0) {
      newCents = 0;
    }

    if (newSemitones != semitones) {
      widget.onSemitonesChanged?.call(newSemitones);
    }
    if (newCents != widget.cents) {
      widget.onCentsChanged?.call(newCents);
    }
  }

  void _handleScroll(int segment, double delta) {
    final direction = delta > 0 ? -1 : 1; // Scroll up = increase

    switch (segment) {
      case 0: // Semitones
        final newValue = (widget.semitones + direction).clamp(minSemitones, maxSemitones);
        widget.onSemitonesChanged?.call(newValue);
        break;
      case 1: // Cents
        _applyPitchWithOverflow(widget.semitones, widget.cents + direction);
        break;
    }
  }

  void _handleDrag(int segment, double deltaY) {
    const pixelsPerIncrement = 3.0;

    if (segment == 0) {
      _semitonesDragAccumulator += deltaY;
      if (_semitonesDragAccumulator.abs() >= pixelsPerIncrement) {
        final increments = (_semitonesDragAccumulator / pixelsPerIncrement).truncate();
        _semitonesDragAccumulator -= increments * pixelsPerIncrement;
        final direction = -increments; // Drag up = increase
        final newValue = (widget.semitones + direction).clamp(minSemitones, maxSemitones);
        widget.onSemitonesChanged?.call(newValue);
      }
    } else {
      _centsDragAccumulator += deltaY;
      if (_centsDragAccumulator.abs() >= pixelsPerIncrement) {
        final increments = (_centsDragAccumulator / pixelsPerIncrement).truncate();
        _centsDragAccumulator -= increments * pixelsPerIncrement;
        final direction = -increments; // Drag up = increase
        _applyPitchWithOverflow(widget.semitones, widget.cents + direction);
      }
    }
  }

  String _formatSemitones(int value) {
    return value.toString();
  }

  String _formatCents(int value) {
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSegment(0, _formatSemitones(widget.semitones), 'st', colors),
        Text(
          '. ',
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        _buildSegment(1, _formatCents(widget.cents), 'ct', colors),
      ],
    );
  }

  Widget _buildSegment(int segment, String value, String suffix, BoojyColors colors) {
    final isEditing = _isEditing && _editingSegment == segment;

    if (isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 18,
            child: TextField(
              controller: _editController,
              focusNode: _editFocusNode,
              autofocus: true,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                LengthLimitingTextInputFormatter(4), // e.g., "-48"
                _FirstKeystrokeReplacer(this),
              ],
              onSubmitted: (_) => _commitEdit(),
            ),
          ),
          Text(
            ' $suffix',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(segment, event.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        onDoubleTap: () => _startEditing(segment),
        onVerticalDragUpdate: (details) {
          _handleDrag(segment, details.delta.dy);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  ' $suffix',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Input formatter that replaces text on first keystroke, then appends
class _FirstKeystrokeReplacer extends TextInputFormatter {
  final _DraggablePitchDisplayState state;

  _FirstKeystrokeReplacer(this.state);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (state._isFirstKeystroke && newValue.text != oldValue.text) {
      state._isFirstKeystroke = false;
    }
    return newValue;
  }
}
