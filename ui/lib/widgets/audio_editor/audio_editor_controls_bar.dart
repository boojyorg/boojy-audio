import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';
import '../piano_roll/loop_time_display.dart';
import '../piano_roll/time_signature_display.dart';

/// Horizontal controls bar for Audio Editor.
/// Provides controls for audio clip editing parameters.
///
/// Layout format:
/// [Loop] Start [1.1.1] Length [4.0.0] Signature [4/4] |
/// [Snap▼] [Quantize▼] (greyed) | [BPM] [Sync] [Stretch▼] |
/// [Transpose] [Fine] | [Gain ━━●━━] [Stereo] | [Reverse] [Normalize▼]
class AudioEditorControlsBar extends StatefulWidget {
  // === Playback Section ===
  final bool loopEnabled;
  final double startOffsetBeats;
  final double lengthBeats;
  final int beatsPerBar;
  final int beatUnit;
  final Function(bool)? onLoopToggle;
  final Function(double)? onStartChanged;
  final Function(double)? onLengthChanged;
  final Function(int)? onBeatsPerBarChanged;
  final Function(int)? onBeatUnitChanged;

  // === Grid Section (greyed out in v1) ===
  final bool snapEnabled;
  final double gridDivision;

  // === Tempo Section ===
  final double bpm;
  final bool syncEnabled;
  final double stretchFactor;
  final Function(double)? onBpmChanged;
  final Function(bool)? onSyncToggle;
  final Function(double)? onStretchChanged;

  // === Pitch Section ===
  final int transposeSemitones;
  final int fineCents;
  final Function(int)? onTransposeChanged;
  final Function(int)? onFineChanged;

  // === Level Section ===
  final double gainDb;
  final bool isStereo;
  final Function(double)? onGainChanged;

  // === Actions Section ===
  final bool reversed;
  final double? normalizeTargetDb;
  final VoidCallback? onReverseToggle;
  final Function(double?)? onNormalizeChanged;

  const AudioEditorControlsBar({
    super.key,
    // Playback section
    this.loopEnabled = true,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onLoopToggle,
    this.onStartChanged,
    this.onLengthChanged,
    this.onBeatsPerBarChanged,
    this.onBeatUnitChanged,
    // Grid section
    this.snapEnabled = true,
    this.gridDivision = 0.25,
    // Tempo section
    this.bpm = 120.0,
    this.syncEnabled = false,
    this.stretchFactor = 1.0,
    this.onBpmChanged,
    this.onSyncToggle,
    this.onStretchChanged,
    // Pitch section
    this.transposeSemitones = 0,
    this.fineCents = 0,
    this.onTransposeChanged,
    this.onFineChanged,
    // Level section
    this.gainDb = 0.0,
    this.isStereo = true,
    this.onGainChanged,
    // Actions section
    this.reversed = false,
    this.normalizeTargetDb,
    this.onReverseToggle,
    this.onNormalizeChanged,
  });

  @override
  State<AudioEditorControlsBar> createState() => _AudioEditorControlsBarState();
}

class _AudioEditorControlsBarState extends State<AudioEditorControlsBar> {
  // Overlay entries for dropdowns
  OverlayEntry? _stretchOverlay;
  OverlayEntry? _normalizeOverlay;
  final GlobalKey _stretchButtonKey = GlobalKey();
  final GlobalKey _normalizeButtonKey = GlobalKey();

  @override
  void dispose() {
    _removeStretchOverlay();
    _removeNormalizeOverlay();
    super.dispose();
  }

  void _removeStretchOverlay() {
    _stretchOverlay?.remove();
    _stretchOverlay = null;
  }

  void _removeNormalizeOverlay() {
    _normalizeOverlay?.remove();
    _normalizeOverlay = null;
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
            // === PLAYBACK GROUP (Loop is first) ===
            _buildPlaybackGroup(context),
            _buildSeparator(context),

            // === GRID GROUP (greyed in v1) ===
            _buildGridGroup(context),
            _buildSeparator(context),

            // === TEMPO GROUP ===
            _buildTempoGroup(context),
            _buildSeparator(context),

            // === PITCH GROUP ===
            _buildPitchGroup(context),
            _buildSeparator(context),

            // === LEVEL GROUP ===
            _buildLevelGroup(context),
            _buildSeparator(context),

            // === ACTIONS GROUP ===
            _buildActionsGroup(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparator(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      color: context.colors.surface,
    );
  }

  // ============ PLAYBACK GROUP ============
  Widget _buildPlaybackGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loop toggle
        _buildToggleButton(
          context,
          icon: Icons.loop,
          label: 'Loop',
          isActive: widget.loopEnabled,
          onTap: () => widget.onLoopToggle?.call(!widget.loopEnabled),
        ),
        const SizedBox(width: 8),

        // Start position
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Start', style: TextStyle(fontSize: 9, color: colors.textMuted)),
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
                beatsPerBar: widget.beatsPerBar,
                isPosition: true,
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),

