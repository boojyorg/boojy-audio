import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/project_view_state.dart';

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

/// UI layout data for saving/loading
class UILayoutData {
  final double libraryWidth;
  final double mixerWidth;
  final double bottomHeight;
  final bool libraryCollapsed;
  final bool mixerCollapsed;
  final bool bottomCollapsed;
  final ProjectViewState? viewState;

  const UILayoutData({
    this.libraryWidth = 200.0,
    this.mixerWidth = 380.0,
    this.bottomHeight = 250.0,
    this.libraryCollapsed = false,
    this.mixerCollapsed = false,
    this.bottomCollapsed = true,
    this.viewState,
  });

  Map<String, dynamic> toJson() => {
    'version': '1.0',
    'panel_sizes': {
      'library_width': libraryWidth,
      'mixer_width': mixerWidth,
      'bottom_height': bottomHeight,
    },
    'panel_collapsed': {
      'library': libraryCollapsed,
      'mixer': mixerCollapsed,
      'bottom': bottomCollapsed,
    },
    if (viewState != null) 'view_state': viewState!.toJson(),
  };

  factory UILayoutData.fromJson(Map<String, dynamic> json) {
    final panelSizes = json['panel_sizes'] as Map<String, dynamic>? ?? {};
    final panelCollapsed = json['panel_collapsed'] as Map<String, dynamic>? ?? {};
    final viewStateJson = json['view_state'] as Map<String, dynamic>?;

    return UILayoutData(
      libraryWidth: (panelSizes['library_width'] as num?)?.toDouble() ?? 200.0,
      mixerWidth: (panelSizes['mixer_width'] as num?)?.toDouble() ?? 380.0,
      bottomHeight: (panelSizes['bottom_height'] as num?)?.toDouble() ?? 250.0,
      libraryCollapsed: panelCollapsed['library'] as bool? ?? false,
      mixerCollapsed: panelCollapsed['mixer'] as bool? ?? false,
      bottomCollapsed: panelCollapsed['bottom'] as bool? ?? true,
      viewState: viewStateJson != null ? ProjectViewState.fromJson(viewStateJson) : null,
    );
  }
}

/// Manages project state and file operations.
///
/// Extracted from daw_screen.dart to improve maintainability.
class ProjectManager extends ChangeNotifier {
  final AudioEngine _audioEngine;

  // Project state
  String? _currentProjectPath;
  String _currentProjectName = 'Untitled Project';
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
    _currentProjectName = 'Untitled Project';
    notifyListeners();
  }

  /// Load a project from the given path
  ///
  /// Returns a ProjectResult with success status and message.
  /// Also returns the UI layout data if available.
  Future<({ProjectResult result, UILayoutData? uiLayout})> loadProject(String path) async {
    if (!path.endsWith('.audio')) {
      return (
        result: ProjectResult(
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

      // Load UI layout data
      final uiLayout = _loadUILayout(path);

      _currentProjectPath = path;
      _currentProjectName = path.split('/').last.replaceAll('.audio', '');
      _isLoading = false;
      notifyListeners();

      return (
        result: ProjectResult(
          success: true,
          message: loadResult,
          path: path,
        ),
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
  Future<ProjectResult> saveProjectToPath(String path, UILayoutData? uiLayout) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = _audioEngine.saveProject(_currentProjectName, path);

      // Save UI layout data if provided
      if (uiLayout != null) {
        _saveUILayout(path, uiLayout);
      }

      _currentProjectPath = path;
      _isLoading = false;
      notifyListeners();

      return ProjectResult(
        success: true,
        message: result,
        path: path,
      );
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
  Future<ProjectResult> saveProjectAsCopy(String name, String parentPath, UILayoutData? uiLayout) async {
    final projectPath = '$parentPath/$name.audio';

    // Temporarily change the name for saving
    final originalName = _currentProjectName;
    _currentProjectName = name;

    final result = await saveProjectToPath(projectPath, uiLayout);

    // Restore original name (copy doesn't change current project)
    _currentProjectName = originalName;

    return result;
  }

  /// Make a copy of the current project
  Future<ProjectResult> makeCopy(String copyName, String parentPath, UILayoutData? uiLayout) async {
    if (_currentProjectPath == null) {
      return const ProjectResult(
        success: false,
        message: 'No project to copy',
      );
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
      final exportResult = _audioEngine.exportToWav(path, true);
      return ProjectResult(
        success: true,
        message: exportResult,
        path: path,
      );
    } catch (e) {
      return ProjectResult(
        success: false,
        message: 'Export failed: $e',
      );
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
      final jsonString = const JsonEncoder.withIndent('  ').convert(uiLayout.toJson());
      final uiLayoutFile = File('$projectPath/ui_layout.json');
      uiLayoutFile.writeAsStringSync(jsonString);
    } catch (e) {
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
    _currentProjectName = 'Untitled Project';
    _isLoading = false;
    notifyListeners();
  }
}
