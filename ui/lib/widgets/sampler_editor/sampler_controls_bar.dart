import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Two-row controls bar for Sampler Editor.
///
/// Row 1 (functional): [Loop] | Atk [slider] | Rel [slider] | Root [dropdown] | [Load]
/// Row 2 (disabled layout placeholder): [Warp] [Stretch] [BPM] [÷2] [×2] | [Reverse] | Pitch | Vol
class SamplerControlsBar extends StatefulWidget {
  // Row 1 — functional controls
  final bool loopEnabled;
  final double attackMs;
  final double releaseMs;
  final int rootNote;
  final VoidCallback? onLoopToggle;
  final Function(double)? onAttackChanged;
  final Function(double)? onReleaseChanged;
  final Function(int)? onRootNoteChanged;
  final VoidCallback? onLoadSample;

  const SamplerControlsBar({
    super.key,
    this.loopEnabled = false,
    this.attackMs = 1.0,
    this.releaseMs = 50.0,
    this.rootNote = 60,
    this.onLoopToggle,
    this.onAttackChanged,
    this.onReleaseChanged,
    this.onRootNoteChanged,
    this.onLoadSample,
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
      decoration: BoxDecoration(
        color: colors.standard,
        border: Border(
          bottom: BorderSide(color: colors.surface, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Functional controls
          _buildRow1(context),
          // Divider between rows
          Container(height: 1, color: colors.surface.withAlpha(80)),
          // Row 2: Disabled placeholders
          _buildRow2(context),
        ],
      ),
    );
  }

  // ============================================================================
  // ROW 1 — Functional: [Loop] | Atk | Rel | Root | [Load]
  // ============================================================================

  Widget _buildRow1(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Loop toggle
          _buildLoopToggle(context),
          _buildSeparator(context),

          // Attack slider
          _buildLabeledSlider(
            context,
            label: 'Atk',
            value: widget.attackMs,
            min: 0,
            max: 5000,
            displayValue: _formatMs(widget.attackMs),
            onChanged: widget.onAttackChanged,
          ),
          const SizedBox(width: 12),

          // Release slider
          _buildLabeledSlider(
            context,
            label: 'Rel',
            value: widget.releaseMs,
            min: 0,
            max: 5000,
            displayValue: _formatMs(widget.releaseMs),
            onChanged: widget.onReleaseChanged,
          ),
          _buildSeparator(context),

          // Root note dropdown
          _buildRootNoteGroup(context),
          _buildSeparator(context),

          // Load button
          _buildLoadButton(context),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLoopToggle(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: widget.loopEnabled ? 'Loop On (1-shot off)' : 'Loop Off (1-shot mode)',
      child: GestureDetector(
        onTap: widget.onLoopToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: widget.loopEnabled ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.loop,
                  size: 13,
                  color: widget.loopEnabled ? colors.elevated : colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Loop',
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.loopEnabled ? colors.elevated : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadButton(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Load Sample',
      child: GestureDetector(
        onTap: widget.onLoadSample,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 13,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Load',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // ROW 2 — Disabled placeholders (layout only, greyed out)
  // ============================================================================

  Widget _buildRow2(BuildContext context) {
    final colors = context.colors;
    final mutedColor = colors.textMuted.withAlpha(80);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Warp label + fake button
          Text('Warp', style: TextStyle(color: mutedColor, fontSize: 9)),
          const SizedBox(width: 4),
          _buildDisabledButton(context, 'Stretch'),
          const SizedBox(width: 4),
          _buildDisabledButton(context, '120 BPM'),
          const SizedBox(width: 2),
          _buildDisabledButton(context, '÷2'),
          const SizedBox(width: 2),
          _buildDisabledButton(context, '×2'),
          _buildSeparator(context, muted: true),

          // Reverse
          _buildDisabledButton(context, 'Reverse'),
          _buildSeparator(context, muted: true),

          // Pitch
          Text('Pitch', style: TextStyle(color: mutedColor, fontSize: 9)),
          const SizedBox(width: 4),
          _buildDisabledButton(context, '+0 st +0 ct'),
          _buildSeparator(context, muted: true),

          // Volume
          Text('Vol', style: TextStyle(color: mutedColor, fontSize: 9)),
          const SizedBox(width: 4),
          Container(
            width: 60,
            height: 14,
            decoration: BoxDecoration(
              color: colors.dark.withAlpha(80),
              borderRadius: BorderRadius.circular(7),
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildDisabledButton(BuildContext context, String label) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.forbidden,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: colors.dark.withAlpha(80),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted.withAlpha(80),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Shared widgets
  // ============================================================================

  Widget _buildSeparator(BuildContext context, {bool muted = false}) {
    final colors = context.colors;
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: muted ? colors.divider.withAlpha(40) : colors.surface,
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
                    final note = 21 + index;
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
      'C', 'C#', 'D', 'D#', 'E', 'F',
      'F#', 'G', 'G#', 'A', 'A#', 'B',
    ];
    final octave = (note ~/ 12) - 1;
    final noteName = noteNames[note % 12];
    return '$noteName$octave';
  }
}
