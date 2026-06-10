import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// A time signature display showing numerator/denominator format.
/// The numerator is clickable/scrollable to edit; the denominator is
/// read-only — the engine has no beat-unit concept yet, so an editable
/// denominator was a control that did nothing (locked to /4 for v0.6).
/// Format: [4] / 4
class TimeSignatureDisplay extends StatefulWidget {
  /// Beats per bar (numerator, e.g., 4 in 4/4)
  final int beatsPerBar;

  /// Beat unit (denominator, e.g., 4 in 4/4) — display only
  final int beatUnit;

  /// Called when beats per bar changes
  final Function(int)? onBeatsPerBarChanged;

  const TimeSignatureDisplay({
    super.key,
    required this.beatsPerBar,
    required this.beatUnit,
    this.onBeatsPerBarChanged,
  });

  @override
  State<TimeSignatureDisplay> createState() => _TimeSignatureDisplayState();
}

class _TimeSignatureDisplayState extends State<TimeSignatureDisplay> {
  bool _isEditing = false;
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

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = widget.beatsPerBar.toString();
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
      // Numerator: 1-99
      final clamped = newValue.clamp(1, 99);
      widget.onBeatsPerBarChanged?.call(clamped);
    }

    setState(() {
      _isEditing = false;
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
        });
      }
    }
  }

  /// Increment/decrement the numerator with scroll
  void _handleScroll(double delta) {
    final direction = delta > 0 ? -1 : 1; // Scroll up = increase
    // Numerator: 1-99
    final newValue = (widget.beatsPerBar + direction).clamp(1, 99);
    widget.onBeatsPerBarChanged?.call(newValue);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNumerator(widget.beatsPerBar.toString(), colors),
        _buildSlash(colors),
        // Denominator: read-only (locked to /4 — see widget doc comment)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            widget.beatUnit.toString(),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 10,
              fontFamily: BT.fontFamilyMono,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumerator(String value, BoojyColors colors) {
    if (_isEditing) {
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
              fontFamily: BT.fontFamilyMono,
              fontFeatures: const [FontFeature.tabularFigures()],
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
          _handleScroll(event.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        onTap: _startEditing,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 10,
                fontFamily: BT.fontFamilyMono,
                fontFeatures: const [FontFeature.tabularFigures()],
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
        fontFamily: BT.fontFamilyMono,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
