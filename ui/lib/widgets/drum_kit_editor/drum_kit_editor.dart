import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../audio_engine.dart';
import '../../models/drum_kit_info.dart';
import '../../models/library_item.dart';
import '../../models/midi_note_data.dart';
import '../../services/commands/clip_commands.dart';
import '../../services/commands/command.dart';
import '../../services/commands/drum_pad_commands.dart';
import '../../services/undo_redo_manager.dart';
import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../utils/track_colors.dart';
import '../shared/editors/capsule_slider.dart';
import '../pan_knob.dart';
import 'drum_step_sequencer.dart';

/// Single source of truth for a pad's colour — shared by the sequencer row
/// swatch, the grid cells, and (later) the piano-roll notes at the pad's pitch.
Color drumPadColor(int padIndex) =>
    TrackColors.manualPalette[padIndex % TrackColors.manualPalette.length];

/// Tab 0 of a drum-kit track: Layout A — a per-pad detail panel on the left and
/// the step sequencer on the right. A drum hit is an ordinary MIDI note at the
/// pad's pinned pitch, so the grid writes to the same clip the piano roll edits.
class DrumKitEditor extends StatefulWidget {
  final AudioEngine? audioEngine;
  final int? trackId;
  final MidiClipData? clipData;
  final void Function(MidiClipData)? onClipUpdated;
  final UndoRedoManager? undoManager;
  final int beatsPerBar;

  /// Playback position in seconds (shared with the timeline playhead). Drives
  /// the step-column highlight; null on platforms without playback.
  final ValueListenable<double>? playheadNotifier;

  /// Project tempo (BPM), used to map the playhead seconds to a 1/16 step.
  final double tempo;

  const DrumKitEditor({
    super.key,
    required this.audioEngine,
    required this.trackId,
    required this.clipData,
    required this.onClipUpdated,
    required this.undoManager,
    this.beatsPerBar = 4,
    this.playheadNotifier,
    this.tempo = 120.0,
  });

  @override
  State<DrumKitEditor> createState() => _DrumKitEditorState();
}

class _DrumKitEditorState extends State<DrumKitEditor> {
  static const double _detailWidth = 264;
  static const int _waveformResolution = 1024;
  // Control ranges (ms) for the slider mappings.
  static const double _attackMaxMs = 200;
  static const double _decayMaxMs = 2000;

  DrumKitInfo? _kit;
  int _selectedPadIndex = 0;

  // Waveform cache for the selected pad only (reloaded when the pad/sample changes).
  List<double> _waveformPeaks = const [];
  int _waveformPadIndex = -1;

  @override
  void initState() {
    super.initState();
    _refreshKit(selectFirst: true);
  }

