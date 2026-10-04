import 'dart:math';

import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/models/track_data.dart';
import 'package:boojy_audio/services/commands/clip_commands.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:boojy_audio/utils/audio_clips_info.dart';
import 'package:boojy_audio/widgets/audio_editor/operations/parameter_operations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

// Random stress test: long seeded runs of real edits through the DAW, with
// the screen checked against the engine after every one; then undo
// everything, redo everything, save and reopen, and check nothing changed.
//
// A failure prints the seed and the actions so far; the same seed replays
// them exactly. CI runs the default seeds. For a longer local hunt:
//   fvm flutter test test/native/daw_stress_test.dart \
//     --dart-define=STRESS_SEEDS=1,2,3,4,5,6,7,8 --dart-define=STRESS_STEPS=200

const _seeds = String.fromEnvironment(
  'STRESS_SEEDS',
  defaultValue: '1,2,3,4,5',
);
const _steps = int.fromEnvironment('STRESS_STEPS', defaultValue: 60);

// Undo everything, then redo everything, and check the project returns to
// empty and back. On by default; --dart-define=STRESS_UNDO_ALL=false skips it
// (to look at a save/reopen failure on its own).
const _undoAll = bool.fromEnvironment('STRESS_UNDO_ALL', defaultValue: true);

void main() {
  if (!isNativeEngineAvailable) {
    test('DAW stress (native engine)', () {}, skip: true);
    return;
  }

  for (final seed in _seeds.split(',').map(int.parse)) {
    testWidgets('stress seed $seed ($_steps actions)', (tester) async {
      final h = await DawHarness.start(tester);
      try {
        await _StressRun(h, seed).run();
      } finally {
        await h.close();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

class _StressRun {
  _StressRun(this.h, this.seed) : random = Random(seed);

  final DawHarness h;
  final int seed;
  final Random random;
  final log = <String>[];
  var _files = 0;

  late final _actions = <(int, String, Future<bool> Function())>[
    (2, 'drop a file', _dropFile),
    (1, 'add a MIDI track', _addMidiTrack),
    (1, 'add a MIDI clip', _addMidiClip),
    (3, 'add a note', _addNote),
    (1, 'extend a MIDI clip to repeat', _extendMidiClip),
    (2, 'copy an audio clip', _copyAudioClip),
    (1, 'copy a MIDI clip', _copyMidiClip),
    (1, 'split a MIDI clip', _splitMidiClip),
    (1, 'delete an audio clip', _deleteAudioClip),
    (1, 'delete a MIDI clip', _deleteMidiClip),
    (2, 'edit an audio clip', _editAudioClip),
    (1, 'change tempo', _changeTempo),
    (1, 'duplicate a track', _duplicateTrack),
    (1, 'delete a track', _deleteTrack),
    (3, 'undo', _undo),
    (2, 'redo', _redo),
  ];

  List<ClipData> get _audioClips => h.daw.timelineKey.currentState!.clips;
  List<MidiClipData> get _midiClips => h.daw.midiPlaybackManager!.midiClips;
  List<TrackData> get _tracks => [
    for (final id in h.engine.getAllTrackIds())
      if (TrackData.fromCSV(h.engine.getTrackInfo(id)) case final t?
          when t.type != 'master')
        t,
  ];

  T? _pick<T>(List<T> items) =>
      items.isEmpty ? null : items[random.nextInt(items.length)];

  Future<void> run() async {
    final empty = _fingerprint();
    log.add('seed $seed, $_steps actions');
    final total = _actions.fold(0, (sum, a) => sum + a.$1);

    for (var step = 0; step < _steps; step++) {
      var roll = random.nextInt(total);
      final action = _actions.firstWhere((a) => (roll -= a.$1) < 0);
      if (await action.$3()) {
        log.add('${log.length + 1}. ${action.$2}');
        await h.settle(frames: 2, ms: 20);
        _check('${action.$2} (step ${step + 1})');
      }
    }
    final last = _fingerprint();
    if (_undoAll) await _undoAndRedoEverything(empty, last);
    await _saveAndReopen(last);
  }

  Future<void> _undoAndRedoEverything(
    List<String> empty,
    List<String> last,
  ) async {
    final undoRedo = h.daw.undoRedoManager;
    var undone = 0;
    while (undoRedo.canUndo) {
      undone++;
      log.add('undo all: ${undoRedo.undoDescription}');
      await h.daw.performUndo();
      await h.settle(frames: 2, ms: 20);
      _check('undoing everything');
    }
    _expectSame(_fingerprint(), empty, 'undoing everything');

    // Redo exactly what was undone: steps the run itself had undone and left
    // on the redo stack aren't part of where it ended.
    for (var i = 0; i < undone; i++) {
      log.add('redo all: ${undoRedo.redoDescription}');
      await h.daw.performRedo();
      await h.settle(frames: 2, ms: 20);
      _check('redoing everything');
    }
    _expectSame(_fingerprint(), last, 'redoing everything');
  }

  Future<void> _saveAndReopen(List<String> last) async {
    final path = '${h.tempDir.path}/Stress.audio';
    await h.realTime(() => h.daw.saveProjectToPath(path));
    await h.settleUntil(() => !h.daw.isLoading, what: 'the save');
    h.daw.executeNewProject();
    await h.settle();
    await h.realTime(() => h.daw.openRecentProject(path));
    await h.settleUntil(() => !h.daw.isLoading, what: 'the reopen');
    await h.settle();
    _check('saving and reopening');
    _expectSame(_fingerprint(), last, 'saving and reopening');
  }

  // --- Checks ---

  void _check(String after) {
    final problems = compareScreenWithEngine(
      engine: EngineSnapshot.read(h.engine),
      screenTempo: h.daw.tempo,
      audioClips: _audioClips,
      midiClips: _midiClips,
      midiEngineIds: h.daw.midiPlaybackManager!.dartToRustClipIds,
    );
    if (problems.isNotEmpty) {
      fail(
        'Seed $seed: screen and engine disagree after $after:\n'
        '  ${problems.join('\n  ')}\n'
        'Actions so far:\n  ${log.join('\n  ')}',
      );
    }
  }

  void _expectSame(List<String> got, List<String> want, String after) {
    if (got.join('\n') == want.join('\n')) return;
    // Count each line: two identical clips are a different project from one.
    Map<String, int> counts(List<String> lines) {
      final c = <String, int>{};
      for (final l in lines) {
        c[l] = (c[l] ?? 0) + 1;
      }
      return c;
    }

    final g = counts(got), w = counts(want);
    final missing = [
      for (final e in w.entries)
        if ((g[e.key] ?? 0) < e.value)
          '${e.key} (×${e.value - (g[e.key] ?? 0)})',
    ];
    final extra = [
      for (final e in g.entries)
        if ((w[e.key] ?? 0) < e.value)
          '${e.key} (×${e.value - (w[e.key] ?? 0)})',
    ];
    fail(
      'Seed $seed: the project changed after $after.\n'
      '  missing: ${missing.join('; ')}\n'
      '  extra: ${extra.join('; ')}\n'
      'Actions:\n  ${log.join('\n  ')}',
    );
  }

  /// What the project plays, without IDs (a reload renumbers them): tempo,
  /// tracks, and every clip with its position and edits. Sorted.
  List<String> _fingerprint() {
    final engine = EngineSnapshot.read(h.engine);
    final names = {for (final t in _tracks) t.id: '${t.type} ${t.name}'};
    String r(double v) => v.toStringAsFixed(3);
    String audio(EngineAudioClipInfo c) {
      final length = c.duration ?? c.fileDuration - c.offset;
      final warp = 'warp ${c.warpEnabled} ${r(c.stretchFactor)}';
      final pitch = 'pitch ${c.transposeSemitones}.${c.transposeCents}';
      return 'audio on ${names[c.trackId]} at ${r(c.startTime)} from '
          '${r(c.offset)} for ${r(length)} gain ${r(c.gainDb)} $warp $pitch '
          'rev ${c.reversed}';
    }

    String midi(EngineMidiClipInfo c) =>
        'midi on ${names[c.trackId]} at ${r(c.startSeconds)} '
        'notes ${c.noteCount}';

    return [
      'tempo ${r(engine.tempo)}',
      for (final t in _tracks) 'track ${t.type} ${t.name}',
      for (final c in engine.audioClips) audio(c),
      for (final c in engine.midiClips.where((c) => c.plays)) midi(c),
    ]..sort();
  }

  // --- Actions (each returns false when there was nothing to act on) ---

  Future<bool> _dropFile() async {
    await h.daw.onAudioFileDroppedOnEmpty(
      h.writeClickWav('take${_files++}.wav'),
    );
    return true;
  }

  Future<bool> _addMidiTrack() async {
    final before = _tracks.length;
    await h.tester.tap(find.text('MIDI').first, warnIfMissed: false);
    await h.settle(frames: 2, ms: 20);
    return _tracks.length > before;
  }

  Future<bool> _addMidiClip() async {
    final track = _pick(_tracks.where((t) => t.isMidi).toList());
    if (track == null) return false;
    await h.daw.createMidiClipWithParams(
      track.id,
      random.nextInt(16).toDouble(),
      4,
    );
    return true;
  }

  Future<bool> _addNote() async {
    final clip = _pick(_midiClips);
    if (clip == null) return false;
    final note = MidiNoteData(
      note: 48 + random.nextInt(24),
      velocity: 100,
      startTime: random.nextInt((clip.loopLength * 4).floor()) / 4,
      duration: 0.25 * (1 + random.nextInt(4)),
    );
    final after = clip.copyWith(notes: [...clip.notes, note]);
    await h.daw.undoRedoManager.execute(
      MidiClipSnapshotCommand(
        beforeState: clip,
        afterState: after,
        actionDescription: 'Add note',
        onApplyState: (state) =>
            h.daw.midiClipController.updateClip(state, h.daw.playheadPosition),
      ),
    );
    return true;
  }

  Future<bool> _extendMidiClip() async {
    final clip = _pick(_midiClips);
    if (clip == null) return false;
    final after = clip.copyWith(
      duration: clip.loopLength * (2 + random.nextInt(2)),
      canRepeat: true,
    );
    await h.daw.undoRedoManager.execute(
      MidiClipSnapshotCommand(
        beforeState: clip,
        afterState: after,
        actionDescription: 'Extend clip',
        onApplyState: (state) =>
            h.daw.midiClipController.updateClip(state, h.daw.playheadPosition),
      ),
    );
    return true;
  }

  Future<bool> _copyAudioClip() async {
    final clip = _pick(_audioClips);
    if (clip == null) return false;
    h.daw.onAudioClipCopied(clip, clip.startTime + random.nextInt(8));
    return true;
  }

  Future<bool> _copyMidiClip() async {
    final clip = _pick(_midiClips);
    if (clip == null) return false;
    h.daw.onMidiClipCopied(clip, clip.startTime + clip.duration);
    return true;
  }

  Future<bool> _splitMidiClip() async {
    final clip = _pick(_midiClips.where((c) => c.duration > 1).toList());
    if (clip == null) return false;
    h.daw.onMidiClipSplit(clip, clip.startTime + 1);
    return true;
  }

  Future<bool> _deleteAudioClip() async {
    final clip = _pick(_audioClips);
    if (clip == null) return false;
    h.daw.deleteAudioClipsBatch([clip]);
    return true;
  }

  Future<bool> _deleteMidiClip() async {
    final clip = _pick(_midiClips);
    if (clip == null) return false;
    h.daw.deleteMidiClip(clip.clipId, clip.trackId);
    return true;
  }

  Future<bool> _editAudioClip() async {
    final clip = _pick(_audioClips);
    if (clip == null) return false;
    final before = clip.editData ?? const AudioClipEditData();
    final after = switch (random.nextInt(4)) {
      0 => before.copyWith(syncEnabled: true, bpm: _pick([90.0, 120.0, 150.0])),
      1 => before.copyWith(transposeSemitones: random.nextInt(11) - 5),
      2 => before.copyWith(reversed: !before.reversed),
      _ => before.copyWith(gainDb: -random.nextInt(12).toDouble()),
    };
    await h.daw.undoRedoManager.execute(
      AudioClipEditCommand(
        beforeState: before,
        afterState: after,
        clipData: clip,
        actionDescription: 'Edit clip',
        onApplyState: (state, data) => h.daw.timelineKey.currentState!
            .updateClip(data.copyWith(editData: state)),
      ),
    );
    return true;
  }

  Future<bool> _changeTempo() async {
    await h.daw.onTempoChanged(_pick([90.0, 110.0, 128.0, 140.0, 170.0])!);
    return true;
  }

  Future<bool> _duplicateTrack() async {
    final track = _pick(_tracks);
    if (track == null) return false;
    await h.daw.onDuplicateTrackRequested(track);
    return true;
  }

  Future<bool> _deleteTrack() async {
    final track = _pick(_tracks);
    if (track == null) return false;
    await h.daw.onDeleteTrackRequested(track);
    return true;
  }

  Future<bool> _undo() async {
    if (!h.daw.undoRedoManager.canUndo) return false;
    log.add('   (undoing: ${h.daw.undoRedoManager.undoDescription})');
    await h.daw.performUndo();
    return true;
  }

  Future<bool> _redo() async {
    if (!h.daw.undoRedoManager.canRedo) return false;
    log.add('   (redoing: ${h.daw.undoRedoManager.redoDescription})');
    await h.daw.performRedo();
    return true;
  }
}
