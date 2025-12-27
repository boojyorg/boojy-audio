import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings for the Rust audio engine
class AudioEngine {
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
  late final _GetClipDurationFfi _getClipDuration;

  // Latency Control functions
  late final _SetBufferSizeFfi _setBufferSize;
  late final _GetBufferSizePresetFfi _getBufferSizePreset;
  late final _GetActualBufferSizeFfi _getActualBufferSize;
  late final _GetLatencyInfoFfi _getLatencyInfo;
  late final _SetClipStartTimeFfi _setClipStartTime;
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
  late final _SetTempoFfi _setTempo;
  late final _GetTempoFfi _getTempo;
  late final _SetMetronomeEnabledFfi _setMetronomeEnabled;
  late final _IsMetronomeEnabledFfi _isMetronomeEnabled;

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

  // M4 functions - Tracks & Mixer
  late final _CreateTrackFfi _createTrack;
  late final _SetTrackVolumeFfi _setTrackVolume;
  late final _SetTrackPanFfi _setTrackPan;
  late final _SetTrackMuteFfi _setTrackMute;
  late final _SetTrackSoloFfi _setTrackSolo;
  late final _SetTrackArmedFfi _setTrackArmed;
  late final _SetTrackNameFfi _setTrackName;
  late final _GetTrackCountFfi _getTrackCount;
  late final _GetAllTrackIdsFfi _getAllTrackIds;
  late final _GetTrackInfoFfi _getTrackInfo;
  late final _GetTrackPeakLevelsFfi _getTrackPeakLevels;
  late final _DeleteTrackFfi _deleteTrack;
  late final _DuplicateTrackFfi _duplicateTrack;
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
  late final _QuantizeMidiClipFfi _quantizeMidiClip;
  late final _GetMidiClipInfoFfi _getMidiClipInfo;
  late final _GetAllMidiClipsInfoFfi _getAllMidiClipsInfo;
  late final _GetMidiClipNotesFfi _getMidiClipNotes;

  // Audio Device functions
  late final _GetAudioInputDevicesFfi _getAudioInputDevices;
  late final _GetAudioOutputDevicesFfi _getAudioOutputDevices;
  late final _SetAudioInputDeviceFfi _setAudioInputDevice;
  late final _GetSampleRateFfi _getSampleRate;

