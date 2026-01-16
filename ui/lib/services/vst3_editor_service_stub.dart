/// Stub implementation of VST3EditorService for web platform.
/// VST3 plugins are not supported on web, so all methods are no-ops.

import '../audio_engine.dart';

class VST3EditorService {
  static void initialize(AudioEngine engine) {
    // No-op on web - VST3 not supported
  }

  static Future<bool> openFloatingWindow({
    required int effectId,
    required String pluginName,
    required double width,
    required double height,
  }) async {
    return false; // Not supported on web
  }

  static Future<bool> closeFloatingWindow({
    required int effectId,
  }) async {
    return false; // Not supported on web
  }

  static Future<bool> attachEditor({
    required int effectId,
  }) async {
    return false; // Not supported on web
  }

  static Future<bool> detachEditor({
    required int effectId,
  }) async {
    return false; // Not supported on web
  }
}
