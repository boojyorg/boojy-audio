part of 'audio_engine_native.dart';

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

typedef _GetPlayStartPositionFfiNative = ffi.Double Function();
typedef _GetPlayStartPositionFfi = double Function();

typedef _SetPlayStartPositionFfiNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _SetPlayStartPositionFfi = ffi.Pointer<Utf8> Function(double);

typedef _GetRecordStartPositionFfiNative = ffi.Double Function();
typedef _GetRecordStartPositionFfi = double Function();

typedef _SetRecordStartPositionFfiNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _SetRecordStartPositionFfi = ffi.Pointer<Utf8> Function(double);

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

// Latency Test types
typedef _StartLatencyTestFfiNative = ffi.Pointer<Utf8> Function();
typedef _StartLatencyTestFfi = ffi.Pointer<Utf8> Function();

typedef _StopLatencyTestFfiNative = ffi.Pointer<Utf8> Function();
typedef _StopLatencyTestFfi = ffi.Pointer<Utf8> Function();

typedef _GetLatencyTestStatusFfiNative = ffi.Void Function(
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Float>);
typedef _GetLatencyTestStatusFfi = void Function(
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Float>);

typedef _GetLatencyTestErrorFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetLatencyTestErrorFfi = ffi.Pointer<Utf8> Function();

typedef _GetClipDurationFfiNative = ffi.Double Function(ffi.Uint64);
typedef _GetClipDurationFfi = double Function(int);

typedef _SetClipStartTimeFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _SetClipStartTimeFfi = ffi.Pointer<Utf8> Function(int, int, double);

typedef _SetClipOffsetFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _SetClipOffsetFfi = ffi.Pointer<Utf8> Function(int, int, double);

typedef _SetClipDurationFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _SetClipDurationFfi = ffi.Pointer<Utf8> Function(int, int, double);

typedef _SetAudioClipGainFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Float);
typedef _SetAudioClipGainFfi = ffi.Pointer<Utf8> Function(int, int, double);

typedef _SetAudioClipWarpFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Bool, ffi.Float, ffi.Int32);
typedef _SetAudioClipWarpFfi = ffi.Pointer<Utf8> Function(int, int, bool, double, int);

typedef _SetAudioClipTransposeFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Uint64, ffi.Int32, ffi.Int32);
typedef _SetAudioClipTransposeFfi = ffi.Pointer<Utf8> Function(int, int, int, int);

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

typedef _GetCountInBeatFfiNative = ffi.Uint32 Function();
typedef _GetCountInBeatFfi = int Function();

typedef _GetCountInProgressFfiNative = ffi.Float Function();
typedef _GetCountInProgressFfi = double Function();

typedef _SetTempoFfiNative = ffi.Pointer<Utf8> Function(ffi.Double);
typedef _SetTempoFfi = ffi.Pointer<Utf8> Function(double);

typedef _GetTempoFfiNative = ffi.Double Function();
typedef _GetTempoFfi = double Function();

typedef _SetMetronomeEnabledFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetMetronomeEnabledFfi = ffi.Pointer<Utf8> Function(int);

typedef _IsMetronomeEnabledFfiNative = ffi.Int32 Function();
typedef _IsMetronomeEnabledFfi = int Function();

typedef _SetTimeSignatureFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint32);
typedef _SetTimeSignatureFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetTimeSignatureFfiNative = ffi.Uint32 Function();
typedef _GetTimeSignatureFfi = int Function();

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

typedef _SetTrackVolumeAutomationFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<Utf8>);
typedef _SetTrackVolumeAutomationFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>);

typedef _SetTrackPanFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Float);
typedef _SetTrackPanFfi = ffi.Pointer<Utf8> Function(int, double);

typedef _SetTrackMuteFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackMuteFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackSoloFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackSoloFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackArmedFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackArmedFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _SetTrackInputFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Int32, ffi.Uint32);
typedef _SetTrackInputFfi = ffi.Pointer<Utf8> Function(int, int, int);

typedef _GetTrackInputFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64);
typedef _GetTrackInputFfi = ffi.Pointer<Utf8> Function(int);

typedef _SetTrackInputMonitoringFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Bool);
typedef _SetTrackInputMonitoringFfi = ffi.Pointer<Utf8> Function(int, bool);

typedef _GetInputChannelLevelFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint32);
typedef _GetInputChannelLevelFfi = ffi.Pointer<Utf8> Function(int);

typedef _GetInputChannelCountFfiNative = ffi.Uint32 Function();
typedef _GetInputChannelCountFfi = int Function();

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

typedef _DuplicateAudioClipFfiNative = ffi.Int64 Function(ffi.Uint64, ffi.Uint64, ffi.Double);
typedef _DuplicateAudioClipFfi = int Function(int, int, double);

typedef _RemoveAudioClipFfiNative = ffi.Int32 Function(ffi.Uint64, ffi.Uint64);
typedef _RemoveAudioClipFfi = int Function(int, int);

