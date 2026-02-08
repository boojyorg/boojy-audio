import 'package:flutter/material.dart';
import '../../models/audio_clip_edit_data.dart';
import '../../theme/theme_extension.dart';
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
  final int beatUnit; // Time signature denominator (e.g., 4 for 4/4)
  final Function(double)? onStartChanged;
  final Function(double)? onLengthChanged;
  final Function(int, int)? onSignatureChanged; // (numerator, denominator)

  // === Warp/Tempo ===
  final bool warpEnabled;
  final VoidCallback? onWarpToggle;
  final WarpMode warpMode;
  final Function(WarpMode)? onWarpModeChanged;
  final double originalBpm; // Clip's original tempo
  final Function(double)? onOriginalBpmChanged;
  final double projectBpm; // Project tempo (read-only display or editable)
  final Function(double)? onProjectBpmChanged;

  // === Pitch ===
  final int transposeSemitones;
  final Function(int)? onTransposeChanged;
  final int fineCents;
  final Function(int)? onFineCentsChanged;

  // === Reverse ===
  final bool reversed;
  final VoidCallback? onReverseToggle;

  // === Volume ===
  final double gainDb;
  final Function(double)? onGainChanged;

  // === Create Sampler ===
  final VoidCallback? onCreateSamplerFromClip;

  const AudioEditorControlsBar({
    super.key,
    this.loopEnabled = true,
    this.onLoopToggle,
    this.startOffsetBeats = 0.0,
    this.lengthBeats = 4.0,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onStartChanged,
    this.onLengthChanged,
    this.onSignatureChanged,
    this.warpEnabled = true,
    this.onWarpToggle,
    this.warpMode = WarpMode.warp,
    this.onWarpModeChanged,
    this.originalBpm = 120.0,
    this.onOriginalBpmChanged,
    this.projectBpm = 120.0,
    this.onProjectBpmChanged,
    this.transposeSemitones = 0,
    this.onTransposeChanged,
    this.fineCents = 0,
    this.onFineCentsChanged,
    this.reversed = false,
    this.onReverseToggle,
    this.gainDb = 0.0,
    this.onGainChanged,
    this.onCreateSamplerFromClip,
  });

  @override
  State<AudioEditorControlsBar> createState() => _AudioEditorControlsBarState();
}

class _AudioEditorControlsBarState extends State<AudioEditorControlsBar> {
  // Hover states for warp split button
  bool _isHoveringWarpLabel = false;
  bool _isHoveringWarpDropdown = false;

  // Overlay for warp mode menu
  OverlayEntry? _warpModeOverlay;
  final GlobalKey _warpButtonKey = GlobalKey();

  @override
  void dispose() {
    _removeWarpModeOverlay();
    super.dispose();
  }

