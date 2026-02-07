import 'package:boojy_audio/models/sampler_info.dart';
import 'package:boojy_audio/services/commands/audio_engine_interface.dart';

/// Shared mock AudioEngine for testing commands and services.
/// Tracks all method calls for verification and provides configurable return values.
class MockAudioEngine implements AudioEngineInterface {
  /// Ordered list of method names called on this mock.
  final List<String> calls = [];

  /// Configurable return values.
  int nextTrackId = 1;
  int nextEffectId = 1;
  int nextClipId = 1;
  String trackInfoResponse = '';

  void _record(String method) => calls.add(method);

  /// Reset call history and return values.
  void reset() {
    calls.clear();
    nextTrackId = 1;
    nextEffectId = 1;
    nextClipId = 1;
    trackInfoResponse = '';
  }

  // --- Clip operations ---

  @override
  String setClipStartTime(int trackId, int clipId, double startTime) {
    _record('setClipStartTime');
    return 'OK';
  }

  @override
  String setClipOffset(int trackId, int clipId, double offset) {
    _record('setClipOffset');
    return 'OK';
  }

  @override
  String setClipDuration(int trackId, int clipId, double duration) {
    _record('setClipDuration');
    return 'OK';
  }

  @override
  String setAudioClipGain(int trackId, int clipId, double gainDb) {
    _record('setAudioClipGain');
    return 'OK';
  }

  @override
  String setAudioClipWarp(int trackId, int clipId, bool warpEnabled,
      double stretchFactor, int warpMode) {
    _record('setAudioClipWarp');
    return 'OK';
  }

  @override
  String setAudioClipTranspose(
      int trackId, int clipId, int semitones, int cents) {
    _record('setAudioClipTranspose');
    return 'OK';
  }

  @override
  int loadAudioFileToTrack(String filePath, int trackId,
      {double startTime = 0.0}) {
    _record('loadAudioFileToTrack');
    return nextClipId++;
  }

  @override
  double getClipDuration(int clipId) {
    _record('getClipDuration');
    return 4.0;
  }

  @override
  List<double> getWaveformPeaks(int clipId, int resolution) {
    _record('getWaveformPeaks');
    return [];
  }

  @override
  bool removeAudioClip(int trackId, int clipId) {
    _record('removeAudioClip');
    return true;
  }

  @override
  int addExistingClipToTrack(int clipId, int trackId, double startTime,
      {double offset = 0.0, double? duration}) {
    _record('addExistingClipToTrack');
    return nextClipId++;
  }

  @override
  int duplicateAudioClip(int trackId, int clipId, double startTime) {
    _record('duplicateAudioClip');
    return clipId + 1000;
  }

  // --- Track operations ---

  @override
  int createTrack(String trackType, String name) {
    _record('createTrack');
    return nextTrackId++;
  }

  @override
  String deleteTrack(int trackId) {
    _record('deleteTrack');
    return 'OK';
  }

  @override
  int duplicateTrack(int sourceTrackId) {
    _record('duplicateTrack');
    return sourceTrackId + 1000;
  }

  @override
  String getTrackInfo(int trackId) {
    _record('getTrackInfo');
    return trackInfoResponse;
  }

  @override
  void setTrackName(int trackId, String name) => _record('setTrackName');

  @override
  void setTrackVolume(int trackId, double volumeDb) =>
      _record('setTrackVolume');

  @override
  void setTrackVolumeAutomation(int trackId, String csvData) =>
      _record('setTrackVolumeAutomation');

  @override
  void setTrackPan(int trackId, double pan) => _record('setTrackPan');

  @override
  void setTrackMute(int trackId, {required bool mute}) =>
      _record('setTrackMute');

  @override
  void setTrackSolo(int trackId, {required bool solo}) =>
      _record('setTrackSolo');

  @override
  void setTrackArmed(int trackId, {required bool armed}) =>
      _record('setTrackArmed');

  // --- Effect operations ---

  @override
  int addEffectToTrack(int trackId, String effectType) {
    _record('addEffectToTrack');
    return nextEffectId++;
  }

