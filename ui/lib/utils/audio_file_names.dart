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

/// Id of the "couldn't find these samples" notice, so a later project (opened,
/// new or closed) can take the previous one's notice away.
const missingSamplesNoticeId = 'missing-samples';

/// The notice to show when a project opens with sampler or drum-pad samples
/// the engine could not find, or null when [fileNames] is empty. A name used
/// by several pads is listed once; a long list is cut to three names.
String? missingSamplesMessage(List<String> fileNames) {
  final names = fileNames.toSet().toList();
  if (names.isEmpty) return null;
  if (names.length == 1) {
    return "Couldn't find the sample ${names.first}. "
        'It stays silent until you load it again.';
  }
  const shown = 3;
  final listed = names.take(shown).join(', ');
  final more = names.length > shown ? ' and ${names.length - shown} more' : '';
  return "Couldn't find ${names.length} samples: $listed$more. "
      'They stay silent until you load them again.';
}
