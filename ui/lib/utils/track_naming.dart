/// Whether [name] is one Boojy gave a track rather than one the user typed:
/// a default ("MIDI", "MIDI 3", "Audio 2"), a built-in instrument's name
/// ("Synthesizer", "Sampler", "Sampler: kick", "Drum Kit"), or the name of the
/// plugin currently on the track. Dropping an instrument renames only such
/// tracks. Decided from the name alone, so it holds after reopening a project.
bool isAutomaticTrackName(String name, {String? currentPluginName}) {
  final n = name.trim();
  if (n.isEmpty) return true;
  if (RegExp(r'^(MIDI|Audio)( \d+)?$').hasMatch(n)) return true;
  if (const {'Synthesizer', 'Sampler', 'Drum Kit'}.contains(n)) return true;
  if (n.startsWith('Sampler: ')) return true;
  return currentPluginName != null && currentPluginName == n;
}
