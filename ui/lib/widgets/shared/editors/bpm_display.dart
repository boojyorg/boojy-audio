import 'package:flutter/material.dart';
import '../../../theme/theme_extension.dart';

/// BPM display widget with drag-to-adjust and double-click for precise input.
/// Reusable across Audio Editor and Sampler Editor.
class BpmDisplay extends StatefulWidget {
  final double bpm;
  final Function(double)? onBpmChanged;
  final bool enabled;

  const BpmDisplay({
    super.key,
    required this.bpm,
    this.onBpmChanged,
    this.enabled = true,
  });

  @override
  State<BpmDisplay> createState() => _BpmDisplayState();
}

class _BpmDisplayState extends State<BpmDisplay> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartBpm = 120.0;

  String _formatBpm(double bpm) {
    if (bpm == bpm.roundToDouble()) {
      return '${bpm.round()} BPM';
    } else {
      return '${bpm.toStringAsFixed(2)} BPM';
    }
  }

  void _showBpmDialog(BuildContext context) {
    final initialText = widget.bpm == widget.bpm.roundToDouble()
        ? widget.bpm.round().toString()
        : widget.bpm.toStringAsFixed(2);
    final controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Original BPM'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Clip's original tempo (20 - 999)",
          ),
          autofocus: true,
          onSubmitted: (_) {
            final value = double.tryParse(controller.text) ?? 120.0;
            widget.onBpmChanged?.call(value.clamp(20, 999));
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
              widget.onBpmChanged?.call(value.clamp(20, 999));
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
    final colors = context.colors;
    final bpmText = _formatBpm(widget.bpm);
    final isEnabled = widget.enabled;

    return Tooltip(
      message: isEnabled
          ? 'Original clip tempo (drag to adjust, double-click for precise input)'
          : 'Enable Warp to adjust BPM',
      child: GestureDetector(
        onVerticalDragStart: isEnabled
            ? (details) {
                setState(() {
                  _isDragging = true;
                  _dragStartY = details.globalPosition.dy;
                  _dragStartBpm = widget.bpm.roundToDouble();
                });
              }
            : null,
        onVerticalDragUpdate: isEnabled
            ? (details) {
                if (widget.onBpmChanged != null) {
                  final deltaY = _dragStartY - details.globalPosition.dy;
                  final deltaBpm = (deltaY * 0.5).roundToDouble();
                  final newBpm = (_dragStartBpm + deltaBpm).clamp(20.0, 999.0);
                  widget.onBpmChanged!(newBpm);
                }
              }
            : null,
        onVerticalDragEnd: isEnabled
            ? (details) {
                setState(() {
                  _isDragging = false;
                });
              }
            : null,
        onDoubleTap: isEnabled ? () => _showBpmDialog(context) : null,
        child: MouseRegion(
          cursor: isEnabled ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.forbidden,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: _isDragging
                  ? colors.accent.withValues(alpha: 0.2)
                  : colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: _isDragging
                  ? Border.all(color: colors.accent, width: 1.5)
                  : Border.all(
                      color: isEnabled ? colors.surface : colors.surface.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
            ),
            child: Text(
              bpmText,
              style: TextStyle(
                color: isEnabled ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.5),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
