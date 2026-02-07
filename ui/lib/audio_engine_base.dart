part of 'audio_engine_native.dart';

class _AudioEngineBase {
  late final ffi.DynamicLibrary _lib;

  // M0 functions
  late final _InitAudioEngineFfi _initAudioEngine;
  late final _PlaySineWaveFfi _playSineWave;
  late final _FreeRustString _freeRustString;

  // M1 functions
  late final _InitAudioGraphFfi _initAudioGraph;
  late final _LoadAudioFileFfi _loadAudioFile;
  late final _LoadAudioFileToTrackFfi _loadAudioFileToTrack;
  late final _TransportPlayFfi _transportPlay;
  late final _TransportPauseFfi _transportPause;
  late final _TransportStopFfi _transportStop;
  late final _TransportSeekFfi _transportSeek;
  late final _GetPlayheadPositionFfi _getPlayheadPosition;
  late final _GetTransportStateFfi _getTransportState;
  late final _GetPlayStartPositionFfi _getPlayStartPosition;
  late final _SetPlayStartPositionFfi _setPlayStartPosition;
  late final _GetRecordStartPositionFfi _getRecordStartPosition;
  late final _SetRecordStartPositionFfi _setRecordStartPosition;
  late final _GetClipDurationFfi _getClipDuration;

  // Latency Control functions
  late final _SetBufferSizeFfi _setBufferSize;
  late final _GetBufferSizePresetFfi _getBufferSizePreset;
  late final _GetActualBufferSizeFfi _getActualBufferSize;
  late final _GetLatencyInfoFfi _getLatencyInfo;
  late final _StartLatencyTestFfi _startLatencyTest;
  late final _StopLatencyTestFfi _stopLatencyTest;
  late final _GetLatencyTestStatusFfi _getLatencyTestStatus;
  late final _GetLatencyTestErrorFfi _getLatencyTestError;
  late final _SetClipStartTimeFfi _setClipStartTime;
  late final _SetClipOffsetFfi _setClipOffset;
  late final _SetClipDurationFfi _setClipDuration;
  late final _SetAudioClipGainFfi _setAudioClipGain;
  late final _SetAudioClipWarpFfi _setAudioClipWarp;
  late final _SetAudioClipTransposeFfi _setAudioClipTranspose;
  late final _GetWaveformPeaksFfi _getWaveformPeaks;
  late final _FreeWaveformPeaksFfi _freeWaveformPeaks;

  // M2 functions - Recording & Input
  late final _StartRecordingFfi _startRecording;
  late final _StopRecordingFfi _stopRecording;
  late final _GetRecordingStateFfi _getRecordingState;
  late final _GetRecordedDurationFfi _getRecordedDuration;
  late final _GetRecordingWaveformFfi _getRecordingWaveform;
  late final _SetCountInBarsFfi _setCountInBars;
  late final _GetCountInBarsFfi _getCountInBars;
  late final _GetCountInBeatFfi _getCountInBeat;
  late final _GetCountInProgressFfi _getCountInProgress;
  late final _SetTempoFfi _setTempo;
  late final _GetTempoFfi _getTempo;
  late final _SetMetronomeEnabledFfi _setMetronomeEnabled;
  late final _IsMetronomeEnabledFfi _isMetronomeEnabled;
  late final _SetTimeSignatureFfi _setTimeSignature;
  late final _GetTimeSignatureFfi _getTimeSignature;

  // M3 functions - MIDI
  late final _StartMidiInputFfi _startMidiInput;
  late final _StopMidiInputFfi _stopMidiInput;
  late final _SetSynthOscillatorTypeFfi _setSynthOscillatorType;
  late final _SetSynthVolumeFfi _setSynthVolume;
  late final _SendMidiNoteOnFfi _sendMidiNoteOn;
  late final _SendMidiNoteOffFfi _sendMidiNoteOff;
  late final _CreateMidiClipFfi _createMidiClip;
  late final _AddMidiNoteToClipFfi _addMidiNoteToClip;
  late final _AddMidiClipToTrackFfi _addMidiClipToTrack;
  late final _RemoveMidiClipFfi _removeMidiClip;
  late final _ClearMidiClipFfi _clearMidiClip;

  // M6 functions - Per-track Synthesizer
  late final _SetTrackInstrumentFfi _setTrackInstrument;
  late final _SetSynthParameterFfi _setSynthParameter;
  late final _GetSynthParametersFfi _getSynthParameters;
  late final _SendTrackMidiNoteOnFfi _sendTrackMidiNoteOn;
  late final _SendTrackMidiNoteOffFfi _sendTrackMidiNoteOff;

  // Sampler functions
  late final _CreateSamplerForTrackFfi _createSamplerForTrack;
  late final _LoadSampleForTrackFfi _loadSampleForTrack;
  late final _SetSamplerParameterFfi _setSamplerParameter;
  late final _IsSamplerTrackFfi _isSamplerTrack;
  late final _GetSamplerInfoFfi _getSamplerInfo;
  late final _GetSamplerWaveformPeaksFfi _getSamplerWaveformPeaks;
  late final _FreeSamplerWaveformPeaksFfi _freeSamplerWaveformPeaks;

