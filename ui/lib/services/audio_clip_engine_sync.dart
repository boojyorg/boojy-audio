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
