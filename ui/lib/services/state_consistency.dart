import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../utils/audio_clips_info.dart';
import 'commands/audio_engine_interface.dart';

// The screen keeps its own copy of the arrangement (clip lists, edits, MIDI
// notes) and pushes changes to the engine. When the two drift apart, what you
// see is not what plays: Duplicate Track's clips played unseen, warp kept a
// stale stretch, a reload mixed up clip IDs. This compares the two so tests,
// and development builds after every action, catch that the moment it
// happens.

/// One MIDI clip as the engine lists it (a row of `getAllMidiClipsInfo`).
class EngineMidiClipInfo {
  final int clipId;
  final int trackId;
  final double startSeconds;
  final int noteCount;

  /// On a track, so it plays (not only held in the engine's clip storage).
  final bool plays;

  const EngineMidiClipInfo({
    required this.clipId,
    required this.trackId,
    required this.startSeconds,
    required this.noteCount,
    required this.plays,
  });
}

/// Parse `getAllMidiClipsInfo`: `;`-separated rows of
/// `clip_id,track_id,start_time,duration,note_count,plays`. Rows from an
/// engine without the `plays` field count as playing when on a track.
List<EngineMidiClipInfo> parseMidiClipsInfo(String raw) {
  if (raw.isEmpty || raw.startsWith('Error:')) return const [];
  final clips = <EngineMidiClipInfo>[];
  for (final row in raw.split(';')) {
    final f = row.split(',');
    if (f.length < 5) continue;
    final clipId = int.tryParse(f[0]);
    final trackId = int.tryParse(f[1]);
    final start = double.tryParse(f[2]);
    final notes = int.tryParse(f[4]);
    if (clipId == null || trackId == null || start == null || notes == null) {
      continue;
    }
    clips.add(
      EngineMidiClipInfo(
        clipId: clipId,
        trackId: trackId,
        startSeconds: start,
        noteCount: notes,
        plays: f.length > 5 ? f[5] == '1' : trackId >= 0,
      ),
    );
  }
  return clips;
}

/// What the engine holds, read in one go.
class EngineSnapshot {
  final double tempo;
  final List<EngineAudioClipInfo> audioClips;
  final List<EngineMidiClipInfo> midiClips;

  const EngineSnapshot({
    required this.tempo,
    required this.audioClips,
    required this.midiClips,
  });

  factory EngineSnapshot.read(AudioEngineInterface engine) => EngineSnapshot(
    tempo: engine.getTempo(),
    audioClips: parseAudioClipsInfo(engine.getAllAudioClipsInfo()),
    midiClips: parseMidiClipsInfo(engine.getAllMidiClipsInfo()),
  );
}

const _seconds = 1e-3; // position and length tolerance
const _db = 0.01;

