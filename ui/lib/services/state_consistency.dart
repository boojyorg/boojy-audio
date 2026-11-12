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

/// One note as the engine holds it (an entry of `getMidiClipNotes`), in
/// seconds from the start of its clip.
class EngineMidiNote {
  final int pitch;
  final int velocity;
  final double startSeconds;
  final double lengthSeconds;

  const EngineMidiNote({
    required this.pitch,
    required this.velocity,
    required this.startSeconds,
    required this.lengthSeconds,
  });

  @override
  String toString() =>
      'pitch $pitch at ${startSeconds.toStringAsFixed(3)}s for '
      '${lengthSeconds.toStringAsFixed(3)}s (velocity $velocity)';
}

/// Parse `getMidiClipNotes`: `;`-separated `note,velocity,start_time,duration`.
List<EngineMidiNote> parseMidiClipNotes(String raw) {
  if (raw.isEmpty || raw.startsWith('Error:')) return const [];
  final notes = <EngineMidiNote>[];
  for (final entry in raw.split(';')) {
    final f = entry.split(',');
    if (f.length < 4) continue;
    final pitch = int.tryParse(f[0]);
    final velocity = int.tryParse(f[1]);
    final start = double.tryParse(f[2]);
    final length = double.tryParse(f[3]);
    if (pitch == null || velocity == null || start == null || length == null) {
      continue;
    }
    notes.add(
      EngineMidiNote(
        pitch: pitch,
        velocity: velocity,
        startSeconds: start,
        lengthSeconds: length,
      ),
    );
  }
  return notes;
}

/// One MIDI clip as the engine lists it (a row of `getAllMidiClipsInfo`).
class EngineMidiClipInfo {
  final int clipId;
  final int trackId;
  final double startSeconds;
  final int noteCount;

  /// On a track, so it plays (not only held in the engine's clip storage).
  final bool plays;

  /// Under "Mute Clip": the engine keeps its notes and plays none.
  final bool muted;

  /// The notes themselves; null when only the row was read, and then only
  /// [noteCount] can be compared. A count alone misses a clip holding the
  /// right number of wrong notes.
  final List<EngineMidiNote>? notes;

  const EngineMidiClipInfo({
    required this.clipId,
    required this.trackId,
    required this.startSeconds,
    required this.noteCount,
    required this.plays,
    this.muted = false,
    this.notes,
  });

  EngineMidiClipInfo withNotes(List<EngineMidiNote> notes) =>
      EngineMidiClipInfo(
        clipId: clipId,
        trackId: trackId,
        startSeconds: startSeconds,
        noteCount: noteCount,
        plays: plays,
        muted: muted,
        notes: notes,
      );
}

/// Parse `getAllMidiClipsInfo`: `;`-separated rows of
/// `clip_id,track_id,start_time,duration,note_count,plays,muted`. Rows from
/// an engine without the `plays` field count as playing when on a track, and
/// without `muted` as not muted.
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
        muted: f.length > 6 && f[6] == '1',
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
    midiClips: [
      for (final clip in parseMidiClipsInfo(engine.getAllMidiClipsInfo()))
        if (clip.plays)
          clip.withNotes(
            parseMidiClipNotes(engine.getMidiClipNotes(clip.clipId)),
          )
        else
          clip,
    ],
  );
}

String _muteWord(bool muted) => muted ? 'muted' : 'not muted';

/// The first note start or end the screen and the engine disagree on, as a
/// one-item list; empty when they hold the same notes, null when the
/// engine's weren't read.
///
/// Starts and ends are compared separately, not note by note. The engine
/// holds note-ons and note-offs and pairs them itself when asked for notes,
/// giving each note-off to the oldest sounding note of its pitch: a note
/// from beat 0 to 4 with another of the same pitch inside it, 1 to 2, comes
/// back as 0 to 2 and 1 to 4. The same events, so the same sound.
List<String>? _noteDifference(
  MidiClipData clip,
  List<EngineMidiNote>? engineNotes,
  double tempo,
) {
  if (engineNotes == null) return null;
  final secondsPerBeat = 60.0 / tempo;
  final screen = [
    for (final n in clip.unrolledNotes())
      EngineMidiNote(
        pitch: n.note,
        velocity: n.velocity,
        startSeconds: n.startTime * secondsPerBeat,
        lengthSeconds: n.duration * secondsPerBeat,
      ),
  ];
  if (screen.length != engineNotes.length) {
    return ['notes: screen ${screen.length}, engine ${engineNotes.length}'];
  }

  // (pitch, time, velocity) of every note start, in a fixed order.
  List<(int, double, int)> starts(List<EngineMidiNote> notes) =>
      [for (final n in notes) (n.pitch, n.startSeconds, n.velocity)]
        ..sort(_byPitchTimeVelocity);
  // Note ends carry no velocity.
  List<(int, double, int)> ends(List<EngineMidiNote> notes) =>
      [for (final n in notes) (n.pitch, n.startSeconds + n.lengthSeconds, 0)]
        ..sort(_byPitchTimeVelocity);

  String? firstDifference(
    String what,
    List<(int, double, int)> onScreen,
    List<(int, double, int)> inEngine,
  ) {
    for (var i = 0; i < onScreen.length; i++) {
      final (pitch, time, velocity) = onScreen[i];
      final (enginePitch, engineTime, engineVelocity) = inEngine[i];
      if (pitch != enginePitch ||
          velocity != engineVelocity ||
          (time - engineTime).abs() > _seconds) {
        String say(int p, double t, int v) =>
            'pitch $p at ${t.toStringAsFixed(3)}s'
            '${what == 'note start' ? ' (velocity $v)' : ''}';
        return '$what: screen ${say(pitch, time, velocity)}, '
            'engine ${say(enginePitch, engineTime, engineVelocity)}';
      }
    }
    return null;
  }

  final difference =
      firstDifference('note start', starts(screen), starts(engineNotes)) ??
      firstDifference('note end', ends(screen), ends(engineNotes));
  return [?difference];
}

int _byPitchTimeVelocity((int, double, int) a, (int, double, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
  return a.$3.compareTo(b.$3);
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
      if (e.noteCount != notes)
        'notes: screen $notes, engine ${e.noteCount}'
      else
        ...?_noteDifference(clip, e.notes, engine.tempo),
      if (e.muted != clip.isMuted)
        'mute: screen ${_muteWord(clip.isMuted)}, engine ${_muteWord(e.muted)}',
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
