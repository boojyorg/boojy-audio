// Stub file for conditional imports - used during static analysis
// This file should never be imported directly at runtime
// ignore_for_file: avoid_positional_boolean_parameters

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

  // Buffer size presets
  static const Map<int, String> bufferSizePresets = {};

  // ========================================================================
  // Init & Config
  // ========================================================================

  String initAudioEngine() => throw UnsupportedError('stub');
  String playSineWave(double frequency, int durationMs) => throw UnsupportedError('stub');
  String initAudioGraph() => throw UnsupportedError('stub');

  // ========================================================================
  // Transport & Playback
  // ========================================================================

  double getPlayheadPosition() => throw UnsupportedError('stub');
  int getTransportState() => throw UnsupportedError('stub');
  void transportPlay() => throw UnsupportedError('stub');
  void transportPause() => throw UnsupportedError('stub');
  void transportStop() => throw UnsupportedError('stub');
  void transportSeek(double position) => throw UnsupportedError('stub');
  double getPlayStartPosition() => throw UnsupportedError('stub');
  String setPlayStartPosition(double positionSeconds) => throw UnsupportedError('stub');
  double getRecordStartPosition() => throw UnsupportedError('stub');
  String setRecordStartPosition(double positionSeconds) => throw UnsupportedError('stub');

  // ========================================================================
  // Latency & Buffer Control
  // ========================================================================

  String setBufferSize(int preset) => throw UnsupportedError('stub');
  int getBufferSizePreset() => throw UnsupportedError('stub');
  int getActualBufferSize() => throw UnsupportedError('stub');
  Map<String, double> getLatencyInfo() => throw UnsupportedError('stub');
  String startLatencyTest() => throw UnsupportedError('stub');
  String stopLatencyTest() => throw UnsupportedError('stub');
  (int, double) getLatencyTestStatus() => throw UnsupportedError('stub');
  String? getLatencyTestError() => throw UnsupportedError('stub');
  Future<double?> runLatencyTest({Duration timeout = const Duration(seconds: 5), Duration pollInterval = const Duration(milliseconds: 100)}) => throw UnsupportedError('stub');

  // ========================================================================
  // Audio File Operations
  // ========================================================================

  int loadAudioFile(String path) => throw UnsupportedError('stub');

  @override
  int loadAudioFileToTrack(String filePath, int trackId, {double startTime = 0.0}) =>
      throw UnsupportedError('stub');

  @override
  double getClipDuration(int clipId) => throw UnsupportedError('stub');

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) =>
      throw UnsupportedError('stub');

  // ========================================================================
  // Clip Operations
  // ========================================================================

  @override
  String setClipStartTime(int trackId, int clipId, double startTime) =>
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
  bool removeAudioClip(int trackId, int clipId) =>
      throw UnsupportedError('stub');

  @override
  int addExistingClipToTrack(int clipId, int trackId, double startTime,
          {double offset = 0.0, double? duration}) =>
      throw UnsupportedError('stub');

  @override
  int duplicateAudioClip(int trackId, int clipId, double startTime) =>
      throw UnsupportedError('stub');

  // ========================================================================
  // Track Operations
  // ========================================================================

  @override
  int createTrack(String trackType, String name) =>
      throw UnsupportedError('stub');

  @override
  String deleteTrack(int trackId) => throw UnsupportedError('stub');

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
  void setTrackVolumeAutomation(int trackId, String csvData) =>
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

  int getTrackCount() => throw UnsupportedError('stub');
  List<int> getAllTrackIds() => throw UnsupportedError('stub');
  String getTrackPeakLevels(int trackId) => throw UnsupportedError('stub');
  String clearAllTracks() => throw UnsupportedError('stub');

  // Track input
  String setTrackInput(int trackId, int deviceIndex, int channel) => throw UnsupportedError('stub');
  Map<String, int> getTrackInput(int trackId) => throw UnsupportedError('stub');
  String setTrackInputMonitoring(int trackId, {required bool enabled}) => throw UnsupportedError('stub');

  // ========================================================================
  // Effects
  // ========================================================================

  @override
  int addEffectToTrack(int trackId, String effectType) =>
      throw UnsupportedError('stub');

  @override
  int addVst3EffectToTrack(int trackId, String effectPath) =>
      throw UnsupportedError('stub');

  @override
  String removeEffectFromTrack(int trackId, int effectId) =>
      throw UnsupportedError('stub');

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) =>
      throw UnsupportedError('stub');

  bool getEffectBypass(int effectId) => throw UnsupportedError('stub');

  @override
  void reorderTrackEffects(int trackId, List<int> order) =>
      throw UnsupportedError('stub');

  String getTrackEffects(int trackId) => throw UnsupportedError('stub');
  String getEffectInfo(int effectId) => throw UnsupportedError('stub');
  String setEffectParameter(int effectId, String paramName, double value) => throw UnsupportedError('stub');

  // ========================================================================
  // Sampler
  // ========================================================================

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

  // ========================================================================
  // Instruments & Synth
  // ========================================================================

  int setTrackInstrument(int trackId, String instrumentType) => throw UnsupportedError('stub');
  String setSynthParameter(int trackId, String paramName, dynamic value) => throw UnsupportedError('stub');
  String getSynthParameters(int trackId) => throw UnsupportedError('stub');
  String sendTrackMidiNoteOn(int trackId, int note, int velocity) => throw UnsupportedError('stub');
  String sendTrackMidiNoteOff(int trackId, int note, int velocity) => throw UnsupportedError('stub');

  // ========================================================================
  // MIDI Clip Operations
  // ========================================================================

  @override
  int createMidiClip() => throw UnsupportedError('stub');

  @override
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration) =>
      throw UnsupportedError('stub');

  @override
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) =>
      throw UnsupportedError('stub');

  @override
  int removeMidiClip(int trackId, int clipId) => throw UnsupportedError('stub');

  String clearMidiClip(int clipId) => throw UnsupportedError('stub');
  String quantizeMidiClip(int clipId, int gridDivision) => throw UnsupportedError('stub');
  String getMidiClipInfo(int clipId) => throw UnsupportedError('stub');
  String getAllMidiClipsInfo() => throw UnsupportedError('stub');
  String getMidiClipNotes(int clipId) => throw UnsupportedError('stub');

  // ========================================================================
  // MIDI Input & Synth
  // ========================================================================

  String startMidiInput() => throw UnsupportedError('stub');
  String stopMidiInput() => throw UnsupportedError('stub');
  String setSynthOscillatorType(int oscType) => throw UnsupportedError('stub');
  String setSynthVolume(double volume) => throw UnsupportedError('stub');
  String sendMidiNoteOn(int note, int velocity) => throw UnsupportedError('stub');
  String sendMidiNoteOff(int note, int velocity) => throw UnsupportedError('stub');
  List<Map<String, dynamic>> getMidiInputDevices() => throw UnsupportedError('stub');
  void selectMidiInputDevice(int deviceIndex) => throw UnsupportedError('stub');
  void refreshMidiDevices() => throw UnsupportedError('stub');
  String getMidiRecorderLiveEvents() => throw UnsupportedError('stub');

  // ========================================================================
  // Recording
  // ========================================================================

  void startRecording() => throw UnsupportedError('stub');
  int stopRecording() => throw UnsupportedError('stub');
  void startMidiRecording() => throw UnsupportedError('stub');
  int stopMidiRecording() => throw UnsupportedError('stub');
  int getRecordingState() => throw UnsupportedError('stub');
  int getMidiRecordingState() => throw UnsupportedError('stub');
  double getRecordedDuration() => throw UnsupportedError('stub');
  List<double> getRecordingWaveform(int numPeaks) => throw UnsupportedError('stub');

  // ========================================================================
  // Tempo, Metronome, Time Signature
  // ========================================================================

  @override
  void setTempo(double bpm) => throw UnsupportedError('stub');

  double getTempo() => throw UnsupportedError('stub');

  @override
  void setCountInBars(int bars) => throw UnsupportedError('stub');

  String getCountInBars() => throw UnsupportedError('stub');
  int getCountInBeat() => throw UnsupportedError('stub');
  double getCountInProgress() => throw UnsupportedError('stub');
  void setMetronomeEnabled({required bool enabled}) => throw UnsupportedError('stub');
  bool isMetronomeEnabled() => throw UnsupportedError('stub');
  String setTimeSignature(int beatsPerBar) => throw UnsupportedError('stub');
  int getTimeSignature() => throw UnsupportedError('stub');

  // ========================================================================
  // Audio Devices
  // ========================================================================

  List<Map<String, dynamic>> getAudioInputDevices() => throw UnsupportedError('stub');
  List<Map<String, dynamic>> getAudioOutputDevices() => throw UnsupportedError('stub');
  String setAudioInputDevice(int deviceIndex) => throw UnsupportedError('stub');
  String setAudioOutputDevice(String deviceName) => throw UnsupportedError('stub');
  String getSelectedAudioOutputDevice() => throw UnsupportedError('stub');
  double getInputChannelLevel(int channel) => throw UnsupportedError('stub');
  int getInputChannelCount() => throw UnsupportedError('stub');
  int getSampleRate() => throw UnsupportedError('stub');

  // ========================================================================
  // VST3 Plugin Hosting
  // ========================================================================

  List<Map<String, String>> scanVst3PluginsStandard() => throw UnsupportedError('stub');
  int getVst3ParameterCount(int effectId) => throw UnsupportedError('stub');
  Map<String, dynamic>? getVst3ParameterInfo(int effectId, int paramIndex) => throw UnsupportedError('stub');
  double getVst3ParameterValue(int effectId, int paramIndex) => throw UnsupportedError('stub');

  @override
  bool setVst3ParameterValue(int effectId, int paramIndex, double value) =>
      throw UnsupportedError('stub');

  bool vst3HasEditor(int effectId) => throw UnsupportedError('stub');
  String vst3OpenEditor(int effectId) => throw UnsupportedError('stub');
  void vst3CloseEditor(int effectId) => throw UnsupportedError('stub');
  Map<String, int>? vst3GetEditorSize(int effectId) => throw UnsupportedError('stub');
  String vst3AttachEditor(int effectId, dynamic parentPtr) => throw UnsupportedError('stub');
  String vst3SendMidiNote(int effectId, int eventType, int channel, int note, int velocity) => throw UnsupportedError('stub');

  // ========================================================================
  // Project Operations
  // ========================================================================

  String saveProject(String projectName, String projectPath) =>
      throw UnsupportedError('stub');

  String loadProject(String projectPath) => throw UnsupportedError('stub');
  String loadProjectFromJson(String json) => throw UnsupportedError('stub');

  // ========================================================================
  // Export
  // ========================================================================

  String exportToWav(String outputPath, {required bool normalize}) => throw UnsupportedError('stub');
  bool isFfmpegAvailable() => throw UnsupportedError('stub');
  String exportAudio(String outputPath, String optionsJson) => throw UnsupportedError('stub');
  String exportWavWithOptions({
    required String outputPath,
    int bitDepth = 16,
    int sampleRate = 44100,
    bool normalize = false,
    bool dither = false,
    bool mono = false,
  }) => throw UnsupportedError('stub');
  String exportMp3WithOptions({
    required String outputPath,
    int bitrate = 320,
    int sampleRate = 44100,
    bool normalize = false,
    bool mono = false,
  }) => throw UnsupportedError('stub');
  String writeMp3Metadata(String filePath, String metadataJson) => throw UnsupportedError('stub');
  String getTracksForStems() => throw UnsupportedError('stub');
  String exportStems({
    required String outputDir,
    required String baseName,
    String trackIdsJson = '',
    required String optionsJson,
  }) => throw UnsupportedError('stub');
  String getExportProgress() => throw UnsupportedError('stub');
  void cancelExport() => throw UnsupportedError('stub');
  void resetExportProgress() => throw UnsupportedError('stub');

  // ========================================================================
  // Library Preview
  // ========================================================================

  @override
  String previewLoadAudio(String path) => throw UnsupportedError('stub');

  @override
  void previewPlay() => throw UnsupportedError('stub');

  @override
  void previewStop() => throw UnsupportedError('stub');

  @override
  void previewSeek(double positionSeconds) => throw UnsupportedError('stub');

  @override
  double previewGetPosition() => throw UnsupportedError('stub');

  @override
  double previewGetDuration() => throw UnsupportedError('stub');

  @override
  bool previewIsPlaying() => throw UnsupportedError('stub');

  @override
  void previewSetLooping(bool shouldLoop) => throw UnsupportedError('stub');

  @override
  bool previewIsLooping() => throw UnsupportedError('stub');

  @override
  List<double> previewGetWaveform(int resolution) => throw UnsupportedError('stub');

  // ========================================================================
  // Punch Recording
  // ========================================================================

  @override
  String setPunchInEnabled({required bool enabled}) => throw UnsupportedError('stub');

  @override
  bool isPunchInEnabled() => throw UnsupportedError('stub');

  @override
  String setPunchOutEnabled({required bool enabled}) => throw UnsupportedError('stub');

  @override
  bool isPunchOutEnabled() => throw UnsupportedError('stub');

  @override
  String setPunchRegion(double inSeconds, double outSeconds) => throw UnsupportedError('stub');

  @override
  double getPunchInSeconds() => throw UnsupportedError('stub');

  @override
  double getPunchOutSeconds() => throw UnsupportedError('stub');

  @override
  bool isPunchComplete() => throw UnsupportedError('stub');
}
