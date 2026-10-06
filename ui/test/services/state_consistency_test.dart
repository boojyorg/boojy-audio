import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/services/state_consistency.dart';
import 'package:boojy_audio/utils/audio_clips_info.dart';
import 'package:flutter_test/flutter_test.dart';

EngineAudioClipInfo engineAudio({
  int id = 1,
  int track = 1,
  double start = 0,
  double? duration,
  double stretch = 1,
  bool warp = false,
  int semitones = 0,
  bool reversed = false,
  double? loopLength = 4,
  double loopStart = 0,
}) => EngineAudioClipInfo(
  clipId: id,
  trackId: track,
  startTime: start,
  offset: 0,
  duration: duration,
  fileDuration: 4,
  gainDb: 0,
  warpEnabled: warp,
  stretchFactor: stretch,
  warpMode: 0,
  transposeSemitones: semitones,
  transposeCents: 0,
  reversed: reversed,
  loopLength: loopLength,
  loopStart: loopStart,
  filePath: '/a.wav',
);

ClipData screenAudio({
  int id = 1,
  int track = 1,
  double start = 0,
  AudioClipEditData? edit,
  double? loopLength,
  double loopStart = 0,
  bool canRepeat = true,
}) => ClipData(
  clipId: id,
  trackId: track,
  filePath: '/a.wav',
  startTime: start,
  duration: 4,
  editData: edit,
  loopLength: loopLength,
  loopStart: loopStart,
  canRepeat: canRepeat,
);

MidiClipData screenMidi({int id = 10, int track = 2, double startBeats = 4}) =>
    MidiClipData(
      clipId: id,
      trackId: track,
      startTime: startBeats,
      duration: 4,
      name: 'Riff',
      notes: [MidiNoteData(note: 60, velocity: 100, startTime: 0, duration: 1)],
    );

EngineMidiClipInfo engineMidi({
  int id = 7,
  int track = 2,
  double start = 2, // beat 4 at 120 BPM
  int notes = 1,
  bool plays = true,
}) => EngineMidiClipInfo(
  clipId: id,
  trackId: track,
  startSeconds: start,
  noteCount: notes,
  plays: plays,
);

List<String> compare({
  double engineTempo = 120,
  double screenTempo = 120,
  List<EngineAudioClipInfo> engineAudioClips = const [],
  List<EngineMidiClipInfo> engineMidiClips = const [],
  List<ClipData> audioClips = const [],
  List<MidiClipData> midiClips = const [],
  Map<int, int> midiEngineIds = const {},
}) => compareScreenWithEngine(
  engine: EngineSnapshot(
    tempo: engineTempo,
    audioClips: engineAudioClips,
    midiClips: engineMidiClips,
  ),
  screenTempo: screenTempo,
  audioClips: audioClips,
  midiClips: midiClips,
  midiEngineIds: midiEngineIds,
);

