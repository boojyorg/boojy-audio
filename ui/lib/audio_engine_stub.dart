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
  String setClipOffset(int trackId, int clipId, double offset) =>
      throw UnsupportedError('stub');

  @override
  String setClipDuration(int trackId, int clipId, double duration) =>
      throw UnsupportedError('stub');

  @override
  String setAudioClipGain(int trackId, int clipId, double gainDb) =>
      throw UnsupportedError('stub');

  @override
  String setAudioClipWarp(int trackId, int clipId, bool warpEnabled, double stretchFactor, int warpMode) =>
      throw UnsupportedError('stub');

  @override
  String setAudioClipTranspose(int trackId, int clipId, int semitones, int cents) =>
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
  int addExistingClipToTrack(int clipId, int trackId, double startTime,
          {double offset = 0.0, double? duration}) =>
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

  String setTrackInput(int trackId, int deviceIndex, int channel) => 'OK';

  Map<String, int> getTrackInput(int trackId) =>
      {'deviceIndex': -1, 'channel': 0};

  String setTrackInputMonitoring(int trackId, {required bool enabled}) => 'OK';

  double getInputChannelLevel(int channel) => 0.0;

  int getInputChannelCount() => 0;

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

  // Sampler operations
  @override
  int createSamplerForTrack(int trackId) => throw UnsupportedError('stub');

  @override
  bool loadSampleForTrack(int trackId, String path, int rootNote) =>
      throw UnsupportedError('stub');

  @override
  String setSamplerParameter(int trackId, String param, String value) =>
      throw UnsupportedError('stub');

  @override
  bool isSamplerTrack(int trackId) => throw UnsupportedError('stub');

  // MIDI clip operations
  @override
  int createMidiClip() => throw UnsupportedError('stub');

  @override
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration) =>
      throw UnsupportedError('stub');

  @override
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) =>
      throw UnsupportedError('stub');

  @override
  void setTempo(double bpm) => throw UnsupportedError('stub');

  @override
  void setCountInBars(int bars) => throw UnsupportedError('stub');

  String getMidiClipInfo(int clipId) => throw UnsupportedError('stub');

  // Transport / playback
  double getPlayheadPosition() => throw UnsupportedError('stub');
  double getTempo() => throw UnsupportedError('stub');
  void transportPlay() => throw UnsupportedError('stub');
  void transportPause() => throw UnsupportedError('stub');
  void transportStop() => throw UnsupportedError('stub');
  void transportSeek(double position) => throw UnsupportedError('stub');

  // Recording
  void startRecording() => throw UnsupportedError('stub');
  int stopRecording() => throw UnsupportedError('stub');
  void startMidiRecording() => throw UnsupportedError('stub');
  int stopMidiRecording() => throw UnsupportedError('stub');
  int getRecordingState() => throw UnsupportedError('stub');
  int getCountInBeat() => throw UnsupportedError('stub');
  double getCountInProgress() => throw UnsupportedError('stub');
  double getRecordedDuration() => throw UnsupportedError('stub');
  void setMetronomeEnabled({required bool enabled}) =>
      throw UnsupportedError('stub');

  // MIDI
  void startMidiInput() => throw UnsupportedError('stub');
  List<Map<String, dynamic>> getMidiInputDevices() =>
      throw UnsupportedError('stub');
  void selectMidiInputDevice(int deviceIndex) =>
      throw UnsupportedError('stub');
  void refreshMidiDevices() => throw UnsupportedError('stub');
  String getMidiRecorderLiveEvents() => throw UnsupportedError('stub');

  // Audio device operations
  List<Map<String, dynamic>> getAudioInputDevices() => [];

  // Audio file operations (not in interface but used directly)
  int loadAudioFile(String path) => throw UnsupportedError('stub');

  List<int> getAllTrackIds() => throw UnsupportedError('stub');

  String getTrackPeakLevels(int trackId) => throw UnsupportedError('stub');

  @override
  void setTrackVolumeAutomation(int trackId, String csvData) =>
      throw UnsupportedError('stub');

  // Project operations (not in interface but used by ProjectManager)
  String saveProject(String projectName, String projectPath) =>
      throw UnsupportedError('stub');

  String loadProject(String projectPath) => throw UnsupportedError('stub');

  String loadProjectFromJson(String json) => throw UnsupportedError('stub');

  // Time signature
  String setTimeSignature(int beatsPerBar) => throw UnsupportedError('stub');

  int getTimeSignature() => throw UnsupportedError('stub');

  // Buffer size presets
  static const Map<int, String> bufferSizePresets = {};
}
