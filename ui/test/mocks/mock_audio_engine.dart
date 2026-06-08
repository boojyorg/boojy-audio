import 'package:boojy_audio/models/drum_kit_info.dart';
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
  int nextReturnId = 1;
  String trackInfoResponse = '';

  /// Configurable responses for the delete-track snapshot path.
  String trackSendsResponse = '';
  String trackEffectsResponse = '';
  final Map<int, String> effectInfoResponses = {};

  /// VST3 state blobs keyed by effect id, returned by [getVst3State]. Lets
  /// DeleteTrackCommand tests assert a plugin's state was captured + restored.
  final Map<int, String> vst3StateResponses = {};

  /// (effectId, base64) pairs passed to [setVst3State], in call order.
  final List<({int effectId, String stateBase64})> setVst3StateCalls = [];

  /// (trackId, pluginPath) pairs passed to [addVst3EffectToTrack], in order.
  final List<({int trackId, String path})> addedVst3Plugins = [];

  /// Captured arguments for remove operations, in call order. These let redo
  /// tests assert that after undo→redo a Remove command targets the *recreated*
  /// engine id rather than the stale original id.
  final List<int> removedEffectIds = [];
  final List<int> removedReturnIds = [];
  final List<int> removedClipIds = [];
  final List<List<int>> joinedClipIdLists = [];

  /// trackIds passed to deleteTrack, in call order — lets DeleteTrackCommand
  /// redo tests assert it targets the recreated id, not the stale original (C62).
  final List<int> deletedTrackIds = [];

  /// The effect-chain order passed to the most recent reorderTrackEffects call.
  List<int>? lastReorder;

  /// EQ band-op captures (effectId, index), in call order, for command tests.
  final List<({int effectId, int index})> removedEqBands = [];
  final List<({int effectId, int index})> insertedEqBands = [];
  final List<int> addedEqBandEffectIds = [];

  /// Index returned by [addEqBand].
  int eqBandIndex = 0;

  /// (effectId, paramName, value) passed to [setEffectParameter], in call order.
  final List<({int effectId, String paramName, double value})> setParamCalls =
      [];

  void _record(String method) => calls.add(method);

  /// Reset call history and return values.
  void reset() {
    calls.clear();
    nextTrackId = 1;
    nextEffectId = 1;
    nextClipId = 1;
    nextReturnId = 1;
    trackInfoResponse = '';
    trackSendsResponse = '';
    trackEffectsResponse = '';
    effectInfoResponses.clear();
    vst3StateResponses.clear();
    setVst3StateCalls.clear();
    addedVst3Plugins.clear();
    removedEffectIds.clear();
    removedReturnIds.clear();
    removedClipIds.clear();
    deletedTrackIds.clear();
    lastReorder = null;
    removedEqBands.clear();
    insertedEqBands.clear();
    addedEqBandEffectIds.clear();
    setParamCalls.clear();
    eqBandIndex = 0;
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
  String setAudioClipWarp(
    int trackId,
    int clipId,
    bool warpEnabled,
    double stretchFactor,
    int warpMode,
  ) {
    _record('setAudioClipWarp');
    return 'OK';
  }

  @override
  String setAudioClipTranspose(
    int trackId,
    int clipId,
    int semitones,
    int cents,
  ) {
    _record('setAudioClipTranspose');
    return 'OK';
  }

  @override
  String setAudioClipReverse(
    int trackId,
    int clipId, {
    required bool reversed,
  }) {
    _record('setAudioClipReverse');
    return 'OK';
  }

  @override
  int loadAudioFileToTrack(
    String filePath,
    int trackId, {
    double startTime = 0.0,
  }) {
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
    removedClipIds.add(clipId);
    return true;
  }

  @override
  int addExistingClipToTrack(
    int clipId,
    int trackId,
    double startTime, {
    double offset = 0.0,
    double? duration,
  }) {
    _record('addExistingClipToTrack');
    return nextClipId++;
  }

  @override
  String? joinAudioClips(int trackId, List<int> clipIds) {
    _record('joinAudioClips');
    joinedClipIdLists.add(List<int>.from(clipIds));
    return '/tmp/boojy_join_test.wav';
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
    deletedTrackIds.add(trackId);
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
    addedVst3Plugins.add((trackId: trackId, path: effectPath));
    return nextEffectId++;
  }

  @override
  String getVst3State(int effectId) {
    _record('getVst3State');
    return vst3StateResponses[effectId] ?? '';
  }

  @override
  String setVst3State(int effectId, String stateBase64) {
    _record('setVst3State');
    setVst3StateCalls.add((effectId: effectId, stateBase64: stateBase64));
    return 'OK';
  }

  @override
  String removeEffectFromTrack(int trackId, int effectId) {
    _record('removeEffectFromTrack');
    removedEffectIds.add(effectId);
    return 'OK';
  }

  @override
  String getTrackEffects(int trackId) {
    _record('getTrackEffects');
    return trackEffectsResponse;
  }

  @override
  String getEffectInfo(int effectId) {
    _record('getEffectInfo');
    return effectInfoResponses[effectId] ?? '';
  }

  @override
  void setEffectBypass(int effectId, {required bool bypassed}) =>
      _record('setEffectBypass');

  @override
  void setEffectParameter(int effectId, String paramName, double value) {
    _record('setEffectParameter');
    setParamCalls.add((effectId: effectId, paramName: paramName, value: value));
  }

  @override
  int addEqBand(int effectId) {
    _record('addEqBand');
    addedEqBandEffectIds.add(effectId);
    return eqBandIndex;
  }

  @override
  String removeEqBand(int effectId, int index) {
    _record('removeEqBand');
    removedEqBands.add((effectId: effectId, index: index));
    return 'OK';
  }

  @override
  String insertEqBand(int effectId, int index) {
    _record('insertEqBand');
    insertedEqBands.add((effectId: effectId, index: index));
    return 'OK';
  }

  @override
  void setSynthBypass(int trackId, {required bool bypassed}) =>
      _record('setSynthBypass');

  @override
  void reorderTrackEffects(int trackId, List<int> order) {
    _record('reorderTrackEffects');
    lastReorder = List<int>.from(order);
  }

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

  // --- Drum-kit operations ---

  @override
  int createDrumKitForTrack(int trackId) {
    _record('createDrumKitForTrack');
    return 1;
  }

  @override
  int addDrumPad(int trackId, int pinnedNote) {
    _record('addDrumPad');
    return 0;
  }

  @override
  String removeDrumPad(int trackId, int padIndex) {
    _record('removeDrumPad');
    return 'OK';
  }

  @override
  bool loadDrumPadSample(int trackId, int padIndex, String path) {
    _record('loadDrumPadSample');
    return true;
  }

  @override
  String setDrumPadParameter(
    int trackId,
    int padIndex,
    String param,
    String value,
  ) {
    _record('setDrumPadParameter');
    return 'OK';
  }

  @override
  bool isDrumKitTrack(int trackId) {
    _record('isDrumKitTrack');
    return false;
  }

  @override
  int drumNextFreeNote(int trackId, int start) {
    _record('drumNextFreeNote');
    return start;
  }

  @override
  DrumKitInfo? getDrumKitInfo(int trackId) {
    _record('getDrumKitInfo');
    return null;
  }

  @override
  List<double> getDrumPadWaveformPeaks(
    int trackId,
    int padIndex,
    int resolution,
  ) {
    _record('getDrumPadWaveformPeaks');
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
    int clipId,
    int note,
    int velocity,
    double startTime,
    double duration,
  ) {
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
  void previewLoadAudioAsync(String path) => _record('previewLoadAudioAsync');

  @override
  bool previewIsLoaded() {
    _record('previewIsLoaded');
    return true;
  }

  @override
  bool previewCheckFullClip() {
    _record('previewCheckFullClip');
    return false;
  }

  @override
  bool previewIsFullyDecoded() {
    _record('previewIsFullyDecoded');
    return true;
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

  @override
  List<int> getAllTrackIds() {
    _record('getAllTrackIds');
    return [];
  }

  @override
  int findReturnByEffectType(String effectType) {
    _record('findReturnByEffectType');
    return 0;
  }

  @override
  int createReturnWithEffect(String effectType, {String? name}) {
    _record('createReturnWithEffect');
    return nextReturnId++;
  }

  @override
  String addSharedSend(int sourceTrackId, String effectType) {
    _record('addSharedSend');
    return '1,-20.00';
  }

  @override
  String addSend(int sourceTrackId, int returnTrackId, double amountDb) {
    _record('addSend');
    return 'OK';
  }

  @override
  String setSendAmount(int sourceTrackId, int returnTrackId, double amountDb) {
    _record('setSendAmount');
    return 'OK';
  }

  @override
  String removeSend(int sourceTrackId, int returnTrackId) {
    _record('removeSend');
    return 'OK';
  }

  @override
  String removeReturn(int returnTrackId) {
    _record('removeReturn');
    removedReturnIds.add(returnTrackId);
    return 'OK';
  }

  @override
  String getTrackSends(int trackId) {
    _record('getTrackSends');
    return trackSendsResponse;
  }

  @override
  String getAllReturns() {
    _record('getAllReturns');
    return '';
  }

  @override
  int countSendsToReturn(int returnTrackId) {
    _record('countSendsToReturn');
    return 0;
  }

  @override
  bool getMasterTimelineVisible() {
    _record('getMasterTimelineVisible');
    return false;
  }

  @override
  String setMasterTimelineVisible({required bool visible}) {
    _record('setMasterTimelineVisible');
    return 'OK';
  }

  @override
  bool syncMasterTimelineVisibility() {
    _record('syncMasterTimelineVisibility');
    return false;
  }
}