/// Every difference between what the screen shows and what the engine will
/// play, in plain words; empty when they agree.
///
/// [midiEngineIds] maps each on-screen MIDI clip ID to the engine's clip ID
/// (the playback manager's map).
List<String> compareScreenWithEngine({
  required EngineSnapshot engine,
  required double screenTempo,
  required List<ClipData> audioClips,
  required List<MidiClipData> midiClips,
  required Map<int, int> midiEngineIds,
}) {
  final problems = <String>[];

  if ((screenTempo - engine.tempo).abs() > 1e-6) {
    problems.add(
      'Tempo: the screen says $screenTempo BPM, the engine plays at '
      '${engine.tempo} BPM',
    );
  }

  // --- Audio clips ---
  final engineAudio = {for (final c in engine.audioClips) c.clipId: c};
  final onScreen = <int>{};
  for (final clip in audioClips) {
    onScreen.add(clip.clipId);
    final label = 'Audio clip ${clip.clipId} ("${clip.fileName}")';
    final e = engineAudio[clip.clipId];
    if (e == null) {
      problems.add('$label is on the screen but the engine has no such clip');
      continue;
    }
    final edit = clip.editData;
    final engineLength = e.duration ?? e.fileDuration - e.offset;
    final gain = edit?.gainDb ?? 0;
    final warp = edit?.syncEnabled ?? false;
    final stretch = edit?.stretchAt(engine.tempo) ?? 1.0;
    final semitones = edit?.transposeSemitones ?? 0;
    final cents = edit?.fineCents ?? 0;
    final reversed = edit?.reversed ?? false;
    final enginePitch = '${e.transposeSemitones} st ${e.transposeCents} ct';
    final loop = clip.engineLoopLength > 0 ? clip.engineLoopLength : null;
    final differences = <String>[
      if (e.trackId != clip.trackId)
        'track: screen ${clip.trackId}, engine ${e.trackId}',
      if ((e.startTime - clip.startTime).abs() > _seconds)
        'start: screen ${clip.startTime}s, engine ${e.startTime}s',
      if ((e.offset - clip.offset).abs() > _seconds)
        'trim: screen ${clip.offset}s, engine ${e.offset}s',
      if ((engineLength - clip.duration).abs() > _seconds)
        'length: screen ${clip.duration}s, engine ${engineLength}s',
      if ((e.gainDb - gain).abs() > _db)
        'gain: screen $gain dB, engine ${e.gainDb} dB',
      if (e.warpEnabled != warp) 'warp: screen $warp, engine ${e.warpEnabled}',
      if (e.warpEnabled && (e.stretchFactor - stretch).abs() > 1e-3)
        'stretch: screen $stretch×, engine ${e.stretchFactor}×',
      if (e.transposeSemitones != semitones || e.transposeCents != cents)
        'pitch: screen $semitones st $cents ct, engine $enginePitch',
      if (e.reversed != reversed)
        'reverse: screen $reversed, engine ${e.reversed}',
      if ((loop == null) != (e.loopLength == null) ||
          (loop != null && (loop - e.loopLength!).abs() > _seconds))
        'loop: screen ${loop ?? 'off'}, engine ${e.loopLength ?? 'off'}',
      if ((e.loopStart - clip.loopStart).abs() > _seconds)
        'loop start: screen ${clip.loopStart}s, engine ${e.loopStart}s',
    ];
    if (differences.isNotEmpty) {
      problems.add('$label differs: ${differences.join('; ')}');
    }
  }
  for (final e in engine.audioClips) {
    if (!onScreen.contains(e.clipId)) {
      problems.add(
        'Audio clip ${e.clipId} plays on track ${e.trackId} but is not on '
        'the screen',
      );
    }
  }

  // --- MIDI clips ---
  final engineMidi = {for (final c in engine.midiClips) c.clipId: c};
  final claimed = <int>{};
  for (final clip in midiClips) {
    final label = 'MIDI clip "${clip.name}" (${clip.clipId})';
    final engineId = midiEngineIds[clip.clipId];
    if (engineId == null) {
      problems.add('$label is on the screen but was never sent to the engine');
      continue;
    }
    claimed.add(engineId);
    final e = engineMidi[engineId];
    if (e == null || !e.plays) {
      problems.add('$label is on the screen but does not play');
      continue;
    }
    final startSeconds = clip.startTime * 60.0 / engine.tempo;
    final notes = clip.unrolledNotes().length;
    final differences = <String>[
      if (e.trackId != clip.trackId)
        'track: screen ${clip.trackId}, engine ${e.trackId}',
      if ((e.startSeconds - startSeconds).abs() > _seconds)
        'start: screen ${startSeconds}s, engine ${e.startSeconds}s',
      if (e.noteCount != notes) 'notes: screen $notes, engine ${e.noteCount}',
    ];
    if (differences.isNotEmpty) {
      problems.add('$label differs: ${differences.join('; ')}');
    }
  }
  for (final e in engine.midiClips) {
    if (e.plays && !claimed.contains(e.clipId)) {
      problems.add(
        'MIDI clip ${e.clipId} plays on track ${e.trackId} but is not on the '
        'screen',
      );
    }
  }

  return problems;
}
