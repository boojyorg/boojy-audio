import 'package:flutter/material.dart';
import '../../models/audio_clip_edit_data.dart';
import '../../theme/theme_extension.dart';
import '../audio_editor/draggable_pitch_display.dart';
import '../piano_roll/loop_time_display.dart';
import '../shared/editors/bpm_display.dart';
import '../shared/editors/capsule_slider.dart';

/// Full controls bar for Sampler Editor.
/// Matches Audio Editor controls bar styling with sampler-specific controls.
///
/// Layout (left to right):
/// [Loop] | Atk [══] Rel [══] | Root [C4▼] | Start [1.1.1] Length [2.0.0] Sig [4/4▼] |
/// Warp [↻Re-Pitch▼] [120BPM] [÷2][×2] [Rev] | Pitch [+0st. 0ct] | Vol [+0.0dB] [══] | ... | [Load]
class SamplerControlsBar extends StatefulWidget {
  // === Sampler identity (left) ===
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;
  final double attackMs;
  final double releaseMs;
  final Function(double)? onAttackChanged;
  final Function(double)? onReleaseChanged;
  final int rootNote;
  final Function(int)? onRootNoteChanged;

  // === Clip group (Start / Length / Signature) ===
  final double loopStartSeconds;
  final double loopEndSeconds;
  final double sampleDuration;
  final Function(double)? onLoopStartChanged;
  final Function(double)? onLoopEndChanged;
  final int beatsPerBar;
  final int beatUnit;
  final Function(int, int)? onSignatureChanged;

  // === Warp group ===
  final bool warpEnabled;
  final VoidCallback? onWarpToggle;
  final int warpMode; // 0=repitch, 1=warp
  final Function(int)? onWarpModeChanged;
  final double originalBpm;
  final Function(double)? onOriginalBpmChanged;

  // === Reverse ===
  final bool reversed;
  final VoidCallback? onReverseToggle;

  // === Pitch ===
  final int transposeSemitones;
  final int fineCents;
  final Function(int)? onTransposeChanged;
  final Function(int)? onFineCentsChanged;

  // === Volume ===
  final double volumeDb;
  final Function(double)? onVolumeChanged;

  // === Load ===
  final VoidCallback? onLoadSample;

  const SamplerControlsBar({
    super.key,
    this.loopEnabled = false,
    this.onLoopToggle,
    this.attackMs = 1.0,
    this.releaseMs = 50.0,
    this.onAttackChanged,
    this.onReleaseChanged,
    this.rootNote = 60,
    this.onRootNoteChanged,
    this.loopStartSeconds = 0.0,
    this.loopEndSeconds = 1.0,
    this.sampleDuration = 0.0,
    this.onLoopStartChanged,
    this.onLoopEndChanged,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onSignatureChanged,
    this.warpEnabled = false,
    this.onWarpToggle,
    this.warpMode = 0,
    this.onWarpModeChanged,
    this.originalBpm = 120.0,
    this.onOriginalBpmChanged,
    this.reversed = false,
    this.onReverseToggle,
    this.transposeSemitones = 0,
    this.fineCents = 0,
    this.onTransposeChanged,
    this.onFineCentsChanged,
    this.volumeDb = 0.0,
    this.onVolumeChanged,
    this.onLoadSample,
  });

  @override
  State<SamplerControlsBar> createState() => _SamplerControlsBarState();
}

class _SamplerControlsBarState extends State<SamplerControlsBar> {
  // Root note overlay
  OverlayEntry? _rootNoteOverlay;
  final GlobalKey _rootNoteButtonKey = GlobalKey();

  // Warp mode overlay
  OverlayEntry? _warpModeOverlay;
  final GlobalKey _warpButtonKey = GlobalKey();
  bool _isHoveringWarpLabel = false;
  bool _isHoveringWarpDropdown = false;

  @override
  void dispose() {
    _removeRootNoteOverlay();
    _removeWarpModeOverlay();
    super.dispose();
  }

  void _removeRootNoteOverlay() {
    _rootNoteOverlay?.remove();
    _rootNoteOverlay = null;
  }

