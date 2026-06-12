import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../services/user_settings.dart';

/// Display mode for the position readout
enum PositionDisplayMode { bars, time, both }

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
  PositionDisplayMode _mode = PositionDisplayMode.bars;
  bool _isEditing = false;
  bool _isHovered = false;
  bool _isScrubbing = false;
  double _scrubBeats = 0;
  DateTime? _lastTapAt;
  PositionDisplayMode? _modeBeforeTap;
  late TextEditingController _editController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _mode = _modeFromString(UserSettings().positionDisplayMode);
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
      _mode = _nextMode(_mode);
    });
    // Persist globally so the chosen readout mode survives restarts.
    UserSettings().positionDisplayMode = _mode.name;
  }

  // Double-click is detected manually from single taps: a real onDoubleTap
  // recognizer holds the gesture arena for ~300 ms after every tap-up, which
  // made every mode-cycle tap land late (X1). The first tap of a double-click
  // cycles immediately; the second tap reverts that cycle and opens the edit.
  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last) < kDoubleTapTimeout) {
      _lastTapAt = null;
      final revert = _modeBeforeTap;
      if (revert != null && revert != _mode) {
        setState(() => _mode = revert);
        UserSettings().positionDisplayMode = _mode.name;
      }
      _startEdit();
    } else {
      _lastTapAt = now;
      _modeBeforeTap = _mode;
      _toggleMode();
    }
  }

  static PositionDisplayMode _nextMode(PositionDisplayMode m) {
    switch (m) {
      case PositionDisplayMode.bars:
        return PositionDisplayMode.time;
      case PositionDisplayMode.time:
        return PositionDisplayMode.both;
      case PositionDisplayMode.both:
        return PositionDisplayMode.bars;
    }
  }

  static PositionDisplayMode _modeFromString(String s) {
    switch (s) {
      case 'time':
        return PositionDisplayMode.time;
      case 'both':
        return PositionDisplayMode.both;
      default:
        return PositionDisplayMode.bars;
    }
  }

  void _startEdit() {
    setState(() {
      _isEditing = true;
      _editController.text = _mode == PositionDisplayMode.time
          ? ''
          : _formatBars()
                .split('.')
                .first; // bars & both: pre-fill the bar number
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

    if (_mode == PositionDisplayMode.time) {
      // Parse time as seconds
      final seconds = double.tryParse(text);
      if (seconds != null && seconds >= 0) {
        widget.onPositionChanged?.call(seconds);
      }
    } else {
      // bars & both: parse bar number and convert to seconds
      final bar = int.tryParse(text);
      if (bar != null && bar >= 1) {
        final beats = (bar - 1) * widget.beatsPerBar.toDouble();
        final seconds = beats * 60.0 / widget.tempo;
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

  /// The numeric readout content for the current mode. In "both" mode the
  /// bars line sits over a smaller, dimmer min:sec line (Logic-style dual).
  Widget _buildReadout() {
    final colors = context.colors;
    final base = BT.display(colors.textPrimary);
    final primaryStyle = widget.scale == 1.0
        ? base
        : base.copyWith(fontSize: (base.fontSize ?? 15.0) * widget.scale);
    switch (_mode) {
      case PositionDisplayMode.bars:
        return Text(
          _formatBars(),
          textAlign: TextAlign.center,
          style: primaryStyle,
        );
      case PositionDisplayMode.time:
        return Text(
          _formatTime(),
          textAlign: TextAlign.center,
          style: primaryStyle,
        );
      case PositionDisplayMode.both:
        final timeStyle = BT
            .display(colors.textSecondary)
            .copyWith(fontSize: BT.fontLabel * widget.scale);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatBars(),
              textAlign: TextAlign.center,
              style: primaryStyle,
            ),
            Text(_formatTime(), textAlign: TextAlign.center, style: timeStyle),
          ],
        );
    }
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
      message:
          'Drag to scrub · Click to cycle bars / time / both · Double-click to jump',
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