  // M4 functions - Tracks & Mixer
  late final _CreateTrackFfi _createTrack;
  late final _SetTrackVolumeFfi _setTrackVolume;
  late final _SetTrackVolumeAutomationFfi _setTrackVolumeAutomation;
  late final _SetTrackPanFfi _setTrackPan;
  late final _SetTrackMuteFfi _setTrackMute;
  late final _SetTrackSoloFfi _setTrackSolo;
  late final _SetTrackArmedFfi _setTrackArmed;
  late final _SetTrackInputFfi _setTrackInput;
  late final _GetTrackInputFfi _getTrackInput;
  late final _SetTrackInputMonitoringFfi _setTrackInputMonitoring;
  late final _GetInputChannelLevelFfi _getInputChannelLevel;
  late final _GetInputChannelCountFfi _getInputChannelCount;
  late final _SetTrackNameFfi _setTrackName;
  late final _GetTrackCountFfi _getTrackCount;
  late final _GetAllTrackIdsFfi _getAllTrackIds;
  late final _GetTrackInfoFfi _getTrackInfo;
  late final _GetTrackPeakLevelsFfi _getTrackPeakLevels;
  late final _DeleteTrackFfi _deleteTrack;
  late final _DuplicateTrackFfi _duplicateTrack;
  late final _DuplicateAudioClipFfi _duplicateAudioClip;
  late final _RemoveAudioClipFfi _removeAudioClip;
  late final _AddExistingClipToTrackFfi _addExistingClipToTrack;
  late final _ClearAllTracksFfi _clearAllTracks;

  // M4 functions - Effects
  late final _AddEffectToTrackFfi _addEffectToTrack;
  late final _RemoveEffectFromTrackFfi _removeEffectFromTrack;
  late final _GetTrackEffectsFfi _getTrackEffects;
  late final _GetEffectInfoFfi _getEffectInfo;
  late final _SetEffectParameterFfi _setEffectParameter;
  late final _SetEffectBypassFfi _setEffectBypass;
  late final _GetEffectBypassFfi _getEffectBypass;
  late final _ReorderTrackEffectsFfi _reorderTrackEffects;

  // M5 functions - Save/Load Project
  late final _SaveProjectFfi _saveProject;
  late final _LoadProjectFfi _loadProject;
  late final _ExportToWavFfi _exportToWav;

  // M8 functions - Enhanced Export
  late final _IsFfmpegAvailableFfi _isFfmpegAvailable;
  late final _ExportAudioFfi _exportAudio;
  late final _ExportWavWithOptionsFfi _exportWavWithOptions;
  late final _ExportMp3WithOptionsFfi _exportMp3WithOptions;
  late final _WriteMp3MetadataFfi _writeMp3Metadata;
  late final _GetTracksForStemsFfi _getTracksForStems;
  late final _ExportStemsFfi _exportStems;

  // M8 Export Progress functions
  late final _GetExportProgressFfi _getExportProgress;
  late final _CancelExportFfi _cancelExport;
  late final _ResetExportProgressFfi _resetExportProgress;

  // M7 functions - VST3 Plugin Hosting
  late final _ScanVst3PluginsStandardFfi _scanVst3PluginsStandard;
  late final _AddVst3EffectToTrackFfi _addVst3EffectToTrack;
  late final _GetVst3ParameterCountFfi _getVst3ParameterCount;
  late final _GetVst3ParameterInfoFfi _getVst3ParameterInfo;
  late final _GetVst3ParameterValueFfi _getVst3ParameterValue;
  late final _SetVst3ParameterValueFfi _setVst3ParameterValue;

  // M7 VST3 Editor functions
  late final _Vst3HasEditorFfi _vst3HasEditor;
  late final _Vst3OpenEditorFfi _vst3OpenEditor;
  late final _Vst3CloseEditorFfi _vst3CloseEditor;
  late final _Vst3GetEditorSizeFfi _vst3GetEditorSize;
  late final _Vst3AttachEditorFfi _vst3AttachEditor;
  late final _Vst3SendMidiNoteFfi _vst3SendMidiNote;

  // MIDI Recording functions
  late final _GetMidiInputDevicesFfi _getMidiInputDevices;
  late final _SelectMidiInputDeviceFfi _selectMidiInputDevice;
  late final _RefreshMidiDevicesFfi _refreshMidiDevices;
  late final _StartMidiRecordingFfi _startMidiRecording;
  late final _StopMidiRecordingFfi _stopMidiRecording;
  late final _GetMidiRecordingStateFfi _getMidiRecordingState;
  late final _GetMidiRecorderLiveEventsFfi _getMidiRecorderLiveEvents;
  late final _QuantizeMidiClipFfi _quantizeMidiClip;
  late final _GetMidiClipInfoFfi _getMidiClipInfo;
  late final _GetAllMidiClipsInfoFfi _getAllMidiClipsInfo;
  late final _GetMidiClipNotesFfi _getMidiClipNotes;

  // Audio Device functions
  late final _GetAudioInputDevicesFfi _getAudioInputDevices;
  late final _GetAudioOutputDevicesFfi _getAudioOutputDevices;
  late final _SetAudioInputDeviceFfi _setAudioInputDevice;
  late final _SetAudioOutputDeviceFfi _setAudioOutputDevice;
  late final _GetSelectedAudioOutputDeviceFfi _getSelectedAudioOutputDevice;
  late final _GetSampleRateFfi _getSampleRate;

  // Library Preview functions
  late final _PreviewLoadAudioFfi _previewLoadAudio;
  late final _PreviewPlayFfi _previewPlay;
  late final _PreviewStopFfi _previewStop;
  late final _PreviewSeekFfi _previewSeek;
  late final _PreviewGetPositionFfi _previewGetPosition;
  late final _PreviewGetDurationFfi _previewGetDuration;
  late final _PreviewIsPlayingFfi _previewIsPlaying;
  late final _PreviewSetLoopingFfi _previewSetLooping;
  late final _PreviewIsLoopingFfi _previewIsLooping;
  late final _PreviewGetWaveformFfi _previewGetWaveform;

