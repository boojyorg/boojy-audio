/// Abstract interface for AudioEngine to enable testing.
/// Commands use this interface instead of the concrete AudioEngine class,
/// allowing mock implementations in tests.
abstract class AudioEngineInterface {
  // Clip operations
  String setClipStartTime(int trackId, int clipId, double startTime);
  String setClipOffset(int trackId, int clipId, double offset);
  String setClipDuration(int trackId, int clipId, double duration);
  String setAudioClipGain(int trackId, int clipId, double gainDb);
  String setAudioClipWarp(int trackId, int clipId, bool warpEnabled, double stretchFactor, int warpMode);
  String setAudioClipTranspose(int trackId, int clipId, int semitones, int cents);
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0});
  double getClipDuration(int clipId);
  List<double> getWaveformPeaks(int clipId, int resolution);
  bool removeAudioClip(int trackId, int clipId);
  int addExistingClipToTrack(int clipId, int trackId, double startTime,
      {double offset = 0.0, double? duration});
  int duplicateAudioClip(int trackId, int clipId, double startTime);

  // Track operations
  int createTrack(String trackType, String name);
  String deleteTrack(int trackId);
  int duplicateTrack(int sourceTrackId);
  String getTrackInfo(int trackId);
  void setTrackName(int trackId, String name);
  void setTrackVolume(int trackId, double volumeDb);
  void setTrackVolumeAutomation(int trackId, String csvData);
  void setTrackPan(int trackId, double pan);
  void setTrackMute(int trackId, {required bool mute});
  void setTrackSolo(int trackId, {required bool solo});
  void setTrackArmed(int trackId, {required bool armed});

  // Effect operations
  int addEffectToTrack(int trackId, String effectType);
  int addVst3EffectToTrack(int trackId, String effectPath);
  String removeEffectFromTrack(int trackId, int effectId);
  void setEffectBypass(int effectId, {required bool bypassed});
  void reorderTrackEffects(int trackId, List<int> order);
  bool setVst3ParameterValue(int effectId, int paramIndex, double value);

  // Sampler operations
  int createSamplerForTrack(int trackId);
  bool loadSampleForTrack(int trackId, String path, int rootNote);
  String setSamplerParameter(int trackId, String param, String value);
  bool isSamplerTrack(int trackId);

  // MIDI clip operations
  int createMidiClip();
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration);
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds);
  int removeMidiClip(int trackId, int clipId);

  // Project operations
  void setTempo(double bpm);
  void setCountInBars(int bars);

  // Library preview operations
  String previewLoadAudio(String path);
  void previewPlay();
  void previewStop();
  void previewSeek(double positionSeconds);
  double previewGetPosition();
  double previewGetDuration();
  bool previewIsPlaying();
  void previewSetLooping(bool shouldLoop);
  bool previewIsLooping();
  List<double> previewGetWaveform(int resolution);

  // Punch recording operations
  String setPunchInEnabled({required bool enabled});
  bool isPunchInEnabled();
  String setPunchOutEnabled({required bool enabled});
  bool isPunchOutEnabled();
  String setPunchRegion(double inSeconds, double outSeconds);
  double getPunchInSeconds();
  double getPunchOutSeconds();
  bool isPunchComplete();
}