  @override
  int addVst3EffectToTrack(int trackId, String effectPath) {
    _record('addVst3EffectToTrack');
    return nextEffectId++;
  }

  @override
  String removeEffectFromTrack(int trackId, int effectId) {
    _record('removeEffectFromTrack');
    return 'OK';
  }

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) =>
      _record('setEffectBypass');

  @override
  void reorderTrackEffects(int trackId, List<int> order) =>
      _record('reorderTrackEffects');

  @override
  bool setVst3ParameterValue(int effectId, int paramIndex, double value) {
    _record('setVst3ParameterValue');
    return true;
  }

  // --- Sampler operations ---

  @override
  int createSamplerForTrack(int trackId) {
    _record('createSamplerForTrack');
    return 1;
  }

  @override
  bool loadSampleForTrack(int trackId, String path, int rootNote) {
    _record('loadSampleForTrack');
    return true;
  }

  @override
  String setSamplerParameter(int trackId, String param, String value) {
    _record('setSamplerParameter');
    return 'OK';
  }

  @override
  bool isSamplerTrack(int trackId) {
    _record('isSamplerTrack');
    return false;
  }

  @override
  SamplerInfo? getSamplerInfo(int trackId) {
    _record('getSamplerInfo');
    return null;
  }

  @override
  List<double> getSamplerWaveformPeaks(int trackId, int resolution) {
    _record('getSamplerWaveformPeaks');
    return [];
  }

  // --- MIDI clip operations ---

  @override
  int createMidiClip() {
    _record('createMidiClip');
    return nextClipId++;
  }

  @override
  String addMidiNoteToClip(
      int clipId, int note, int velocity, double startTime, double duration) {
    _record('addMidiNoteToClip');
    return 'OK';
  }

  @override
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) {
    _record('addMidiClipToTrack');
    return 1;
  }

  @override
  int removeMidiClip(int trackId, int clipId) {
    _record('removeMidiClip');
    return 1;
  }

  // --- Project operations ---

  @override
  void setTempo(double bpm) => _record('setTempo');

  @override
  void setCountInBars(int bars) => _record('setCountInBars');

  // --- Library preview operations ---

  @override
  String previewLoadAudio(String path) {
    _record('previewLoadAudio');
    return 'OK';
  }

  @override
  void previewPlay() => _record('previewPlay');

  @override
  void previewStop() => _record('previewStop');

  @override
  void previewSeek(double positionSeconds) => _record('previewSeek');

  @override
  double previewGetPosition() {
    _record('previewGetPosition');
    return 0.0;
  }

  @override
  double previewGetDuration() {
    _record('previewGetDuration');
    return 0.0;
  }

  @override
  bool previewIsPlaying() {
    _record('previewIsPlaying');
    return false;
  }

  @override
  void previewSetLooping(bool shouldLoop) => _record('previewSetLooping');

  @override
  bool previewIsLooping() {
    _record('previewIsLooping');
    return false;
  }

  @override
  List<double> previewGetWaveform(int resolution) {
    _record('previewGetWaveform');
    return [];
  }

  // --- Punch recording operations ---

  @override
  String setPunchInEnabled({required bool enabled}) {
    _record('setPunchInEnabled');
    return 'OK';
  }

  @override
  bool isPunchInEnabled() {
    _record('isPunchInEnabled');
    return false;
  }

  @override
  String setPunchOutEnabled({required bool enabled}) {
    _record('setPunchOutEnabled');
    return 'OK';
  }

  @override
  bool isPunchOutEnabled() {
    _record('isPunchOutEnabled');
    return false;
  }

  @override
  String setPunchRegion(double inSeconds, double outSeconds) {
    _record('setPunchRegion');
    return 'OK';
  }

  @override
  double getPunchInSeconds() {
    _record('getPunchInSeconds');
    return 0.0;
  }

  @override
  double getPunchOutSeconds() {
    _record('getPunchOutSeconds');
    return 0.0;
  }

  @override
  bool isPunchComplete() {
    _record('isPunchComplete');
    return false;
  }
}
