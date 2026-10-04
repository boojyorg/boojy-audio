import '../models/audio_clip_edit_data.dart';
import '../models/clip_data.dart';
import 'commands/audio_engine_interface.dart';

/// Send a clip's edits (gain, warp, pitch, reverse) to the engine.
///
/// The warp stretch comes from the clip's own BPM and the engine's current
/// tempo at the moment of sending, so it always matches the project.
void pushAudioClipEdits(
  AudioEngineInterface engine,
  int trackId,
  int clipId,
  AudioClipEditData edit,
) {
  engine.setAudioClipGain(trackId, clipId, edit.gainDb);
  _pushWarp(engine, trackId, clipId, edit);
  engine.setAudioClipTranspose(
    trackId,
    clipId,
    edit.transposeSemitones,
    edit.fineCents,
  );
  engine.setAudioClipReverse(trackId, clipId, reversed: edit.reversed);
}

/// Put a removed clip back in the engine: reload its file at its position,
/// then re-apply its trim and its edits. Returns the engine's new clip ID
/// (-1 if the file wouldn't load). Restores used to bring back the trim only,
/// so a warped, reversed or pitched clip came back as the plain file while
/// the screen still showed its edits.
///
/// The clip comes back under its own ID when the engine still holds its audio
/// (it keeps a deleted clip's audio), so undo and redo steps before and after
/// still find it; reloading the file is the fallback.
int restoreAudioClip(AudioEngineInterface engine, ClipData clip) {
  final id = placeAudioFile(
    engine,
    clip.filePath,
    clip.trackId,
    clip.startTime,
    reuseId: clip.clipId,
  );
  if (id < 0) return id;
  engine.setClipOffset(clip.trackId, id, clip.offset);
  engine.setClipDuration(clip.trackId, id, clip.duration);
  final edit = clip.editData;
  if (edit != null) pushAudioClipEdits(engine, clip.trackId, id, edit);
  return id;
}

/// Put an audio file on a track at [startTime] and return its clip ID. With
/// [reuseId] (a redo, or a restore) the clip comes back under that ID from
/// the engine's clip store; only the first time, or if the store no longer
/// has it, is the file loaded under a fresh ID.
int placeAudioFile(
  AudioEngineInterface engine,
  String filePath,
  int trackId,
  double startTime, {
  int? reuseId,
}) {
  if (reuseId != null &&
      engine.addExistingClipToTrack(reuseId, trackId, startTime) >= 0) {
    return reuseId;
  }
  return engine.loadAudioFileToTrack(filePath, trackId, startTime: startTime);
}

/// Re-stretch every warped clip to the engine's current tempo. Call once a
/// tempo change is finished (not on every step of a drag: each call
/// re-renders the stretched audio of every warped clip).
void pushWarpForTempo(AudioEngineInterface engine, Iterable<ClipData> clips) {
  for (final clip in clips) {
    final edit = clip.editData;
    if (edit != null && edit.syncEnabled) {
      _pushWarp(engine, clip.trackId, clip.clipId, edit);
    }
  }
}

void _pushWarp(
  AudioEngineInterface engine,
  int trackId,
  int clipId,
  AudioClipEditData edit,
) {
  engine.setAudioClipWarp(
    trackId,
    clipId,
    edit.syncEnabled,
    edit.stretchAt(engine.getTempo()),
  );
}