void main() {
  test('agrees when every clip matches', () {
    expect(
      compare(
        engineAudioClips: [engineAudio(start: 2)],
        audioClips: [screenAudio(start: 2)],
        engineMidiClips: [engineMidi()],
        midiClips: [screenMidi()],
        midiEngineIds: {10: 7},
      ),
      isEmpty,
    );
  });

  group('audio', () {
    test('a clip that plays but is not on the screen (Duplicate Track)', () {
      final problems = compare(
        engineAudioClips: [engineAudio(), engineAudio(id: 2, track: 5)],
        audioClips: [screenAudio()],
      );
      expect(problems.single, contains('Audio clip 2 plays on track 5'));
    });

    test('a clip on the screen that the engine does not have', () {
      final problems = compare(audioClips: [screenAudio(id: 3)]);
      expect(problems.single, contains('engine has no such clip'));
    });

    test('a clip on the wrong track or in the wrong place', () {
      final problems = compare(
        engineAudioClips: [engineAudio(track: 2, start: 1)],
        audioClips: [screenAudio()],
      );
      expect(problems.single, contains('track: screen 1, engine 2'));
      expect(problems.single, contains('start: screen 0.0s, engine 1.0s'));
    });

    test('a warp stretch left over from an old tempo', () {
      // A 150 BPM clip at 170 BPM should play at 170/150; the engine kept
      // the stretch it got at 120.
      final problems = compare(
        engineTempo: 170,
        screenTempo: 170,
        engineAudioClips: [engineAudio(warp: true, stretch: 0.8)],
        audioClips: [
          screenAudio(
            edit: const AudioClipEditData(bpm: 150, syncEnabled: true),
          ),
        ],
      );
      expect(problems.single, contains('stretch'));
    });

    test('pitch and reverse that never reached the engine', () {
      final problems = compare(
        engineAudioClips: [engineAudio()],
        audioClips: [
          screenAudio(
            edit: const AudioClipEditData(
              transposeSemitones: 5,
              reversed: true,
            ),
          ),
        ],
      );
      expect(problems.single, contains('pitch: screen 5 st'));
      expect(problems.single, contains('reverse: screen true'));
    });

    test('a loop that never reached the engine', () {
      // Repeats drawn on the screen but silent: the engine still loops the
      // whole file, or has no loop at all.
      final problems = compare(
        engineAudioClips: [engineAudio(), engineAudio(id: 2, loopLength: null)],
        audioClips: [
          screenAudio(loopLength: 1, loopStart: 0.5),
          screenAudio(id: 2),
        ],
      );
      expect(problems, hasLength(2));
      expect(problems[0], contains('loop: screen 1.0, engine 4.0'));
      expect(problems[0], contains('loop start: screen 0.5s, engine 0.0s'));
      expect(problems[1], contains('loop: screen 4.0, engine off'));
    });

    test('a clip that cannot repeat has no loop in the engine', () {
      expect(
        compare(
          engineAudioClips: [engineAudio(loopLength: null)],
          audioClips: [screenAudio(canRepeat: false)],
        ),
        isEmpty,
      );
    });

    test('a clip that plays to the end of its file has the file length', () {
      // The engine reports no explicit length; the screen shows 4 s.
      expect(
        compare(engineAudioClips: [engineAudio()], audioClips: [screenAudio()]),
        isEmpty,
      );
    });
  });

  group('MIDI', () {
    test('a clip that was never sent to the engine', () {
      final problems = compare(midiClips: [screenMidi()]);
      expect(problems.single, contains('never sent to the engine'));
    });

    test('a clip the engine holds but does not play', () {
      final problems = compare(
        engineMidiClips: [engineMidi(plays: false)],
        midiClips: [screenMidi()],
        midiEngineIds: {10: 7},
      );
      expect(problems.single, contains('does not play'));
    });

    test('a clip that plays but is not on the screen', () {
      final problems = compare(engineMidiClips: [engineMidi(id: 9)]);
      expect(problems.single, contains('MIDI clip 9 plays on track 2'));
    });

    test('a stored-only clip nobody shows is not a problem', () {
      expect(compare(engineMidiClips: [engineMidi(plays: false)]), isEmpty);
    });

    test('a clip in the wrong place or with missing notes', () {
      final problems = compare(
        engineMidiClips: [engineMidi(start: 3, notes: 0)],
        midiClips: [screenMidi()],
        midiEngineIds: {10: 7},
      );
      expect(problems.single, contains('start: screen 2.0s, engine 3.0s'));
      expect(problems.single, contains('notes: screen 1, engine 0'));
    });
  });

  test('the screen and engine at different tempos', () {
    expect(compare(screenTempo: 170).single, contains('Tempo'));
  });

  group('parseMidiClipsInfo', () {
    test('reads the plays field', () {
      final clips = parseMidiClipsInfo('7,2,2.0,2.0,4,1;8,-1,0.0,2.0,0,0');
      expect(clips.map((c) => c.plays), [true, false]);
      expect(clips.first.noteCount, 4);
    });

    test('older rows without plays count as playing when on a track', () {
      final clips = parseMidiClipsInfo('7,2,2.0,2.0,4;8,-1,0.0,2.0,0');
      expect(clips.map((c) => c.plays), [true, false]);
    });
  });
}
