/// The name to show for an audio file.
///
/// A save copies audio into the project's `audio/` folder as `NNN-name.wav`
/// (clip id, dash, name). Inside such a folder those leading `NNN-` groups are
/// bookkeeping, not part of the name, so they are stripped: `014-010-kick.wav`
/// shows as `kick.wav`. A file anywhere else keeps its name exactly, so a
/// sample you called `808-kick.wav` is never shortened.
///
/// Mirrors `clean_audio_file_name` in engine/src/project.rs — keep in sync.
String cleanAudioFileName(String path) {
  final segments = path.split(RegExp(r'[/\\]'));
  final name = segments.isEmpty ? path : segments.last;

  final inProjectAudioDir =
      segments.length >= 3 &&
      segments[segments.length - 2] == 'audio' &&
      segments[segments.length - 3].endsWith('.audio');
  if (!inProjectAudioDir) return name;

  var rest = name;
  final prefix = RegExp(r'^\d{3,}-(?=.)');
  while (prefix.hasMatch(rest)) {
    rest = rest.replaceFirst(prefix, '');
  }
  return rest;
}
