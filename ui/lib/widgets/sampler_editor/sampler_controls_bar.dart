import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../shared/editors/capsule_slider.dart';

/// Slim controls bar for the Sampler editor — one row, beginner-first
/// (GarageBand Quick Sampler model):
///
/// [Loop] | Atk [══] 1ms  Rel [══] 50ms | Root [C4▾] | [Reverse] | Vol … | [Load]
///
/// The previous bar carried the whole Audio-Editor control set (Start/Length/
/// Sig, Warp/BPM/÷2/×2, Pitch) — clip-warping concepts that don't fit a
/// pitched instrument, several of which were stored-but-dead engine params.
/// They were cut by design (design_recs_2026_06_10.md §5); loop points are now
/// edited with handles on the waveform itself.
class SamplerControlsBar extends StatefulWidget {
  final bool loopEnabled;
  final VoidCallback? onLoopToggle;

  final double attackMs;
  final double releaseMs;
  final Function(double)? onAttackChanged;
  final Function(double)? onReleaseChanged;

  final int rootNote;
  final Function(int)? onRootNoteChanged;

  final bool reversed;
  final VoidCallback? onReverseToggle;

  final double volumeDb;
  final Function(double)? onVolumeChanged;
  final VoidCallback? onVolumeReset;

  final VoidCallback? onLoadSample;

  /// Coalesce slider drags into one undo step: fired with the engine param
  /// key ('attack_ms' / 'release_ms' / 'volume_db') when a drag begins/ends.
  final void Function(String param)? onParamGestureStart;
  final void Function(String param)? onParamGestureEnd;

