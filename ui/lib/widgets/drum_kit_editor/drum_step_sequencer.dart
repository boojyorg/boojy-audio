import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/drum_kit_info.dart';
import '../../models/library_item.dart';
import '../../models/midi_note_data.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../capsule_fader.dart';
import '../volume_readout_box.dart';

/// The right-hand pane of the Drum Kit editor: one row per pad
/// (colour swatch + name + compact fader + Mute/Solo) followed by a 1/16 step
/// grid. Clicking a cell toggles a note at the pad's pinned pitch; the grid
/// auto-grows in 16-step blocks as the clip lengthens.
///
/// Stateless by design — all mutation flows up through the callbacks so the
/// editor owns the clip + undo, mirroring how the piano roll persists edits.
///
/// Layout note: the left control column is frozen while the ruler and every
/// step row share a single horizontal scroll, so they can never drift apart.
class DrumStepSequencer extends StatelessWidget {
  final DrumKitInfo kit;
  final MidiClipData? clipData;
  final int selectedPadIndex;
  final int stepCount;
  final int beatsPerBar;

  /// Project tempo (BPM) — maps playhead seconds to a 1/16 step.
  final double tempo;

  /// Playback position in seconds; drives the playing-column highlight. Null
  /// disables the highlight.
  final ValueListenable<double>? playheadNotifier;

  /// Single source of truth for a pad's colour (shared with the grid + piano roll).
  final Color Function(int padIndex) padColor;

  final void Function(int padIndex) onPadSelected;
  final void Function(int padIndex, String filePath) onPadSampleDropped;
  final void Function(int pinnedNote, int stepIndex) onToggleStep;
  final VoidCallback onAddPad;
  final void Function(int padIndex, double db) onPadVolumeChanged;
  final void Function(int padIndex)? onPadVolumeDragStart;
  final void Function(int padIndex)? onPadVolumeDragEnd;
  final void Function(int padIndex) onPadMuteToggle;
  final void Function(int padIndex) onPadSoloToggle;

  const DrumStepSequencer({
    super.key,
    required this.kit,
    required this.clipData,
    required this.selectedPadIndex,
    required this.stepCount,
    required this.beatsPerBar,
    required this.tempo,
    required this.padColor,
    required this.onPadSelected,
    required this.onPadSampleDropped,
    required this.onToggleStep,
    required this.onAddPad,
    required this.onPadVolumeChanged,
    required this.onPadMuteToggle,
    required this.onPadSoloToggle,
    this.playheadNotifier,
    this.onPadVolumeDragStart,
    this.onPadVolumeDragEnd,
  });

  static const double _rowHeight = 34;
  static const double _controlWidth = 232;
  static const double _rulerHeight = 20;
  static const double _cellSize = 24;
  static const double _cellGap = 3;

  int get _stepsPerBeat => 4; // 1/16 grid
  int get _stepsPerBar => beatsPerBar * _stepsPerBeat;

  /// Extra left gap so beats and bars read as visual groups. Shared by the
  /// ruler and every pad row to keep them pixel-aligned.
  double _leftGapFor(int step) {
    if (step == 0) return 0;
    if (step % _stepsPerBar == 0) return _cellGap * 4; // bar boundary
    if (step % _stepsPerBeat == 0) return _cellGap * 2; // beat boundary
    return 0;
  }

  /// Active steps per pinned note (a note quantised to its 1/16 step index).
  Map<int, Set<int>> _activeSteps() {
    final map = <int, Set<int>>{};
    final clip = clipData;
    if (clip == null) return map;
    for (final note in clip.notes) {
      final step = (note.startTime / 0.25).round();
      (map[note.note] ??= <int>{}).add(step);
    }
    return map;
  }

