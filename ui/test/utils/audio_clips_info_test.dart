import 'dart:ui' show Color;

import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/utils/audio_clips_info.dart';
import 'package:boojy_audio/utils/audio_file_names.dart';
import 'package:flutter_test/flutter_test.dart';

EngineAudioClipInfo _engine({
  required int id,
  int track = 1,
  double start = 0.0,
  double offset = 0.0,
  double? duration,
  double fileDuration = 4.0,
  String path = '/p/My Song.audio/audio/014-010-kick.wav',
}) => EngineAudioClipInfo(
  clipId: id,
  trackId: track,
  startTime: start,
  offset: offset,
  duration: duration,
  fileDuration: fileDuration,
  gainDb: 0,
  warpEnabled: false,
  stretchFactor: 1,
  warpMode: 0,
  transposeSemitones: 0,
  transposeCents: 0,
  reversed: false,
  filePath: path,
);

ClipData _saved({
  required int id,
  int track = 1,
  double start = 0.0,
  double duration = 4.0,
  String path = '/samples/808 Kick.wav',
  Color? color,
  double? loopLength,
  bool canRepeat = true,
  List<double> peaks = const [],
}) => ClipData(
  clipId: id,
  trackId: track,
  filePath: path,
  startTime: start,
  duration: duration,
  color: color,
  loopLength: loopLength,
  canRepeat: canRepeat,
  waveformPeaks: peaks,
);

List<double> _peaks(int id, double dur) => [id.toDouble(), dur];

