import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:boojy_audio/audio_engine.dart';
import 'package:boojy_audio/controllers/recording_controller.dart';
import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/audio_input_status.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/services/commands/track_commands.dart';
import 'package:boojy_audio/services/midi_playback_manager.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_engine_harness.dart';

// The screen-vs-engine check (`state_consistency.dart`) against the real
// engine: it stays quiet when the two agree, and names the bugs it exists to
// catch (clips playing unseen, a stale warp stretch, a lost take).

/// A 2 s mono 48 kHz 16-bit WAV.
File _writeWav(Directory dir, String name) {
  const rate = 48000;
  const frames = rate * 2;
  final data = ByteData(44 + frames * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = (math.sin(2 * math.pi * 220 * i / rate) * 8000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return File('${dir.path}/$name')..writeAsBytesSync(data.buffer.asUint8List());
}

void main() {
  if (!isNativeEngineAvailable) {
    test('Screen/engine check (native engine)', () {}, skip: true);
    return;
  }

  late AudioEngine engine;
  late Directory dir;

  setUp(() async {
    engine = await createInitializedEngine();
    engine.clearAllTracks();
    engine.setTempo(120);
    dir = Directory.systemTemp.createTempSync('screen_engine_check');
  });

  tearDown(() {
    engine.clearAllTracks();
    dir.deleteSync(recursive: true);
  });

  List<String> check({
    required List<ClipData> audio,
    List<MidiClipData> midi = const [],
    Map<int, int> midiIds = const {},
  }) => compareScreenWithEngine(
    engine: EngineSnapshot.read(engine),
    screenTempo: engine.getTempo(),
    audioClips: audio,
    midiClips: midi,
    midiEngineIds: midiIds,
  );

  ClipData loadClip(int trackId, {double start = 0}) {
    final path = _writeWav(dir, 'tone_$trackId.wav').path;
    final id = engine.loadAudioFileToTrack(path, trackId, startTime: start);
    expect(id, greaterThanOrEqualTo(0));
    return ClipData(
      clipId: id,
      trackId: trackId,
      filePath: path,
      startTime: start,
      duration: engine.getClipDuration(id),
    );
  }

  test('quiet when the screen shows what the engine plays', () {
    final track = engine.createTrack('audio', 'Audio');
    expect(check(audio: [loadClip(track, start: 1)]), isEmpty);
  });

  test(
    'Duplicate Track: copies agree; the old invisible copies are caught',
    () async {
      final track = engine.createTrack('audio', 'Audio');
      final original = loadClip(track);
      final shown = <ClipData>[original];
      final command = DuplicateTrackCommand(
        sourceTrackId: track,
        sourceTrackName: 'Audio',
        audioClips: [original],
        onCopied: (_, audioCopies, _) => shown.addAll(audioCopies),
      );
      await command.execute(engine);
      expect(check(audio: shown), isEmpty);

      // The pre-#184 bug: the copy plays but never reached the screen.
      final problems = check(audio: [original]);
      expect(problems.single, contains('plays on track'));
      expect(problems.single, contains('not on the screen'));
    },
  );

  test('a warp stretch the engine kept from an old tempo is caught', () {
    final track = engine.createTrack('audio', 'Audio');
    final clip = loadClip(
      track,
    ).copyWith(editData: const AudioClipEditData(bpm: 150, syncEnabled: true));
    pushAudioClipEdits(engine, track, clip.clipId, clip.editData!);
    expect(check(audio: [clip]), isEmpty);

    // A tempo change the warped clips weren't told about (the pre-#185 bug).
    engine.setTempo(170);
    expect(check(audio: [clip]).single, contains('stretch'));

    pushWarpForTempo(engine, [clip]);
    expect(check(audio: [clip]), isEmpty);
  });

  test('a looped MIDI clip agrees before and after a tempo change', () {
    final track = engine.createTrack('midi', 'Synth');
    final manager = MidiPlaybackManager(engine);
    final clip = MidiClipData(
      clipId: 42,
      trackId: track,
      startTime: 4,
      duration: 10, // 2.5 loops of 4 beats
      loopLength: 4,
      canRepeat: true,
      name: 'Riff',
      notes: [
        MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1),
        MidiNoteData(note: 64, velocity: 100, startTime: 2.5, duration: 2),
      ],
    );
    manager
      ..addRecordedClip(clip)
      ..rescheduleClip(clip, 120);
    List<String> midiCheck() => check(
      audio: const [],
      midi: manager.midiClips,
      midiIds: manager.dartToRustClipIds,
    );
    expect(midiCheck(), isEmpty);

    engine.setTempo(97);
    manager.rescheduleAllClips(97);
    expect(midiCheck(), isEmpty);
  });

  // Known bug (BACKLOG, Fix before release): with two audio tracks armed the
  // engine records a take on each, but the screen gets only the first. Needs
  // a real input, so it also skips where none opens.
  test('recording onto two armed tracks shows every take', () async {
    engine.setAudioInputChoice('');
    engine.setCountInBars(0);
    final first = engine.createTrack('audio', 'Audio 1');
    engine.createTrack('audio', 'Audio 2');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final health = engine.getAudioInputHealth().state;
    if (health == InputHealthState.failed || health == InputHealthState.off) {
      markTestSkipped('no audio input on this machine');
      engine.setAudioInputChoice(kAudioInputOff);
      return;
    }

    final controller = RecordingController()..initialize(engine);
    controller.startRecording(isAlreadyPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final result = controller.stopRecording();
    engine.transportStop();
    controller.dispose();
    engine.setAudioInputChoice(kAudioInputOff);

    // What the app puts on screen: the one take the result reports.
    final shown = [
      ClipData(
        clipId: result.audioClipId!,
        trackId: first,
        filePath: '',
        startTime: 0,
        duration: engine.getClipDuration(result.audioClipId!),
      ),
    ];
    expect(check(audio: shown), isEmpty);
  }, skip: 'Known bug: two armed tracks show only the first take (BACKLOG)');
}