  // Punch Recording functions
  late final _SetPunchInEnabledFfi _setPunchInEnabled;
  late final _IsPunchInEnabledFfi _isPunchInEnabled;
  late final _SetPunchOutEnabledFfi _setPunchOutEnabled;
  late final _IsPunchOutEnabledFfi _isPunchOutEnabled;
  late final _SetPunchRegionFfi _setPunchRegion;
  late final _GetPunchInSecondsFfi _getPunchInSeconds;
  late final _GetPunchOutSecondsFfi _getPunchOutSeconds;
  late final _IsPunchCompleteFfi _isPunchComplete;

  _AudioEngineBase() {
    // Load the native library
    if (Platform.isMacOS) {
      // Find the library by searching multiple locations
      // Priority: 1) Executable-relative paths, 2) Current directory paths

      String? libPath;

      // Get the executable path to find library relative to app bundle
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent.path;

      // List of paths to try, in order of priority
      // Debug paths first (most common during development), then release
      final pathsToTry = <String>[
        // Release build: Frameworks folder inside app bundle
        '$executableDir/../Frameworks/libengine.dylib',
      ];

      // Search from current directory (works for flutter run)
      // Debug before release so we don't load a stale release build
      var searchDir = Directory.current;
      for (var i = 0; i < 5; i++) {
        pathsToTry.add('${searchDir.path}/macos/Runner/libengine.dylib');
        pathsToTry.add('${searchDir.path}/engine/target/debug/libengine.dylib');
        pathsToTry.add('${searchDir.path}/engine/target/release/libengine.dylib');
        final parent = searchDir.parent;
        if (parent.path == searchDir.path) break;
        searchDir = parent;
      }

      // Try each path
      for (final path in pathsToTry) {
        final file = File(path);
        if (file.existsSync()) {
          libPath = path;
          break;
        }
      }

      if (libPath == null) {
        throw Exception('Library file not found. Run: cd engine && cargo build --release');
      }

      try {
        _lib = ffi.DynamicLibrary.open(libPath);
      } catch (e) {
        rethrow;
      }
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('engine.dll');
    } else if (Platform.isLinux) {
      _lib = ffi.DynamicLibrary.open('libengine.so');
    } else if (Platform.isIOS) {
      // On iOS, the static library is linked into the app at build time
      // In Debug mode, Flutter uses Runner.debug.dylib for Hot Restart support
      // In Release mode, symbols are in the main executable

      // Try loading the debug dylib first (for debug builds)
      try {
        _lib = ffi.DynamicLibrary.open('Runner.debug.dylib');
      } catch (e) {
        // Fall back to process() for release builds
        _lib = ffi.DynamicLibrary.process();
      }
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }

    // Bind M0 functions
    try {
      _initAudioEngine = _lib
          .lookup<ffi.NativeFunction<_InitAudioEngineFfiNative>>(
              'init_audio_engine_ffi')
          .asFunction();

      _playSineWave = _lib
          .lookup<ffi.NativeFunction<_PlaySineWaveFfiNative>>(
              'play_sine_wave_ffi')
          .asFunction();

      _freeRustString = _lib
          .lookup<ffi.NativeFunction<_FreeRustStringNative>>(
              'free_rust_string')
          .asFunction();

      // Bind M1 functions
      _initAudioGraph = _lib
          .lookup<ffi.NativeFunction<_InitAudioGraphFfiNative>>(
              'init_audio_graph_ffi')
          .asFunction();

      _loadAudioFile = _lib
          .lookup<ffi.NativeFunction<_LoadAudioFileFfiNative>>(
              'load_audio_file_ffi')
          .asFunction();

      _loadAudioFileToTrack = _lib
          .lookup<ffi.NativeFunction<_LoadAudioFileToTrackFfiNative>>(
              'load_audio_file_to_track_ffi')
          .asFunction();

      _transportPlay = _lib
          .lookup<ffi.NativeFunction<_TransportPlayFfiNative>>(
              'transport_play_ffi')
          .asFunction();

      _transportPause = _lib
          .lookup<ffi.NativeFunction<_TransportPauseFfiNative>>(
              'transport_pause_ffi')
          .asFunction();

      _transportStop = _lib
          .lookup<ffi.NativeFunction<_TransportStopFfiNative>>(
              'transport_stop_ffi')
          .asFunction();

      _transportSeek = _lib
          .lookup<ffi.NativeFunction<_TransportSeekFfiNative>>(
              'transport_seek_ffi')
          .asFunction();

      _getPlayheadPosition = _lib
          .lookup<ffi.NativeFunction<_GetPlayheadPositionFfiNative>>(
              'get_playhead_position_ffi')
          .asFunction();

      _getTransportState = _lib
          .lookup<ffi.NativeFunction<_GetTransportStateFfiNative>>(
              'get_transport_state_ffi')
          .asFunction();

      _getPlayStartPosition = _lib
          .lookup<ffi.NativeFunction<_GetPlayStartPositionFfiNative>>(
              'get_play_start_position_ffi')
          .asFunction();

      _setPlayStartPosition = _lib
          .lookup<ffi.NativeFunction<_SetPlayStartPositionFfiNative>>(
              'set_play_start_position_ffi')
          .asFunction();

      _getRecordStartPosition = _lib
          .lookup<ffi.NativeFunction<_GetRecordStartPositionFfiNative>>(
              'get_record_start_position_ffi')
          .asFunction();

      _setRecordStartPosition = _lib
          .lookup<ffi.NativeFunction<_SetRecordStartPositionFfiNative>>(
              'set_record_start_position_ffi')
          .asFunction();

      // Latency Control bindings
      _setBufferSize = _lib
          .lookup<ffi.NativeFunction<_SetBufferSizeFfiNative>>(
              'set_buffer_size_ffi')
          .asFunction();

      _getBufferSizePreset = _lib
          .lookup<ffi.NativeFunction<_GetBufferSizePresetFfiNative>>(
              'get_buffer_size_preset_ffi')
          .asFunction();

      _getActualBufferSize = _lib
          .lookup<ffi.NativeFunction<_GetActualBufferSizeFfiNative>>(
              'get_actual_buffer_size_ffi')
          .asFunction();

      _getLatencyInfo = _lib
          .lookup<ffi.NativeFunction<_GetLatencyInfoFfiNative>>(
              'get_latency_info_ffi')
          .asFunction();

      _startLatencyTest = _lib
          .lookup<ffi.NativeFunction<_StartLatencyTestFfiNative>>(
              'start_latency_test_ffi')
          .asFunction();

      _stopLatencyTest = _lib
          .lookup<ffi.NativeFunction<_StopLatencyTestFfiNative>>(
              'stop_latency_test_ffi')
          .asFunction();

      _getLatencyTestStatus = _lib
          .lookup<ffi.NativeFunction<_GetLatencyTestStatusFfiNative>>(
              'get_latency_test_status_ffi')
          .asFunction();

      _getLatencyTestError = _lib
          .lookup<ffi.NativeFunction<_GetLatencyTestErrorFfiNative>>(
              'get_latency_test_error_ffi')
          .asFunction();

      _getClipDuration = _lib
          .lookup<ffi.NativeFunction<_GetClipDurationFfiNative>>(
              'get_clip_duration_ffi')
          .asFunction();

      _setClipStartTime = _lib
          .lookup<ffi.NativeFunction<_SetClipStartTimeFfiNative>>(
              'set_clip_start_time_ffi')
          .asFunction();

      _setClipOffset = _lib
          .lookup<ffi.NativeFunction<_SetClipOffsetFfiNative>>(
              'set_clip_offset_ffi')
          .asFunction();

      _setClipDuration = _lib
          .lookup<ffi.NativeFunction<_SetClipDurationFfiNative>>(
              'set_clip_duration_ffi')
          .asFunction();

      _setAudioClipGain = _lib
          .lookup<ffi.NativeFunction<_SetAudioClipGainFfiNative>>(
              'set_audio_clip_gain_ffi')
          .asFunction();

      _setAudioClipWarp = _lib
          .lookup<ffi.NativeFunction<_SetAudioClipWarpFfiNative>>(
              'set_audio_clip_warp_ffi')
          .asFunction();

      _setAudioClipTranspose = _lib
          .lookup<ffi.NativeFunction<_SetAudioClipTransposeFfiNative>>(
              'set_audio_clip_transpose_ffi')
          .asFunction();

      _getWaveformPeaks = _lib
          .lookup<ffi.NativeFunction<_GetWaveformPeaksFfiNative>>(
              'get_waveform_peaks_ffi')
          .asFunction();

      _freeWaveformPeaks = _lib
          .lookup<ffi.NativeFunction<_FreeWaveformPeaksFfiNative>>(
              'free_waveform_peaks_ffi')
          .asFunction();

      // Bind M2 functions
      _startRecording = _lib
          .lookup<ffi.NativeFunction<_StartRecordingFfiNative>>(
              'start_recording_ffi')
          .asFunction();

      _stopRecording = _lib
          .lookup<ffi.NativeFunction<_StopRecordingFfiNative>>(
              'stop_recording_ffi')
          .asFunction();

      _getRecordingState = _lib
          .lookup<ffi.NativeFunction<_GetRecordingStateFfiNative>>(
              'get_recording_state_ffi')
          .asFunction();

      _getRecordedDuration = _lib
          .lookup<ffi.NativeFunction<_GetRecordedDurationFfiNative>>(
              'get_recorded_duration_ffi')
          .asFunction();

      _getRecordingWaveform = _lib
          .lookup<ffi.NativeFunction<_GetRecordingWaveformFfiNative>>(
              'get_recording_waveform_ffi')
          .asFunction();

      _setCountInBars = _lib
          .lookup<ffi.NativeFunction<_SetCountInBarsFfiNative>>(
              'set_count_in_bars_ffi')
          .asFunction();

      _getCountInBars = _lib
          .lookup<ffi.NativeFunction<_GetCountInBarsFfiNative>>(
              'get_count_in_bars_ffi')
          .asFunction();

      _getCountInBeat = _lib
          .lookup<ffi.NativeFunction<_GetCountInBeatFfiNative>>(
              'get_count_in_beat_ffi')
          .asFunction();

      _getCountInProgress = _lib
          .lookup<ffi.NativeFunction<_GetCountInProgressFfiNative>>(
              'get_count_in_progress_ffi')
          .asFunction();

      _setTempo = _lib
          .lookup<ffi.NativeFunction<_SetTempoFfiNative>>(
              'set_tempo_ffi')
          .asFunction();

      _getTempo = _lib
          .lookup<ffi.NativeFunction<_GetTempoFfiNative>>(
              'get_tempo_ffi')
          .asFunction();

      _setMetronomeEnabled = _lib
          .lookup<ffi.NativeFunction<_SetMetronomeEnabledFfiNative>>(
              'set_metronome_enabled_ffi')
          .asFunction();

      _isMetronomeEnabled = _lib
          .lookup<ffi.NativeFunction<_IsMetronomeEnabledFfiNative>>(
              'is_metronome_enabled_ffi')
          .asFunction();

      _setTimeSignature = _lib
          .lookup<ffi.NativeFunction<_SetTimeSignatureFfiNative>>(
              'set_time_signature_ffi')
          .asFunction();

      _getTimeSignature = _lib
          .lookup<ffi.NativeFunction<_GetTimeSignatureFfiNative>>(
              'get_time_signature_ffi')
          .asFunction();

      // Bind M3 functions
      _startMidiInput = _lib
          .lookup<ffi.NativeFunction<_StartMidiInputFfiNative>>(
              'start_midi_input_ffi')
          .asFunction();

      _stopMidiInput = _lib
          .lookup<ffi.NativeFunction<_StopMidiInputFfiNative>>(
              'stop_midi_input_ffi')
          .asFunction();

      _setSynthOscillatorType = _lib
          .lookup<ffi.NativeFunction<_SetSynthOscillatorTypeFfiNative>>(
              'set_synth_oscillator_type_ffi')
          .asFunction();

      _setSynthVolume = _lib
          .lookup<ffi.NativeFunction<_SetSynthVolumeFfiNative>>(
              'set_synth_volume_ffi')
          .asFunction();

      _sendMidiNoteOn = _lib
          .lookup<ffi.NativeFunction<_SendMidiNoteOnFfiNative>>(
              'send_midi_note_on_ffi')
          .asFunction();

      _sendMidiNoteOff = _lib
          .lookup<ffi.NativeFunction<_SendMidiNoteOffFfiNative>>(
              'send_midi_note_off_ffi')
          .asFunction();

      _createMidiClip = _lib
          .lookup<ffi.NativeFunction<_CreateMidiClipFfiNative>>(
              'create_midi_clip_ffi')
          .asFunction();

      _addMidiNoteToClip = _lib
          .lookup<ffi.NativeFunction<_AddMidiNoteToClipFfiNative>>(
              'add_midi_note_to_clip_ffi')
          .asFunction();

      _addMidiClipToTrack = _lib
          .lookup<ffi.NativeFunction<_AddMidiClipToTrackFfiNative>>(
              'add_midi_clip_to_track_ffi')
          .asFunction();

      _removeMidiClip = _lib
          .lookup<ffi.NativeFunction<_RemoveMidiClipFfiNative>>(
              'remove_midi_clip_ffi')
          .asFunction();

      _clearMidiClip = _lib
          .lookup<ffi.NativeFunction<_ClearMidiClipFfiNative>>(
              'clear_midi_clip_ffi')
          .asFunction();

      // Bind M4 functions
      _createTrack = _lib
          .lookup<ffi.NativeFunction<_CreateTrackFfiNative>>(
              'create_track_ffi')
          .asFunction();

      _setTrackVolume = _lib
          .lookup<ffi.NativeFunction<_SetTrackVolumeFfiNative>>(
              'set_track_volume_ffi')
          .asFunction();

      _setTrackVolumeAutomation = _lib
          .lookup<ffi.NativeFunction<_SetTrackVolumeAutomationFfiNative>>(
              'set_track_volume_automation_ffi')
          .asFunction();

      _setTrackPan = _lib
          .lookup<ffi.NativeFunction<_SetTrackPanFfiNative>>(
              'set_track_pan_ffi')
          .asFunction();

      _setTrackMute = _lib
          .lookup<ffi.NativeFunction<_SetTrackMuteFfiNative>>(
              'set_track_mute_ffi')
          .asFunction();

      _setTrackSolo = _lib
          .lookup<ffi.NativeFunction<_SetTrackSoloFfiNative>>(
              'set_track_solo_ffi')
          .asFunction();

      _setTrackArmed = _lib
          .lookup<ffi.NativeFunction<_SetTrackArmedFfiNative>>(
              'set_track_armed_ffi')
          .asFunction();

      _setTrackInput = _lib
          .lookup<ffi.NativeFunction<_SetTrackInputFfiNative>>(
              'set_track_input_ffi')
          .asFunction();

      _getTrackInput = _lib
          .lookup<ffi.NativeFunction<_GetTrackInputFfiNative>>(
              'get_track_input_ffi')
          .asFunction();

      _setTrackInputMonitoring = _lib
          .lookup<ffi.NativeFunction<_SetTrackInputMonitoringFfiNative>>(
              'set_track_input_monitoring_ffi')
          .asFunction();

      _getInputChannelLevel = _lib
          .lookup<ffi.NativeFunction<_GetInputChannelLevelFfiNative>>(
              'get_input_channel_level_ffi')
          .asFunction();

      _getInputChannelCount = _lib
          .lookup<ffi.NativeFunction<_GetInputChannelCountFfiNative>>(
              'get_input_channel_count_ffi')
          .asFunction();

      _setTrackName = _lib
          .lookup<ffi.NativeFunction<_SetTrackNameFfiNative>>(
              'set_track_name_ffi')
          .asFunction();

      _getTrackCount = _lib
          .lookup<ffi.NativeFunction<_GetTrackCountFfiNative>>(
              'get_track_count_ffi')
          .asFunction();

      _getAllTrackIds = _lib
          .lookup<ffi.NativeFunction<_GetAllTrackIdsFfiNative>>(
              'get_all_track_ids_ffi')
          .asFunction();

      _getTrackInfo = _lib
          .lookup<ffi.NativeFunction<_GetTrackInfoFfiNative>>(
              'get_track_info_ffi')
          .asFunction();

      _getTrackPeakLevels = _lib
          .lookup<ffi.NativeFunction<_GetTrackPeakLevelsFfiNative>>(
              'get_track_peak_levels_ffi')
          .asFunction();

      _deleteTrack = _lib
          .lookup<ffi.NativeFunction<_DeleteTrackFfiNative>>(
              'delete_track_ffi')
          .asFunction();

      _duplicateTrack = _lib
          .lookup<ffi.NativeFunction<_DuplicateTrackFfiNative>>(
              'duplicate_track_ffi')
          .asFunction();

      _duplicateAudioClip = _lib
          .lookup<ffi.NativeFunction<_DuplicateAudioClipFfiNative>>(
              'duplicate_audio_clip_ffi')
          .asFunction();

      _removeAudioClip = _lib
          .lookup<ffi.NativeFunction<_RemoveAudioClipFfiNative>>(
              'remove_audio_clip_ffi')
          .asFunction();

      _addExistingClipToTrack = _lib
          .lookup<ffi.NativeFunction<_AddExistingClipToTrackFfiNative>>(
              'add_existing_clip_to_track_ffi')
          .asFunction();

      _clearAllTracks = _lib
          .lookup<ffi.NativeFunction<_ClearAllTracksFfiNative>>(
              'clear_all_tracks_ffi')
          .asFunction();

      // Bind M4 effect functions
      _addEffectToTrack = _lib
          .lookup<ffi.NativeFunction<_AddEffectToTrackFfiNative>>(
              'add_effect_to_track_ffi')
          .asFunction();

      _removeEffectFromTrack = _lib
          .lookup<ffi.NativeFunction<_RemoveEffectFromTrackFfiNative>>(
              'remove_effect_from_track_ffi')
          .asFunction();

      _getTrackEffects = _lib
          .lookup<ffi.NativeFunction<_GetTrackEffectsFfiNative>>(
              'get_track_effects_ffi')
          .asFunction();

      _getEffectInfo = _lib
          .lookup<ffi.NativeFunction<_GetEffectInfoFfiNative>>(
              'get_effect_info_ffi')
          .asFunction();

      _setEffectParameter = _lib
          .lookup<ffi.NativeFunction<_SetEffectParameterFfiNative>>(
              'set_effect_parameter_ffi')
          .asFunction();

      _setEffectBypass = _lib
          .lookup<ffi.NativeFunction<_SetEffectBypassFfiNative>>(
              'set_effect_bypass_ffi')
          .asFunction();

      _getEffectBypass = _lib
          .lookup<ffi.NativeFunction<_GetEffectBypassFfiNative>>(
              'get_effect_bypass_ffi')
          .asFunction();

      _reorderTrackEffects = _lib
          .lookup<ffi.NativeFunction<_ReorderTrackEffectsFfiNative>>(
              'reorder_track_effects_ffi')
          .asFunction();

      // Bind M5 functions - Save/Load
      _saveProject = _lib
          .lookup<ffi.NativeFunction<_SaveProjectFfiNative>>(
              'save_project_ffi')
          .asFunction();

      _loadProject = _lib
          .lookup<ffi.NativeFunction<_LoadProjectFfiNative>>(
              'load_project_ffi')
          .asFunction();

      _exportToWav = _lib
          .lookup<ffi.NativeFunction<_ExportToWavFfiNative>>(
              'export_to_wav_ffi')
          .asFunction();

      // Bind M8 functions - Enhanced Export
      _isFfmpegAvailable = _lib
          .lookup<ffi.NativeFunction<_IsFfmpegAvailableFfiNative>>(
              'is_ffmpeg_available_ffi')
          .asFunction();

      _exportAudio = _lib
          .lookup<ffi.NativeFunction<_ExportAudioFfiNative>>(
              'export_audio_ffi')
          .asFunction();

      _exportWavWithOptions = _lib
          .lookup<ffi.NativeFunction<_ExportWavWithOptionsFfiNative>>(
              'export_wav_with_options_ffi')
          .asFunction();

      _exportMp3WithOptions = _lib
          .lookup<ffi.NativeFunction<_ExportMp3WithOptionsFfiNative>>(
              'export_mp3_with_options_ffi')
          .asFunction();

      _writeMp3Metadata = _lib
          .lookup<ffi.NativeFunction<_WriteMp3MetadataFfiNative>>(
              'write_mp3_metadata_ffi')
          .asFunction();

      _getTracksForStems = _lib
          .lookup<ffi.NativeFunction<_GetTracksForStemsFfiNative>>(
              'get_tracks_for_stems_ffi')
          .asFunction();

      _exportStems = _lib
          .lookup<ffi.NativeFunction<_ExportStemsFfiNative>>(
              'export_stems_ffi')
          .asFunction();

      // Bind M8 Export Progress functions
      _getExportProgress = _lib
          .lookup<ffi.NativeFunction<_GetExportProgressFfiNative>>(
              'get_export_progress_ffi')
          .asFunction();

      _cancelExport = _lib
          .lookup<ffi.NativeFunction<_CancelExportFfiNative>>(
              'cancel_export_ffi')
          .asFunction();

      _resetExportProgress = _lib
          .lookup<ffi.NativeFunction<_ResetExportProgressFfiNative>>(
              'reset_export_progress_ffi')
          .asFunction();

      // Bind M6 functions - Per-track Synthesizer
      _setTrackInstrument = _lib
          .lookup<ffi.NativeFunction<_SetTrackInstrumentFfiNative>>(
              'set_track_instrument_ffi')
          .asFunction();

      _setSynthParameter = _lib
          .lookup<ffi.NativeFunction<_SetSynthParameterFfiNative>>(
              'set_synth_parameter_ffi')
          .asFunction();

      _getSynthParameters = _lib
          .lookup<ffi.NativeFunction<_GetSynthParametersFfiNative>>(
              'get_synth_parameters_ffi')
          .asFunction();

      _sendTrackMidiNoteOn = _lib
          .lookup<ffi.NativeFunction<_SendTrackMidiNoteOnFfiNative>>(
              'send_track_midi_note_on_ffi')
          .asFunction();

      _sendTrackMidiNoteOff = _lib
          .lookup<ffi.NativeFunction<_SendTrackMidiNoteOffFfiNative>>(
              'send_track_midi_note_off_ffi')
          .asFunction();

      // Bind Sampler functions
      _createSamplerForTrack = _lib
          .lookup<ffi.NativeFunction<_CreateSamplerForTrackFfiNative>>(
              'create_sampler_for_track_ffi')
          .asFunction();

      _loadSampleForTrack = _lib
          .lookup<ffi.NativeFunction<_LoadSampleForTrackFfiNative>>(
              'load_sample_for_track_ffi')
          .asFunction();

      _setSamplerParameter = _lib
          .lookup<ffi.NativeFunction<_SetSamplerParameterFfiNative>>(
              'set_sampler_parameter_ffi')
          .asFunction();

      _isSamplerTrack = _lib
          .lookup<ffi.NativeFunction<_IsSamplerTrackFfiNative>>(
              'is_sampler_track_ffi')
          .asFunction();

      _getSamplerInfo = _lib
          .lookup<ffi.NativeFunction<_GetSamplerInfoFfiNative>>(
              'get_sampler_info_ffi')
          .asFunction();

      _getSamplerWaveformPeaks = _lib
          .lookup<ffi.NativeFunction<_GetSamplerWaveformPeaksFfiNative>>(
              'get_sampler_waveform_peaks_ffi')
          .asFunction();

      _freeSamplerWaveformPeaks = _lib
          .lookup<ffi.NativeFunction<_FreeSamplerWaveformPeaksFfiNative>>(
              'free_sampler_waveform_peaks_ffi')
          .asFunction();

      // Bind M7 functions - VST3 Plugin Hosting
      _scanVst3PluginsStandard = _lib
          .lookup<ffi.NativeFunction<_ScanVst3PluginsStandardFfiNative>>(
              'scan_vst3_plugins_standard_ffi')
          .asFunction();

      _addVst3EffectToTrack = _lib
          .lookup<ffi.NativeFunction<_AddVst3EffectToTrackFfiNative>>(
              'add_vst3_effect_to_track_ffi')
          .asFunction();

      _getVst3ParameterCount = _lib
          .lookup<ffi.NativeFunction<_GetVst3ParameterCountFfiNative>>(
              'get_vst3_parameter_count_ffi')
          .asFunction();

      _getVst3ParameterInfo = _lib
          .lookup<ffi.NativeFunction<_GetVst3ParameterInfoFfiNative>>(
              'get_vst3_parameter_info_ffi')
          .asFunction();

      _getVst3ParameterValue = _lib
          .lookup<ffi.NativeFunction<_GetVst3ParameterValueFfiNative>>(
              'get_vst3_parameter_value_ffi')
          .asFunction();

      _setVst3ParameterValue = _lib
          .lookup<ffi.NativeFunction<_SetVst3ParameterValueFfiNative>>(
              'set_vst3_parameter_value_ffi')
          .asFunction();

      // M7 VST3 Editor functions
      _vst3HasEditor = _lib
          .lookup<ffi.NativeFunction<_Vst3HasEditorFfiNative>>(
              'vst3_has_editor_ffi')
          .asFunction();

      _vst3OpenEditor = _lib
          .lookup<ffi.NativeFunction<_Vst3OpenEditorFfiNative>>(
              'vst3_open_editor_ffi')
          .asFunction();

      _vst3CloseEditor = _lib
          .lookup<ffi.NativeFunction<_Vst3CloseEditorFfiNative>>(
              'vst3_close_editor_ffi')
          .asFunction();

      _vst3GetEditorSize = _lib
          .lookup<ffi.NativeFunction<_Vst3GetEditorSizeFfiNative>>(
              'vst3_get_editor_size_ffi')
          .asFunction();

      _vst3AttachEditor = _lib
          .lookup<ffi.NativeFunction<_Vst3AttachEditorFfiNative>>(
              'vst3_attach_editor_ffi')
          .asFunction();

      _vst3SendMidiNote = _lib
          .lookup<ffi.NativeFunction<_Vst3SendMidiNoteFfiNative>>(
              'vst3_send_midi_note_ffi')
          .asFunction();

      // Bind MIDI Recording functions
      _getMidiInputDevices = _lib
          .lookup<ffi.NativeFunction<_GetMidiInputDevicesFfiNative>>(
              'get_midi_input_devices_ffi')
          .asFunction();

      _selectMidiInputDevice = _lib
          .lookup<ffi.NativeFunction<_SelectMidiInputDeviceFfiNative>>(
              'select_midi_input_device_ffi')
          .asFunction();

      _refreshMidiDevices = _lib
          .lookup<ffi.NativeFunction<_RefreshMidiDevicesFfiNative>>(
              'refresh_midi_devices_ffi')
          .asFunction();

      _startMidiRecording = _lib
          .lookup<ffi.NativeFunction<_StartMidiRecordingFfiNative>>(
              'start_midi_recording_ffi')
          .asFunction();

      _stopMidiRecording = _lib
          .lookup<ffi.NativeFunction<_StopMidiRecordingFfiNative>>(
              'stop_midi_recording_ffi')
          .asFunction();

      _getMidiRecordingState = _lib
          .lookup<ffi.NativeFunction<_GetMidiRecordingStateFfiNative>>(
              'get_midi_recording_state_ffi')
          .asFunction();

      _getMidiRecorderLiveEvents = _lib
          .lookup<ffi.NativeFunction<_GetMidiRecorderLiveEventsFfiNative>>(
              'get_midi_recorder_live_events_ffi')
          .asFunction();

      _quantizeMidiClip = _lib
          .lookup<ffi.NativeFunction<_QuantizeMidiClipFfiNative>>(
              'quantize_midi_clip_ffi')
          .asFunction();

      _getMidiClipInfo = _lib
          .lookup<ffi.NativeFunction<_GetMidiClipInfoFfiNative>>(
              'get_midi_clip_info_ffi')
          .asFunction();

      _getAllMidiClipsInfo = _lib
          .lookup<ffi.NativeFunction<_GetAllMidiClipsInfoFfiNative>>(
              'get_all_midi_clips_info_ffi')
          .asFunction();

      _getMidiClipNotes = _lib
          .lookup<ffi.NativeFunction<_GetMidiClipNotesFfiNative>>(
              'get_midi_clip_notes_ffi')
          .asFunction();

      // Bind Audio Device functions
      _getAudioInputDevices = _lib
          .lookup<ffi.NativeFunction<_GetAudioInputDevicesFfiNative>>(
              'get_audio_input_devices_ffi')
          .asFunction();

      _getAudioOutputDevices = _lib
          .lookup<ffi.NativeFunction<_GetAudioOutputDevicesFfiNative>>(
              'get_audio_output_devices_ffi')
          .asFunction();

      _setAudioInputDevice = _lib
          .lookup<ffi.NativeFunction<_SetAudioInputDeviceFfiNative>>(
              'set_audio_input_device_ffi')
          .asFunction();

      _setAudioOutputDevice = _lib
          .lookup<ffi.NativeFunction<_SetAudioOutputDeviceFfiNative>>(
              'set_audio_output_device_ffi')
          .asFunction();

      _getSelectedAudioOutputDevice = _lib
          .lookup<ffi.NativeFunction<_GetSelectedAudioOutputDeviceFfiNative>>(
              'get_selected_audio_output_device_ffi')
          .asFunction();

      _getSampleRate = _lib
          .lookup<ffi.NativeFunction<_GetSampleRateFfiNative>>(
              'get_sample_rate_ffi')
          .asFunction();

      // Bind Library Preview functions
      _previewLoadAudio = _lib
          .lookup<ffi.NativeFunction<_PreviewLoadAudioFfiNative>>(
              'preview_load_audio_ffi')
          .asFunction();

      _previewPlay = _lib
          .lookup<ffi.NativeFunction<_PreviewPlayFfiNative>>(
              'preview_play_ffi')
          .asFunction();

      _previewStop = _lib
          .lookup<ffi.NativeFunction<_PreviewStopFfiNative>>(
              'preview_stop_ffi')
          .asFunction();

      _previewSeek = _lib
          .lookup<ffi.NativeFunction<_PreviewSeekFfiNative>>(
              'preview_seek_ffi')
          .asFunction();

      _previewGetPosition = _lib
          .lookup<ffi.NativeFunction<_PreviewGetPositionFfiNative>>(
              'preview_get_position_ffi')
          .asFunction();

      _previewGetDuration = _lib
          .lookup<ffi.NativeFunction<_PreviewGetDurationFfiNative>>(
              'preview_get_duration_ffi')
          .asFunction();

      _previewIsPlaying = _lib
          .lookup<ffi.NativeFunction<_PreviewIsPlayingFfiNative>>(
              'preview_is_playing_ffi')
          .asFunction();

      _previewSetLooping = _lib
          .lookup<ffi.NativeFunction<_PreviewSetLoopingFfiNative>>(
              'preview_set_looping_ffi')
          .asFunction();

      _previewIsLooping = _lib
          .lookup<ffi.NativeFunction<_PreviewIsLoopingFfiNative>>(
              'preview_is_looping_ffi')
          .asFunction();

      _previewGetWaveform = _lib
          .lookup<ffi.NativeFunction<_PreviewGetWaveformFfiNative>>(
              'preview_get_waveform_ffi')
          .asFunction();

      // Bind Punch Recording functions
      _setPunchInEnabled = _lib
          .lookup<ffi.NativeFunction<_SetPunchInEnabledFfiNative>>(
              'set_punch_in_enabled_ffi')
          .asFunction();

      _isPunchInEnabled = _lib
          .lookup<ffi.NativeFunction<_IsPunchInEnabledFfiNative>>(
              'is_punch_in_enabled_ffi')
          .asFunction();

      _setPunchOutEnabled = _lib
          .lookup<ffi.NativeFunction<_SetPunchOutEnabledFfiNative>>(
              'set_punch_out_enabled_ffi')
          .asFunction();

      _isPunchOutEnabled = _lib
          .lookup<ffi.NativeFunction<_IsPunchOutEnabledFfiNative>>(
              'is_punch_out_enabled_ffi')
          .asFunction();

      _setPunchRegion = _lib
          .lookup<ffi.NativeFunction<_SetPunchRegionFfiNative>>(
              'set_punch_region_ffi')
          .asFunction();

      _getPunchInSeconds = _lib
          .lookup<ffi.NativeFunction<_GetPunchInSecondsFfiNative>>(
              'get_punch_in_seconds_ffi')
          .asFunction();

      _getPunchOutSeconds = _lib
          .lookup<ffi.NativeFunction<_GetPunchOutSecondsFfiNative>>(
              'get_punch_out_seconds_ffi')
          .asFunction();

      _isPunchComplete = _lib
          .lookup<ffi.NativeFunction<_IsPunchCompleteFfiNative>>(
              'is_punch_complete_ffi')
          .asFunction();

    } catch (e) {
      rethrow;
    }
  }
}
