import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/services/midi_playback_manager.dart';
import '../mocks/mock_audio_engine.dart';

/// Engine-resync behaviour of [MidiPlaybackManager.replaceClipsOnTrack] (#16):
/// undoing a MIDI recording must remove the recorded clip from the ENGINE
/// (not just the UI), and redo must recreate it with a fresh engine id so
/// later deletes/moves don't silently no-op on a stale mapping.
void main() {
  const trackId = 1;
  const tempo = 120.0;

  late MockAudioEngine mockEngine;
  late MidiPlaybackManager manager;
  late MidiClipData preExistingClip;
  late MidiClipData recordedClip;

  setUp(() {
    mockEngine = MockAudioEngine();
    manager = MidiPlaybackManager(mockEngine);

    preExistingClip = MidiClipData(
      clipId: 100,
      trackId: trackId,
      startTime: 0.0,
      duration: 4.0,
      name: 'Existing',
      notes: [
        MidiNoteData(note: 60, velocity: 100, startTime: 0.0, duration: 1.0),
      ],
    );
    recordedClip = MidiClipData(
      clipId: 200,
      trackId: trackId,
      startTime: 4.0,
      duration: 4.0,
      name: 'Recorded',
      notes: [
        MidiNoteData(note: 64, velocity: 90, startTime: 0.0, duration: 1.0),
      ],
    );

    // Simulate the post-recording state: one pre-existing clip in the list
    // and scheduled in the engine (id 1 from the mock's counter), plus a
    // freshly recorded clip whose engine id came from stop_midi_recording
    // (55). addRecordedClip is just "add to the clip list" here.
    manager.addRecordedClip(preExistingClip);
    manager.rescheduleClip(preExistingClip, tempo);
    manager.addRecordedClip(recordedClip, rustClipId: 55);
    mockEngine.calls.clear();
  });

  group('replaceClipsOnTrack (recording undo/redo engine sync)', () {
    test('undo removes the recorded clip from the engine', () {
      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo);

      expect(mockEngine.removedMidiClips, [(trackId: trackId, clipId: 55)]);
      expect(manager.dartToRustClipIds.containsKey(200), isFalse);
    });

    test('undo resyncs surviving clips in place (no duplicate engine clip)', () {
      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo);

      // Survivor keeps engine id 1: cleared + notes re-added + start time set,
      // rather than being recreated.
      expect(mockEngine.clearedMidiClipIds, [1]);
      expect(mockEngine.calls, contains('addMidiNoteToClip'));
      expect(mockEngine.calls, contains('setClipStartTime'));
      expect(mockEngine.calls, isNot(contains('createMidiClip')));
      expect(manager.dartToRustClipIds[100], 1);
    });

    test('redo recreates the recorded clip with a fresh engine id', () {
      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo); // undo
      mockEngine.calls.clear();

      manager.replaceClipsOnTrack(trackId, [
        preExistingClip,
        recordedClip,
      ], tempo); // redo

      // Recorded clip got a new engine clip (mock counter: 1 was taken by the
      // pre-existing clip, so the recreated clip is 2) added to the track.
      expect(mockEngine.calls, contains('createMidiClip'));
      expect(mockEngine.calls, contains('addMidiClipToTrack'));
      expect(manager.dartToRustClipIds[200], 2);
    });

    test('delete after undo+redo hits the engine with the fresh id', () {
      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo); // undo
      manager.replaceClipsOnTrack(trackId, [
        preExistingClip,
        recordedClip,
      ], tempo); // redo
      mockEngine.removedMidiClips.clear();

      // A subsequent removal of the recorded clip (e.g. delete, or another
      // undo) must target the recreated engine id — not stale 55, not nothing.
      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo);

      expect(mockEngine.removedMidiClips, [(trackId: trackId, clipId: 2)]);
      expect(manager.dartToRustClipIds.containsKey(200), isFalse);
    });

    test(
      'replacing with an empty list clears the whole track in the engine',
      () {
        manager.replaceClipsOnTrack(trackId, [], tempo);

        expect(
          mockEngine.removedMidiClips,
          containsAll([
            (trackId: trackId, clipId: 1),
            (trackId: trackId, clipId: 55),
          ]),
        );
        expect(manager.midiClips, isEmpty);
        expect(manager.dartToRustClipIds, isEmpty);
      },
    );

    test('editing clip that survives the replacement stays open', () {
      // User has the pre-existing clip open in the piano roll, then undoes
      // the recording: the recorded clip goes, the open clip must NOT blank.
      manager.selectClip(preExistingClip.clipId, preExistingClip);

      final survivorCopy = preExistingClip.copyWith(name: 'Existing v2');
      manager.replaceClipsOnTrack(trackId, [survivorCopy], tempo);

      expect(manager.currentEditingClip, isNotNull);
      expect(manager.currentEditingClip!.clipId, preExistingClip.clipId);
      // It points at the refreshed copy, not a stale pre-replacement snapshot.
      expect(manager.currentEditingClip!.name, 'Existing v2');
      expect(manager.selectedClipId, preExistingClip.clipId);
    });

    test('editing clip removed by the replacement is cleared', () {
      // User has the recorded clip open, then undoes the recording: the open
      // clip is gone, so the editor selection must clear.
      manager.selectClip(recordedClip.clipId, recordedClip);

      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo);

      expect(manager.currentEditingClip, isNull);
      expect(manager.selectedClipId, isNull);
    });

    test('clips on other tracks are untouched', () {
      final otherTrackClip = MidiClipData(
        clipId: 300,
        trackId: 2,
        startTime: 0.0,
        duration: 4.0,
        name: 'Other',
        notes: [
          MidiNoteData(note: 62, velocity: 80, startTime: 0.0, duration: 1.0),
        ],
      );
      manager.addRecordedClip(otherTrackClip);
      manager.rescheduleClip(otherTrackClip, tempo);
      mockEngine.calls.clear();
      mockEngine.removedMidiClips.clear();

      manager.replaceClipsOnTrack(trackId, [preExistingClip], tempo);

      expect(mockEngine.removedMidiClips.where((r) => r.trackId == 2), isEmpty);
      expect(manager.midiClips.where((c) => c.trackId == 2), isNotEmpty);
      expect(manager.dartToRustClipIds.containsKey(300), isTrue);
    });
  });
}