void main() {
  group('parseAudioClipsInfo', () {
    test('parses rows, -1 duration means "to the end of the file"', () {
      final clips = parseAudioClipsInfo(
        '3,2,1.5,0.25,-1,4,-3,1,1.5,0,2,10,1,/a/b.wav;'
        '7,2,9,0,2.5,4,0,0,1,0,0,0,0,/a/c.wav',
      );
      expect(clips, hasLength(2));
      expect(clips[0].clipId, 3);
      expect(clips[0].trackId, 2);
      expect(clips[0].startTime, 1.5);
      expect(clips[0].offset, 0.25);
      expect(clips[0].duration, isNull);
      expect(clips[0].fileDuration, 4);
      expect(clips[0].gainDb, -3);
      expect(clips[0].warpEnabled, isTrue);
      expect(clips[0].stretchFactor, 1.5);
      expect(clips[0].transposeSemitones, 2);
      expect(clips[0].transposeCents, 10);
      expect(clips[0].reversed, isTrue);
      expect(clips[0].filePath, '/a/b.wav');
      expect(clips[1].duration, 2.5);
    });

    test('decodes the percent-encoded path', () {
      final clips = parseAudioClipsInfo(
        '1,1,0,0,-1,1,0,0,1,0,0,0,0,/a/Drums%2C Kit%3B v2 100%25.wav',
      );
      expect(clips.single.filePath, '/a/Drums, Kit; v2 100%.wav');
    });

    test('empty, error and malformed input yield what can be read', () {
      expect(parseAudioClipsInfo(''), isEmpty);
      expect(parseAudioClipsInfo('Error: nope'), isEmpty);
      expect(
        parseAudioClipsInfo('oops;1,1,0,0,-1,1,0,0,1,0,0,0,0,/x.wav'),
        hasLength(1),
      );
    });
  });

  group('rebuildAudioClips', () {
    test('matches saved extras by clip id and keeps the engine position', () {
      final rebuilt = rebuildAudioClips(
        engineClips: [_engine(id: 5, start: 2.0, offset: 0.5, duration: 3.0)],
        savedClips: [
          _saved(
            id: 5,
            start: 99, // stale UI position: the engine is authoritative
            color: const Color(0xFFFF5500),
            loopLength: 1.5,
            canRepeat: false,
          ),
        ],
        peaksFor: _peaks,
      );

      expect(rebuilt, hasLength(1));
      final clip = rebuilt.single;
      expect(clip.clipId, 5);
      expect(clip.trackId, 1);
      expect(clip.startTime, 2.0);
      expect(clip.offset, 0.5);
      expect(clip.duration, 3.0);
      expect(clip.color, const Color(0xFFFF5500));
      expect(clip.loopLength, 1.5);
      expect(clip.canRepeat, isFalse);
      // The user's dropped file is what the clip shows and reloads from.
      expect(clip.filePath, '/samples/808 Kick.wav');
      expect(clip.fileName, '808 Kick.wav');
    });

    test(
      'engine clip with no saved match still appears, with a clean name',
      () {
        final rebuilt = rebuildAudioClips(
          engineClips: [
            _engine(
              id: 1,
              start: 8,
              fileDuration: 4,
              offset: 1,
              path: '/p/My Song.audio/audio/014-010-007-005-kick.wav',
            ),
          ],
          savedClips: const [],
          peaksFor: _peaks,
        );

        expect(rebuilt, hasLength(1));
        final clip = rebuilt.single;
        expect(clip.fileName, 'kick.wav');
        expect(clip.startTime, 8);
        expect(clip.duration, 3, reason: 'no length: plays from offset to end');
        expect(clip.loopLength, 3);
        expect(clip.canRepeat, isTrue);
        expect(clip.color, isNull);
        expect(clip.editData, isNull);
        expect(clip.waveformPeaks, _peaks(1, 4));
      },
    );

    test('saved clip with no engine counterpart is dropped', () {
      final rebuilt = rebuildAudioClips(
        engineClips: [_engine(id: 1)],
        savedClips: [_saved(id: 1), _saved(id: 2), _saved(id: 3)],
        peaksFor: _peaks,
      );
      expect(rebuilt.map((c) => c.clipId), [1]);
    });

    test('a saved clip that reuses the id on another track is not merged', () {
      final rebuilt = rebuildAudioClips(
        engineClips: [_engine(id: 4, track: 2)],
        savedClips: [_saved(id: 4, track: 9, color: const Color(0xFF00FF00))],
        peaksFor: _peaks,
      );
      expect(rebuilt.single.trackId, 2);
      expect(rebuilt.single.color, isNull);
      expect(rebuilt.single.filePath, contains('014-010-kick.wav'));
    });

    test('saved peaks (old layout files) are reused, not recomputed', () {
      var computed = 0;
      final rebuilt = rebuildAudioClips(
        engineClips: [_engine(id: 1), _engine(id: 2)],
        savedClips: [
          _saved(id: 1, peaks: [0.1, 0.2]),
        ],
        peaksFor: (id, dur) {
          computed++;
          return _peaks(id, dur);
        },
      );
      expect(rebuilt[0].waveformPeaks, [0.1, 0.2]);
      expect(rebuilt[1].waveformPeaks, _peaks(2, 4));
      expect(computed, 1);
    });

    test('engine duration wins, otherwise the saved arrangement length', () {
      final rebuilt = rebuildAudioClips(
        engineClips: [
          _engine(id: 1, duration: 2.0),
          _engine(id: 2, fileDuration: 4),
        ],
        savedClips: [
          _saved(id: 1, duration: 8),
          _saved(id: 2, duration: 8), // looped out past the file length
        ],
        peaksFor: _peaks,
      );
      expect(rebuilt[0].duration, 2.0);
      expect(rebuilt[1].duration, 8.0);
    });
  });

  group('cleanAudioFileName', () {
    test('strips stacked id prefixes inside a project audio folder', () {
      expect(
        cleanAudioFileName('/x/Song.audio/audio/014-010-007-005-kick.wav'),
        'kick.wav',
      );
      expect(
        cleanAudioFileName(r'C:\x\Song.audio\audio\003-kick.wav'),
        'kick.wav',
      );
    });

    test('leaves a user file alone, even if it looks like a prefix', () {
      expect(cleanAudioFileName('/samples/808-kick.wav'), '808-kick.wav');
      expect(cleanAudioFileName('kick.wav'), 'kick.wav');
    });
  });
}