typedef _AddExistingClipToTrackFfiNative = ffi.Int64 Function(
    ffi.Uint64, ffi.Uint64, ffi.Double, ffi.Double, ffi.Int32, ffi.Double);
typedef _AddExistingClipToTrackFfi = int Function(
    int, int, double, double, int, double);

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

// Sampler types
typedef _CreateSamplerForTrackFfiNative = ffi.Int64 Function(ffi.Uint64);
typedef _CreateSamplerForTrackFfi = int Function(int);

typedef _LoadSampleForTrackFfiNative = ffi.Int32 Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Uint8);
typedef _LoadSampleForTrackFfi = int Function(int, ffi.Pointer<ffi.Char>, int);

typedef _SetSamplerParameterFfiNative = ffi.Pointer<Utf8> Function(ffi.Uint64, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _SetSamplerParameterFfi = ffi.Pointer<Utf8> Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

typedef _IsSamplerTrackFfiNative = ffi.Int32 Function(ffi.Uint64);
typedef _IsSamplerTrackFfi = int Function(int);

typedef _GetSamplerInfoFfiNative = ffi.Int32 Function(
    ffi.Uint64, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);
typedef _GetSamplerInfoFfi = int Function(
    int, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Double>, ffi.Pointer<ffi.Int32>,
    ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>);

typedef _GetSamplerWaveformPeaksFfiNative = ffi.Pointer<ffi.Float> Function(
    ffi.Uint64, ffi.Size, ffi.Pointer<ffi.Size>);
typedef _GetSamplerWaveformPeaksFfi = ffi.Pointer<ffi.Float> Function(
    int, int, ffi.Pointer<ffi.Size>);

typedef _FreeSamplerWaveformPeaksFfiNative = ffi.Void Function(
    ffi.Pointer<ffi.Float>, ffi.Size);
typedef _FreeSamplerWaveformPeaksFfi = void Function(
    ffi.Pointer<ffi.Float>, int);

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

typedef _GetMidiRecorderLiveEventsFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetMidiRecorderLiveEventsFfi = ffi.Pointer<Utf8> Function();

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

typedef _SetAudioOutputDeviceFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _SetAudioOutputDeviceFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _GetSelectedAudioOutputDeviceFfiNative = ffi.Pointer<Utf8> Function();
typedef _GetSelectedAudioOutputDeviceFfi = ffi.Pointer<Utf8> Function();

typedef _GetSampleRateFfiNative = ffi.Uint32 Function();
typedef _GetSampleRateFfi = int Function();

// Library Preview types
typedef _PreviewLoadAudioFfiNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>);
typedef _PreviewLoadAudioFfi = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Char>);

typedef _PreviewPlayFfiNative = ffi.Void Function();
typedef _PreviewPlayFfi = void Function();

typedef _PreviewStopFfiNative = ffi.Void Function();
typedef _PreviewStopFfi = void Function();

typedef _PreviewSeekFfiNative = ffi.Void Function(ffi.Double);
typedef _PreviewSeekFfi = void Function(double);

typedef _PreviewGetPositionFfiNative = ffi.Double Function();
typedef _PreviewGetPositionFfi = double Function();

typedef _PreviewGetDurationFfiNative = ffi.Double Function();
typedef _PreviewGetDurationFfi = double Function();

typedef _PreviewIsPlayingFfiNative = ffi.Bool Function();
typedef _PreviewIsPlayingFfi = bool Function();

typedef _PreviewSetLoopingFfiNative = ffi.Void Function(ffi.Bool);
typedef _PreviewSetLoopingFfi = void Function(bool);

typedef _PreviewIsLoopingFfiNative = ffi.Bool Function();
typedef _PreviewIsLoopingFfi = bool Function();

typedef _PreviewGetWaveformFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _PreviewGetWaveformFfi = ffi.Pointer<Utf8> Function(int);

// Punch Recording types
typedef _SetPunchInEnabledFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetPunchInEnabledFfi = ffi.Pointer<Utf8> Function(int);

typedef _IsPunchInEnabledFfiNative = ffi.Int32 Function();
typedef _IsPunchInEnabledFfi = int Function();

typedef _SetPunchOutEnabledFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32);
typedef _SetPunchOutEnabledFfi = ffi.Pointer<Utf8> Function(int);

typedef _IsPunchOutEnabledFfiNative = ffi.Int32 Function();
typedef _IsPunchOutEnabledFfi = int Function();

typedef _SetPunchRegionFfiNative = ffi.Pointer<Utf8> Function(ffi.Double, ffi.Double);
typedef _SetPunchRegionFfi = ffi.Pointer<Utf8> Function(double, double);

typedef _GetPunchInSecondsFfiNative = ffi.Double Function();
typedef _GetPunchInSecondsFfi = double Function();

typedef _GetPunchOutSecondsFfiNative = ffi.Double Function();
typedef _GetPunchOutSecondsFfi = double Function();

typedef _IsPunchCompleteFfiNative = ffi.Int32 Function();
typedef _IsPunchCompleteFfi = int Function();