  /// Hold-to-audition: ▶ press plays the sample at the root note, release
  /// stops it.
  final VoidCallback? onPreviewStart;
  final VoidCallback? onPreviewEnd;

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
    this.reversed = false,
    this.onReverseToggle,
    this.volumeDb = 0.0,
    this.onVolumeChanged,
    this.onVolumeReset,
    this.onLoadSample,
    this.onParamGestureStart,
    this.onParamGestureEnd,
    this.onPreviewStart,
    this.onPreviewEnd,
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
        border: Border(bottom: BorderSide(color: colors.surface, width: 1)),
      ),
      child: Row(
        children: [
          _buildToggleButton(
            context,
            label: 'Loop',
            icon: BI.loop,
            isActive: widget.loopEnabled,
            tooltip: widget.loopEnabled
                ? 'Loop On (1-shot off)'
                : 'Loop Off (1-shot mode)',
            onTap: widget.onLoopToggle,
          ),
          _buildSeparator(context),
          _buildEnvelopeGroup(context),
          _buildSeparator(context),
          _buildRootNoteGroup(context),
          const SizedBox(width: 6),
          _buildPreviewButton(context),
          _buildSeparator(context),
          _buildToggleButton(
            context,
            label: 'Reverse',
            isActive: widget.reversed,
            tooltip: 'Play the sample backwards',
            onTap: widget.onReverseToggle,
          ),
          _buildSeparator(context),
          // Expanded (not Flexible+Spacer): the volume group absorbs all
          // remaining width so Load stays visible at any panel width — the
          // Spacer variant gave the slider zero space when the bar got tight.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildVolumeControl(context),
            ),
          ),
          const SizedBox(width: 8),
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

  /// Toggle role: outline at rest, selection fill+border when active.
  Widget _buildToggleButton(
    BuildContext context, {
    required String label,
    required bool isActive,
    required String tooltip,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final colors = context.colors;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? colors.selectionFill : colors.dark,
              borderRadius: BorderRadius.circular(BT.radiusSm),
              border: Border.all(
                color: isActive ? colors.selectionBorder : colors.surface,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 13,
                    color: isActive ? colors.accent : colors.textPrimary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive && icon == null
                        ? colors.accent
                        : colors.textPrimary,
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

    Widget capsule({
      required String label,
      required String param,
      required double normalized,
      required void Function(double normalized)? onChanged,
      required String readout,
    }) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 52,
            height: 20,
            child: CapsuleSlider(
              value: normalized,
              onChanged: onChanged,
              onChangeStart: () => widget.onParamGestureStart?.call(param),
              onChangeEnd: () => widget.onParamGestureEnd?.call(param),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 38,
            child: Text(
              readout,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: BT.fontCaption,
                fontFamily: BT.fontFamilyMono,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        capsule(
          label: 'Atk',
          param: 'attack_ms',
          normalized: (widget.attackMs / 5000.0).clamp(0.0, 1.0),
          onChanged: (v) => widget.onAttackChanged?.call(v * 5000.0),
          readout: _formatMs(widget.attackMs),
        ),
        const SizedBox(width: 8),
        capsule(
          label: 'Rel',
          param: 'release_ms',
          normalized: (widget.releaseMs / 5000.0).clamp(0.0, 1.0),
          onChanged: (v) => widget.onReleaseChanged?.call(v * 5000.0),
          readout: _formatMs(widget.releaseMs),
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
        Text(
          'Root',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
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
                borderRadius: BorderRadius.circular(BT.radiusSm),
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
                      fontFamily: BT.fontFamilyMono,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(BI.caretDown, size: 14, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // Preview button — hold to hear the sample at the root note
  // ============================================================================

  Widget _buildPreviewButton(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Hold to preview at the root note',
      child: GestureDetector(
        onTapDown: (_) => widget.onPreviewStart?.call(),
        onTapUp: (_) => widget.onPreviewEnd?.call(),
        onTapCancel: () => widget.onPreviewEnd?.call(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: colors.dark,
              borderRadius: BorderRadius.circular(BT.radiusSm),
              border: Border.all(color: colors.surface, width: 1),
            ),
            child: Icon(BI.play, size: 13, color: colors.textPrimary),
          ),
        ),
      ),
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
        Text(
          'Volume',
          style: TextStyle(color: colors.textMuted, fontSize: BT.fontCaption),
        ),
        const SizedBox(width: 4),
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: colors.dark,
            borderRadius: BorderRadius.circular(BT.radiusSm),
            border: Border.all(color: colors.surface, width: 1),
          ),
          child: Text(
            widget.volumeDb <= -70
                ? '-∞ dB'
                : '${widget.volumeDb.toStringAsFixed(1)} dB',
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
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120, minWidth: 48),
            child: SizedBox(
              height: 20,
              child: CapsuleSlider(
                value: sliderValue,
                onChanged: (value) {
                  widget.onVolumeChanged?.call(_sliderToDb(value));
                },
                onDoubleTap: widget.onVolumeReset,
                onChangeStart: () =>
                    widget.onParamGestureStart?.call('volume_db'),
                onChangeEnd: () => widget.onParamGestureEnd?.call('volume_db'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // Load button (action role)
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
              borderRadius: BorderRadius.circular(BT.radiusSm),
              border: Border.all(color: colors.surface, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(BI.folderOpen, size: 13, color: colors.textPrimary),
                const SizedBox(width: 4),
                Text(
                  'Load',
                  style: TextStyle(fontSize: 10, color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Root note overlay
  // ============================================================================

  void _showRootNoteMenu() {
    _removeRootNoteOverlay();

    final renderBox =
        _rootNoteButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);

    _rootNoteOverlay = OverlayEntry(
      // The theme is read inside the overlay's builder — a build context —
      // never in this event handler. A listen:true read here is the
      // listen-outside-build debug assert that made this dropdown a silent
      // no-op in debug builds (bug-hunt #23).
      builder: (overlayContext) {
        final colors = overlayContext.colors;
        return Stack(
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
                borderRadius: BorderRadius.circular(BT.radiusMd),
                elevation: 8,
                child: Container(
                  width: 200,
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.divider),
                    borderRadius: BorderRadius.circular(BT.radiusMd),
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
                                        ? BT.weightSemiBold
                                        : BT.weightRegular,
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
        );
      },
    );

    Overlay.of(context).insert(_rootNoteOverlay!);
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
      'B',
    ];
    final octave = (note ~/ 12) - 1;
    final noteName = noteNames[note % 12];
    return '$noteName$octave';
  }
}
