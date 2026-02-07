// FFI function signatures require positional bool parameters
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'services/commands/audio_engine_interface.dart';

part 'audio_engine_base.dart';
part 'audio_engine_transport.dart';
part 'audio_engine_recording.dart';
part 'audio_engine_tracks.dart';
part 'audio_engine_plugins.dart';
part 'audio_engine_typedefs.dart';

/// FFI bindings for the Rust audio engine
class AudioEngine extends _AudioEngineBase
    with _TransportMixin, _RecordingMixin, _TracksMixin, _PluginsMixin
    implements AudioEngineInterface {
  AudioEngine() : super();

  /// Buffer size presets for latency control
  static const Map<int, String> bufferSizePresets = {
    0: 'Lowest (64 samples, ~1.3ms)',
    1: 'Low (128 samples, ~2.7ms)',
    2: 'Balanced (256 samples, ~5.3ms)',
    3: 'Safe (512 samples, ~10.7ms)',
    4: 'High Stability (1024 samples, ~21.3ms)',
  };
}
