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
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'Piano',
      );

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
