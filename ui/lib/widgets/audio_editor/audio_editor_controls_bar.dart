import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../piano_roll/loop_time_display.dart';
import '../shared/editors/bpm_display.dart';
import '../shared/editors/capsule_slider.dart';
import 'draggable_pitch_display.dart';

/// Simplified horizontal controls bar for Audio Editor.
/// Matches Piano Roll styling with essential controls.
///
/// Layout format:
/// [Loop] Start [1.1.1] Length [4.0.0] | [↻ Warp ▼] [120 BPM] | Pitch [+0 st] | Vol [+0.0 dB]
class AudioEditorControlsBar extends StatefulWidget {
  // === Loop Toggle ===
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;

  // === Start/Length ===
  final double startOffsetBeats;
  final double lengthBeats;
  final int beatsPerBar; // Needed for LoopTimeDisplay formatting
  final Function(double)? onStartChanged;
  final Function(double)? onLengthChanged;

  /// A drag on the Start or Length box starts and ends (one undo step).
  final VoidCallback? onStartDragStart;
  final VoidCallback? onStartDragEnd;
  final VoidCallback? onLengthDragStart;
  final VoidCallback? onLengthDragEnd;

  // === Warp/Tempo ===
  final bool warpEnabled;
  final VoidCallback? onWarpToggle;
  final double originalBpm; // Clip's original tempo
  final Function(double)? onOriginalBpmChanged;
  final VoidCallback? onOriginalBpmDragStart;
  final VoidCallback? onOriginalBpmDragEnd;
  final double projectBpm; // Project tempo (read-only display or editable)
  final Function(double)? onProjectBpmChanged;

  // === Pitch ===
  final int transposeSemitones;
  final VoidCallback? onPitchDragStart;
  final VoidCallback? onPitchDragEnd;
  final Function(int)? onTransposeChanged;
  final int fineCents;
  final Function(int)? onFineCentsChanged;

  // === Reverse ===
  final bool reversed;
  final VoidCallback? onReverseToggle;

  // === Volume ===
  final double gainDb;
  final Function(double)? onGainChanged;

  /// A press or drag on the volume slider starts and ends (one undo step).
  final VoidCallback? onGainDragStart;
  final VoidCallback? onGainDragEnd;

  // === Create Sampler ===
  final VoidCallback? onCreateSamplerFromClip;

  const AudioEditorControlsBar({
    super.key,
    this.loopEnabled = true,
    this.onLoopToggle,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.onStartChanged,
    this.onLengthChanged,
    this.onStartDragStart,
    this.onStartDragEnd,
    this.onLengthDragStart,
    this.onLengthDragEnd,
    this.warpEnabled = true,
    this.onWarpToggle,
    this.originalBpm = 120.0,
    this.onOriginalBpmChanged,
    this.onOriginalBpmDragStart,
    this.onOriginalBpmDragEnd,
    this.projectBpm = 120.0,
    this.onProjectBpmChanged,
    this.transposeSemitones = 0,
    this.onPitchDragStart,
    this.onPitchDragEnd,
    this.onTransposeChanged,
    this.fineCents = 0,
    this.onFineCentsChanged,
    this.reversed = false,
    this.onReverseToggle,
    this.gainDb = 0.0,
    this.onGainChanged,
    this.onGainDragStart,
    this.onGainDragEnd,
    this.onCreateSamplerFromClip,
  });

  @override
  State<AudioEditorControlsBar> createState() => _AudioEditorControlsBarState();
}

class _AudioEditorControlsBarState extends State<AudioEditorControlsBar> {
  // Hover states for warp split button
  bool _isHoveringWarpLabel = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(bottom: BorderSide(color: colors.surface, width: 1)),
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

          // Spacer to push everything left, Sampler button at right
          const Spacer(),

