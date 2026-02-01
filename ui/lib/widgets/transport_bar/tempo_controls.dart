import 'package:flutter/material.dart';
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
          totalInterval += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
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
    final isRecentTap = _tapTimes.isNotEmpty &&
        DateTime.now().difference(_tapTimes.last).inMilliseconds < 500;
    final bgColor = isRecentTap
        ? context.colors.accent.withValues(alpha: 0.3)
        : (_isHovered ? context.colors.elevated : context.colors.dark);
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 13, color: textColor),
                  if (widget.mode == ButtonDisplayMode.wide) ...[
                    const SizedBox(width: 3),
                    Text(
                      'Tap',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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

  const TempoDisplay({
    super.key,
    required this.tempo,
    this.onTempoChanged,
  });

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
          decoration: const InputDecoration(
            labelText: 'BPM (20 - 300)',
          ),
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

  @override
  Widget build(BuildContext context) {
    final tempoText = _formatTempo(widget.tempo);

    return Tooltip(
      message: 'Tempo (drag to adjust, double-click for precise input)',
      child: GestureDetector(
        onVerticalDragStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartY = details.globalPosition.dy;
            // Snap start position to whole BPM for cleaner dragging
            _dragStartTempo = widget.tempo.roundToDouble();
          });
        },
        onVerticalDragUpdate: (details) {
          if (widget.onTempoChanged != null) {
            // Drag up = increase tempo, drag down = decrease tempo
            final deltaY = _dragStartY - details.globalPosition.dy;
            // ~0.5 BPM per pixel, then round to whole BPM
            final deltaTempo = (deltaY * 0.5).roundToDouble();
            final newTempo = (_dragStartTempo + deltaTempo).clamp(20.0, 300.0);
            widget.onTempoChanged!(newTempo);
          }
        },
        onVerticalDragEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        onDoubleTap: () => _showTempoDialog(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: _isDragging
                  ? context.colors.accent.withValues(alpha: 0.2)
                  : context.colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: _isDragging
                  ? Border.all(color: context.colors.accent, width: 1.5)
                  : Border.all(color: context.colors.surface, width: 1.5),
            ),
            child: Text(
              tempoText,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
