import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';

/// Display mode for the position readout
enum PositionDisplayMode { bars, time }

/// Position display with click-to-toggle between bars and time,
/// and double-click to jump to a specific position.
///
/// Mode 1 (bars): bar.beat.subdivision (1.1.1)
/// Mode 2 (time): min:sec.ms (0:00.000)
class PositionDisplay extends StatefulWidget {
  final double playheadPosition; // seconds
  final double tempo;
  final int beatsPerBar;
  final Function(double seconds)? onPositionChanged;

  const PositionDisplay({
    super.key,
    required this.playheadPosition,
    required this.tempo,
    this.beatsPerBar = 4,
    this.onPositionChanged,
  });

  @override
  State<PositionDisplay> createState() => _PositionDisplayState();
}

class _PositionDisplayState extends State<PositionDisplay> {
  PositionDisplayMode _mode = PositionDisplayMode.bars;
  bool _isEditing = false;
  bool _isHovered = false;
  late TextEditingController _editController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _cancelEdit();
      }
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatBars() {
    final beatsPerSecond = widget.tempo / 60.0;
    final totalBeats = widget.playheadPosition * beatsPerSecond;
    const subdivisionsPerBeat = 4;

    final bar = (totalBeats / widget.beatsPerBar).floor() + 1;
    final beat = (totalBeats % widget.beatsPerBar).floor() + 1;
    final subdivision = ((totalBeats % 1) * subdivisionsPerBeat).floor() + 1;

    return '$bar.$beat.$subdivision';
  }

  String _formatTime() {
    final totalSeconds = widget.playheadPosition;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).floor();
    final millis = ((totalSeconds % 1) * 1000).floor();

    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
  }

  void _toggleMode() {
    if (_isEditing) return;
    setState(() {
      _mode = _mode == PositionDisplayMode.bars
          ? PositionDisplayMode.time
          : PositionDisplayMode.bars;
    });
  }

  void _startEdit() {
    setState(() {
      _isEditing = true;
      _editController.text = _mode == PositionDisplayMode.bars
          ? _formatBars()
                .split('.')
                .first // Pre-fill with bar number
          : '';
    });
    // Focus after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _confirmEdit() {
    final text = _editController.text.trim();
    if (text.isEmpty) {
      _cancelEdit();
      return;
    }

    if (_mode == PositionDisplayMode.bars) {
      // Parse bar number and convert to seconds
      final bar = int.tryParse(text);
      if (bar != null && bar >= 1) {
        final beats = (bar - 1) * widget.beatsPerBar.toDouble();
        final seconds = beats * 60.0 / widget.tempo;
        widget.onPositionChanged?.call(seconds);
      }
    } else {
      // Parse time as seconds
      final seconds = double.tryParse(text);
      if (seconds != null && seconds >= 0) {
        widget.onPositionChanged?.call(seconds);
      }
    }

    _cancelEdit();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayText = _mode == PositionDisplayMode.bars
        ? _formatBars()
        : _formatTime();

    if (_isEditing) {
      return Container(
        width: 80,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colors.darkest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.accent, width: 1),
        ),
        child: TextField(
          controller: _editController,
          focusNode: _focusNode,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
          ],
          onSubmitted: (_) => _confirmEdit(),
        ),
      );
    }

    return Tooltip(
      message: 'Click to switch bars/time · Double-click to jump',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: _toggleMode,
          onDoubleTap: _startEdit,
          child: Container(
            constraints: const BoxConstraints(minWidth: 80),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.darkest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isHovered ? colors.accent : colors.divider,
                width: 1,
              ),
            ),
            child: Text(
              displayText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