        // Length
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Length', style: TextStyle(fontSize: 9, color: colors.textMuted)),
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
                beatsPerBar: widget.beatsPerBar,
                isPosition: false,
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),

        // Time signature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: TimeSignatureDisplay(
            beatsPerBar: widget.beatsPerBar,
            beatUnit: widget.beatUnit,
            onBeatsPerBarChanged: widget.onBeatsPerBarChanged,
            onBeatUnitChanged: widget.onBeatUnitChanged,
          ),
        ),
      ],
    );
  }

  // ============ GRID GROUP (greyed in v1) ============
  Widget _buildGridGroup(BuildContext context) {
    final colors = context.colors;
    // Use red tint for disabled controls to indicate "inactive"
    final disabledColor = colors.error.withValues(alpha: 0.5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Snap (greyed)
        Tooltip(
          message: 'Snap (coming in v2)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: colors.dark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_4x4, size: 12, color: disabledColor),
                const SizedBox(width: 4),
                Text(
                  'Snap',
                  style: TextStyle(fontSize: 9, color: disabledColor),
                ),
                Icon(Icons.arrow_drop_down, size: 12, color: disabledColor),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Quantize (greyed)
        Tooltip(
          message: 'Quantize (coming in v2)',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: colors.dark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.straighten, size: 12, color: disabledColor),
                const SizedBox(width: 4),
                Text(
                  'Quantize',
                  style: TextStyle(fontSize: 9, color: disabledColor),
                ),
                Icon(Icons.arrow_drop_down, size: 12, color: disabledColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============ TEMPO GROUP ============
  Widget _buildTempoGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // BPM field
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('BPM', style: TextStyle(fontSize: 9, color: colors.textMuted)),
            const SizedBox(width: 4),
            _buildNumberInput(
              context,
              value: widget.bpm,
              width: 50,
              onChanged: (value) => widget.onBpmChanged?.call(value),
              min: 20,
              max: 999,
              decimals: 1,
            ),
          ],
        ),
        const SizedBox(width: 8),

        // Sync toggle
        _buildToggleButton(
          context,
          icon: Icons.link,
          label: 'Sync',
          isActive: widget.syncEnabled,
          onTap: () => widget.onSyncToggle?.call(!widget.syncEnabled),
        ),
        const SizedBox(width: 8),

        // Stretch dropdown
        _buildStretchDropdown(context),
      ],
    );
  }

  Widget _buildStretchDropdown(BuildContext context) {
    final colors = context.colors;
    final stretchLabel = 'x${widget.stretchFactor.toStringAsFixed(widget.stretchFactor == widget.stretchFactor.roundToDouble() ? 0 : 1)}';

    return GestureDetector(
      key: _stretchButtonKey,
      onTap: _showStretchMenu,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stretch', style: TextStyle(fontSize: 9, color: colors.textMuted)),
              const SizedBox(width: 4),
              Text(
                stretchLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: colors.textPrimary),
              ),
              Icon(Icons.arrow_drop_down, size: 12, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showStretchMenu() {
    final renderBox = _stretchButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _stretchOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeStretchOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Menu
          Positioned(
            left: position.dx,
            top: position.dy + size.height + 4,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(2),
              color: context.colors.elevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final factor in [0.5, 0.75, 1.0, 1.5, 2.0, 4.0])
                    _buildStretchMenuItem(context, factor),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_stretchOverlay!);
  }

  Widget _buildStretchMenuItem(BuildContext context, double factor) {
    final colors = context.colors;
    final isSelected = widget.stretchFactor == factor;

    return InkWell(
      onTap: () {
        widget.onStretchChanged?.call(factor);
        _removeStretchOverlay();
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? colors.accent.withValues(alpha: 0.2) : Colors.transparent,
        child: Text(
          'x${factor.toStringAsFixed(factor == factor.roundToDouble() ? 0 : 2)}',
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? colors.accent : colors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ============ PITCH GROUP ============
  Widget _buildPitchGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Transpose
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Transpose', style: TextStyle(fontSize: 9, color: colors.textMuted)),
            const SizedBox(width: 4),
            _buildIntegerInput(
              context,
              value: widget.transposeSemitones,
              width: 45,
              onChanged: (value) => widget.onTransposeChanged?.call(value),
              min: -48,
              max: 48,
              suffix: 'st',
              showSign: true,
            ),
          ],
        ),
        const SizedBox(width: 8),

        // Fine
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Fine', style: TextStyle(fontSize: 9, color: colors.textMuted)),
            const SizedBox(width: 4),
            _buildIntegerInput(
              context,
              value: widget.fineCents,
              width: 50,
              onChanged: (value) => widget.onFineChanged?.call(value),
              min: -100,
              max: 100,
              suffix: 'ct',
              showSign: true,
            ),
          ],
        ),
      ],
    );
  }

  // ============ LEVEL GROUP ============
  Widget _buildLevelGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gain display and slider
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // dB display
              SizedBox(
                width: 45,
                child: Text(
                  '${widget.gainDb >= 0 ? '+' : ''}${widget.gainDb.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              // Gain slider
              SizedBox(
                width: 80,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.surface,
                    thumbColor: colors.accent,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: widget.gainDb.clamp(-24.0, 12.0),
                    min: -24.0,
                    max: 12.0,
                    onChanged: (value) => widget.onGainChanged?.call(value),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.volume_up, size: 12, color: colors.textMuted),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Stereo indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: widget.isStereo ? colors.accent.withValues(alpha: 0.2) : colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: widget.isStereo ? colors.accent.withValues(alpha: 0.5) : colors.surface,
            ),
          ),
          child: Text(
            widget.isStereo ? 'Stereo' : 'Mono',
            style: TextStyle(
              fontSize: 9,
              color: widget.isStereo ? colors.accent : colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  // ============ ACTIONS GROUP ============
  Widget _buildActionsGroup(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reverse button
        _buildActionButton(
          context,
          icon: Icons.swap_horiz,
          label: 'Reverse',
          isActive: widget.reversed,
          onTap: widget.onReverseToggle,
        ),
        const SizedBox(width: 8),

        // Normalize dropdown
        _buildNormalizeDropdown(context),
      ],
    );
  }

  Widget _buildNormalizeDropdown(BuildContext context) {
    final colors = context.colors;
    final hasNormalize = widget.normalizeTargetDb != null;
    final label = hasNormalize
        ? '${widget.normalizeTargetDb!.toStringAsFixed(0)} dB'
        : 'Off';

    return GestureDetector(
      key: _normalizeButtonKey,
      onTap: _showNormalizeMenu,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: hasNormalize ? colors.accent.withValues(alpha: 0.2) : colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: hasNormalize
                ? Border.all(color: colors.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.equalizer,
                size: 12,
                color: hasNormalize ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Normalize',
                style: TextStyle(
                  fontSize: 9,
                  color: hasNormalize ? colors.accent : colors.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: hasNormalize ? colors.accent : colors.textMuted,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 12,
                color: hasNormalize ? colors.accent : colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNormalizeMenu() {
    final renderBox = _normalizeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _normalizeOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeNormalizeOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Menu
          Positioned(
            left: position.dx,
            top: position.dy + size.height + 4,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(2),
              color: context.colors.elevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNormalizeMenuItem(context, null, 'Off'),
                  _buildNormalizeMenuItem(context, 0.0, '0 dB'),
                  _buildNormalizeMenuItem(context, -1.0, '-1 dB'),
                  _buildNormalizeMenuItem(context, -3.0, '-3 dB'),
                  _buildNormalizeMenuItem(context, -6.0, '-6 dB'),
                  _buildNormalizeMenuItem(context, -12.0, '-12 dB'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_normalizeOverlay!);
  }

  Widget _buildNormalizeMenuItem(BuildContext context, double? value, String label) {
    final colors = context.colors;
    final isSelected = widget.normalizeTargetDb == value;

    return InkWell(
      onTap: () {
        widget.onNormalizeChanged?.call(value);
        _removeNormalizeOverlay();
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected ? colors.accent.withValues(alpha: 0.2) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? colors.accent : colors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ============ HELPER WIDGETS ============

  Widget _buildToggleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? colors.accent : colors.dark,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: isActive ? colors.elevated : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isActive ? colors.elevated : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? colors.accent.withValues(alpha: 0.2) : colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: isActive
                ? Border.all(color: colors.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: isActive ? colors.accent : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isActive ? colors.accent : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberInput(
    BuildContext context, {
    required double value,
    required double width,
    required Function(double) onChanged,
    double min = 0,
    double max = 999,
    int decimals = 0,
  }) {
    final colors = context.colors;
    final controller = TextEditingController(text: value.toStringAsFixed(decimals));

    return SizedBox(
      width: width,
      height: 24,
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontSize: 9,
          color: colors.textPrimary,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.dark,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide.none,
          ),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (text) {
          final parsed = double.tryParse(text);
          if (parsed != null) {
            onChanged(parsed.clamp(min, max));
          }
        },
      ),
    );
  }

  Widget _buildIntegerInput(
    BuildContext context, {
    required int value,
    required double width,
    required Function(int) onChanged,
    int min = -999,
    int max = 999,
    String suffix = '',
    bool showSign = false,
  }) {
    final colors = context.colors;
    final displayValue = showSign && value > 0 ? '+$value' : '$value';
    final controller = TextEditingController(text: displayValue);

    return SizedBox(
      width: width,
      height: 24,
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontSize: 9,
          color: colors.textPrimary,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.dark,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: BorderSide.none,
          ),
          suffixText: suffix,
          suffixStyle: TextStyle(fontSize: 10, color: colors.textMuted),
        ),
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        onSubmitted: (text) {
          // Remove any + sign before parsing
          final cleanText = text.replaceAll('+', '');
          final parsed = int.tryParse(cleanText);
          if (parsed != null) {
            onChanged(parsed.clamp(min, max));
          }
        },
      ),
    );
  }
}
