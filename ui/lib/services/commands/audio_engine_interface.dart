// ignore_for_file: avoid_positional_boolean_parameters
import '../../models/drum_kit_info.dart';
import '../../models/sampler_info.dart';

/// Abstract interface for AudioEngine to enable testing.
/// Commands use this interface instead of the concrete AudioEngine class,
/// allowing mock implementations in tests.
abstract class AudioEngineInterface {
  // Clip operations
  String setClipStartTime(int trackId, int clipId, double startTime);
  String setClipOffset(int trackId, int clipId, double offset);
  String setClipDuration(int trackId, int clipId, double duration);
  String setAudioClipGain(int trackId, int clipId, double gainDb);
  String setAudioClipWarp(
    int trackId,
    int clipId,
    bool warpEnabled,
    double stretchFactor,
  );
  String setAudioClipTranspose(
    int trackId,
    int clipId,
    int semitones,
    int cents,
  );
  String setAudioClipReverse(int trackId, int clipId, {required bool reversed});

  /// The project tempo the engine is playing at, in BPM.
  double getTempo();
  int loadAudioFileToTrack(
    String filePath,
    int trackId, {
    double startTime = 0.0,
  });
  double getClipDuration(int clipId);
  String getAllAudioClipsInfo();
  List<double> getWaveformPeaks(int clipId, int resolution);
  bool removeAudioClip(int trackId, int clipId);
  int addExistingClipToTrack(
    int clipId,
    int trackId,
    double startTime, {
    double offset = 0.0,
    double? duration,
  });
  // [newClipId]/[newTrackId]/[id]: undo and redo bring things back under the
  // id they had, so the steps around them still find them.
  int duplicateAudioClip(
    int trackId,
    int clipId,
    double startTime, {
    int? newClipId,
  });
  int duplicateAudioClipToTrack(
    int sourceTrackId,
    int sourceClipId,
    int targetTrackId,
    double startTime, {
    int? newClipId,
  });

  /// Render the given audio clips on a track into one WAV, baking clip edits.
  /// Returns the rendered WAV path, or null on error. Render-only — does not
  /// mutate the track (the JoinAudioClipsCommand owns the timeline changes).
  String? joinAudioClips(int trackId, List<int> clipIds);

  // Track operations
  int createTrack(String trackType, String name, {int? id});
  String deleteTrack(int trackId);
  int duplicateTrack(int sourceTrackId, {int? newTrackId});
  String getTrackInfo(int trackId);
  void setTrackName(int trackId, String name);
  void setTrackVolume(int trackId, double volumeDb);
  void setTrackVolumeAutomation(int trackId, String csvData);
  void setTrackPan(int trackId, double pan);
  void setTrackMute(int trackId, {required bool mute});
  void setTrackSolo(int trackId, {required bool solo});
  void setTrackArmed(int trackId, {required bool armed});

  List<int> getAllTrackIds();

  // Effect operations
  int addEffectToTrack(int trackId, String effectType);
  int addVst3EffectToTrack(int trackId, String effectPath);
  String removeEffectFromTrack(int trackId, int effectId);

  /// Add a band to a Graphic EQ. Returns the new band index, or -1 on error.
  int addEqBand(int effectId);

  /// Remove the band at [index] from a Graphic EQ.
  String removeEqBand(int effectId, int index);

  /// Insert a default band at [index] in a Graphic EQ (undo of a removal).
  String insertEqBand(int effectId, int index);

  /// CSV of effect IDs on a track ("id,id,..."). Used to snapshot a track's
  /// FX chain before deletion so undo can rebuild it.
  String getTrackEffects(int trackId);

  /// Effect type + bypass + parameters as "type:eq,bypassed:0,low_freq:..,..".
  /// Built-in effects round-trip through `addEffectToTrack` + `setEffectParameter`
  /// (the parameter names here match those setters). VST3 effects report
  /// "type:vst3,bypassed:..,name:..,path:.." — rebuildable via
  /// `addVst3EffectToTrack(path)` + `setVst3State` (read `path:` as everything
  /// after the marker, since a plugin path may contain commas).
  String getEffectInfo(int effectId);
  void setEffectBypass(int effectId, {required bool bypassed});
  void setEffectParameter(int effectId, String paramName, double value);
  void setSynthBypass(int trackId, {required bool bypassed});
  void reorderTrackEffects(int trackId, List<int> order);
  bool setVst3ParameterValue(int effectId, int paramIndex, double value);

  /// Base64-encoded opaque state blob of a VST3 plugin (its full patch). Used to
  /// snapshot a plugin before track deletion so undo can restore its exact state.
  String getVst3State(int effectId);

  /// Restore a VST3 plugin's state from a base64 blob produced by [getVst3State].
  String setVst3State(int effectId, String stateBase64);

  // Sampler operations
  int createSamplerForTrack(int trackId);
  bool loadSampleForTrack(int trackId, String path, int rootNote);
  bool unloadSampleForTrack(int trackId);
  String? getSamplerSamplePath(int trackId);
  String setSamplerParameter(int trackId, String param, String value);
  bool isSamplerTrack(int trackId);
  SamplerInfo? getSamplerInfo(int trackId);
  List<double> getSamplerWaveformPeaks(int trackId, int resolution);

  // Drum-kit operations (v0.6)
  int createDrumKitForTrack(int trackId);
  int addDrumPad(int trackId, int pinnedNote);
  String removeDrumPad(int trackId, int padIndex);
  bool loadDrumPadSample(int trackId, int padIndex, String path);
  String setDrumPadParameter(
    int trackId,
    int padIndex,
    String param,
    String value,
  );
  bool isDrumKitTrack(int trackId);
  int drumNextFreeNote(int trackId, int start);
  DrumKitInfo? getDrumKitInfo(int trackId);
  List<double> getDrumPadWaveformPeaks(
    int trackId,
    int padIndex,
    int resolution,
  );

  // MIDI clip operations
  int createMidiClip();
  String addMidiNoteToClip(
    int clipId,
    int note,
    int velocity,
    double startTime,
    double duration,
  );
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds);
  int removeMidiClip(int trackId, int clipId);
  String clearMidiClip(int clipId);
  String getAllMidiClipsInfo();
  String getMidiClipNotes(int clipId);
  String sendMidiNoteOn(int note, int velocity);
  String sendMidiNoteOff(int note, int velocity);

  // Project operations
  void setTempo(double bpm);
  void setCountInBars(int bars);

  // Library preview operations
  String previewLoadAudio(String path);
  void previewLoadAudioAsync(String path);
  bool previewIsLoaded();
  bool previewCheckFullClip();
  bool previewIsFullyDecoded();
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

  // Send/return operations
  int findReturnByEffectType(String effectType);
  int createReturnWithEffect(String effectType, {String? name});
  String addSharedSend(int sourceTrackId, String effectType);
  String addSend(int sourceTrackId, int returnTrackId, double amountDb);
  String setSendAmount(int sourceTrackId, int returnTrackId, double amountDb);
  String removeSend(int sourceTrackId, int returnTrackId);
  String removeReturn(int returnTrackId);
  String getTrackSends(int trackId);
  String getAllReturns();
  int countSendsToReturn(int returnTrackId);
  bool getMasterTimelineVisible();
  String setMasterTimelineVisible({required bool visible});
  bool syncMasterTimelineVisibility();
}
