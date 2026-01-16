import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart';

/// Service for managing the application window title.
/// Shows project name in format: "Project Name - Boojy Audio"
class WindowTitleService {
  static const String _appName = 'Boojy Audio';
  static const String _defaultProjectName = 'Untitled';
  static String _currentProjectName = _defaultProjectName;
  static bool _hasUnsavedChanges = false;
  static bool _initialized = false;

  /// Initialize the window manager (call once at app startup)
  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    await windowManager.ensureInitialized();
    _initialized = true;

    // Set dark title bar on macOS
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );

    await _updateTitle();
  }

  /// Set the current project name and update the window title
  static Future<void> setProjectName(String projectName) async {
    _currentProjectName = projectName;
    await _updateTitle();
  }

  /// Set whether there are unsaved changes (shows * indicator)
  static Future<void> setUnsavedChanges({required bool hasUnsavedChanges}) async {
    _hasUnsavedChanges = hasUnsavedChanges;
    await _updateTitle();
  }

  /// Clear project name (when closing/creating new project)
  static Future<void> clearProjectName() async {
    _currentProjectName = _defaultProjectName;
    _hasUnsavedChanges = false;
    await _updateTitle();
  }

  /// Update the window title based on current state
  static Future<void> _updateTitle() async {
    if (kIsWeb || !_initialized) return;

    final unsavedIndicator = _hasUnsavedChanges ? '*' : '';
    final title = '$_currentProjectName$unsavedIndicator - $_appName';

    await windowManager.setTitle(title);
  }
}
