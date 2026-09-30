import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Position readout (bar.beat.subdivision, e.g. 1.1.1). Drag to scrub,
/// double-click to jump to a bar.
class PositionDisplay extends StatefulWidget {
  final double playheadPosition; // seconds
  final double tempo;
  final int beatsPerBar;
  final Function(double seconds)? onPositionChanged;

  /// Font/size multiplier for the readout. 1.0 = the standard transport size;
  /// the top-bar "hero" variants pass >1 to promote the position to the focal
  /// readout.
  final double scale;

  /// When true the widget drops its own bordered LCD shell (background, border,
  /// padding, min-width) and renders just the readout + gestures — used when an
  /// outer panel (Variant B) already supplies the chrome.
  final bool chromeless;

  const PositionDisplay({
    super.key,
    required this.playheadPosition,
    required this.tempo,
    this.beatsPerBar = 4,
    this.onPositionChanged,
    this.scale = 1.0,
    this.chromeless = false,
  });

  @override
  State<PositionDisplay> createState() => _PositionDisplayState();
}

class _PositionDisplayState extends State<PositionDisplay> {
  bool _isEditing = false;
  bool _isHovered = false;
  bool _isScrubbing = false;
  double _scrubBeats = 0;
  DateTime? _lastTapAt;
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

  // Double-click is detected manually from single taps: a real onDoubleTap
  // recognizer holds the gesture arena for ~300 ms after every tap-up.
  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTapAt = null;
      _startEdit();
    } else {
      _lastTapAt = now;
    }
  }

  void _startEdit() {
    setState(() {
      _isEditing = true;
      _editController.text = _formatBars()
          .split('.')
          .first; // pre-fill the bar number
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

    // Parse bar number and convert to seconds
    final bar = int.tryParse(text);
    if (bar != null && bar >= 1) {
      final beats = (bar - 1) * widget.beatsPerBar.toDouble();
      final seconds = beats * 60.0 / widget.tempo;
      widget.onPositionChanged?.call(seconds);
    }

    _cancelEdit();
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
    });
  }

  Widget _buildReadout() {
    final colors = context.colors;
    final base = BT.display(colors.textPrimary);
    final primaryStyle = widget.scale == 1.0
        ? base
        : base.copyWith(fontSize: (base.fontSize ?? 15.0) * widget.scale);
    return Text(
      _formatBars(),
      textAlign: TextAlign.center,
      style: primaryStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_isEditing) {
      return Container(
        width: 80,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colors.darkest,
          borderRadius: BT.borderMd,
          border: Border.all(color: colors.accent, width: 1),
        ),
        child: TextField(
          controller: _editController,
          focusNode: _focusNode,
          style: BT.display(colors.textPrimary),
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
      message: 'Drag to scrub · Double-click to jump',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        onEnter: (_) {
          if (!_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = true);
            });
          }
        },
        onExit: (_) {
          if (_isHovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isHovered = false);
            });
          }
        },
        child: GestureDetector(
          onTap: _handleTap,
          // Horizontal drag scrubs the playhead (same seek path as the ruler).
          onHorizontalDragStart: (_) => setState(() {
            _isScrubbing = true;
            _scrubBeats = widget.playheadPosition * widget.tempo / 60.0;
          }),
          onHorizontalDragUpdate: (details) {
            final fine = HardwareKeyboard.instance.isShiftPressed;
            final pxPerBeat = fine ? 48.0 : 12.0;
            _scrubBeats = (_scrubBeats + details.delta.dx / pxPerBeat).clamp(
              0.0,
              1e9,
            );
            widget.onPositionChanged?.call(_scrubBeats * 60.0 / widget.tempo);
          },
          onHorizontalDragEnd: (_) => setState(() => _isScrubbing = false),
          child: Container(
            constraints: BoxConstraints(
              minWidth: widget.chromeless ? 0 : 64 * widget.scale,
            ),
            padding: widget.chromeless
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: widget.chromeless
                ? null
                : BoxDecoration(
                    color: colors.darkest,
                    borderRadius: BT.borderMd,
                    border: Border.all(
                      color: (_isHovered || _isScrubbing)
                          ? colors.accent
                          : colors.divider,
                      width: 1,
                    ),
                  ),
            child: _buildReadout(),
          ),
        ),
      ),
    );
  }
}
