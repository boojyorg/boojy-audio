import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../piano_roll/loop_time_display.dart';
import '../shared/mini_knob.dart';

/// Simplified horizontal controls bar for Audio Editor.
/// Matches Piano Roll styling with essential controls.
///
/// Layout format:
/// [Loop] Start [1.1.1] Length [4.0.0] | [Warp] [120 BPM] | Pitch [+0 st] | Vol [+0.0 dB]
class AudioEditorControlsBar extends StatelessWidget {
  // === Loop Toggle ===
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;

  // === Start/Length ===
  final double startOffsetBeats;
  final double lengthBeats;
  final int beatsPerBar; // Needed for LoopTimeDisplay formatting
  final Function(double)? onStartChanged;
  final Function(double)? onLengthChanged;

  // === Warp/Tempo ===
  final bool warpEnabled;
  final VoidCallback? onWarpToggle;
  final double originalBpm; // Clip's original tempo
  final Function(double)? onOriginalBpmChanged;
  final double projectBpm; // Project tempo (read-only display or editable)
  final Function(double)? onProjectBpmChanged;

  // === Pitch ===
  final int transposeSemitones;
  final Function(int)? onTransposeChanged;

  // === Volume ===
  final double gainDb;
  final Function(double)? onGainChanged;

  const AudioEditorControlsBar({
    super.key,
    this.loopEnabled = true,
    this.onLoopToggle,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.onStartChanged,
    this.onLengthChanged,
    this.warpEnabled = true,
    this.onWarpToggle,
    this.originalBpm = 120.0,
    this.onOriginalBpmChanged,
    this.projectBpm = 120.0,
    this.onProjectBpmChanged,
    this.transposeSemitones = 0,
    this.onTransposeChanged,
    this.gainDb = 0.0,
    this.onGainChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Row(
        children: [
          // === LOOP TOGGLE ===
          _buildLoopToggle(context),
          const SizedBox(width: 8),

          // === CLIP GROUP (Start + Length) ===
          _buildClipGroup(context),
          _buildSeparator(context),

          // === WARP GROUP (Warp toggle + Original BPM) ===
          _buildWarpGroup(context),
          _buildSeparator(context),

          // === PITCH ===
          _buildPitchControl(context),
          _buildSeparator(context),

          // === VOLUME ===
          _buildVolumeControl(context),

          // Spacer to push everything left
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: context.colors.surface,
    );
  }

  // ============ LOOP TOGGLE ============
  Widget _buildLoopToggle(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Loop (L)',
      child: GestureDetector(
        onTap: onLoopToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: loopEnabled ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.loop,
                  size: 13,
                  color: loopEnabled ? colors.elevated : colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Loop',
                  style: TextStyle(
                    fontSize: 10,
                    color: loopEnabled ? colors.elevated : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ CLIP GROUP (Start + Length) ============
  Widget _buildClipGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Start label + input
        Text('Start', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: startOffsetBeats,
            label: '',
            onChanged: onStartChanged,
            beatsPerBar: beatsPerBar,
            isPosition: true, // 1-indexed position (1.1.1 = start)
          ),
        ),
        const SizedBox(width: 8),

        // Length label + input
        Text('Length', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: lengthBeats,
            label: '',
            onChanged: onLengthChanged,
            beatsPerBar: beatsPerBar,
            isPosition: false, // 0-indexed length (1.0.0 = 1 bar)
          ),
        ),
      ],
    );
  }

  // ============ PITCH CONTROL ============
  Widget _buildPitchControl(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pitch', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        MiniKnob(
          value: transposeSemitones.toDouble(),
          min: -48.0,
          max: 48.0,
          size: 28,
          valueFormatter: (v) {
            final st = v.round();
            return st > 0 ? '+$st' : '$st';
          },
          onChanged: (value) => onTransposeChanged?.call(value.round()),
        ),
        const SizedBox(width: 2),
        Text('st', style: TextStyle(color: colors.textMuted, fontSize: 9)),
      ],
    );
  }

  // ============ VOLUME CONTROL ============
  Widget _buildVolumeControl(BuildContext context) {
    final colors = context.colors;

    // Volume curve: 0 dB at exactly 50%, more sensitivity near 0 dB
    // Piecewise: 0-30% = -70 to -12 dB, 30-50% = -12 to 0 dB, 50-100% = 0 to +24 dB
    double dbToSlider(double db) {
      if (db <= -70) return 0.0;
      if (db >= 24) return 1.0;
      if (db <= -12) {
        // -70 to -12 dB maps to 0.0 to 0.3 (58 dB over 30% = less sensitive)
        return (db + 70) / 193.33; // (70-12) / 0.3
      } else if (db <= 0) {
        // -12 to 0 dB maps to 0.3 to 0.5 (12 dB over 20% = more sensitive)
        return 0.3 + (db + 12) / 60; // 12 / 0.2
      } else {
        // 0 to +24 dB maps to 0.5 to 1.0
        return 0.5 + db / 48; // 24 dB over 0.5
      }
    }

    double sliderToDb(double slider) {
      if (slider <= 0.0) return -70.0;
      if (slider >= 1.0) return 24.0;
      if (slider <= 0.3) {
        // 0.0 to 0.3 maps to -70 to -12 dB
        return -70 + slider * 193.33;
      } else if (slider <= 0.5) {
        // 0.3 to 0.5 maps to -12 to 0 dB
        return -12 + (slider - 0.3) * 60;
      } else {
        // 0.5 to 1.0 maps to 0 to +24 dB
        return (slider - 0.5) * 48;
      }
    }

    final sliderValue = dbToSlider(gainDb);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // dB display box (matches track mixer style)
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Text(
            gainDb <= -70
                ? '-∞ dB'
                : '${gainDb.toStringAsFixed(1)} dB',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: colors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Capsule slider (matches track mixer style)
        SizedBox(
          width: 120,
          height: 20,
          child: _VolumeCapsuleSlider(
            value: sliderValue,
            onChanged: (value) {
              final db = sliderToDb(value);
              onGainChanged?.call(db);
            },
            onDoubleTap: () => onGainChanged?.call(0.0), // Reset to 0 dB
          ),
        ),
      ],
    );
  }

  // ============ WARP GROUP (Warp toggle + Original BPM) ============
  Widget _buildWarpGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warp toggle button
        Tooltip(
          message: 'Warp: sync clip to project tempo',
          child: GestureDetector(
            onTap: onWarpToggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: warpEnabled ? colors.accent : colors.dark,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sync,
                      size: 13,
                      color: warpEnabled ? colors.elevated : colors.textPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Warp',
                      style: TextStyle(
                        fontSize: 10,
                        color: warpEnabled ? colors.elevated : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Original BPM - draggable display like transport bar
        _OriginalBpmDisplay(
          bpm: originalBpm,
          onBpmChanged: onOriginalBpmChanged,
        ),
      ],
    );
  }

}