  /// The playing 1/16 step (wrapped to the clip's loop), or -1 when stopped /
  /// no playhead. step 0 only lights once playback has advanced past 0, so a
  /// stopped playhead at the start shows no highlight.
  int _currentStep(double seconds) {
    if (seconds <= 0 || tempo <= 0) return -1;
    final loopBeats = clipData?.loopLength ?? beatsPerBar.toDouble();
    final loopSteps = (loopBeats * _stepsPerBeat).round();
    if (loopSteps <= 0) return -1;
    final step = (seconds * tempo / 60.0 * _stepsPerBeat).floor();
    if (step < 0) return -1;
    return step % loopSteps;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = _activeSteps();
    final notifier = playheadNotifier;

    return ColoredBox(
      color: colors.darkest,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Frozen control column.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildControlHeader(context),
                for (final pad in kit.pads) _buildPadControls(context, pad),
                _buildAddPadRow(context),
              ],
            ),
            // Shared horizontal scroll: ruler + every step row move together.
            // The grid rebuilds on the playhead notifier so only it repaints.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: notifier == null
                    ? _buildGrid(context, active, -1)
                    : ValueListenableBuilder<double>(
                        valueListenable: notifier,
                        builder: (context, seconds, _) =>
                            _buildGrid(context, active, _currentStep(seconds)),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    Map<int, Set<int>> active,
    int currentStep,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepRuler(context, currentStep),
        for (final pad in kit.pads)
          _buildStepRow(
            context,
            pad,
            active[pad.pinnedNote] ?? const {},
            currentStep,
          ),
      ],
    );
  }

  // ---- Frozen control column ----------------------------------------------

  Widget _buildControlHeader(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: _controlWidth,
      height: _rulerHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
    );
  }

  Widget _buildPadControls(BuildContext context, DrumPadInfo pad) {
    final colors = context.colors;
    final isSelected = pad.padIndex == selectedPadIndex;
    final color = padColor(pad.padIndex);

    // Each row is a drop target so a Library sound can land straight on the pad
    // without first selecting it. The left waveform box still works too.
    return DragTarget<AudioFileItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          onPadSampleDropped(pad.padIndex, details.data.filePath),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return GestureDetector(
          onTap: () => onPadSelected(pad.padIndex),
          child: Container(
            width: _controlWidth,
            height: _rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hovering
                  ? colors.accent.withValues(alpha: 0.18)
                  : (isSelected ? colors.surface.withValues(alpha: 0.5) : null),
              border: Border(
                bottom: BorderSide(color: colors.divider, width: 0.5),
                left: BorderSide(
                  color: hovering ? colors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                // Colour swatch — shared with grid cells + piano-roll notes.
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: colors.textPrimary, width: 1.5)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pad.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? colors.textPrimary
                          : colors.textSecondary,
                      fontSize: BT.fontLabel,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Compact reuse of the mixer fader + dB readout.
                SizedBox(
                  width: 56,
                  height: 14,
                  child: CapsuleFader(
                    leftLevel: 0,
                    rightLevel: 0,
                    volumeDb: pad.volumeDb,
                    onVolumeChanged: (db) =>
                        onPadVolumeChanged(pad.padIndex, db),
                    onDragStart: () => onPadVolumeDragStart?.call(pad.padIndex),
                    onDragEnd: () => onPadVolumeDragEnd?.call(pad.padIndex),
                    onDoubleTap: () => onPadVolumeChanged(pad.padIndex, 0),
                  ),
                ),
                const SizedBox(width: 4),
                VolumeReadoutBox(
                  volumeDb: pad.volumeDb,
                  onVolumeChanged: (db) => onPadVolumeChanged(pad.padIndex, db),
                  onVolumeDragStart: () =>
                      onPadVolumeDragStart?.call(pad.padIndex),
                  onVolumeDragEnd: () => onPadVolumeDragEnd?.call(pad.padIndex),
                  width: 34,
                  fontSize: BT.fontLabel,
                  textColor: colors.textSecondary,
                  showSuffix: false,
                ),
                const SizedBox(width: 4),
                _roundButton(
                  context,
                  'M',
                  pad.muted,
                  colors.muteActive,
                  () => onPadMuteToggle(pad.padIndex),
                ),
                const SizedBox(width: 3),
                _roundButton(
                  context,
                  'S',
                  pad.soloed,
                  colors.soloActive,
                  () => onPadSoloToggle(pad.padIndex),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Round Mute/Solo button — mirrors the mixer strip's control-button pattern.
  Widget _roundButton(
    BuildContext context,
    String label,
    bool isActive,
    Color activeColor,
    VoidCallback onPressed,
  ) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isActive ? activeColor : colors.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? colors.darkest : colors.textSecondary,
              fontSize: 9,
              fontWeight: BT.weightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPadRow(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onAddPad,
      child: Container(
        width: _controlWidth,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(BI.add, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Add pad',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: BT.fontLabel,
                fontWeight: BT.weightMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Scrollable step grid -----------------------------------------------

  /// Bar number ruler aligned to the step grid. The playing step gets a small
  /// white tick so the column reads as a playhead above the cells.
  Widget _buildStepRuler(BuildContext context, int currentStep) {
    final colors = context.colors;
    return Container(
      height: _rulerHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          for (int s = 0; s < stepCount; s++)
            Container(
              width: _cellSize,
              margin: EdgeInsets.only(right: _cellGap, left: _leftGapFor(s)),
              alignment: Alignment.bottomCenter,
              child: s == currentStep
                  ? Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: colors.textPrimary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : (s % _stepsPerBar == 0
                        ? Align(
                            alignment: Alignment.center,
                            child: Text(
                              '${s ~/ _stepsPerBar + 1}',
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: BT.fontLabel,
                                fontWeight: BT.weightMedium,
                              ),
                            ),
                          )
                        : null),
            ),
        ],
      ),
    );
  }

  Widget _buildStepRow(
    BuildContext context,
    DrumPadInfo pad,
    Set<int> activeSteps,
    int currentStep,
  ) {
    final colors = context.colors;
    final color = padColor(pad.padIndex);
    return Container(
      height: _rowHeight,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          for (int s = 0; s < stepCount; s++)
            _buildCell(
              context,
              pad: pad,
              step: s,
              isOn: activeSteps.contains(s),
              color: color,
              isPlaying: s == currentStep,
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required DrumPadInfo pad,
    required int step,
    required bool isOn,
    required Color color,
    required bool isPlaying,
  }) {
    final colors = context.colors;
    final isDownbeat = step % _stepsPerBeat == 0;
    return Padding(
      padding: EdgeInsets.only(right: _cellGap, left: _leftGapFor(step)),
      child: GestureDetector(
        onTap: () => onToggleStep(pad.pinnedNote, step),
        child: Container(
          width: _cellSize,
          height: _cellSize - 6,
          decoration: BoxDecoration(
            color: isOn
                ? color
                : (isDownbeat
                      ? colors.surface
                      : colors.surface.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(3),
            // White outline on the playing column (GarageBand-style), else the
            // pad colour when on, otherwise the faint grid line.
            border: Border.all(
              color: isPlaying
                  ? colors.textPrimary
                  : (isOn ? color : colors.divider),
              width: isPlaying ? 1.5 : 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
