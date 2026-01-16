// Web Project Manager - IndexedDB-based project management for Boojy Audio Web
//
// This implementation uses IndexedDB for persistent storage instead of the
// native file system.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/project_view_state.dart';
import 'web_storage_service.dart';

/// Result of a project operation
class ProjectResult {
  final bool success;
  final String message;
  final String? path; // On web, this is the project ID

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

/// Web-based project manager using IndexedDB storage
class ProjectManager extends ChangeNotifier {
  final AudioEngine _audioEngine;
  final WebStorageService _storage = WebStorageService.instance;

  // Project state
  String? _currentProjectId;
  String _currentProjectName = 'Untitled Project';
  bool _isLoading = false;
  bool _isInitialized = false;

  // Cached list of all projects
  List<WebProject> _allProjects = [];

  ProjectManager(this._audioEngine);

  // Getters
  String? get currentPath => _currentProjectId; // For API compatibility
  String? get currentProjectId => _currentProjectId;
  String get currentName => _currentProjectName;
  bool get isLoading => _isLoading;
  bool get hasProject => _currentProjectId != null;
  List<WebProject> get allProjects => List.unmodifiable(_allProjects);
  bool get isInitialized => _isInitialized;

  /// Initialize the storage service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _storage.initialize();
      await _refreshProjectList();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('ProjectManager: Failed to initialize storage: $e');
    }
  }

  /// Refresh the cached list of all projects
  Future<void> _refreshProjectList() async {
    try {
      _allProjects = await _storage.getAllProjects();
      notifyListeners();
    } catch (e) {
      debugPrint('ProjectManager: Failed to refresh project list: $e');
    }
  }

  /// Reset project state for a new project
  void newProject() {
    _currentProjectId = null;
    _currentProjectName = 'Untitled Project';
    notifyListeners();
  }

  /// Load a project from IndexedDB by ID
  Future<({ProjectResult result, UILayoutData? uiLayout})> loadProject(String projectId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final project = await _storage.getProject(projectId);

      if (project == null) {
        _isLoading = false;
        notifyListeners();
        return (
          result: const ProjectResult(
            success: false,
            message: 'Project not found',
          ),
          uiLayout: null,
        );
      }

      // Load project data into the audio engine
      final loadResult = _audioEngine.loadProjectFromJson(project.data);

      // Parse UI layout if available
      UILayoutData? uiLayout;
      if (project.uiLayoutJson != null) {
        try {
          final layoutJson = jsonDecode(project.uiLayoutJson!) as Map<String, dynamic>;
          uiLayout = UILayoutData.fromJson(layoutJson);
        } catch (e) {
          debugPrint('ProjectManager: Failed to parse UI layout: $e');
        }
      }

      _currentProjectId = projectId;
      _currentProjectName = project.name;
      _isLoading = false;
      notifyListeners();

      return (
        result: ProjectResult(
          success: true,
          message: loadResult,
          path: projectId,
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

  /// Save the current project
  Future<ProjectResult?> saveProject(UILayoutData? uiLayout) async {
    if (_currentProjectId == null) {
      return null; // Caller should use saveProjectAs
    }
    return _saveProjectWithId(_currentProjectId!, _currentProjectName, uiLayout, isNew: false);
  }

  /// Save the project to a specific path (ID on web)
  Future<ProjectResult> saveProjectToPath(String projectId, UILayoutData? uiLayout) async {
    return _saveProjectWithId(projectId, _currentProjectName, uiLayout, isNew: false);
  }

  /// Save project as new with a given name
  Future<ProjectResult> saveProjectAs(String name, UILayoutData? uiLayout) async {
    final projectId = WebStorageService.generateId();
    _currentProjectName = name;
    return _saveProjectWithId(projectId, name, uiLayout, isNew: true);
  }

  /// Internal save implementation
  Future<ProjectResult> _saveProjectWithId(
    String projectId,
    String name,
    UILayoutData? uiLayout, {
    required bool isNew,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get project data from audio engine as JSON
      final projectData = _audioEngine.saveProject(name, ''); // Path not used on web

      // Get existing project to preserve creation date
      final existingProject = isNew ? null : await _storage.getProject(projectId);

      final now = DateTime.now();
      final project = WebProject(
        id: projectId,
        name: name,
        data: projectData,
        createdAt: existingProject?.createdAt ?? now,
        updatedAt: now,
        uiLayoutJson: uiLayout != null ? jsonEncode(uiLayout.toJson()) : null,
      );

      await _storage.saveProject(project);
      await _refreshProjectList();

      _currentProjectId = projectId;
      _currentProjectName = name;
      _isLoading = false;
      notifyListeners();

      return ProjectResult(
        success: true,
        message: 'Project saved',
        path: projectId,
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
    // parentPath is ignored on web - just use name
    final copyId = WebStorageService.generateId();

    _isLoading = true;
    notifyListeners();

    try {
      final projectData = _audioEngine.saveProject(name, '');

      final now = DateTime.now();
      final copyProject = WebProject(
        id: copyId,
        name: name,
        data: projectData,
        createdAt: now,
        updatedAt: now,
        uiLayoutJson: uiLayout != null ? jsonEncode(uiLayout.toJson()) : null,
      );

      await _storage.saveProject(copyProject);
      await _refreshProjectList();

      _isLoading = false;
      notifyListeners();

      return ProjectResult(
        success: true,
        message: 'Copy created: $name',
        path: copyId,
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

  /// Make a copy of the current project
  Future<ProjectResult> makeCopy(String copyName, String parentPath, UILayoutData? uiLayout) async {
    if (_currentProjectId == null) {
      return const ProjectResult(
        success: false,
        message: 'No project to copy',
      );
    }

    return saveProjectAsCopy(copyName, parentPath, uiLayout);
  }

  /// Delete a project
  Future<ProjectResult> deleteProject(String projectId) async {
    try {
      await _storage.deleteProject(projectId);
      await _refreshProjectList();

      // If we deleted the current project, clear state
      if (_currentProjectId == projectId) {
        _currentProjectId = null;
        _currentProjectName = 'Untitled Project';
      }

      notifyListeners();

      return const ProjectResult(
        success: true,
        message: 'Project deleted',
      );
    } catch (e) {
      return ProjectResult(
        success: false,
        message: 'Failed to delete project: $e',
      );
    }
  }

  /// Export project to WAV (triggers browser download)
  Future<ProjectResult> exportToWav(String path) async {
    // On web, export returns data that we'd trigger as a download
    // For now, this is a stub - full implementation requires triggering
    // a browser download with the exported audio data
    return const ProjectResult(
      success: false,
      message: 'WAV export not yet implemented on web',
    );
  }

  /// Close the current project
  void closeProject() {
    _currentProjectId = null;
    _currentProjectName = 'Untitled';
    notifyListeners();
  }

  /// Update project name (for Save As)
  void setProjectName(String name) {
    _currentProjectName = name;
    notifyListeners();
  }

  /// Clear all state
  void clear() {
    _currentProjectId = null;
    _currentProjectName = 'Untitled Project';
    _isLoading = false;
    notifyListeners();
  }

  /// Get storage usage statistics
  Future<Map<String, int>?> getStorageStats() async {
    return _storage.getStorageEstimate();
  }
}
