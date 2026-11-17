import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/services/audio_clip_engine_sync.dart';
import 'package:boojy_audio/services/state_consistency.dart';

import 'daw_harness.dart';

// Steps shared by the workflow tests split out of daw_workflow_test.dart.

/// Drop a 2 s click file onto the empty arrangement; returns its clip.
Future<ClipData> dropClip(DawHarness h, String name) async {
  await h.daw.onAudioFileDroppedOnEmpty(h.writeClickWav(name));
  await h.settle();
  return h.daw.timelineKey.currentState!.clips.last;
}

/// Warp a clip at [bpm], as the audio editor does.
Future<ClipData> warp(DawHarness h, ClipData clip, double bpm) async {
  final edit = AudioClipEditData(bpm: bpm, syncEnabled: true);
  pushAudioClipEdits(h.engine, clip.trackId, clip.clipId, edit);
  final warped = clip.copyWith(editData: edit);
  h.daw.timelineKey.currentState!.updateClip(warped);
  await h.settle();
  return warped;
}

/// Edit a clip as the audio editor does: the change, then one undo step.
Future<ClipData> editClip(
  DawHarness h,
  ClipData clip,
  AudioClipEditData edit,
) async {
  h.daw.onAudioClipEdited(clip.copyWith(editData: edit));
  await h.daw.onAudioClipEditFinished('Edit clip');
  await h.settle();
  return h.daw.timelineKey.currentState!.clips.firstWhere(
    (c) => c.clipId == clip.clipId,
  );
}

double engineStretch(DawHarness h, int clipId) => EngineSnapshot.read(
  h.engine,
).audioClips.firstWhere((c) => c.clipId == clipId).stretchFactor;
