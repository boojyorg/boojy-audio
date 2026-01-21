/// Abstract interface for AudioEngine to enable testing.
/// Commands use this interface instead of the concrete AudioEngine class,
/// allowing mock implementations in tests.
abstract class AudioEngineInterface {
  // Clip operations
  void setClipStartTime(int trackId, int clipId, double startTime);
  String setAudioClipGain(int trackId, int clipId, double gainDb);
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0});
  double getClipDuration(int clipId);
  List<double> getWaveformPeaks(int clipId, int resolution);
  void removeAudioClip(int trackId, int clipId);
  int duplicateAudioClip(int trackId, int clipId, double startTime);

  // Track operations
  int createTrack(String trackType, String name);
  void deleteTrack(int trackId);
  int duplicateTrack(int sourceTrackId);
  String getTrackInfo(int trackId);
  void setTrackName(int trackId, String name);
  void setTrackVolume(int trackId, double volumeDb);
  void setTrackPan(int trackId, double pan);
  void setTrackMute(int trackId, {required bool mute});
  void setTrackSolo(int trackId, {required bool solo});
  void setTrackArmed(int trackId, {required bool armed});

  // Effect operations
  int addEffectToTrack(int trackId, String effectType);
  int addVst3EffectToTrack(int trackId, String effectPath);
  void removeEffectFromTrack(int trackId, int effectId);
  void setEffectBypass(int effectId, {required bool bypassed});
  void reorderTrackEffects(int trackId, List<int> order);
  void setVst3ParameterValue(int effectId, int paramIndex, double value);

  // Sampler operations
  int createSamplerForTrack(int trackId);
  bool loadSampleForTrack(int trackId, String path, int rootNote);
  String setSamplerParameter(int trackId, String param, String value);
  bool isSamplerTrack(int trackId);

  // MIDI clip operations
  int createMidiClip();
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration);
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds);

  // Project operations
  void setTempo(double bpm);
  void setCountInBars(int bars);
}