  void _removeWarpModeOverlay() {
    _warpModeOverlay?.remove();
    _warpModeOverlay = null;
  }

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
                  color: widget.loopEnabled ? colors.elevated : colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Loop',
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.loopEnabled ? colors.elevated : colors.textPrimary,
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
            beats: widget.startOffsetBeats,
            label: '',
            onChanged: widget.onStartChanged,
            beatsPerBar: widget.beatsPerBar,
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
            beats: widget.lengthBeats,
            label: '',
            onChanged: widget.onLengthChanged,
            beatsPerBar: widget.beatsPerBar,
            isPosition: false, // 0-indexed length (1.0.0 = 1 bar)
          ),
        ),
        const SizedBox(width: 8),

        // Signature label + dropdown
        Text('Signature', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        _buildSignatureDropdown(context),
      ],
    );
  }

  // ============ SIGNATURE DROPDOWN ============
  Widget _buildSignatureDropdown(BuildContext context) {
    final colors = context.colors;
    final signature = '${widget.beatsPerBar}/${widget.beatUnit}';

    return GestureDetector(
      onTap: () => _showSignatureMenu(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                signature,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSignatureMenu(BuildContext context) {
    final colors = context.colors;
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final signatures = [
      (2, 4),
      (3, 4),
      (4, 4),
      (5, 4),
      (6, 8),
      (7, 8),
    ];

    showMenu<(int, int)>(
      context: context,
      position: RelativeRect.fromLTRB(
        renderBox.localToGlobal(Offset.zero).dx,
        renderBox.localToGlobal(Offset.zero).dy + renderBox.size.height,
        0,
        0,
      ),
      items: signatures.map((sig) {
        final isSelected = sig.$1 == widget.beatsPerBar && sig.$2 == widget.beatUnit;
        return PopupMenuItem<(int, int)>(
          value: sig,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: isSelected
                    ? Icon(Icons.check, size: 14, color: colors.accent)
                    : null,
              ),
              Text(
                '${sig.$1}/${sig.$2}',
                style: TextStyle(
                  color: isSelected ? colors.accent : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        widget.onSignatureChanged?.call(value.$1, value.$2);
      }
    });
  }

  // ============ PITCH CONTROL ============
  Widget _buildPitchControl(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pitch', style: TextStyle(color: colors.textMuted, fontSize: 9)),
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
        Text('Volume', style: TextStyle(color: colors.textMuted, fontSize: 9)),
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
          child: CapsuleSlider(
            value: sliderValue,
            onChanged: (value) {
              final db = sliderToDb(value);
              widget.onGainChanged?.call(db);
            },
            onDoubleTap: () => widget.onGainChanged?.call(0.0), // Reset to 0 dB
          ),
        ),
      ],
    );
  }

  // ============ WARP GROUP (Warp label + split button + BPM + tempo buttons + Reverse) ============
  Widget _buildWarpGroup(BuildContext context) {
    final colors = context.colors;
    final isEnabled = widget.warpEnabled;
    final mode = widget.warpMode;
    final modeLabel = mode == WarpMode.warp ? 'Stretch' : 'Re-Pitch';
    final bgColor = isEnabled ? colors.accent : colors.dark;
    final textColor = isEnabled ? colors.elevated : colors.textPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warp label
        Text('Warp', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        // Split button: [icon + Stretch | ▼] - like Piano Roll's Snap button
        DecoratedBox(
          key: _warpButtonKey,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left side: Icon + Label (clickable to toggle warp on/off)
              MouseRegion(
                onEnter: (_) => setState(() => _isHoveringWarpLabel = true),
                onExit: (_) => setState(() => _isHoveringWarpLabel = false),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onWarpToggle,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isHoveringWarpLabel
                          ? colors.textPrimary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sync,
                          size: 13,
                          color: textColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          modeLabel,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Divider line
              Container(
                width: 1,
                height: 15,
                color: colors.textPrimary.withValues(alpha: 0.2),
              ),
              // Right side: Dropdown arrow (opens mode menu)
              MouseRegion(
                onEnter: (_) => setState(() => _isHoveringWarpDropdown = true),
                onExit: (_) => setState(() => _isHoveringWarpDropdown = false),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showWarpModeMenu(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isHoveringWarpDropdown
                          ? colors.textPrimary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 14,
                      color: textColor,
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
          enabled: isEnabled,
        ),
        const SizedBox(width: 4),
        // ÷2 button - halves BPM (same style as Reverse toggle)
        _buildActionButton(context, '÷2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call((widget.originalBpm / 2).clamp(20, 999));
        }),
        const SizedBox(width: 2),
        // ×2 button - doubles BPM (same style as Reverse toggle)
        _buildActionButton(context, '×2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call((widget.originalBpm * 2).clamp(20, 999));
        }),
        const SizedBox(width: 4),
        // Reverse toggle
        _buildActionButton(context, 'Reverse', widget.reversed, true, widget.onReverseToggle),
      ],
    );
  }

  // ============ ACTION BUTTON (÷2 / ×2 / Reverse - unified style) ============
  Widget _buildActionButton(BuildContext context, String label, bool isActive, bool enabled, VoidCallback? onTap) {
    final colors = context.colors;

    return Tooltip(
      message: label == 'Reverse' ? 'Reverse (R)' : label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: isActive ? colors.accent : colors.dark,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? colors.elevated
                    : (enabled ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.5)),
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
                Icon(
                  Icons.piano,
                  size: 13,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Sampler',
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

  void _showWarpModeMenu(BuildContext context) {
    if (_warpModeOverlay != null) {
      _removeWarpModeOverlay();
      return;
    }

    final RenderBox? renderBox = _warpButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _warpModeOverlay = OverlayEntry(
      builder: (ctx) => _WarpModeMenuOverlay(
        position: Offset(position.dx, position.dy + size.height + 4),
        currentMode: widget.warpMode,
        onModeSelected: (mode) {
          _removeWarpModeOverlay();
          widget.onWarpModeChanged?.call(mode);
        },
        onDismiss: _removeWarpModeOverlay,
      ),
    );

    Overlay.of(context).insert(_warpModeOverlay!);
  }
}

/// Overlay menu for selecting warp mode.
class _WarpModeMenuOverlay extends StatelessWidget {
  final Offset position;
  final WarpMode currentMode;
  final Function(WarpMode) onModeSelected;
  final VoidCallback onDismiss;

  const _WarpModeMenuOverlay({
    required this.position,
    required this.currentMode,
    required this.onModeSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 160),
              decoration: BoxDecoration(
                color: colors.dark,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.surface, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMenuItem(
                    context,
                    'Warp',
                    'Time-stretch, pitch preserved',
                    WarpMode.warp,
                  ),
                  _buildMenuItem(
                    context,
                    'Re-Pitch',
                    'Speed changes pitch',
                    WarpMode.repitch,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    String label,
    String description,
    WarpMode mode,
  ) {
    final colors = context.colors;
    final isSelected = currentMode == mode;

    return InkWell(
      onTap: () => onModeSelected(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              child: isSelected
                  ? Icon(Icons.check, size: 14, color: colors.accent)
                  : null,
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? colors.accent : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Draggable BPM display for clip's original tempo.