  @override
  void didUpdateWidget(DrumKitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _refreshKit(selectFirst: true);
    }
  }

  DrumPadInfo? get _selectedPad {
    final pads = _kit?.pads;
    if (pads == null) return null;
    for (final p in pads) {
      if (p.padIndex == _selectedPadIndex) return p;
    }
    return pads.isNotEmpty ? pads.first : null;
  }

  void _refreshKit({bool selectFirst = false}) {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    if (engine == null || tid == null) return;
    final kit = engine.getDrumKitInfo(tid);
    setState(() {
      _kit = kit;
      if (kit != null && kit.pads.isNotEmpty) {
        final hasSelected = kit.pads.any(
          (p) => p.padIndex == _selectedPadIndex,
        );
        if (selectFirst || !hasSelected) {
          _selectedPadIndex = kit.pads.first.padIndex;
        }
      }
    });
    _loadWaveformForSelected(force: true);
  }

  void _loadWaveformForSelected({bool force = false}) {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    final pad = _selectedPad;
    if (engine == null || tid == null || pad == null) {
      setState(() {
        _waveformPeaks = const [];
        _waveformPadIndex = -1;
      });
      return;
    }
    if (!force && pad.padIndex == _waveformPadIndex) return;
    final peaks = pad.hasSample
        ? engine.getDrumPadWaveformPeaks(tid, pad.padIndex, _waveformResolution)
        : const <double>[];
    setState(() {
      _waveformPeaks = peaks;
      _waveformPadIndex = pad.padIndex;
    });
  }

  // ---- Engine writes -------------------------------------------------------

  // Active continuous gesture (slider/knob drag) coalesced into one undo step.
  String? _gestureParamKey;
  String? _gestureOldValue;
  int? _gesturePadIndex;

  /// Live engine write + optimistic local update, with no undo entry. Used
  /// during a drag and for the mixer-row volume/mute/solo (kept fire-and-forget
  /// this cycle).
  void _setPadParam(String key, String value, DrumPadInfo optimistic) {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    if (engine == null || tid == null) return;
    engine.setDrumPadParameter(tid, optimistic.padIndex, key, value);
    setState(() => _kit = _kit?.withPad(optimistic));
  }

  /// Re-read the kit from the engine after an undo/redo so the on-screen
  /// controls reflect the reverted value (no waveform reload — params don't
  /// change the sample).
  void _syncKitFromEngine() {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    if (engine == null || tid == null) return;
    final kit = engine.getDrumKitInfo(tid);
    if (mounted) setState(() => _kit = kit);
  }

  /// Current stringified value of [key] on [pad], formatted exactly like the
  /// live setters so old/new comparisons are stable.
  String _padParamValueString(DrumPadInfo pad, String key) {
    switch (key) {
      case 'attack_ms':
        return pad.attackMs.toStringAsFixed(1);
      case 'release_ms':
        return pad.releaseMs.toStringAsFixed(1);
      case 'transpose_semitones':
        return pad.transposeSemitones.toString();
      case 'reversed':
        return pad.reversed.toString();
      case 'pan':
        return pad.pan.toStringAsFixed(3);
      default:
        return '';
    }
  }

  /// Snapshot the pre-gesture value when a drag begins. A tap that becomes a
  /// drag re-enters with the same pad+key — keep the original old value so the
  /// whole drag is one undo step. A different control resets cleanly.
  void _beginPadGesture(int padIndex, String key) {
    if (_gestureParamKey == key && _gesturePadIndex == padIndex) return;
    final pad = _padByIndex(padIndex);
    _gesturePadIndex = padIndex;
    _gestureParamKey = key;
    _gestureOldValue = pad == null ? null : _padParamValueString(pad, key);
  }

  /// Commit the gesture as a single undoable command (old → final value).
  void _endPadGesture() {
    final key = _gestureParamKey;
    final old = _gestureOldValue;
    final padIndex = _gesturePadIndex;
    _gestureParamKey = null;
    _gestureOldValue = null;
    _gesturePadIndex = null;
    if (key == null || old == null || padIndex == null) return;
    final pad = _padByIndex(padIndex);
    if (pad == null) return;
    _pushPadParamCommand(padIndex, key, old, _padParamValueString(pad, key));
  }

  /// Discrete one-shot change (Pitch step, Reverse toggle): apply live, then
  /// record a single undo entry.
  void _commitDiscretePadParam(
    int padIndex,
    String key,
    String oldValue,
    String newValue,
    DrumPadInfo optimistic,
  ) {
    _setPadParam(key, newValue, optimistic);
    _pushPadParamCommand(padIndex, key, oldValue, newValue);
  }

  void _pushPadParamCommand(
    int padIndex,
    String key,
    String oldValue,
    String newValue,
  ) {
    final tid = widget.trackId;
    if (tid == null || oldValue == newValue) return;
    final mgr = widget.undoManager;
    if (mgr == null) {
      // No undo manager wired: the live apply already happened.
      return;
    }
    unawaited(
      mgr.execute(
        SetDrumPadParameterCommand(
          trackId: tid,
          padIndex: padIndex,
          paramName: key,
          oldValue: oldValue,
          newValue: newValue,
          onApplied: _syncKitFromEngine,
        ),
      ),
    );
  }

  Future<void> _loadSampleInto(int padIndex, String path) async {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    if (engine == null || tid == null) return;
    engine.loadDrumPadSample(tid, padIndex, path);
    _refreshKit();
  }

  Future<void> _pickSampleForSelected() async {
    final pad = _selectedPad;
    if (pad == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'flac', 'aif', 'aiff'],
      dialogTitle: 'Select Drum Sample',
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        await _loadSampleInto(pad.padIndex, path);
      }
    }
  }

  void _addPad() {
    final engine = widget.audioEngine;
    final tid = widget.trackId;
    if (engine == null || tid == null) return;
    // Pin the new pad to the next free note after the highest existing pad,
    // defaulting to MIDI 36 (a typical kick) for an empty kit.
    final pads = _kit?.pads ?? const [];
    final start = pads.isEmpty
        ? 36
        : pads.map((p) => p.pinnedNote).reduce(math.max) + 1;
    final note = engine.drumNextFreeNote(tid, start);
    if (note < 0) return;
    final padIndex = engine.addDrumPad(tid, note);
    if (padIndex < 0) return;
    setState(() => _selectedPadIndex = padIndex);
    _refreshKit();
  }

  // ---- Step toggling (writes to the shared MIDI clip, undoable) ------------

  void _toggleStep(int pinnedNote, int stepIndex) {
    final clip = widget.clipData;
    if (clip == null) return;
    final stepBeats = stepIndex * 0.25;

    MidiNoteData? existing;
    for (final n in clip.notes) {
      if (n.note == pinnedNote && (n.startTime - stepBeats).abs() < 0.001) {
        existing = n;
        break;
      }
    }

    if (existing != null) {
      final newNotes = clip.notes.where((n) => n.id != existing!.id).toList();
      final after = clip.copyWith(notes: newNotes);
      _runClipCommand(
        DeleteMidiNotesCommand(
          clipBefore: clip,
          clipAfter: after,
          noteCount: 1,
          onApplyState: _applyClip,
        ),
        after,
      );
    } else {
      final note = MidiNoteData(
        note: pinnedNote,
        velocity: 100,
        startTime: stepBeats,
        duration: 0.25,
      );
      // Auto-grow the clip in whole-bar blocks so the loop follows the pattern.
      final neededBeats = (stepIndex + 1) * 0.25;
      final bar = widget.beatsPerBar.toDouble();
      final grown = (neededBeats / bar).ceil() * bar;
      final newLoopLength = math.max(clip.loopLength, grown);
      final newDuration = math.max(clip.duration, newLoopLength);
      final after = clip.copyWith(
        notes: [...clip.notes, note],
        loopLength: newLoopLength,
        duration: newDuration,
      );
      _runClipCommand(
        AddMidiNoteCommand(
          clipBefore: clip,
          clipAfter: after,
          addedNote: note,
          onApplyState: _applyClip,
        ),
        after,
      );
    }
  }

  void _applyClip(MidiClipData clip) => widget.onClipUpdated?.call(clip);

  void _runClipCommand(Command command, MidiClipData fallbackAfter) {
    final mgr = widget.undoManager;
    if (mgr != null) {
      unawaited(mgr.execute(command));
    } else {
      _applyClip(fallbackAfter);
    }
  }

  // ---- Build ---------------------------------------------------------------

  int get _stepCount {
    final loopBeats =
        widget.clipData?.loopLength ?? widget.beatsPerBar.toDouble();
    final steps = (loopBeats * 4).round();
    final blocks = (steps / 16).ceil().clamp(1, 64);
    return blocks * 16;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final kit = _kit;

    return ColoredBox(
      color: colors.darkest,
      child: Row(
        children: [
          SizedBox(width: _detailWidth, child: _buildDetailPanel(context)),
          Container(width: 1, color: colors.divider),
          Expanded(
            child: (kit == null || kit.pads.isEmpty)
                ? _buildEmptyKitCta(context)
                : DrumStepSequencer(
                    kit: kit,
                    clipData: widget.clipData,
                    selectedPadIndex: _selectedPadIndex,
                    stepCount: _stepCount,
                    beatsPerBar: widget.beatsPerBar,
                    tempo: widget.tempo,
                    playheadNotifier: widget.playheadNotifier,
                    padColor: drumPadColor,
                    onPadSelected: (i) {
                      setState(() => _selectedPadIndex = i);
                      _loadWaveformForSelected();
                    },
                    onPadSampleDropped: (i, path) {
                      setState(() => _selectedPadIndex = i);
                      _loadSampleInto(i, path);
                    },
                    onToggleStep: _toggleStep,
                    onAddPad: _addPad,
                    onPadVolumeChanged: (i, db) {
                      final pad = _padByIndex(i);
                      if (pad != null) {
                        _setPadParam(
                          'volume_db',
                          db.toStringAsFixed(2),
                          pad.copyWith(volumeDb: db),
                        );
                      }
                    },
                    onPadMuteToggle: (i) {
                      final pad = _padByIndex(i);
                      if (pad != null) {
                        _setPadParam(
                          'muted',
                          (!pad.muted).toString(),
                          pad.copyWith(muted: !pad.muted),
                        );
                      }
                    },
                    onPadSoloToggle: (i) {
                      final pad = _padByIndex(i);
                      if (pad != null) {
                        _setPadParam(
                          'soloed',
                          (!pad.soloed).toString(),
                          pad.copyWith(soloed: !pad.soloed),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  DrumPadInfo? _padByIndex(int padIndex) {
    for (final p in _kit?.pads ?? const <DrumPadInfo>[]) {
      if (p.padIndex == padIndex) return p;
    }
    return null;
  }

  Widget _buildEmptyKitCta(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(BI.gridOn, size: 48, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Drag a sound here or tap + to start',
            style: TextStyle(color: colors.textMuted, fontSize: BT.fontBody),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context) {
    final colors = context.colors;
    final pad = _selectedPad;

    if (pad == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No pad selected',
            style: TextStyle(color: colors.textMuted, fontSize: BT.fontLabel),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pad title.
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: drumPadColor(pad.padIndex),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pad.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: BT.fontBody,
                    fontWeight: BT.weightSemiBold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Control block (all controls grouped above the waveform).
          _buildSliderControl(
            context,
            'Attack',
            (pad.attackMs / _attackMaxMs).clamp(0.0, 1.0),
            (v) => _setPadParam(
              'attack_ms',
              (v * _attackMaxMs).toStringAsFixed(1),
              pad.copyWith(attackMs: v * _attackMaxMs),
            ),
            '${pad.attackMs.toStringAsFixed(0)} ms',
            onChangeStart: () => _beginPadGesture(pad.padIndex, 'attack_ms'),
            onChangeEnd: _endPadGesture,
          ),
          _buildSliderControl(
            context,
            'Decay',
            (pad.releaseMs / _decayMaxMs).clamp(0.0, 1.0),
            (v) => _setPadParam(
              'release_ms',
              (v * _decayMaxMs).toStringAsFixed(1),
              pad.copyWith(releaseMs: v * _decayMaxMs),
            ),
            '${pad.releaseMs.toStringAsFixed(0)} ms',
            onChangeStart: () => _beginPadGesture(pad.padIndex, 'release_ms'),
            onChangeEnd: _endPadGesture,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildPitchControl(context, pad),
              const Spacer(),
              _buildReverseToggle(context, pad),
              const SizedBox(width: 12),
              _buildPanControl(context, pad),
            ],
          ),
          const SizedBox(height: 12),
          // Waveform block — also the sample drop / click-to-load target.
          Expanded(child: _buildWaveformBlock(context, pad)),
        ],
      ),
    );
  }

  Widget _buildSliderControl(
    BuildContext context,
    String label,
    double value,
    ValueChanged<double> onChanged,
    String readout, {
    VoidCallback? onChangeStart,
    VoidCallback? onChangeEnd,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: BT.fontLabel,
                ),
              ),
              Text(
                readout,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: BT.fontLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            child: CapsuleSlider(
              value: value,
              onChanged: onChanged,
              onChangeStart: onChangeStart,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchControl(BuildContext context, DrumPadInfo pad) {
    final colors = context.colors;
    void bump(int delta) {
      final next = (pad.transposeSemitones + delta).clamp(-24, 24);
      _commitDiscretePadParam(
        pad.padIndex,
        'transpose_semitones',
        pad.transposeSemitones.toString(),
        next.toString(),
        pad.copyWith(transposeSemitones: next),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pitch',
          style: TextStyle(color: colors.textSecondary, fontSize: BT.fontLabel),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _stepperButton(context, BI.remove, () => bump(-1)),
            SizedBox(
              width: 38,
              child: Text(
                '${pad.transposeSemitones > 0 ? '+' : ''}${pad.transposeSemitones}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: BT.fontLabel,
                  fontWeight: BT.weightMedium,
                ),
              ),
            ),
            _stepperButton(context, BI.add, () => bump(1)),
          ],
        ),
      ],
    );
  }

  Widget _stepperButton(
    BuildContext context,
    IconData icon,
    VoidCallback onTap,
  ) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: colors.textSecondary),
      ),
    );
  }

  Widget _buildReverseToggle(BuildContext context, DrumPadInfo pad) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => _commitDiscretePadParam(
        pad.padIndex,
        'reversed',
        pad.reversed.toString(),
        (!pad.reversed).toString(),
        pad.copyWith(reversed: !pad.reversed),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: pad.reversed ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Reverse',
          style: TextStyle(
            color: pad.reversed ? colors.darkest : colors.textSecondary,
            fontSize: BT.fontLabel,
            fontWeight: BT.weightMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildPanControl(BuildContext context, DrumPadInfo pad) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Pan',
          style: TextStyle(color: colors.textSecondary, fontSize: BT.fontLabel),
        ),
        const SizedBox(height: 4),
        PanKnob(
          pan: pad.pan,
          size: 26,
          onDragStart: () => _beginPadGesture(pad.padIndex, 'pan'),
          onChanged: (v) =>
              _setPadParam('pan', v.toStringAsFixed(3), pad.copyWith(pan: v)),
          onDragEnd: _endPadGesture,
        ),
      ],
    );
  }

  Widget _buildWaveformBlock(BuildContext context, DrumPadInfo pad) {
    final colors = context.colors;
    return DragTarget<AudioFileItem>(
      onAcceptWithDetails: (details) =>
          _loadSampleInto(pad.padIndex, details.data.filePath),
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return GestureDetector(
          onTap: _pickSampleForSelected,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: highlight ? colors.accent : colors.divider,
                width: highlight ? 1.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _waveformPeaks.isEmpty
                ? Center(
                    child: Text(
                      pad.hasSample
                          ? 'No waveform'
                          : 'Drop a sound or click to load',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: BT.fontLabel,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _DrumPadWaveformPainter(
                      peaks: _waveformPeaks,
                      color: drumPadColor(pad.padIndex),
                      colors: colors,
                    ),
                    size: Size.infinite,
                  ),
          ),
        );
      },
    );
  }
}

/// Minimal centred waveform fill for a one-shot pad sample (no loop/beat chrome).
class _DrumPadWaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Color color;
  final BoojyColors colors;

  _DrumPadWaveformPainter({
    required this.peaks,
    required this.color,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final n = peaks.length;
    for (int x = 0; x < size.width; x++) {
      final i = (x / size.width * n).floor().clamp(0, n - 1);
      final amp = peaks[i].clamp(0.0, 1.0) * mid;
      canvas.drawLine(
        Offset(x.toDouble(), mid - amp),
        Offset(x.toDouble(), mid + amp),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DrumPadWaveformPainter old) =>
      old.peaks != peaks || old.color != color;
}
