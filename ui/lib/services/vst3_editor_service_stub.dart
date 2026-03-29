// Stub implementation of VST3EditorService for web platform.
// VST3 plugins are not supported on web, so all methods are no-ops.

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

  static Future<bool> closeFloatingWindow({required int effectId}) async {
    return false; // Not supported on web
  }

  static Future<bool> attachEditor({required int effectId}) async {
    return false; // Not supported on web
  }

  static Future<bool> detachEditor({required int effectId}) async {
    return false; // Not supported on web
  }

  static void closeEditorOnDispose(int effectId) {
    // No-op on web
  }

  static void cleanupViewOnDispose(int effectId) {
    // No-op on web
  }

  static void hideFloatingWindow(int effectId) {}
  static void showFloatingWindow(int effectId) {}

  static void hideAllEditors() {
    // No-op on web
  }

  static void showAllEditors() {
    // No-op on web
  }

  static Future<String?> showNativeContextMenu({
    required List<Map<String, dynamic>> items,
    required double x,
    required double y,
  }) async {
    return null;
  }

  static Future<int?> showNativeAlert({
    required String title,
    required String message,
    required List<Map<String, dynamic>> buttons,
  }) async {
    return null;
  }

  static void setEmbeddedMaxSize(int effectId, int maxW, int maxH) {
    // No-op on web
  }

  static final Map<int, (int, int)> preferredEditorSize = {};
}
