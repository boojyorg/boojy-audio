import 'dart:io';

import 'package:boojy_audio/audio_engine.dart';
import 'package:flutter/foundation.dart';

/// Whether the native Rust engine dylib is available on this host.
///
/// Integration tests skip when the library is missing (CI without a build,
/// web/stub targets, or stale paths).
bool get isNativeEngineAvailable {
  if (kIsWeb) return false;
  return findEngineLibraryPath() != null;
}

/// Search paths aligned with [AudioEngine] dylib discovery in
/// `audio_engine_base.dart`.
String? findEngineLibraryPath() {
  if (kIsWeb) return null;

  final pathsToTry = <String>[];

  if (Platform.isMacOS) {
    var searchDir = Directory.current;
    for (var i = 0; i < 6; i++) {
      pathsToTry.add('${searchDir.path}/macos/Runner/libengine.dylib');
      pathsToTry.add('${searchDir.path}/engine/target/debug/libengine.dylib');
      pathsToTry.add('${searchDir.path}/engine/target/release/libengine.dylib');
      final parent = searchDir.parent;
      if (parent.path == searchDir.path) break;
      searchDir = parent;
    }
  } else if (Platform.isWindows) {
    pathsToTry.add('engine.dll');
  } else if (Platform.isLinux) {
    pathsToTry.add('libengine.so');
  } else {
    return null;
  }

  for (final path in pathsToTry) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// Create and initialize the native [AudioEngine] for integration tests.
///
/// The Rust engine is a process-wide singleton; subsequent calls return the
/// same instance without re-running [AudioEngine.initAudioGraph].
Future<AudioEngine> createInitializedEngine() async {
  if (!isNativeEngineAvailable) {
    throw StateError('Native engine library not found');
  }

  if (_initializedEngine != null) {
    return _initializedEngine!;
  }

  final engine = AudioEngine();

  final initResult = engine.initAudioEngine();
  if (initResult.startsWith('Error')) {
    throw StateError('initAudioEngine failed: $initResult');
  }

  final graphResult = engine.initAudioGraph();
  if (graphResult.startsWith('Error')) {
    throw StateError('initAudioGraph failed: $graphResult');
  }

  engine.setTempo(120.0);
  _initializedEngine = engine;
  return engine;
}

AudioEngine? _initializedEngine;

/// Temporary `.audio` project folder under the system temp directory.
Directory createTempProjectDir({String prefix = 'boojy_integration_'}) {
  return Directory(
    '${Directory.systemTemp.path}/$prefix${DateTime.now().millisecondsSinceEpoch}.audio',
  )..createSync(recursive: true);
}

void deleteTempProjectDir(Directory dir) {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

/// Parse `clip_id,track_id,start_time,duration,note_count` entries from the engine.
List<Map<String, dynamic>> parseMidiClipsInfo(String raw) {
  if (raw.isEmpty || raw.startsWith('Error:')) return [];

  return raw.split(';').where((entry) => entry.isNotEmpty).map((entry) {
    final parts = entry.split(',');
    return {
      'clipId': int.parse(parts[0]),
      'trackId': int.parse(parts[1]),
      'startTime': double.parse(parts[2]),
      'duration': double.parse(parts[3]),
      'noteCount': int.parse(parts[4]),
    };
  }).toList();
}
