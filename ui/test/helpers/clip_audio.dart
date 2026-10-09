import 'package:boojy_audio/models/clip_data.dart';

/// The second of its audio file [clip] plays [x] seconds (of its own audio)
/// after its start, as the engine reads it (`render_audio_clip_sample`).
double audioAt(ClipData clip, double x) {
  final reversed = clip.editData?.reversed ?? false;
  if (clip.isLooped) {
    final into = (clip.loopStart + x) % clip.loopLength;
    return clip.offset + (reversed ? clip.loopLength - into : into);
  }
  return reversed ? clip.offset + clip.duration - x : clip.offset + x;
}
