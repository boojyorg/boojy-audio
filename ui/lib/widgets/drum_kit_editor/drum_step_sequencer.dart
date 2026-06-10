import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
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
/// grid. Clicking a cell toggles a note at the pad's pinned pitch; dragging
/// across a row paints (first cell empty) or erases (first cell filled) every
/// cell crossed. The grid auto-grows in 16-step blocks as the clip lengthens.
///
/// Stateless by design — all mutation flows up through the callbacks so the
/// editor owns the clip + undo, mirroring how the piano roll persists edits.
/// Only the transient drag-to-paint gesture keeps local state, inside each
/// [_PadStepRow].
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

  /// Live (no-undo) apply of the working clip while a drag-to-paint gesture is
  /// in progress. Wire together with [onPaintCommitted] so a whole drag
  /// coalesces into one undo step; when either is null the gesture falls back
  /// to per-cell [onToggleStep] calls (one undo entry per cell).
  final void Function(MidiClipData clip)? onPaintClipChanged;

  /// Commit one finished drag-to-paint gesture as a single undo step
  /// (snapshot `before` → `after`).
  final void Function(MidiClipData before, MidiClipData after)?
  onPaintCommitted;

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
    this.onPaintClipChanged,
    this.onPaintCommitted,
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
  static double _leftGapFor(int step, int stepsPerBar) {
    if (step == 0) return 0;
    if (step % stepsPerBar == 0) return _cellGap * 4; // bar boundary
    if (step % 4 == 0) return _cellGap * 2; // beat boundary
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
  /// no playhead / the clip isn't sounding. step 0 only lights once playback
  /// has advanced past 0, so a stopped playhead at the start shows no
  /// highlight.
  int _currentStep(double seconds) {
    if (seconds <= 0 || tempo <= 0) return -1;
    final clip = clipData;
    final loopBeats = clip?.loopLength ?? beatsPerBar.toDouble();
    final loopSteps = (loopBeats * _stepsPerBeat).round();
    if (loopSteps <= 0) return -1;
    // Global transport seconds → global beats → clip-relative beats. The clip
    // only sounds between its arrangement start and end (startTime is in
    // beats for MIDI clips); outside that window no column is playing.
    final globalBeats = seconds * tempo / 60.0;
    final relBeats = globalBeats - (clip?.startTime ?? 0.0);
    if (relBeats < 0) return -1;
    if (clip != null && relBeats >= clip.totalDuration) return -1;
    // Content space: the clip's content starts contentStartOffset beats in,
    // so shift before mapping to a grid column.
    final localBeats = relBeats + (clip?.contentStartOffset ?? 0.0);
    final step = (localBeats * _stepsPerBeat).floor();
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
          _PadStepRow(
            key: ValueKey(pad.padIndex),
            pad: pad,
            clip: clipData,
            activeSteps: active[pad.pinnedNote] ?? const {},
            currentStep: currentStep,
            stepCount: stepCount,
            beatsPerBar: beatsPerBar,
            color: padColor(pad.padIndex),
            onToggleStep: onToggleStep,
            onPaintClipChanged: onPaintClipChanged,
            onPaintCommitted: onPaintCommitted,
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
              margin: EdgeInsets.only(
                right: _cellGap,
                left: _leftGapFor(s, _stepsPerBar),
              ),
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
}

/// One pad's step row: the cells plus the tap / drag-to-paint gesture. The
/// first cell touched by a drag decides the mode — empty → paint, filled →
/// erase — and every cell crossed is set to that mode. Holds only the
/// transient gesture state; the clip itself still lives with the editor.
class _PadStepRow extends StatefulWidget {
  final DrumPadInfo pad;
  final MidiClipData? clip;
  final Set<int> activeSteps;
  final int currentStep;
  final int stepCount;
  final int beatsPerBar;
  final Color color;
  final void Function(int pinnedNote, int stepIndex) onToggleStep;
  final void Function(MidiClipData clip)? onPaintClipChanged;
  final void Function(MidiClipData before, MidiClipData after)?
  onPaintCommitted;

  const _PadStepRow({
    super.key,
    required this.pad,
    required this.clip,
    required this.activeSteps,
    required this.currentStep,
    required this.stepCount,
    required this.beatsPerBar,
    required this.color,
    required this.onToggleStep,
    required this.onPaintClipChanged,
    required this.onPaintCommitted,
  });

  @override
  State<_PadStepRow> createState() => _PadStepRowState();
}

class _PadStepRowState extends State<_PadStepRow> {
  static const double _cellSize = DrumStepSequencer._cellSize;
  static const double _cellGap = DrumStepSequencer._cellGap;

  /// true = paint, false = erase, null = no drag in progress.
  bool? _paintMode;

  /// Cells already visited this drag (each is applied at most once).
  Set<int> _painted = <int>{};
  int? _lastStep;

  /// Pre-drag snapshot + live working clip, only while the coalescing
  /// callbacks are wired ([_coalesced]); the whole drag commits as one
  /// undo step on release.
  MidiClipData? _dragBefore;
  MidiClipData? _dragClip;

  int get _stepsPerBar => widget.beatsPerBar * 4;

  bool get _coalesced =>
      widget.onPaintClipChanged != null && widget.onPaintCommitted != null;

  /// The step under [dx] (row-local), or null on a beat/bar gap.
  int? _stepAt(double dx) {
    double x = 0;
    for (int s = 0; s < widget.stepCount; s++) {
      x += DrumStepSequencer._leftGapFor(s, _stepsPerBar);
      if (dx < x) return null; // in the gap before this cell
      if (dx < x + _cellSize) return s;
      x += _cellSize + _cellGap;
    }
    return null;
  }

  /// Active steps for this pad computed from [clip] (drag-local view).
  Set<int> _activeFromClip(MidiClipData clip) => <int>{
    for (final n in clip.notes)
      if (n.note == widget.pad.pinnedNote) (n.startTime / 0.25).round(),
  };

  /// [clip] with this pad's note at [step] set on/off, growing the loop in
  /// whole-bar blocks on add — mirrors the editor's single-tap toggle.
  MidiClipData _clipWithStep(MidiClipData clip, int step, bool on) {
    final stepBeats = step * 0.25;
    if (!on) {
      final newNotes = clip.notes
          .where(
            (n) =>
                n.note != widget.pad.pinnedNote ||
                (n.startTime - stepBeats).abs() >= 0.001,
          )
          .toList();
      return clip.copyWith(notes: newNotes);
    }
    final note = MidiNoteData(
      note: widget.pad.pinnedNote,
      velocity: 100,
      startTime: stepBeats,
      duration: 0.25,
    );
    final neededBeats = (step + 1) * 0.25;
    final bar = widget.beatsPerBar.toDouble();
    final grown = (neededBeats / bar).ceil() * bar;
    final newLoopLength = math.max(clip.loopLength, grown);
    final newDuration = math.max(clip.duration, newLoopLength);
    return clip.copyWith(
      notes: [...clip.notes, note],
      loopLength: newLoopLength,
      duration: newDuration,
    );
  }

  void _beginPaint(double dx) {
    final step = _stepAt(dx);
    if (step == null) return;
    _paintMode = !widget.activeSteps.contains(step);
    _painted = {step};
    _lastStep = step;
    if (_coalesced && widget.clip != null) {
      _dragBefore = widget.clip;
      _dragClip = widget.clip;
    }
    _applyPaint(step);
  }

  void _continuePaint(double dx) {
    if (_paintMode == null) return;
    final step = _stepAt(dx);
    // In a beat/bar gap: keep _lastStep as the last real cell. Safe because
    // the row is 1-D — any later span min(_lastStep, step)..max(_lastStep,
    // step) only covers cells the pointer physically crossed, and _painted
    // dedups cells already applied this drag.
    if (step == null) return;
    // Fill the whole span since the last event so fast drags can't skip cells.
    final last = _lastStep ?? step;
    final lo = math.min(last, step);
    final hi = math.max(last, step);
    for (int s = lo; s <= hi; s++) {
      if (_painted.add(s)) _applyPaint(s);
    }
    _lastStep = step;
  }

  void _applyPaint(int step) {
    final on = _paintMode;
    if (on == null) return;
    final dragClip = _dragClip;
    if (dragClip != null) {
      // Coalesced path: mutate the local working clip, live-apply upstream
      // with no undo entry; one snapshot command is committed on release.
      if (_activeFromClip(dragClip).contains(step) == on) return;
      final next = _clipWithStep(dragClip, step, on);
      setState(() => _dragClip = next);
      widget.onPaintClipChanged?.call(next);
    } else {
      // Fallback: per-cell toggle through the editor (one undo entry each).
      if (widget.activeSteps.contains(step) == on) return;
      widget.onToggleStep(widget.pad.pinnedNote, step);
    }
  }

  void _endPaint() {
    if (_paintMode == null) return;
    final before = _dragBefore;
    final after = _dragClip;
    setState(() {
      _paintMode = null;
      _painted = <int>{};
      _lastStep = null;
      _dragBefore = null;
      _dragClip = null;
    });
    if (before != null && after != null && !identical(before, after)) {
      widget.onPaintCommitted?.call(before, after);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dragClip = _dragClip;
    final active = dragClip == null
        ? widget.activeSteps
        : _activeFromClip(dragClip);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Report the drag from the pointer-down position so the cell the user
      // first touched — not the one after the drag slop — decides the mode.
      dragStartBehavior: DragStartBehavior.down,
      onTapUp: (d) {
        final step = _stepAt(d.localPosition.dx);
        if (step != null) widget.onToggleStep(widget.pad.pinnedNote, step);
      },
      onPanStart: (d) => _beginPaint(d.localPosition.dx),
      onPanUpdate: (d) => _continuePaint(d.localPosition.dx),
      onPanEnd: (_) => _endPaint(),
      onPanCancel: _endPaint,
      child: Container(
        height: DrumStepSequencer._rowHeight,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            for (int s = 0; s < widget.stepCount; s++)
              _buildCell(
                context,
                step: s,
                isOn: active.contains(s),
                isPlaying: s == widget.currentStep,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(
    BuildContext context, {
    required int step,
    required bool isOn,
    required bool isPlaying,
  }) {
    final colors = context.colors;
    final isDownbeat = step % 4 == 0;
    return Padding(
      padding: EdgeInsets.only(
        right: _cellGap,
        left: DrumStepSequencer._leftGapFor(step, _stepsPerBar),
      ),
      child: Container(
        width: _cellSize,
        height: _cellSize - 6,
        decoration: BoxDecoration(
          color: isOn
              ? widget.color
              : (isDownbeat
                    ? colors.surface
                    : colors.surface.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(3),
          // White outline on the playing column (GarageBand-style), else the
          // pad colour when on, otherwise the faint grid line.
          border: Border.all(
            color: isPlaying
                ? colors.textPrimary
                : (isOn ? widget.color : colors.divider),
            width: isPlaying ? 1.5 : 0.5,
          ),
        ),
      ),
    );
  }
}