          // === CREATE SAMPLER ===
          if (widget.onCreateSamplerFromClip != null)
            _buildSamplerButton(context),
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
        onTap: widget.onLoopToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: widget.loopEnabled ? colors.selectionFill : colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: widget.loopEnabled
                    ? colors.selectionBorder
                    : colors.surface,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  BI.loop,
                  size: 13,
                  color: widget.loopEnabled
                      ? colors.accent
                      : colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Loop',
                  style: TextStyle(fontSize: 10, color: colors.textPrimary),
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
        Text(
          'Start',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: widget.startOffsetBeats,
            label: '',
            onChanged: widget.onStartChanged,
            onDragStart: widget.onStartDragStart,
            onDragEnd: widget.onStartDragEnd,
            beatsPerBar: widget.beatsPerBar,
            isPosition: true, // 1-indexed position (1.1.1 = start)
          ),
        ),
        const SizedBox(width: 8),

        // Length label + input
        Text(
          'Length',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: LoopTimeDisplay(
            beats: widget.lengthBeats,
            label: '',
            onChanged: widget.onLengthChanged,
            onDragStart: widget.onLengthDragStart,
            onDragEnd: widget.onLengthDragEnd,
            beatsPerBar: widget.beatsPerBar,
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
        Text(
          'Pitch',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: DraggablePitchDisplay(
            semitones: widget.transposeSemitones,
            cents: widget.fineCents,
            onSemitonesChanged: widget.onTransposeChanged,
            onCentsChanged: widget.onFineCentsChanged,
            onDragStart: widget.onPitchDragStart,
            onDragEnd: widget.onPitchDragEnd,
          ),
        ),
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

    final sliderValue = dbToSlider(widget.gainDb);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Volume label
        Text(
          'Volume',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
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
            widget.gainDb <= -70
                ? '-∞ dB'
                : '${widget.gainDb.toStringAsFixed(1)} dB',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: BT.fontCaption,
              color: colors.textPrimary,
              fontFamily: BT.fontFamilyMono,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Capsule slider (matches track mixer style)
        SizedBox(
          width: 120,
          height: 20,
          child: CapsuleSlider(
            value: sliderValue,
            onChanged: (value) {
              final db = sliderToDb(value);
              widget.onGainChanged?.call(db);
            },
            onChangeStart: widget.onGainDragStart,
            onChangeEnd: widget.onGainDragEnd,
            onDoubleTap: () {
              widget.onGainChanged?.call(0.0); // Reset to 0 dB
              widget.onGainDragEnd?.call(); // a double-click has no tap-up
            },
          ),
        ),
      ],
    );
  }

  // ============ WARP GROUP (Warp label + split button + BPM + tempo buttons + Reverse) ============
  Widget _buildWarpGroup(BuildContext context) {
    final colors = context.colors;
    final isEnabled = widget.warpEnabled;
    final bgColor = isEnabled ? colors.selectionFill : colors.dark;
    final iconColor = isEnabled ? colors.accent : colors.textPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warp label
        Text(
          'Warp',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        // Toggle button: [icon + Stretch] (warp on/off)
        DecoratedBox(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isEnabled ? colors.selectionBorder : colors.surface,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                onEnter: (_) {
                  if (!_isHoveringWarpLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isHoveringWarpLabel = true);
                    });
                  }
                },
                onExit: (_) {
                  if (_isHoveringWarpLabel) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _isHoveringWarpLabel = false);
                      }
                    });
                  }
                },
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onWarpToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHoveringWarpLabel
                          ? (isEnabled
                                ? colors.selectionFillHover
                                : colors.textPrimary.withValues(alpha: 0.1))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(BI.sync, size: 13, color: iconColor),
                        const SizedBox(width: 4),
                        Text(
                          'Stretch',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Original BPM - draggable display like transport bar
        // Disabled (greyed out) when Warp is OFF
        BpmDisplay(
          bpm: widget.originalBpm,
          onBpmChanged: isEnabled ? widget.onOriginalBpmChanged : null,
          onDragStart: widget.onOriginalBpmDragStart,
          onDragEnd: widget.onOriginalBpmDragEnd,
          enabled: isEnabled,
        ),
        const SizedBox(width: 4),
        // ÷2 button - halves BPM (same style as Reverse toggle)
        _buildActionButton(context, '÷2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call(
            (widget.originalBpm / 2).clamp(20, 999),
          );
        }),
        const SizedBox(width: 2),
        // ×2 button - doubles BPM (same style as Reverse toggle)
        _buildActionButton(context, '×2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call(
            (widget.originalBpm * 2).clamp(20, 999),
          );
        }),
        const SizedBox(width: 4),
        // Reverse toggle
        _buildActionButton(
          context,
          'Reverse',
          widget.reversed,
          true,
          widget.onReverseToggle,
        ),
      ],
    );
  }

  // ============ ACTION BUTTON (÷2 / ×2 / Reverse - unified style) ============
  Widget _buildActionButton(
    BuildContext context,
    String label,
    bool isActive,
    bool enabled,
    VoidCallback? onTap,
  ) {
    final colors = context.colors;

    return Tooltip(
      message: label == 'Reverse' ? 'Reverse (R)' : label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? colors.selectionFill : colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: isActive ? colors.selectionBorder : colors.surface,
                width: 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? colors.accent
                    : (enabled
                          ? colors.textPrimary
                          : colors.textMuted.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============ SAMPLER BUTTON ============
  Widget _buildSamplerButton(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Create Sampler from this clip',
      child: GestureDetector(
        onTap: widget.onCreateSamplerFromClip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: colors.surface, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(BI.piano, size: 13, color: colors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  'Sampler',
                  style: TextStyle(fontSize: 10, color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draggable BPM display for clip's original tempo.
