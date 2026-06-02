import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/commands/track_commands.dart';
import '../../mocks/mock_audio_engine.dart';

void main() {
  late MockAudioEngine mockEngine;

  setUp(() {
    mockEngine = MockAudioEngine();
  });

  group('CreateTrackCommand', () {
    test('has correct description for audio track', () {
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Guitar',
      );

      expect(command.description, 'Create Audio Track');
    });

    test('has correct description for MIDI track', () {
      final command = CreateTrackCommand(trackType: 'midi', trackName: 'Piano');

      expect(command.description, 'Create MIDI Track');
    });

    test('createdTrackId is null before execute', () {
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Guitar',
      );

      expect(command.createdTrackId, isNull);
    });

    test('execute creates track and stores ID', () async {
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Guitar',
      );

      await command.execute(mockEngine);

      expect(command.createdTrackId, isNotNull);
      expect(command.createdTrackId, greaterThanOrEqualTo(0));
      expect(mockEngine.calls, contains('createTrack'));
    });

    test('undo deletes created track', () async {
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Guitar',
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('deleteTrack'));
    });
  });

  group('DeleteTrackCommand', () {
    test('has correct description', () {
      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
      );

      expect(command.description, 'Delete Track: Guitar');
    });

    test('execute stores state and deletes track', () async {
      // Set up mock to return track info with volume, pan, mute, solo
      mockEngine.trackInfoResponse = 'audio,Guitar,0,-3.0,0.25,true,false';

      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('getTrackInfo'));
      expect(mockEngine.calls, contains('deleteTrack'));
    });

    test('undo recreates track with restored state', () async {
      mockEngine.trackInfoResponse = 'audio,Guitar,0,-3.0,0.25,true,false';

      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('createTrack'));
      expect(mockEngine.calls, contains('setTrackVolume'));
      expect(mockEngine.calls, contains('setTrackPan'));
      expect(mockEngine.calls, contains('setTrackMute'));
      expect(mockEngine.calls, contains('setTrackSolo'));
    });

    test('undo works when no track info was available', () async {
      // Empty response means no state to restore
      mockEngine.trackInfoResponse = '';

      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('createTrack'));
    });

    test('undo works with pre-stored state', () async {
      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
        volumeDb: -6.0,
        pan: 0.5,
        mute: true,
        solo: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('createTrack'));
      expect(mockEngine.calls, contains('setTrackVolume'));
      expect(mockEngine.calls, contains('setTrackPan'));
      expect(mockEngine.calls, contains('setTrackMute'));
      expect(mockEngine.calls, contains('setTrackSolo'));
    });

    test(
      'redo deletes the recreated track id, not the stale original (C62)',
      () async {
        // createTrack (on undo) hands out 42; redo must delete 42, not 1.
        mockEngine.nextTrackId = 42;

        final command = DeleteTrackCommand(
          trackId: 1,
          trackName: 'Guitar',
          trackType: 'audio',
        );

        await command.execute(mockEngine); // deletes original id 1
        await command.undo(mockEngine); // recreates as id 42
        mockEngine.deletedTrackIds.clear();

        await command.execute(mockEngine); // redo (manager re-runs execute)

        expect(mockEngine.deletedTrackIds, [42]);
      },
    );

    test(
      'undo rebuilds the built-in FX chain with params and bypass',
      () async {
        mockEngine.trackEffectsResponse = '10,11';
        mockEngine.effectInfoResponses[10] =
            'type:reverb,bypassed:0,room_size:0.8,damping:0.3,wet_dry:0.5';
        mockEngine.effectInfoResponses[11] =
            'type:eq,bypassed:1,low_freq:100,low_gain:3';

        final command = DeleteTrackCommand(
          trackId: 1,
          trackName: 'Guitar',
          trackType: 'audio',
        );

        await command.execute(mockEngine);
        mockEngine.calls.clear();
        await command.undo(mockEngine);

        expect(
          mockEngine.calls.where((c) => c == 'addEffectToTrack').length,
          2,
          reason: 'both built-in effects re-added',
        );
        expect(mockEngine.calls, contains('setEffectParameter'));
        // Only the eq was bypassed.
        expect(mockEngine.calls.where((c) => c == 'setEffectBypass').length, 1);
      },
    );

    test('undo reloads a VST3 plugin with its path + state', () async {
      // path is last and may contain commas; name precedes it.
      mockEngine.trackEffectsResponse = '10';
      mockEngine.effectInfoResponses[10] =
          'type:vst3,bypassed:0,name:Serum,path:/Library/Audio/Plug-Ins/VST3/Serum.vst3';
      mockEngine.vst3StateResponses[10] = 'BASE64STATE==';
      mockEngine.nextEffectId = 50;

      final restored = <({int trackId, List<RestoredVst3> plugins})>[];
      String? notice;
      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Synth',
        trackType: 'midi',
        onVst3Restored: (tid, list) =>
            restored.add((trackId: tid, plugins: list)),
        onNotice: (m) => notice = m,
      );

      await command.execute(mockEngine);
      // State captured during snapshot.
      expect(mockEngine.calls, contains('getVst3State'));
      mockEngine.calls.clear();
      await command.undo(mockEngine);

      // Reloaded by path, not as a built-in effect.
      expect(mockEngine.calls, isNot(contains('addEffectToTrack')));
      expect(mockEngine.addedVst3Plugins.length, 1);
      expect(
        mockEngine.addedVst3Plugins.single.path,
        '/Library/Audio/Plug-Ins/VST3/Serum.vst3',
      );
      // State restored onto the freshly reloaded effect id.
      expect(mockEngine.setVst3StateCalls.length, 1);
      expect(mockEngine.setVst3StateCalls.single.effectId, 50);
      expect(mockEngine.setVst3StateCalls.single.stateBase64, 'BASE64STATE==');
      // Reported back so the UI plugin manager can re-register it.
      expect(restored.length, 1);
      expect(restored.single.plugins.single.effectId, 50);
      expect(restored.single.plugins.single.name, 'Serum');
      // Successful reload → no failure notice.
      expect(notice, isNull);
    });

    test(
      "undo surfaces a notice when a VST3 plugin can't be reloaded",
      () async {
        mockEngine.trackEffectsResponse = '10';
        mockEngine.effectInfoResponses[10] =
            'type:vst3,bypassed:0,name:Gone,path:/missing/Gone.vst3';
        mockEngine.nextEffectId =
            -1; // addVst3EffectToTrack returns < 0 → failure

        String? notice;
        final command = DeleteTrackCommand(
          trackId: 1,
          trackName: 'Synth',
          trackType: 'midi',
          onNotice: (m) => notice = m,
        );

        await command.execute(mockEngine);
        mockEngine.calls.clear();
        await command.undo(mockEngine);

        // Tried to reload, failed, no state restore, surfaced a notice.
        expect(mockEngine.addedVst3Plugins.length, 1);
        expect(mockEngine.calls, isNot(contains('setVst3State')));
        expect(notice, isNotNull);
        expect(notice, contains('moved or uninstalled'));
      },
    );

    test('undo restores sends from the snapshot', () async {
      mockEngine.trackSendsResponse = '5,-6.00,Reverb;6,-12.00,Delay';

      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();
      await command.undo(mockEngine);

      expect(mockEngine.calls.where((c) => c == 'addSend').length, 2);
    });

    test('onCleanup fires on delete, onRestoreUi on undo', () async {
      mockEngine.nextTrackId = 7;
      int? cleanupId;
      int? restoreId;

      final command = DeleteTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        trackType: 'audio',
        onCleanup: (id) => cleanupId = id,
        onRestoreUi: (id) => restoreId = id,
      );

      await command.execute(mockEngine);
      expect(cleanupId, 1);

      await command.undo(mockEngine);
      expect(restoreId, 7);
    });
  });

  group('DuplicateTrackCommand', () {
    test('has correct description', () {
      final command = DuplicateTrackCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Guitar',
      );

      expect(command.description, 'Duplicate Track: Guitar');
    });

    test('duplicatedTrackId is null before execute', () {
      final command = DuplicateTrackCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Guitar',
      );

      expect(command.duplicatedTrackId, isNull);
    });

    test('execute duplicates track and stores ID', () async {
      final command = DuplicateTrackCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Guitar',
      );

      await command.execute(mockEngine);

      expect(command.duplicatedTrackId, isNotNull);
      expect(mockEngine.calls, contains('duplicateTrack'));
    });

    test('undo deletes duplicated track', () async {
      final command = DuplicateTrackCommand(
        sourceTrackId: 1,
        sourceTrackName: 'Guitar',
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('deleteTrack'));
    });
  });

  group('RenameTrackCommand', () {
    test('has correct description', () {
      final command = RenameTrackCommand(
        trackId: 1,
        oldName: 'Track 1',
        newName: 'Guitar',
      );

      expect(command.description, 'Rename Track: Track 1 → Guitar');
    });

    test('execute renames track and fires callback', () async {
      int? renamedTrackId;
      String? renamedName;

      final command = RenameTrackCommand(
        trackId: 1,
        oldName: 'Track 1',
        newName: 'Guitar',
        onTrackRenamed: (trackId, name) {
          renamedTrackId = trackId;
          renamedName = name;
        },
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackName'));
      expect(renamedTrackId, 1);
      expect(renamedName, 'Guitar');
    });

    test('undo restores old name and fires callback', () async {
      String? renamedName;

      final command = RenameTrackCommand(
        trackId: 1,
        oldName: 'Track 1',
        newName: 'Guitar',
        onTrackRenamed: (trackId, name) {
          renamedName = name;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(renamedName, 'Track 1');
    });
  });

  group('ReorderTrackCommand', () {
    test('has correct description', () {
      final command = ReorderTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        oldIndex: 0,
        newIndex: 2,
      );

      expect(command.description, 'Reorder Track: Guitar');
    });

    test('execute fires callback with new indices', () async {
      int? fromIndex;
      int? toIndex;

      final command = ReorderTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        oldIndex: 0,
        newIndex: 2,
        onTrackReordered: (oldIdx, newIdx) {
          fromIndex = oldIdx;
          toIndex = newIdx;
        },
      );

      await command.execute(mockEngine);

      expect(fromIndex, 0);
      expect(toIndex, 2);
    });

    test('undo fires callback with reversed indices', () async {
      int? fromIndex;
      int? toIndex;

      final command = ReorderTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        oldIndex: 0,
        newIndex: 2,
        onTrackReordered: (oldIdx, newIdx) {
          fromIndex = oldIdx;
          toIndex = newIdx;
        },
      );

      await command.execute(mockEngine);
      await command.undo(mockEngine);

      expect(fromIndex, 2);
      expect(toIndex, 0);
    });

    test('is UI-only (no engine calls)', () async {
      final command = ReorderTrackCommand(
        trackId: 1,
        trackName: 'Guitar',
        oldIndex: 0,
        newIndex: 2,
        onTrackReordered: (oldIdx, newIdx) {},
      );

      await command.execute(mockEngine);

      // ReorderTrack is UI-only, shouldn't call any engine methods
      expect(mockEngine.calls, isEmpty);
    });
  });

  group('ArmTrackCommand', () {
    test('has correct description when arming', () {
      final command = ArmTrackCommand(
        trackId: 1,
        trackName: 'Vocals',
        newArmed: true,
        oldArmed: false,
      );

      expect(command.description, 'Arm Track: Vocals');
    });

    test('has correct description when disarming', () {
      final command = ArmTrackCommand(
        trackId: 1,
        trackName: 'Vocals',
        newArmed: false,
        oldArmed: true,
      );

      expect(command.description, 'Disarm Track: Vocals');
    });

    test('execute sets armed state', () async {
      final command = ArmTrackCommand(
        trackId: 1,
        trackName: 'Vocals',
        newArmed: true,
        oldArmed: false,
      );

      await command.execute(mockEngine);

      expect(mockEngine.calls, contains('setTrackArmed'));
    });

    test('undo restores previous armed state', () async {
      final command = ArmTrackCommand(
        trackId: 1,
        trackName: 'Vocals',
        newArmed: true,
        oldArmed: false,
      );

      await command.execute(mockEngine);
      mockEngine.calls.clear();

      await command.undo(mockEngine);

      expect(mockEngine.calls, contains('setTrackArmed'));
    });
  });
}
