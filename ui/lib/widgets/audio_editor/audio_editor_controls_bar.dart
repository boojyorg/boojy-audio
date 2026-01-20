import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../piano_roll/loop_time_display.dart';

/// Simplified horizontal controls bar for Audio Editor.
/// Matches Piano Roll styling with 5 essential controls.
///
/// Layout format (matches Piano Roll):
/// Start [1.1.1] Length [4.0.0] | Pitch [+0 st] | Vol [━━●━━ +0.0 dB] | BPM [120.0]
class AudioEditorControlsBar extends StatelessWidget {
  // === Start/Length ===
  final double startOffsetBeats;
  final double lengthBeats;
  final int beatsPerBar; // Needed for LoopTimeDisplay formatting
  final Function(double)? onStartChanged;
  final Function(double)? onLengthChanged;

  // === Pitch ===
  final int transposeSemitones;
  final Function(int)? onTransposeChanged;

  // === Volume ===
  final double gainDb;
  final Function(double)? onGainChanged;

  // === BPM ===
  final double bpm;
  final Function(double)? onBpmChanged;

  const AudioEditorControlsBar({
    super.key,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.onStartChanged,
    this.onLengthChanged,
    this.transposeSemitones = 0,
    this.onTransposeChanged,
    this.gainDb = 0.0,
    this.onGainChanged,
    this.bpm = 120.0,
    this.onBpmChanged,
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
          // === CLIP GROUP (Start + Length) ===
          _buildClipGroup(context),
          _buildSeparator(context),

          // === PITCH ===
          _buildPitchControl(context),
          _buildSeparator(context),

          // === VOLUME ===
          _buildVolumeControl(context),
          _buildSeparator(context),

          // === BPM ===
          _buildBpmControl(context),

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
    final displayValue = transposeSemitones > 0 ? '+$transposeSemitones' : '$transposeSemitones';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pitch', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        _NumberInputBox(
          displayText: '$displayValue st',
          onTap: () => _showPitchDialog(context),
        ),
      ],
    );
  }

  void _showPitchDialog(BuildContext context) {
    final controller = TextEditingController(text: '$transposeSemitones');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transpose'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Semitones (-48 to +48)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text) ?? 0;
              onTransposeChanged?.call(value.clamp(-48, 48));
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============ VOLUME CONTROL ============
  Widget _buildVolumeControl(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Vol', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gain slider
              SizedBox(
                width: 60,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.surface,
                    thumbColor: colors.accent,
                    overlayColor: colors.accent.withAlpha(30),
                  ),
                  child: Slider(
                    value: gainDb.clamp(-24.0, 12.0),
                    min: -24.0,
                    max: 12.0,
                    onChanged: (value) => onGainChanged?.call(value),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // dB display
              Text(
                '${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(1)} dB',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============ BPM CONTROL ============
  Widget _buildBpmControl(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('BPM', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        _NumberInputBox(
          displayText: bpm.toStringAsFixed(1),
          onTap: () => _showBpmDialog(context),
        ),
      ],
    );
  }

  void _showBpmDialog(BuildContext context) {
    final controller = TextEditingController(text: bpm.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('BPM'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'BPM (20 - 999)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 120.0;
              onBpmChanged?.call(value.clamp(20, 999));
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Simple clickable input box matching Piano Roll styling
class _NumberInputBox extends StatelessWidget {
  final String displayText;
  final VoidCallback? onTap;

  const _NumberInputBox({
    required this.displayText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Text(
            displayText,
            style: TextStyle(
              fontSize: 9,
              color: colors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