  void _removeWarpModeOverlay() {
    _warpModeOverlay?.remove();
    _warpModeOverlay = null;
  }

  // ============================================================================
  // Seconds <-> Beats conversion
  // ============================================================================

  double _secondsToBeats(double seconds) => seconds * (widget.originalBpm / 60.0);
  double _beatsToSeconds(double beats) => beats * (60.0 / widget.originalBpm);

  // ============================================================================
  // Volume curve (same as Audio Editor)
  // ============================================================================

  double _dbToSlider(double db) {
    if (db <= -70) return 0.0;
    if (db >= 24) return 1.0;
    if (db <= -12) {
      return (db + 70) / 193.33;
    } else if (db <= 0) {
      return 0.3 + (db + 12) / 60;
    } else {
      return 0.5 + db / 48;
    }
  }

  double _sliderToDb(double slider) {
    if (slider <= 0.0) return -70.0;
    if (slider >= 1.0) return 24.0;
    if (slider <= 0.3) {
      return -70 + slider * 193.33;
    } else if (slider <= 0.5) {
      return -12 + (slider - 0.3) * 60;
    } else {
      return (slider - 0.5) * 48;
    }
  }

  // ============================================================================
  // Build
  // ============================================================================

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
          // === SAMPLER IDENTITY (left, beginner-facing) ===
          _buildLoopToggle(context),
          const SizedBox(width: 8),
          _buildEnvelopeGroup(context),
          _buildSeparator(context),
          _buildRootNoteGroup(context),
          _buildSeparator(context),

          // === AUDIO MANIPULATION (right, power-user, same as Audio Editor) ===
          _buildClipGroup(context),
          _buildSeparator(context),
          _buildWarpGroup(context),
          _buildSeparator(context),
          _buildPitchControl(context),
          _buildSeparator(context),
          _buildVolumeControl(context),

          const Spacer(),
          _buildLoadButton(context),
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

  // ============================================================================
  // Loop toggle (matches Audio Editor)
  // ============================================================================

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

  // ============================================================================
  // Envelope group (Atk + Rel capsule sliders)
  // ============================================================================

