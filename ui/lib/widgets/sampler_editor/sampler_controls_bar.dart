import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Controls bar for Sampler Editor.
/// Provides Attack, Release, and Root Note controls for the sampler instrument.
///
/// Layout format:
/// [Attack ━━●━━ 10ms] [Release ━━●━━ 100ms] | [Root Note: C4 ▼]
class SamplerControlsBar extends StatefulWidget {
  final double attackMs;
  final double releaseMs;
  final int rootNote;
  final Function(double)? onAttackChanged;
  final Function(double)? onReleaseChanged;
  final Function(int)? onRootNoteChanged;

  const SamplerControlsBar({
    super.key,
    this.attackMs = 10.0,
    this.releaseMs = 100.0,
    this.rootNote = 60,
    this.onAttackChanged,
    this.onReleaseChanged,
    this.onRootNoteChanged,
  });

  @override
  State<SamplerControlsBar> createState() => _SamplerControlsBarState();
}

class _SamplerControlsBarState extends State<SamplerControlsBar> {
  OverlayEntry? _rootNoteOverlay;
  final GlobalKey _rootNoteButtonKey = GlobalKey();

  @override
  void dispose() {
    _removeRootNoteOverlay();
    super.dispose();
  }

  void _removeRootNoteOverlay() {
    _rootNoteOverlay?.remove();
    _rootNoteOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // === ENVELOPE GROUP ===
            _buildEnvelopeGroup(context),
            _buildSeparator(context),

            // === ROOT NOTE GROUP ===
            _buildRootNoteGroup(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: colors.divider,
    );
  }

  Widget _buildEnvelopeGroup(BuildContext context) {
    return Row(
      children: [
        // Attack slider
        _buildLabeledSlider(
          context,
          label: 'Attack',
          value: widget.attackMs,
          min: 0,
          max: 5000,
          displayValue: _formatMs(widget.attackMs),
          onChanged: widget.onAttackChanged,
        ),
        const SizedBox(width: 16),

        // Release slider
        _buildLabeledSlider(
          context,
          label: 'Release',
          value: widget.releaseMs,
          min: 0,
          max: 5000,
          displayValue: _formatMs(widget.releaseMs),
          onChanged: widget.onReleaseChanged,
        ),
      ],
    );
  }

  Widget _buildLabeledSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    Function(double)? onChanged,
  }) {
    final colors = context.colors;

    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.divider,
              thumbColor: colors.accent,
              overlayColor: colors.accent.withAlpha(30),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            displayValue,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRootNoteGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Text(
          'Root',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          key: _rootNoteButtonKey,
          onTap: _showRootNoteMenu,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  Text(
                    _midiNoteToName(widget.rootNote),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showRootNoteMenu() {
    _removeRootNoteOverlay();

    final renderBox =
        _rootNoteButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final colors = context.colors;

    _rootNoteOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss area
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeRootNoteOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

          // Menu
          Positioned(
            left: position.dx,
            top: position.dy + renderBox.size.height + 4,
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(4),
              elevation: 8,
              child: Container(
                width: 200,
                constraints: const BoxConstraints(maxHeight: 300),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.divider),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: 88, // Piano range: A0 (21) to C8 (108)
                  itemBuilder: (context, index) {
                    final note = 21 + index; // Start from A0
                    final isSelected = note == widget.rootNote;

                    return InkWell(
                      onTap: () {
                        widget.onRootNoteChanged?.call(note);
                        _removeRootNoteOverlay();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        color: isSelected
                            ? colors.accent.withAlpha(50)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                _midiNoteToName(note),
                                style: TextStyle(
                                  color: isSelected
                                      ? colors.accent
                                      : colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            Text(
                              '($note)',
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_rootNoteOverlay!);
  }

  String _formatMs(double ms) {
    if (ms < 1000) {
      return '${ms.toInt()}ms';
    } else {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
  }

  String _midiNoteToName(int note) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B'
    ];
    final octave = (note ~/ 12) - 1;
    final noteName = noteNames[note % 12];
    return '$noteName$octave';
  }
}
