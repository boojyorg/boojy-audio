import '../models/instrument_data.dart';
import '../models/midi_note_data.dart';

/// Service to generate meaningful names for MIDI clips
/// Priority: Instrument name → Track name → "MIDI"
class ClipNamingService {
  /// Generate a name for a new MIDI clip based on instrument and track info
  static String generateClipName({
    required InstrumentData? instrument,
    required String? trackName,
  }) {
    // Priority 1: Use instrument name
    if (instrument != null) {
      if (instrument.isVst3 && instrument.pluginName != null) {
        return instrument.pluginName!;
      } else if (instrument.type == 'synthesizer') {
        return 'Synthesizer';
      }
    }

    // Priority 2: Use track name
    if (trackName != null && trackName.isNotEmpty) {
      return trackName;
    }

    // Priority 3: Default fallback
    return 'MIDI';
  }

  /// Count instances of clips with the same pattern on a track
  static int countPatternInstances(
    List<MidiClipData> clips,
    int trackId,
    String? patternId,
  ) {
    if (patternId == null) return 1;
    return clips.where((c) => c.trackId == trackId && c.patternId == patternId).length;
  }

  /// Count total clips on a track with the same name
  static int countClipsWithName(
    List<MidiClipData> clips,
    int trackId,
    String name,
  ) {
    return clips.where((c) => c.trackId == trackId && c.name == name).length;
  }
}