  Widget _buildEnvelopeGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Attack
        Text('Atk', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        SizedBox(
          width: 52,
          height: 20,
          child: CapsuleSlider(
            value: (widget.attackMs / 5000.0).clamp(0.0, 1.0),
            onChanged: (v) => widget.onAttackChanged?.call(v * 5000.0),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 38,
          child: Text(
            _formatMs(widget.attackMs),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Release
        Text('Rel', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        SizedBox(
          width: 52,
          height: 20,
          child: CapsuleSlider(
            value: (widget.releaseMs / 5000.0).clamp(0.0, 1.0),
            onChanged: (v) => widget.onReleaseChanged?.call(v * 5000.0),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 38,
          child: Text(
            _formatMs(widget.releaseMs),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // Root note group
  // ============================================================================

  Widget _buildRootNoteGroup(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Root', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        GestureDetector(
          key: _rootNoteButtonKey,
          onTap: _showRootNoteMenu,
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
                    _midiNoteToName(widget.rootNote),
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
        ),
      ],
    );
  }

  // ============================================================================
  // Clip group (Start + Length + Signature) — same as Audio Editor
  // ============================================================================

  Widget _buildClipGroup(BuildContext context) {
    final colors = context.colors;
    final startBeats = _secondsToBeats(widget.loopStartSeconds);
    final lengthBeats = _secondsToBeats(widget.loopEndSeconds - widget.loopStartSeconds);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Start
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
            beats: startBeats,
            label: '',
            onChanged: (beats) {
              widget.onLoopStartChanged?.call(_beatsToSeconds(beats));
            },
            beatsPerBar: widget.beatsPerBar,
            isPosition: true,
          ),
        ),
        const SizedBox(width: 8),

        // Length
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
            onChanged: (beats) {
              final lengthSeconds = _beatsToSeconds(beats);
              widget.onLoopEndChanged?.call(widget.loopStartSeconds + lengthSeconds);
            },
            beatsPerBar: widget.beatsPerBar,
            isPosition: false,
          ),
        ),
        const SizedBox(width: 8),

        // Signature
        Text('Sig', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        _buildSignatureDropdown(context),
      ],
    );
  }

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
      (2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8),
    ];

    showMenu<(int, int)>(
      context: context,
      position: RelativeRect.fromLTRB(
        renderBox.localToGlobal(Offset.zero).dx,
        renderBox.localToGlobal(Offset.zero).dy + renderBox.size.height,
        0, 0,
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

  // ============================================================================
  // Warp group — same as Audio Editor
  // ============================================================================

  Widget _buildWarpGroup(BuildContext context) {
    final colors = context.colors;
    final isEnabled = widget.warpEnabled;
    final warpMode = widget.warpMode == 1 ? WarpMode.warp : WarpMode.repitch;
    final modeLabel = warpMode == WarpMode.warp ? 'Stretch' : 'Re-Pitch';
    final bgColor = isEnabled ? colors.accent : colors.dark;
    final textColor = isEnabled ? colors.elevated : colors.textPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Warp label
        Text('Warp', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        // Split button
        DecoratedBox(
          key: _warpButtonKey,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left side: toggle
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
                        Icon(Icons.sync, size: 13, color: textColor),
                        const SizedBox(width: 4),
                        Text(
                          modeLabel,
                          style: TextStyle(color: textColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Divider
              Container(
                width: 1,
                height: 15,
                color: colors.textPrimary.withValues(alpha: 0.2),
              ),
              // Right side: dropdown
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
        // BPM display
        BpmDisplay(
          bpm: widget.originalBpm,
          onBpmChanged: isEnabled ? widget.onOriginalBpmChanged : null,
          enabled: isEnabled,
        ),
        const SizedBox(width: 4),
        // ÷2 button
        _buildActionButton(context, '÷2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call((widget.originalBpm / 2).clamp(20, 999));
        }),
        const SizedBox(width: 2),
        // ×2 button
        _buildActionButton(context, '×2', false, isEnabled, () {
          widget.onOriginalBpmChanged?.call((widget.originalBpm * 2).clamp(20, 999));
        }),
        const SizedBox(width: 4),
        // Reverse toggle
        _buildActionButton(context, 'Reverse', widget.reversed, true, widget.onReverseToggle),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, String label, bool isActive, bool enabled, VoidCallback? onTap) {
    final colors = context.colors;

    return Tooltip(
      message: label,
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

  // ============================================================================
  // Pitch control — reuses DraggablePitchDisplay
  // ============================================================================

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

  // ============================================================================
  // Volume control — same curve as Audio Editor
  // ============================================================================

  Widget _buildVolumeControl(BuildContext context) {
    final colors = context.colors;
    final sliderValue = _dbToSlider(widget.volumeDb);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Volume', style: TextStyle(color: colors.textMuted, fontSize: 9)),
        const SizedBox(width: 4),
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Text(
            widget.volumeDb <= -70
                ? '-\u221E dB'
                : '${widget.volumeDb.toStringAsFixed(1)} dB',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: colors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 120,
          height: 20,
          child: CapsuleSlider(
            value: sliderValue,
            onChanged: (value) {
              final db = _sliderToDb(value);
              widget.onVolumeChanged?.call(db);
            },
            onDoubleTap: () => widget.onVolumeChanged?.call(0.0),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // Load button
  // ============================================================================

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
              border: Border.all(color: colors.surface, width: 1),
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
  // Overlays
  // ============================================================================

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
          Positioned.fill(
            child: GestureDetector(
              onTap: _removeRootNoteOverlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),
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

  // ============================================================================
  // Helpers
  // ============================================================================

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

// ============================================================================
// Warp mode overlay menu
// ============================================================================

class _WarpModeMenuOverlay extends StatelessWidget {
  final Offset position;
  final int currentMode; // 0=repitch, 1=warp
  final Function(int) onModeSelected;
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
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
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
                  _buildMenuItem(context, 'Warp', 'Time-stretch, pitch preserved', 1),
                  _buildMenuItem(context, 'Re-Pitch', 'Speed changes pitch', 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(BuildContext context, String label, String description, int mode) {
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
