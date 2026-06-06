import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../utils/logger.dart';
import 'project_persistence.dart';

/// Result of a project operation
class ProjectResult {
  final bool success;
  final String message;
  final String? path;

  const ProjectResult({
    required this.success,
    required this.message,
    this.path,
  });
}

/// Manages project state and file operations.
///
/// Extracted from daw_screen.dart to improve maintainability.
class ProjectManager extends ChangeNotifier {
  final AudioEngine _audioEngine;

  // Project state
  String? _currentProjectPath;
  String _currentProjectName = 'Untitled';
  bool _isLoading = false;

  ProjectManager(this._audioEngine);

  // Getters
  String? get currentPath => _currentProjectPath;
  String get currentName => _currentProjectName;
  bool get isLoading => _isLoading;
  bool get hasProject => _currentProjectPath != null;

  /// Reset project state for a new project
  void newProject() {
    _currentProjectPath = null;
    _currentProjectName = 'Untitled';
    notifyListeners();
  }

  /// Load a project from the given path
  ///
  /// Returns a ProjectResult with success status and message.
  /// Also returns the UI layout data if available.
  Future<({ProjectResult result, UILayoutData? uiLayout})> loadProject(
    String path,
  ) async {
    if (!path.endsWith('.audio')) {
      return (
        result: const ProjectResult(
          success: false,
          message: 'Please select a .audio folder',
        ),
        uiLayout: null,
      );
    }

    _isLoading = true;
    notifyListeners();

    try {
      final loadResult = _audioEngine.loadProject(path);

      // The engine returns an "Error: …" string on failure rather than
      // throwing. Treating that as success silently overwrites the project
      // path (so a later auto-save clobbers the bad file) and defeats the
      // crash-recovery gate. Bail out before touching any project state.
      if (loadResult.startsWith('Error:')) {
        _isLoading = false;
        notifyListeners();
        return (
          result: ProjectResult(success: false, message: loadResult),
          uiLayout: null,
        );
      }

      // Load UI layout data
      final uiLayout = _loadUILayout(path);

      _currentProjectPath = path;
      _currentProjectName = path.split('/').last.replaceAll('.audio', '');
      _isLoading = false;
      notifyListeners();

      return (
        result: ProjectResult(success: true, message: loadResult, path: path),
        uiLayout: uiLayout,
      );
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return (
        result: ProjectResult(
          success: false,
          message: 'Failed to load project: $e',
        ),
        uiLayout: null,
      );
    }
  }

  /// Save the current project to its existing path
  ///
  /// Returns null if there's no current path (should call saveProjectAs instead).
  Future<ProjectResult?> saveProject(UILayoutData? uiLayout) async {
    if (_currentProjectPath == null) {
      return null; // Caller should use saveProjectAs
    }
    return saveProjectToPath(_currentProjectPath!, uiLayout);
  }

  /// Save the project to a specific path
  ///
  /// Set [updateCurrentPath] to false for saves that must not repoint the
  /// project at the written file (auto-save backups, copies) — otherwise
  /// every later save would silently target the backup/copy instead of the
  /// real project.
  Future<ProjectResult> saveProjectToPath(
    String path,
    UILayoutData? uiLayout, {
    bool updateCurrentPath = true,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = _audioEngine.saveProject(_currentProjectName, path);

      // The engine returns an "Error: …" string on failure rather than
      // throwing. Treating that as success would repoint the project (and
      // auto-save) at a corrupt path while the UI shows "saved". Mirror the
      // load-path guard: bail out before touching any project state.
      if (result.startsWith('Error:')) {
        _isLoading = false;
        notifyListeners();
        return ProjectResult(success: false, message: result);
      }

      // Save UI layout data if provided
      if (uiLayout != null) {
        _saveUILayout(path, uiLayout);
      }

      if (updateCurrentPath) {
        _currentProjectPath = path;
      }
      _isLoading = false;
      notifyListeners();

      return ProjectResult(success: true, message: result, path: path);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return ProjectResult(
        success: false,
        message: 'Failed to save project: $e',
      );
    }
  }

  /// Save project as a new copy
  Future<ProjectResult> saveProjectAsCopy(
    String name,
    String parentPath,
    UILayoutData? uiLayout,
  ) async {
    final projectPath = '$parentPath/$name.audio';

    // Temporarily change the name for saving
    final originalName = _currentProjectName;
    _currentProjectName = name;

    // A copy must not become the current project — keep saves targeting the
    // original path.
    final result = await saveProjectToPath(
      projectPath,
      uiLayout,
      updateCurrentPath: false,
    );

    // Restore original name (copy doesn't change current project)
    _currentProjectName = originalName;

    return result;
  }

  /// Make a copy of the current project
  Future<ProjectResult> makeCopy(
    String copyName,
    String parentPath,
    UILayoutData? uiLayout,
  ) async {
    if (_currentProjectPath == null) {
      return const ProjectResult(success: false, message: 'No project to copy');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final copyPath = '$parentPath/$copyName.audio';
      _audioEngine.saveProject(copyName, copyPath);

      // Save UI layout data for the copy
      if (uiLayout != null) {
        _saveUILayout(copyPath, uiLayout);
      }

      _isLoading = false;
      notifyListeners();

      return ProjectResult(
        success: true,
        message: 'Copy created: $copyName',
        path: copyPath,
      );
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return ProjectResult(
        success: false,
        message: 'Failed to create copy: $e',
      );
    }
  }

  /// Export project to WAV file
  Future<ProjectResult> exportToWav(String path) async {
    try {
      final exportResult = _audioEngine.exportToWav(path, normalize: true);
      return ProjectResult(success: true, message: exportResult, path: path);
    } catch (e) {
      return ProjectResult(success: false, message: 'Export failed: $e');
    }
  }

  /// Close the current project
  void closeProject() {
    _currentProjectPath = null;
    _currentProjectName = 'Untitled';
    notifyListeners();
  }

  /// Update project name (for Save As)
  void setProjectName(String name) {
    _currentProjectName = name;
    notifyListeners();
  }

  /// Save UI layout to JSON file
  void _saveUILayout(String projectPath, UILayoutData uiLayout) {
    try {
      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(uiLayout.toJson());
      final uiLayoutFile = File('$projectPath/ui_layout.json');
      uiLayoutFile.writeAsStringSync(jsonString);
    } catch (e) {
      Log.e('ProjectManager: Error saving UI layout: $e');
    }
  }

  /// Load UI layout from JSON file
  UILayoutData? _loadUILayout(String projectPath) {
    try {
      final uiLayoutFile = File('$projectPath/ui_layout.json');
      if (!uiLayoutFile.existsSync()) {
        return null;
      }

      final jsonString = uiLayoutFile.readAsStringSync();
      final Map<String, dynamic> data = jsonDecode(jsonString);
      return UILayoutData.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Clear all state
  void clear() {
    _currentProjectPath = null;
    _currentProjectName = 'Untitled';
    _isLoading = false;
    notifyListeners();
  }
}