  AudioEngine() {
    // Load the native library
    if (Platform.isMacOS) {
      // Find the library by searching multiple locations
      // Priority: 1) Executable-relative paths, 2) Current directory paths

      String? libPath;

      // Get the executable path to find library relative to app bundle
      final executablePath = Platform.resolvedExecutable;
      final executableDir = File(executablePath).parent.path;

      // List of paths to try, in order of priority
      final pathsToTry = <String>[
        // Development: symlink in Runner directory (relative to app bundle)
        '$executableDir/../../../macos/Runner/libengine.dylib',
        // Development: engine folder relative to app bundle
        '$executableDir/../../../../engine/target/release/libengine.dylib',
        // Development: direct path from project root
        '/Users/tyrbujac/Documents/Developments/2025/Flutter/Boojy Audio/engine/target/release/libengine.dylib',
      ];

      // Also search from current directory (works for flutter run)
      var searchDir = Directory.current;
      for (var i = 0; i < 5; i++) {
        pathsToTry.add('${searchDir.path}/engine/target/release/libengine.dylib');
        pathsToTry.add('${searchDir.path}/macos/Runner/libengine.dylib');
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

      _getClipDuration = _lib
          .lookup<ffi.NativeFunction<_GetClipDurationFfiNative>>(
              'get_clip_duration_ffi')
          .asFunction();

      _setClipStartTime = _lib
          .lookup<ffi.NativeFunction<_SetClipStartTimeFfiNative>>(
              'set_clip_start_time_ffi')
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

      _getSampleRate = _lib
          .lookup<ffi.NativeFunction<_GetSampleRateFfiNative>>(
              'get_sample_rate_ffi')
          .asFunction();

    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M0 API
  // ========================================================================

  /// Initialize the audio engine
  String initAudioEngine() {
    try {
      final resultPtr = _initAudioEngine();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Play a sine wave at the specified frequency
  String playSineWave(double frequency, int durationMs) {
    try {
      final resultPtr = _playSineWave(frequency, durationMs);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M1 API
  // ========================================================================

  /// Initialize the audio graph
  String initAudioGraph() {
    try {
      final resultPtr = _initAudioGraph();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Load an audio file and return clip ID (-1 on error)
  /// Legacy method - adds clip to first available audio track
  int loadAudioFile(String path) {
    try {
      final pathPtr = path.toNativeUtf8();
      final clipId = _loadAudioFile(pathPtr.cast());
      malloc.free(pathPtr);

      if (clipId < 0) {
        return -1;
      }

      return clipId;
    } catch (e) {
      rethrow;
    }
  }

  /// Load an audio file to a specific track and return clip ID (-1 on error)
  int loadAudioFileToTrack(String path, int trackId, {double startTime = 0.0}) {
    try {
      final pathPtr = path.toNativeUtf8();
      final clipId = _loadAudioFileToTrack(pathPtr.cast(), trackId, startTime);
      malloc.free(pathPtr);

      if (clipId < 0) {
        return -1;
      }

      return clipId;
    } catch (e) {
      rethrow;
    }
  }

  /// Start playback
  String transportPlay() {
    try {
      final resultPtr = _transportPlay();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Pause playback
  String transportPause() {
    try {
      final resultPtr = _transportPause();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Stop playback
  String transportStop() {
    try {
      final resultPtr = _transportStop();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Seek to position in seconds
  String transportSeek(double positionSeconds) {
    try {
      final resultPtr = _transportSeek(positionSeconds);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get current playhead position in seconds
  double getPlayheadPosition() {
    try {
      return _getPlayheadPosition();
    } catch (e) {
      return 0.0;
    }
  }

  /// Get transport state (0=Stopped, 1=Playing, 2=Paused)
  int getTransportState() {
    try {
      return _getTransportState();
    } catch (e) {
      return 0;
    }
  }

  // ============================================================================
  // Latency Control API
  // ============================================================================

  /// Buffer size presets for latency control
  static const Map<int, String> bufferSizePresets = {
    0: 'Lowest (64 samples, ~1.3ms)',
    1: 'Low (128 samples, ~2.7ms)',
    2: 'Balanced (256 samples, ~5.3ms)',
    3: 'Safe (512 samples, ~10.7ms)',
    4: 'High Stability (1024 samples, ~21.3ms)',
  };

  /// Set buffer size preset
  /// 0=Lowest, 1=Low, 2=Balanced, 3=Safe, 4=HighStability
  String setBufferSize(int preset) {
    try {
      final result = _setBufferSize(preset);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get current buffer size preset (0-4)
  int getBufferSizePreset() {
    try {
      return _getBufferSizePreset();
    } catch (e) {
      return 2; // Default to Balanced
    }
  }

  /// Get actual buffer size in samples
  int getActualBufferSize() {
    try {
      return _getActualBufferSize();
    } catch (e) {
      return 256;
    }
  }

  /// Get audio latency info
  /// Returns: {bufferSize, inputLatencyMs, outputLatencyMs, roundtripMs}
  Map<String, double> getLatencyInfo() {
    final bufferSizePtr = calloc<ffi.Uint32>();
    final inputLatencyPtr = calloc<ffi.Float>();
    final outputLatencyPtr = calloc<ffi.Float>();
    final roundtripPtr = calloc<ffi.Float>();

    try {
      _getLatencyInfo(bufferSizePtr, inputLatencyPtr, outputLatencyPtr, roundtripPtr);

      return {
        'bufferSize': bufferSizePtr.value.toDouble(),
        'inputLatencyMs': inputLatencyPtr.value,
        'outputLatencyMs': outputLatencyPtr.value,
        'roundtripMs': roundtripPtr.value,
      };
    } catch (e) {
      return {
        'bufferSize': 256,
        'inputLatencyMs': 5.3,
        'outputLatencyMs': 5.3,
        'roundtripMs': 10.7,
      };
    } finally {
      calloc.free(bufferSizePtr);
      calloc.free(inputLatencyPtr);
      calloc.free(outputLatencyPtr);
      calloc.free(roundtripPtr);
    }
  }

  /// Get clip duration in seconds
  double getClipDuration(int clipId) {
    try {
      return _getClipDuration(clipId);
    } catch (e) {
      return 0.0;
    }
  }

  /// Set clip start time (position) on timeline
  /// Used for dragging clips to reposition them
  String setClipStartTime(int trackId, int clipId, double startTime) {
    try {
      final result = _setClipStartTime(trackId, clipId, startTime);
      final str = result.toDartString();
      _freeRustString(result);
      return str;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get waveform peaks for visualization
  List<double> getWaveformPeaks(int clipId, int resolution) {
    try {
      final lengthPtr = malloc<ffi.Size>();
      final peaksPtr = _getWaveformPeaks(clipId, resolution, lengthPtr);
      final length = lengthPtr.value;
      malloc.free(lengthPtr);
      
      if (peaksPtr == ffi.nullptr || length == 0) {
        return [];
      }
      
      // Convert to Dart list
      final peaks = <double>[];
      for (int i = 0; i < length; i++) {
        peaks.add(peaksPtr[i]);
      }
      
      // Free the peaks array
      _freeWaveformPeaks(peaksPtr, length);
      
      return peaks;
    } catch (e) {
      return [];
    }
  }

  // ========================================================================
  // M2 API - Recording & Input
  // ========================================================================

  /// Start recording audio
  String startRecording() {
    try {
      final resultPtr = _startRecording();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Stop recording and return clip ID (-1 if no recording)
  int stopRecording() {
    try {
      final clipId = _stopRecording();
      return clipId;
    } catch (e) {
      return -1;
    }
  }

  /// Get recording state (0=Idle, 1=CountingIn, 2=Recording)
  int getRecordingState() {
    try {
      return _getRecordingState();
    } catch (e) {
      return 0;
    }
  }

  /// Get recorded duration in seconds
  double getRecordedDuration() {
    try {
      return _getRecordedDuration();
    } catch (e) {
      return 0.0;
    }
  }

  /// Get recording waveform preview as list of peak values (0.0-1.0)
  /// numPeaks: number of downsampled peaks to return
  List<double> getRecordingWaveform(int numPeaks) {
    try {
      final resultPtr = _getRecordingWaveform(numPeaks);
      final csv = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (csv.isEmpty) {
        return [];
      }

      return csv.split(',')
          .map((s) => double.tryParse(s) ?? 0.0)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Set count-in duration in bars
  String setCountInBars(int bars) {
    try {
      final resultPtr = _setCountInBars(bars);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get count-in duration in bars
  int getCountInBars() {
    try {
      return _getCountInBars();
    } catch (e) {
      return 2;
    }
  }

  /// Set tempo in BPM
  String setTempo(double bpm) {
    try {
      final resultPtr = _setTempo(bpm);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get tempo in BPM
  double getTempo() {
    try {
      return _getTempo();
    } catch (e) {
      return 120.0;
    }
  }

  /// Enable or disable metronome
  String setMetronomeEnabled(bool enabled) {
    try {
      final resultPtr = _setMetronomeEnabled(enabled ? 1 : 0);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Check if metronome is enabled
  bool isMetronomeEnabled() {
    try {
      return _isMetronomeEnabled() != 0;
    } catch (e) {
      return true;
    }
  }

  // ========================================================================
  // M3 API - MIDI
  // ========================================================================

  /// Start MIDI input (initializes MIDI system and synthesizer)
  String startMidiInput() {
    try {
      final resultPtr = _startMidiInput();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Stop MIDI input
  String stopMidiInput() {
    try {
      final resultPtr = _stopMidiInput();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set synthesizer oscillator type (0=Sine, 1=Saw, 2=Square)
  String setSynthOscillatorType(int oscType) {
    try {
      final resultPtr = _setSynthOscillatorType(oscType);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set synthesizer volume (0.0 to 1.0)
  String setSynthVolume(double volume) {
    try {
      final resultPtr = _setSynthVolume(volume);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note on event to synthesizer (for virtual piano)
  String sendMidiNoteOn(int note, int velocity) {
    try {
      final resultPtr = _sendMidiNoteOn(note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note off event to synthesizer (for virtual piano)
  String sendMidiNoteOff(int note, int velocity) {
    try {
      final resultPtr = _sendMidiNoteOff(note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new empty MIDI clip in Rust
  /// Returns clip ID or -1 on error
  int createMidiClip() {
    try {
      return _createMidiClip();
    } catch (e) {
      return -1;
    }
  }

  /// Add a MIDI note to a clip
  /// Returns success message or error
  String addMidiNoteToClip(int clipId, int note, int velocity, double startTime, double duration) {
    try {
      final resultPtr = _addMidiNoteToClip(clipId, note, velocity, startTime, duration);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Add a MIDI clip to a track's timeline for playback
  /// Returns 0 on success, -1 on error
  int addMidiClipToTrack(int trackId, int clipId, double startTimeSeconds) {
    try {
      return _addMidiClipToTrack(trackId, clipId, startTimeSeconds);
    } catch (e) {
      return -1;
    }
  }

  /// Remove a MIDI clip from a track and global storage
  /// Returns 0 if removed, 1 if not found, -1 on error
  int removeMidiClip(int trackId, int clipId) {
    try {
      return _removeMidiClip(trackId, clipId);
    } catch (e) {
      return -1;
    }
  }

  /// Clear all MIDI notes from a clip
  /// Returns success message or error
  String clearMidiClip(int clipId) {
    try {
      final resultPtr = _clearMidiClip(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // MIDI Recording API
  // ========================================================================

  /// Get available MIDI input devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getMidiInputDevices() {
    try {
      final resultPtr = _getMidiInputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Select a MIDI input device by index
  /// Returns success message or error
  String selectMidiInputDevice(int deviceIndex) {
    try {
      final resultPtr = _selectMidiInputDevice(deviceIndex);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Refresh MIDI devices (rescan)
  /// Returns success message or error
  String refreshMidiDevices() {
    try {
      final resultPtr = _refreshMidiDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // Audio Device API
  // ========================================================================

  /// Get available audio input devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getAudioInputDevices() {
    try {
      final resultPtr = _getAudioInputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Get available audio output devices
  /// Returns list of devices with id, name, and isDefault
  List<Map<String, dynamic>> getAudioOutputDevices() {
    try {
      final resultPtr = _getAudioOutputDevices();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      // Parse result: "id|name|is_default" per line
      final devices = <Map<String, dynamic>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 3) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'isDefault': parts[2] == '1',
          });
        }
      }

      return devices;
    } catch (e) {
      return [];
    }
  }

  /// Set audio input device by index
  /// Returns success message or error
  String setAudioInputDevice(int deviceIndex) {
    try {
      final resultPtr = _setAudioInputDevice(deviceIndex);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get current sample rate
  int getSampleRate() {
    try {
      return _getSampleRate();
    } catch (e) {
      return 48000; // Default fallback
    }
  }

  /// Start MIDI recording
  /// Returns success message or error
  String startMidiRecording() {
    try {
      final resultPtr = _startMidiRecording();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Stop MIDI recording and return clip ID
  /// Returns clip ID or -1 if no recording
  int stopMidiRecording() {
    try {
      final clipId = _stopMidiRecording();
      return clipId;
    } catch (e) {
      return -1;
    }
  }

  /// Get MIDI recording state (0=Idle, 1=Recording)
  int getMidiRecordingState() {
    try {
      return _getMidiRecordingState();
    } catch (e) {
      return 0;
    }
  }

  /// Quantize a MIDI clip to grid
  /// gridDivision: 4=1/4 note, 8=1/8, 16=1/16, 32=1/32
  String quantizeMidiClip(int clipId, int gridDivision) {
    try {
      final resultPtr = _quantizeMidiClip(clipId, gridDivision);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get MIDI clip info
  /// Returns: "clip_id,track_id,start_time,duration,note_count"
  /// track_id is -1 if not assigned to a track
  String getMidiClipInfo(int clipId) {
    try {
      final resultPtr = _getMidiClipInfo(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get all MIDI clips info
  /// Returns semicolon-separated list: "clip_id,track_id,start_time,duration,note_count"
  /// Each clip info is separated by semicolon
  String getAllMidiClipsInfo() {
    try {
      final resultPtr = _getAllMidiClipsInfo();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get MIDI notes from a clip
  /// Returns semicolon-separated list: "note,velocity,start_time,duration"
  String getMidiClipNotes(int clipId) {
    try {
      final resultPtr = _getMidiClipNotes(clipId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // M4 API - Tracks & Mixer
  // ========================================================================

  /// Create a new track
  /// trackType: "audio", "midi", "return", "group", or "master"
  /// Returns track ID or -1 on error
  int createTrack(String trackType, String name) {
    try {
      final typePtr = trackType.toNativeUtf8();
      final namePtr = name.toNativeUtf8();
      final trackId = _createTrack(typePtr.cast(), namePtr.cast());
      malloc.free(typePtr);
      malloc.free(namePtr);

      if (trackId < 0) {
        return -1;
      }

      return trackId;
    } catch (e) {
      return -1;
    }
  }

  /// Set track volume in dB (-∞ to +6 dB)
  String setTrackVolume(int trackId, double volumeDb) {
    try {
      final resultPtr = _setTrackVolume(trackId, volumeDb);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set track pan (-1.0 = full left, 0.0 = center, 1.0 = full right)
  String setTrackPan(int trackId, double pan) {
    try {
      final resultPtr = _setTrackPan(trackId, pan);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Mute or unmute a track
  String setTrackMute(int trackId, bool mute) {
    try {
      final resultPtr = _setTrackMute(trackId, mute);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Solo or unsolo a track
  String setTrackSolo(int trackId, bool solo) {
    try {
      final resultPtr = _setTrackSolo(trackId, solo);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Arm or disarm a track for recording
  String setTrackArmed(int trackId, bool armed) {
    try {
      final resultPtr = _setTrackArmed(trackId, armed);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Rename a track
  String setTrackName(int trackId, String name) {
    try {
      final namePtr = name.toNativeUtf8();
      final resultPtr = _setTrackName(trackId, namePtr);
      calloc.free(namePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get total number of tracks
  int getTrackCount() {
    try {
      return _getTrackCount();
    } catch (e) {
      return 0;
    }
  }

  /// Get all track IDs as list
  List<int> getAllTrackIds() {
    try {
      final resultPtr = _getAllTrackIds();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      return result.split(',').map((id) => int.parse(id)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get track info as CSV: "track_id,name,type,volume_db,pan,mute,solo"
  String getTrackInfo(int trackId) {
    try {
      final resultPtr = _getTrackInfo(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Get track peak levels (M5.5) as CSV: "peak_left_db,peak_right_db"
  String getTrackPeakLevels(int trackId) {
    try {
      final resultPtr = _getTrackPeakLevels(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      // Fail silently for peak levels (called frequently)
      return '-96.0,-96.0';
    }
  }

  /// Delete a track (cannot delete master track)
  String deleteTrack(int trackId) {
    try {
      final resultPtr = _deleteTrack(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Duplicate a track (cannot duplicate master track)
  /// Returns the new track ID, or -1 on error
  int duplicateTrack(int trackId) {
    try {
      final newTrackId = _duplicateTrack(trackId);
      if (newTrackId >= 0) {
        return newTrackId;
      } else {
        return -1;
      }
    } catch (e) {
      return -1;
    }
  }

  /// Clear all tracks except master - used for New Project / Close Project
  String clearAllTracks() {
    try {
      final resultPtr = _clearAllTracks();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M4 API - Effects
  // ========================================================================

  /// Add an effect to a track's FX chain
  /// effectType: "eq", "compressor", "reverb", "delay", "chorus", "limiter"
  /// Returns effect ID or -1 on error
  int addEffectToTrack(int trackId, String effectType) {
    try {
      final typePtr = effectType.toNativeUtf8();
      final effectId = _addEffectToTrack(trackId, typePtr.cast());
      malloc.free(typePtr);

      if (effectId < 0) {
        return -1;
      }

      return effectId;
    } catch (e) {
      return -1;
    }
  }

  /// Remove an effect from a track's FX chain
  String removeEffectFromTrack(int trackId, int effectId) {
    try {
      final resultPtr = _removeEffectFromTrack(trackId, effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all effects on a track (returns CSV of effect IDs)
  String getTrackEffects(int trackId) {
    try {
      final resultPtr = _getTrackEffects(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Get effect info (type and parameters)
  /// Returns format: "type:eq,low_freq:100,low_gain:0,..."
  String getEffectInfo(int effectId) {
    try {
      final resultPtr = _getEffectInfo(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Set an effect parameter
  String setEffectParameter(int effectId, String paramName, double value) {
    try {
      final namePtr = paramName.toNativeUtf8();
      final resultPtr = _setEffectParameter(effectId, namePtr.cast(), value);
      malloc.free(namePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set effect bypass state
  /// Returns true on success, false on failure
  bool setEffectBypass(int effectId, bool bypassed) {
    try {
      final result = _setEffectBypass(effectId, bypassed ? 1 : 0);
      return result == 1;
    } catch (e) {
      return false;
    }
  }

  /// Get effect bypass state
  /// Returns true if bypassed, false if not bypassed or on error
  bool getEffectBypass(int effectId) {
    try {
      final result = _getEffectBypass(effectId);
      return result == 1;
    } catch (e) {
      return false;
    }
  }

  /// Reorder effects in a track's FX chain
  /// Takes a list of effect IDs in the desired order
  String reorderTrackEffects(int trackId, List<int> effectIds) {
    try {
      final idsStr = effectIds.join(',');
      final idsPtr = idsStr.toNativeUtf8();
      final resultPtr = _reorderTrackEffects(trackId, idsPtr.cast());
      malloc.free(idsPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ========================================================================
  // M5 API - Save/Load Project
  // ========================================================================

  /// Save project to .audio folder
  String saveProject(String projectName, String projectPath) {
    try {
      final namePtr = projectName.toNativeUtf8();
      final pathPtr = projectPath.toNativeUtf8();
      final resultPtr = _saveProject(namePtr.cast(), pathPtr.cast());
      malloc.free(namePtr);
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Load project from .audio folder
  String loadProject(String projectPath) {
    try {
      final pathPtr = projectPath.toNativeUtf8();
      final resultPtr = _loadProject(pathPtr.cast());
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export project to WAV file (legacy method - uses 32-bit float, 48kHz)
  String exportToWav(String outputPath, bool normalize) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportToWav(pathPtr.cast(), normalize);
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M8 API - Enhanced Export
  // ========================================================================

  /// Check if ffmpeg is available for MP3 encoding
  bool isFfmpegAvailable() {
    return _isFfmpegAvailable() == 1;
  }

  /// Export audio with generic JSON options
  /// Returns JSON string with ExportResult on success
  String exportAudio(String outputPath, String optionsJson) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final optionsPtr = optionsJson.toNativeUtf8();
      final resultPtr = _exportAudio(pathPtr.cast(), optionsPtr.cast());
      malloc.free(pathPtr);
      malloc.free(optionsPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export WAV with configurable options
  /// bitDepth: 16, 24, or 32 (float)
  /// sampleRate: 44100 or 48000
  /// Returns JSON string with ExportResult on success
  String exportWavWithOptions({
    required String outputPath,
    int bitDepth = 16,
    int sampleRate = 44100,
    bool normalize = false,
    bool dither = false,
    bool mono = false,
  }) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportWavWithOptions(
        pathPtr.cast(),
        bitDepth,
        sampleRate,
        normalize,
        dither,
        mono,
      );
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export MP3 with configurable options
  /// bitrate: 128, 192, or 320 kbps
  /// sampleRate: 44100 or 48000
  /// Returns JSON string with ExportResult on success
  String exportMp3WithOptions({
    required String outputPath,
    int bitrate = 320,
    int sampleRate = 44100,
    bool normalize = false,
    bool mono = false,
  }) {
    try {
      final pathPtr = outputPath.toNativeUtf8();
      final resultPtr = _exportMp3WithOptions(
        pathPtr.cast(),
        bitrate,
        sampleRate,
        normalize,
        mono,
      );
      malloc.free(pathPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Write ID3 metadata to an MP3 file
  /// metadataJson: JSON string with title, artist, album, year, genre, etc.
  String writeMp3Metadata(String filePath, String metadataJson) {
    try {
      final pathPtr = filePath.toNativeUtf8();
      final metadataPtr = metadataJson.toNativeUtf8();
      final resultPtr = _writeMp3Metadata(pathPtr.cast(), metadataPtr.cast());
      malloc.free(pathPtr);
      malloc.free(metadataPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get tracks available for stem export
  /// Returns JSON array of {id, name, type} objects
  String getTracksForStems() {
    try {
      final resultPtr = _getTracksForStems();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Export stems (individual tracks) to a directory
  /// outputDir: Directory to export stems to
  /// baseName: Base filename for stems (e.g., "My Song")
  /// trackIdsJson: JSON array of track IDs to export, or empty string for all tracks
  /// optionsJson: JSON string of ExportOptions
  /// Returns JSON string with StemExportResult on success
  String exportStems({
    required String outputDir,
    required String baseName,
    String trackIdsJson = '',
    required String optionsJson,
  }) {
    try {
      final dirPtr = outputDir.toNativeUtf8();
      final namePtr = baseName.toNativeUtf8();
      final trackIdsPtr = trackIdsJson.toNativeUtf8();
      final optionsPtr = optionsJson.toNativeUtf8();

      final resultPtr = _exportStems(
        dirPtr.cast(),
        namePtr.cast(),
        trackIdsPtr.cast(),
        optionsPtr.cast(),
      );

      malloc.free(dirPtr);
      malloc.free(namePtr);
      malloc.free(trackIdsPtr);
      malloc.free(optionsPtr);

      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.startsWith('Error:')) {
        throw Exception(result);
      }

      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M8 API - Export Progress
  // ========================================================================

  /// Get current export progress as JSON
  /// Returns: {"progress": 0-100, "is_running": bool, "is_cancelled": bool, "status": string, "error": string|null}
  String getExportProgress() {
    try {
      final resultPtr = _getExportProgress();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '{"progress": 0, "is_running": false, "is_cancelled": false, "status": "", "error": "Failed to get progress: $e"}';
    }
  }

  /// Cancel the current export operation
  void cancelExport() {
    try {
      _cancelExport();
    } catch (e) {
    }
  }

  /// Reset export progress state (call before starting a new export)
  void resetExportProgress() {
    try {
      _resetExportProgress();
    } catch (e) {
    }
  }

  // ========================================================================
  // M6 API - Per-track Synthesizer
  // ========================================================================

  /// Set the instrument for a track
  /// Returns the instrument ID or -1 on error
  int setTrackInstrument(int trackId, String instrumentType) {
    try {
      final typePtr = instrumentType.toNativeUtf8();
      final instrumentId = _setTrackInstrument(trackId, typePtr.cast());
      malloc.free(typePtr);

      if (instrumentId < 0) {
        return -1;
      }

      return instrumentId;
    } catch (e) {
      rethrow;
    }
  }

  /// Set a synthesizer parameter for a track
  /// paramName: parameter name (e.g., 'osc1_type', 'filter_cutoff')
  /// value: parameter value (will be converted to string)
  String setSynthParameter(int trackId, String paramName, dynamic value) {
    try {
      final namePtr = paramName.toNativeUtf8();
      final valueStr = value.toString();
      final valuePtr = valueStr.toNativeUtf8();
      final resultPtr = _setSynthParameter(trackId, namePtr.cast(), valuePtr.cast());
      malloc.free(namePtr);
      malloc.free(valuePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all synthesizer parameters for a track
  /// Returns a comma-separated string of key:value pairs
  String getSynthParameters(int trackId) {
    try {
      final resultPtr = _getSynthParameters(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note on to a specific track's instrument
  /// trackId: the track to send MIDI to
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  String sendTrackMidiNoteOn(int trackId, int note, int velocity) {
    try {
      final resultPtr = _sendTrackMidiNoteOn(trackId, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Send MIDI note off to a specific track's instrument
  /// trackId: the track to send MIDI to
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  String sendTrackMidiNoteOff(int trackId, int note, int velocity) {
    try {
      final resultPtr = _sendTrackMidiNoteOff(trackId, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M7 API - VST3 Plugin Hosting
  // ========================================================================

  /// Scan standard VST3 plugin locations
  /// Returns list of plugin info: name, path, vendor, type
  List<Map<String, String>> scanVst3PluginsStandard() {
    try {
      final resultPtr = _scanVst3PluginsStandard();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty) {
        return [];
      }

      // Parse result: "PluginName|/path/to/plugin.vst3|Vendor|is_instrument|is_effect"
      final plugins = <Map<String, String>>[];
      for (final line in result.split('\n')) {
        if (line.isEmpty) continue;
        final parts = line.split('|');
        if (parts.length >= 5) {
          plugins.add({
            'name': parts[0],
            'path': parts[1],
            'vendor': parts[2],
            'is_instrument': parts[3],
            'is_effect': parts[4],
          });
        } else if (parts.length >= 2) {
          // Fallback for old format without type info
          plugins.add({
            'name': parts[0],
            'path': parts[1],
            'vendor': parts.length > 2 ? parts[2] : '',
            'is_instrument': '0',
            'is_effect': '1',
          });
        }
      }

      return plugins;
    } catch (e) {
      return [];
    }
  }

  /// Add a VST3 plugin to a track's FX chain
  /// Returns the effect ID (>= 0) or -1 on error
  int addVst3EffectToTrack(int trackId, String pluginPath) {
    try {
      final pathPtr = pluginPath.toNativeUtf8();
      final effectId = _addVst3EffectToTrack(trackId, pathPtr.cast());
      malloc.free(pathPtr);

      if (effectId < 0) {
        return -1;
      }

      return effectId;
    } catch (e) {
      return -1;
    }
  }

  /// Get the number of parameters in a VST3 plugin
  int getVst3ParameterCount(int effectId) {
    try {
      final count = _getVst3ParameterCount(effectId);
      if (count < 0) {
        return 0;
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  /// Get info about a VST3 parameter
  /// Returns map with keys: name, min, max, default
  Map<String, dynamic>? getVst3ParameterInfo(int effectId, int paramIndex) {
    try {
      final resultPtr = _getVst3ParameterInfo(effectId, paramIndex);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty) {
        return null;
      }

      // Parse result: "name,0.0,1.0,0.5"
      final parts = result.split(',');
      if (parts.length >= 4) {
        return {
          'name': parts[0],
          'min': double.tryParse(parts[1]) ?? 0.0,
          'max': double.tryParse(parts[2]) ?? 1.0,
          'default': double.tryParse(parts[3]) ?? 0.5,
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get a VST3 parameter value (normalized 0.0-1.0)
  double getVst3ParameterValue(int effectId, int paramIndex) {
    try {
      final value = _getVst3ParameterValue(effectId, paramIndex);
      return value;
    } catch (e) {
      return 0.0;
    }
  }

  /// Set a VST3 parameter value (normalized 0.0-1.0)
  bool setVst3ParameterValue(int effectId, int paramIndex, double value) {
    try {
      final resultPtr = _setVst3ParameterValue(effectId, paramIndex, value);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result.contains('Set VST3');
    } catch (e) {
      return false;
    }
  }

  // M7: VST3 Editor methods

  /// Check if a VST3 plugin has an editor GUI
  bool vst3HasEditor(int effectId) {
    try {
      return _vst3HasEditor(effectId);
    } catch (e) {
      return false;
    }
  }

  /// Open VST3 plugin editor (creates IPlugView)
  /// Returns error message or empty string on success
  String vst3OpenEditor(int effectId) {
    try {
      final resultPtr = _vst3OpenEditor(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to open editor: $e';
    }
  }

  /// Close VST3 plugin editor
  void vst3CloseEditor(int effectId) {
    try {
      _vst3CloseEditor(effectId);
    } catch (e) {
    }
  }

  /// Get VST3 editor size in pixels
  /// Returns map with 'width' and 'height' keys, or null on error
  Map<String, int>? vst3GetEditorSize(int effectId) {
    try {
      final resultPtr = _vst3GetEditorSize(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error')) {
        return null;
      }

      // Parse result: "width,height"
      final parts = result.split(',');
      if (parts.length == 2) {
        return {
          'width': int.tryParse(parts[0]) ?? 800,
          'height': int.tryParse(parts[1]) ?? 600,
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Attach VST3 editor to a parent window
  /// parentPtr: Pointer to NSView (on macOS)
  /// Returns error message or empty string on success
  String vst3AttachEditor(int effectId, ffi.Pointer<ffi.Void> parentPtr) {
    try {
      final resultPtr = _vst3AttachEditor(effectId, parentPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to attach editor: $e';
    }
  }

  /// Send a MIDI note event to a VST3 plugin
  /// eventType: 0 = note on, 1 = note off
  /// channel: MIDI channel (0-15)
  /// note: MIDI note number (0-127)
  /// velocity: MIDI velocity (0-127)
  /// Returns error message or empty string on success
  String vst3SendMidiNote(int effectId, int eventType, int channel, int note, int velocity) {
    try {
      final resultPtr = _vst3SendMidiNote(effectId, eventType, channel, note, velocity);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Failed to send MIDI note: $e';
    }
  }
}

// ==========================================================================
// Native function type definitions
// ==========================================================================

// M0 types
typedef _InitAudioEngineFfiNative = ffi.Pointer<Utf8> Function();
typedef _InitAudioEngineFfi = ffi.Pointer<Utf8> Function();

typedef _PlaySineWaveFfiNative = ffi.Pointer<Utf8> Function(
    ffi.Float frequency, ffi.Uint32 durationMs);
typedef _PlaySineWaveFfi = ffi.Pointer<Utf8> Function(
    double frequency, int durationMs);

typedef _FreeRustStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeRustString = void Function(ffi.Pointer<Utf8>);

// M1 types
typedef _InitAudioGraphFfiNative = ffi.Pointer<Utf8> Function();
typedef _InitAudioGraphFfi = ffi.Pointer<Utf8> Function();

typedef _LoadAudioFileFfiNative = ffi.Int64 Function(ffi.Pointer<ffi.Char>);
typedef _LoadAudioFileFfi = int Function(ffi.Pointer<ffi.Char>);

typedef _LoadAudioFileToTrackFfiNative = ffi.Int64 Function(ffi.Pointer<ffi.Char>, ffi.Uint64, ffi.Double);
typedef _LoadAudioFileToTrackFfi = int Function(ffi.Pointer<ffi.Char>, int, double);

typedef _TransportPlayFfiNative = ffi.Pointer<Utf8> Function();
typedef _TransportPlayFfi = ffi.Pointer<Utf8> Function();

typedef _TransportPauseFfiNative = ffi.Pointer<Utf8> Function();
typedef _TransportPauseFfi = ffi.Pointer<Utf8> Function();

typedef _TransportStopFfiNative = ffi.Pointer<Utf8> Function();
typedef _TransportStopFfi = ffi.Pointer<Utf8> Function();

typedef _TransportSeekFfiNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _TransportSeekFfi = ffi.Pointer<Utf8> Function(double);

typedef _GetPlayheadPositionFfiNative = ffi.Double Function();
typedef _GetPlayheadPositionFfi = double Function();

typedef _GetTransportStateFfiNative = ffi.Int32 Function();
typedef _GetTransportStateFfi = int Function();

// Latency Control types
typedef _SetBufferSizeFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetBufferSizeFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetBufferSizePresetFfiNative = ffi.Int32 Function();
typedef _GetBufferSizePresetFfi = int Function();

typedef _GetActualBufferSizeFfiNative = ffi.Uint32 Function();
typedef _GetActualBufferSizeFfi = int Function();

typedef _GetLatencyInfoFfiNative = ffi.Void Function(
    ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);
typedef _GetLatencyInfoFfi = void Function(
    ffi.Pointer<ffi.Uint32>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Float>);

typedef _GetClipDurationFfiNative = ffi.Double Function(ffi.Uint64);
typedef _GetClipDurationFfi = double Function(int);

typedef _SetClipStartTimeFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _SetClipStartTimeFfi = ffi.Pointer<Utf8> Function(int, int, double);

typedef _GetWaveformPeaksFfiNative = ffi.Pointer<ffi.Float> Function(
    ffi.Uint64, ffi.Size, ffi.Pointer<ffi.Size>);
typedef _GetWaveformPeaksFfi = ffi.Pointer<ffi.Float> Function(
    int, int, ffi.Pointer<ffi.Size>);

typedef _FreeWaveformPeaksFfiNative = ffi.Void Function(
    ffi.Pointer<ffi.Float>, ffi.Size);
typedef _FreeWaveformPeaksFfi = void Function(ffi.Pointer<ffi.Float>, int);

// M2 types - Recording & Input
typedef _StartRecordingFfiNative = ffi.Pointer<Utf8> Function();
typedef _StartRecordingFfi = ffi.Pointer<Utf8> Function();

typedef _StopRecordingFfiNative = ffi.Int64 Function();
typedef _StopRecordingFfi = int Function();

typedef _GetRecordingStateFfiNative = ffi.Int32 Function();
typedef _GetRecordingStateFfi = int Function();

typedef _GetRecordedDurationFfiNative = ffi.Double Function();
typedef _GetRecordedDurationFfi = double Function();

typedef _GetRecordingWaveformFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint32);
typedef _GetRecordingWaveformFfi = ffi.Pointer<Utf8> Function(int);

typedef _SetCountInBarsFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint32);
typedef _SetCountInBarsFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetCountInBarsFfiNative = ffi.Uint32 Function();
typedef _GetCountInBarsFfi = int Function();

typedef _SetTempoFfiNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _SetTempoFfi = ffi.Pointer<Utf8> Function(double);

typedef _GetTempoFfiNative = ffi.Double Function();
typedef _GetTempoFfi = double Function();

typedef _SetMetronomeEnabledFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetMetronomeEnabledFfi = ffi.Pointer<Utf8> Function(int);

typedef _IsMetronomeEnabledFfiNative = ffi.Int32 Function();
typedef _IsMetronomeEnabledFfi = int Function();

// M3 types - MIDI
typedef _StartMidiInputFfiNative = ffi.Pointer<Utf8> Function();
typedef _StartMidiInputFfi = ffi.Pointer<Utf8> Function();

typedef _StopMidiInputFfiNative = ffi.Pointer<Utf8> Function();
typedef _StopMidiInputFfi = ffi.Pointer<Utf8> Function();

typedef _SetSynthOscillatorTypeFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetSynthOscillatorTypeFfi = ffi.Pointer<Utf8> Function(int);

typedef _SetSynthVolumeFfiNative = ffi.Pointer<Utf8> Function(ffi.Float);
typedef _SetSynthVolumeFfi = ffi.Pointer<Utf8> Function(double);

typedef _SendMidiNoteOnFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint8, ffi.Uint8);
typedef _SendMidiNoteOnFfi = ffi.Pointer<Utf8> Function(int, int);

typedef _SendMidiNoteOffFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint8, ffi.Uint8);
typedef _SendMidiNoteOffFfi = ffi.Pointer<Utf8> Function(int, int);

// MIDI Clip Management
typedef _CreateMidiClipFfiNative = ffi.Int64 Function();
typedef _CreateMidiClipFfi = int Function();

typedef _AddMidiNoteToClipFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint8, ffi.Uint8, ffi.Double, ffi.Double);
typedef _AddMidiNoteToClipFfi = ffi.Pointer<Utf8> Function(int, int, int, double, double);

typedef _AddMidiClipToTrackFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _AddMidiClipToTrackFfi = int Function(int, int, double);

typedef _RemoveMidiClipFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Uint64);
typedef _RemoveMidiClipFfi = int Function(int, int);

typedef _ClearMidiClipFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _ClearMidiClipFfi = ffi.Pointer<Utf8> Function(int);

// M4 types - Tracks & Mixer
typedef _CreateTrackFfiNative = ffi.Int64 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _CreateTrackFfi = int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _SetTrackVolumeFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Float);
typedef _SetTrackVolumeFfi = ffi.Pointer<Utf8> Function(int, double);

typedef _SetTrackPanFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Float);
typedef _SetTrackPanFfi = ffi.Pointer<Utf8> Function(int, double);

typedef _SetTrackMuteFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackMuteFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackSoloFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackSoloFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackArmedFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackArmedFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackNameFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>);
typedef _SetTrackNameFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);

typedef _GetTrackCountFfiNative = ffi.Size Function();
typedef _GetTrackCountFfi = int Function();

typedef _GetAllTrackIdsFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetAllTrackIdsFfi = ffi.Pointer<Utf8> Function();

typedef _GetTrackInfoFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetTrackInfoFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetTrackPeakLevelsFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetTrackPeakLevelsFfi = ffi.Pointer<Utf8> Function(int);

typedef _DeleteTrackFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _DeleteTrackFfi = ffi.Pointer<Utf8> Function(int);

typedef _DuplicateTrackFfiNative = ffi.Int64 Function(ffi.Uint64);
typedef _DuplicateTrackFfi = int Function(int);

typedef _ClearAllTracksFfiNative = ffi.Pointer<Utf8> Function();
typedef _ClearAllTracksFfi = ffi.Pointer<Utf8> Function();

// M4 types - Effects
typedef _AddEffectToTrackFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Pointer<ffi.Char>);
typedef _AddEffectToTrackFfi = int Function(int, ffi.Pointer<ffi.Char>);

typedef _RemoveEffectFromTrackFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64);
typedef _RemoveEffectFromTrackFfi = ffi.Pointer<Utf8> Function(int, int);

typedef _GetTrackEffectsFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetTrackEffectsFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetEffectInfoFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetEffectInfoFfi = ffi.Pointer<Utf8> Function(int);

typedef _SetEffectParameterFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Float);
typedef _SetEffectParameterFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<ffi.Char>, double);

typedef _SetEffectBypassFfiNative = ffi.Int32 Function(ffi.Uint64, ffi.Int32);
typedef _SetEffectBypassFfi = int Function(int, int);

typedef _GetEffectBypassFfiNative = ffi.Int32 Function(ffi.Uint64);
typedef _GetEffectBypassFfi = int Function(int);

typedef _ReorderTrackEffectsFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<ffi.Char>);
typedef _ReorderTrackEffectsFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<ffi.Char>);

// M5 types - Save/Load Project
typedef _SaveProjectFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _SaveProjectFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _LoadProjectFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>);
typedef _LoadProjectFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>);

typedef _ExportToWavFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Bool);
typedef _ExportToWavFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, bool);

// M8 types - Enhanced Export
typedef _IsFfmpegAvailableFfiNative = ffi.Int32 Function();
typedef _IsFfmpegAvailableFfi = int Function();

typedef _ExportAudioFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _ExportAudioFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _ExportWavWithOptionsFfiNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, ffi.Int32, ffi.Uint32, ffi.Bool, ffi.Bool, ffi.Bool);
typedef _ExportWavWithOptionsFfi = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, int, int, bool, bool, bool);

typedef _ExportMp3WithOptionsFfiNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, ffi.Int32, ffi.Uint32, ffi.Bool, ffi.Bool);
typedef _ExportMp3WithOptionsFfi = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, int, int, bool, bool);

typedef _WriteMp3MetadataFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WriteMp3MetadataFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _GetTracksForStemsFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetTracksForStemsFfi = ffi.Pointer<Utf8> Function();

typedef _ExportStemsFfiNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _ExportStemsFfi = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

// M8 Export Progress types
typedef _GetExportProgressFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetExportProgressFfi = ffi.Pointer<Utf8> Function();

typedef _CancelExportFfiNative = ffi.Void Function();
typedef _CancelExportFfi = void Function();

typedef _ResetExportProgressFfiNative = ffi.Void Function();
typedef _ResetExportProgressFfi = void Function();

// M6 types - Per-track Synthesizer
typedef _SetTrackInstrumentFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Pointer<ffi.Char>);
typedef _SetTrackInstrumentFfi = int Function(int, ffi.Pointer<ffi.Char>);

typedef _SetSynthParameterFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _SetSynthParameterFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _GetSynthParametersFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetSynthParametersFfi = ffi.Pointer<Utf8> Function(int);

typedef _SendTrackMidiNoteOnFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint8, ffi.Uint8);
typedef _SendTrackMidiNoteOnFfi = ffi.Pointer<Utf8> Function(int, int, int);

typedef _SendTrackMidiNoteOffFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint8, ffi.Uint8);
typedef _SendTrackMidiNoteOffFfi = ffi.Pointer<Utf8> Function(int, int, int);

// M7 types - VST3 Plugin Hosting
typedef _ScanVst3PluginsStandardFfiNative = ffi.Pointer<Utf8> Function();
typedef _ScanVst3PluginsStandardFfi = ffi.Pointer<Utf8> Function();

typedef _AddVst3EffectToTrackFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Pointer<ffi.Char>);
typedef _AddVst3EffectToTrackFfi = int Function(int, ffi.Pointer<ffi.Char>);

typedef _GetVst3ParameterCountFfiNative = ffi.Int32 Function(ffi.Uint64);
typedef _GetVst3ParameterCountFfi = int Function(int);

typedef _GetVst3ParameterInfoFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint32);
typedef _GetVst3ParameterInfoFfi = ffi.Pointer<Utf8> Function(int, int);

typedef _GetVst3ParameterValueFfiNative = ffi.Double Function(ffi.Uint64, ffi.Uint32);
typedef _GetVst3ParameterValueFfi = double Function(int, int);

typedef _SetVst3ParameterValueFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint32, ffi.Double);
typedef _SetVst3ParameterValueFfi = ffi.Pointer<Utf8> Function(int, int, double);

// M7 VST3 Editor function typedefs
typedef _Vst3HasEditorFfiNative = ffi.Bool Function(ffi.Uint64);
typedef _Vst3HasEditorFfi = bool Function(int);

typedef _Vst3OpenEditorFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _Vst3OpenEditorFfi = ffi.Pointer<Utf8> Function(int);

typedef _Vst3CloseEditorFfiNative = ffi.Void Function(ffi.Uint64);
typedef _Vst3CloseEditorFfi = void Function(int);

typedef _Vst3GetEditorSizeFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _Vst3GetEditorSizeFfi = ffi.Pointer<Utf8> Function(int);

typedef _Vst3AttachEditorFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<ffi.Void>);
typedef _Vst3AttachEditorFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<ffi.Void>);

typedef _Vst3SendMidiNoteFfiNative = ffi.Pointer<Utf8> Function(ffi.Int64, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _Vst3SendMidiNoteFfi = ffi.Pointer<Utf8> Function(int, int, int, int, int);

// MIDI Recording types
typedef _GetMidiInputDevicesFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetMidiInputDevicesFfi = ffi.Pointer<Utf8> Function();

typedef _SelectMidiInputDeviceFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SelectMidiInputDeviceFfi = ffi.Pointer<Utf8> Function(int);

typedef _RefreshMidiDevicesFfiNative = ffi.Pointer<Utf8> Function();
typedef _RefreshMidiDevicesFfi = ffi.Pointer<Utf8> Function();

typedef _StartMidiRecordingFfiNative = ffi.Pointer<Utf8> Function();
typedef _StartMidiRecordingFfi = ffi.Pointer<Utf8> Function();

typedef _StopMidiRecordingFfiNative = ffi.Int64 Function();
typedef _StopMidiRecordingFfi = int Function();

typedef _GetMidiRecordingStateFfiNative = ffi.Int32 Function();
typedef _GetMidiRecordingStateFfi = int Function();

typedef _QuantizeMidiClipFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint32);
typedef _QuantizeMidiClipFfi = ffi.Pointer<Utf8> Function(int, int);

typedef _GetMidiClipInfoFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetMidiClipInfoFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetAllMidiClipsInfoFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetAllMidiClipsInfoFfi = ffi.Pointer<Utf8> Function();

typedef _GetMidiClipNotesFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetMidiClipNotesFfi = ffi.Pointer<Utf8> Function(int);

// Audio Device types
typedef _GetAudioInputDevicesFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetAudioInputDevicesFfi = ffi.Pointer<Utf8> Function();

typedef _GetAudioOutputDevicesFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetAudioOutputDevicesFfi = ffi.Pointer<Utf8> Function();

typedef _SetAudioInputDeviceFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetAudioInputDeviceFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetSampleRateFfiNative = ffi.Uint32 Function();
typedef _GetSampleRateFfi = int Function();
