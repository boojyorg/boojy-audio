// Stub file for conditional imports - used during static analysis
// This file should never be imported directly at runtime

import 'services/commands/audio_engine_interface.dart';

/// Stub AudioEngine that throws on all methods
/// This is only used for static analysis and should never be instantiated
class AudioEngine implements AudioEngineInterface {
  AudioEngine() {
    throw UnsupportedError(
      'AudioEngine stub should not be instantiated. '
      'Use conditional imports to get the correct implementation.',
    );
  }

  @override
  void setClipStartTime(int trackId, int clipId, double startTime) =>
      throw UnsupportedError('stub');

  @override
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0}) =>
      throw UnsupportedError('stub');

  @override
  double getClipDuration(int clipId) => throw UnsupportedError('stub');

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) =>
      throw UnsupportedError('stub');

  @override
  void removeAudioClip(int trackId, int clipId) =>
      throw UnsupportedError('stub');

  @override
  int duplicateAudioClip(int trackId, int clipId, double startTime) =>
      throw UnsupportedError('stub');

  @override
  int createTrack(String trackType, String name) =>
      throw UnsupportedError('stub');

  @override
  void deleteTrack(int trackId) => throw UnsupportedError('stub');

  @override
  int duplicateTrack(int sourceTrackId) => throw UnsupportedError('stub');

  @override
  String getTrackInfo(int trackId) => throw UnsupportedError('stub');

  @override
  void setTrackName(int trackId, String name) =>
      throw UnsupportedError('stub');

  @override
  void setTrackVolume(int trackId, double volumeDb) =>
      throw UnsupportedError('stub');

  @override
  void setTrackPan(int trackId, double pan) => throw UnsupportedError('stub');

  @override
  void setTrackMute(int trackId, {required bool mute}) =>
      throw UnsupportedError('stub');

  @override
  void setTrackSolo(int trackId, {required bool solo}) =>
      throw UnsupportedError('stub');

  @override
  void setTrackArmed(int trackId, {required bool armed}) =>
      throw UnsupportedError('stub');

  @override
  int addEffectToTrack(int trackId, String effectType) =>
      throw UnsupportedError('stub');

  @override
  int addVst3EffectToTrack(int trackId, String effectPath) =>
      throw UnsupportedError('stub');

  @override
  void removeEffectFromTrack(int trackId, int effectId) =>
      throw UnsupportedError('stub');

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) =>
      throw UnsupportedError('stub');

  @override
  void reorderTrackEffects(int trackId, List<int> order) =>
      throw UnsupportedError('stub');

  @override
  void setVst3ParameterValue(int effectId, int paramIndex, double value) =>
      throw UnsupportedError('stub');

  @override
  void setTempo(double bpm) => throw UnsupportedError('stub');

  @override
  void setCountInBars(int bars) => throw UnsupportedError('stub');

  // Project operations (not in interface but used by ProjectManager)
  String saveProject(String projectName, String projectPath) =>
      throw UnsupportedError('stub');

  String loadProject(String projectPath) => throw UnsupportedError('stub');

  String loadProjectFromJson(String json) => throw UnsupportedError('stub');

  // Buffer size presets
  static const Map<int, String> bufferSizePresets = {};
}
