import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_extension.dart';
import '../shared/pill_toggle_button.dart' show ButtonDisplayMode;

/// Tap tempo pill button with tap-to-set-tempo functionality
class TapTempoPill extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;
  final ButtonDisplayMode mode;

  const TapTempoPill({
    super.key,
    required this.tempo,
    this.onTempoChanged,
    required this.mode,
  });

  @override
  State<TapTempoPill> createState() => _TapTempoPillState();
}

class _TapTempoPillState extends State<TapTempoPill> {
  bool _isHovered = false;
  bool _isPressed = false;
  final List<DateTime> _tapTimes = [];

  void _onTapTempo() {
    final now = DateTime.now();
    setState(() {
      // Remove taps older than 3 seconds
      _tapTimes.removeWhere((time) => now.difference(time).inSeconds > 3);

      // Add current tap
      _tapTimes.add(now);

      // Need at least 2 taps to calculate tempo
      if (_tapTimes.length >= 2) {
        // Calculate average interval between taps
        double totalInterval = 0.0;
        for (int i = 1; i < _tapTimes.length; i++) {
          totalInterval += _tapTimes[i]
              .difference(_tapTimes[i - 1])
              .inMilliseconds;
        }
        final avgInterval = totalInterval / (_tapTimes.length - 1);

        // Convert interval to BPM (60000ms = 1 minute)
        final bpm = (60000.0 / avgInterval).clamp(20.0, 300.0).roundToDouble();
        widget.onTempoChanged?.call(bpm);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0);
    final isRecentTap =
        _tapTimes.isNotEmpty &&
        DateTime.now().difference(_tapTimes.last).inMilliseconds < 500;
    final bgColor = isRecentTap
        ? context.colors.accent.withValues(alpha: 0.3)
        : context.colors.surface;
    final textColor = context.colors.textSecondary;

    return Tooltip(
      message: 'Tap Tempo',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            _onTapTempo();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: context.colors.divider, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tempo display with drag-to-adjust functionality - shows [120 BPM] format
/// Dragging snaps to whole BPM values; double-tap opens dialog for decimal input.
class TempoDisplay extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;

  const TempoDisplay({super.key, required this.tempo, this.onTempoChanged});

  @override
  State<TempoDisplay> createState() => _TempoDisplayState();
}

class _TempoDisplayState extends State<TempoDisplay> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartTempo = 120.0;

  /// Format tempo for display:
  /// - If whole number (120.0), show as "120 BPM"
  /// - If has decimal (120.5), show as "120.50 BPM"
  String _formatTempo(double tempo) {
    if (tempo == tempo.roundToDouble()) {
      return '${tempo.round()} BPM';
    } else {
      return '${tempo.toStringAsFixed(2)} BPM';
    }
  }

  void _showTempoDialog(BuildContext context) {
    // Show current value - if whole number, show without decimal
    final initialText = widget.tempo == widget.tempo.roundToDouble()
        ? widget.tempo.round().toString()
        : widget.tempo.toStringAsFixed(2);
    final controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Project Tempo'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'BPM (20 - 300)'),
          autofocus: true,
          onSubmitted: (_) {
            final value = double.tryParse(controller.text) ?? 120.0;
            widget.onTempoChanged?.call(value.clamp(20, 300));
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 120.0;
              widget.onTempoChanged?.call(value.clamp(20, 300));
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onScroll(PointerScrollEvent event) {
    if (widget.onTempoChanged == null) return;
    // Scroll up = increase, scroll down = decrease
    final direction = event.scrollDelta.dy < 0 ? 1.0 : -1.0;
    // Shift held = fine mode (0.1 BPM), normal = 1 BPM
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final delta = isShift ? 0.1 : 1.0;
    final newTempo = (widget.tempo + direction * delta).clamp(20.0, 999.0);
    widget.onTempoChanged!(newTempo);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tempoText = _formatTempo(widget.tempo);

    return Tooltip(
      message: 'Click to edit tempo · Scroll to adjust',
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) _onScroll(event);
        },
        child: GestureDetector(
          onVerticalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _dragStartY = details.globalPosition.dy;
              _dragStartTempo = widget.tempo.roundToDouble();
            });
          },
          onVerticalDragUpdate: (details) {
            if (widget.onTempoChanged != null) {
              final deltaY = _dragStartY - details.globalPosition.dy;
              final deltaTempo = (deltaY * 0.5).roundToDouble();
              final newTempo = (_dragStartTempo + deltaTempo).clamp(
                20.0,
                999.0,
              );
              widget.onTempoChanged!(newTempo);
            }
          },
          onVerticalDragEnd: (details) {
            setState(() => _isDragging = false);
          },
          onDoubleTap: () => _showTempoDialog(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: Container(
              constraints: const BoxConstraints(minWidth: 90),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isDragging
                    ? colors.accent.withValues(alpha: 0.2)
                    : colors.darkest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _isDragging ? colors.accent : colors.divider,
                  width: 1,
                ),
              ),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: tempoText.replaceAll(' BPM', ''),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    TextSpan(
                      text: ' BPM',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