/// Draggable BPM display for clip's original tempo.
/// Similar to _TempoDisplay in transport_bar.dart.
class _OriginalBpmDisplay extends StatefulWidget {
  final double bpm;
  final Function(double)? onBpmChanged;

  const _OriginalBpmDisplay({
    required this.bpm,
    this.onBpmChanged,
  });

  @override
  State<_OriginalBpmDisplay> createState() => _OriginalBpmDisplayState();
}

class _OriginalBpmDisplayState extends State<_OriginalBpmDisplay> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartBpm = 120.0;

  /// Format BPM for display:
  /// - If whole number (110.0), show as "110 BPM"
  /// - If has decimal (110.5), show as "110.50 BPM"
  String _formatBpm(double bpm) {
    if (bpm == bpm.roundToDouble()) {
      return '${bpm.round()} BPM';
    } else {
      return '${bpm.toStringAsFixed(2)} BPM';
    }
  }

  void _showBpmDialog(BuildContext context) {
    // Show current value - if whole number, show without decimal
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

    return Tooltip(
      message: 'Original clip tempo (drag to adjust, double-click for precise input)',
      child: GestureDetector(
        onVerticalDragStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartY = details.globalPosition.dy;
            // Snap start position to whole BPM for cleaner dragging
            _dragStartBpm = widget.bpm.roundToDouble();
          });
        },
        onVerticalDragUpdate: (details) {
          if (widget.onBpmChanged != null) {
            // Drag up = increase BPM, drag down = decrease BPM
            final deltaY = _dragStartY - details.globalPosition.dy;
            // ~0.5 BPM per pixel, then round to whole BPM
            final deltaBpm = (deltaY * 0.5).roundToDouble();
            final newBpm = (_dragStartBpm + deltaBpm).clamp(20.0, 999.0);
            widget.onBpmChanged!(newBpm);
          }
        },
        onVerticalDragEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        onDoubleTap: () => _showBpmDialog(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: _isDragging
                  ? colors.accent.withValues(alpha: 0.2)
                  : colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: _isDragging
                  ? Border.all(color: colors.accent, width: 1.5)
                  : Border.all(color: colors.surface, width: 1.5),
            ),
            child: Text(
              bpmText,
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
}

/// Capsule-style volume slider matching track mixer fader appearance.
/// Has a pill-shaped track with a circular handle.
class _VolumeCapsuleSlider extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final Function(double)? onChanged;
  final VoidCallback? onDoubleTap;

  const _VolumeCapsuleSlider({
    required this.value,
    this.onChanged,
    this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTap: onDoubleTap,
          onHorizontalDragUpdate: (details) {
            if (onChanged == null) return;
            final sliderValue =
                (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onChanged!(sliderValue);
          },
          onTapDown: (details) {
            if (onChanged == null) return;
            final sliderValue =
                (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onChanged!(sliderValue);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _VolumeCapsulePainter(sliderValue: value),
            ),
          ),
        );
      },
    );
  }
}

class _VolumeCapsulePainter extends CustomPainter {
  final double sliderValue; // 0.0 to 1.0

  _VolumeCapsulePainter({required this.sliderValue});

  @override
  void paint(Canvas canvas, Size size) {
    final capsuleRadius = size.height / 2;
    final capsuleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(capsuleRadius),
    );

    // Draw capsule background
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(capsuleRect, bgPaint);

    // Draw capsule border
    final borderPaint = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(capsuleRect, borderPaint);

    // Draw volume handle/thumb
    final handleRadius = size.height / 2 - 1;
    final usableWidth = size.width - handleRadius * 2;
    final handleX = handleRadius + sliderValue * usableWidth;
    final handleY = size.height / 2;

    // Draw semi-transparent grey circle (Logic Pro style)
    final handlePaint = Paint()
      ..color = const Color(0xFF808080).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(handleX, handleY), handleRadius, handlePaint);

    // Draw subtle border on handle
    final handleBorderPaint = Paint()
      ..color = const Color(0xFFAAAAAA).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(handleX, handleY), handleRadius, handleBorderPaint);
  }

  @override
  bool shouldRepaint(_VolumeCapsulePainter oldDelegate) {
    return oldDelegate.sliderValue != sliderValue;
  }
}
