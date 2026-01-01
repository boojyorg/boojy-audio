import 'package:flutter/foundation.dart';
import '../../../services/project_manager.dart';

/// Controller for project-level operations.
/// Handles new, save, save as, and load operations.
///
/// This is a utility wrapper around ProjectManager that provides
/// a higher-level API for common project operations.
class ProjectOperationsController extends ChangeNotifier {
  ProjectManager? _projectManager;
  bool _isOperationInProgress = false;
  String? _lastError;

  /// Whether a project operation is in progress.
  bool get isOperationInProgress => _isOperationInProgress;

  /// Last error message (if any).
  String? get lastError => _lastError;

  /// Whether there's an open project with a saved path.
  bool get hasProject => _projectManager?.hasProject ?? false;

  /// Current project path.
  String? get currentPath => _projectManager?.currentPath;

  /// Current project name.
  String get currentName => _projectManager?.currentName ?? 'Untitled Project';

  /// Initialize with project manager.
  void initialize({
    required ProjectManager projectManager,
  }) {
    _projectManager = projectManager;
  }

  /// Create a new project, optionally prompting to save current work.
  /// Returns true if new project was created successfully.
  Future<bool> newProject({
    required Future<bool> Function() confirmDiscardChanges,
    required VoidCallback onProjectCleared,
  }) async {
    // Check if there are unsaved changes
    if (hasProject) {
      final shouldDiscard = await confirmDiscardChanges();
      if (!shouldDiscard) {
        return false; // User cancelled
      }
    }

    _setOperationInProgress(true);
    _lastError = null;

    try {
      // Reset project manager state
      _projectManager?.newProject();

      // Notify parent to reset UI state
      onProjectCleared();

      return true;
    } catch (e) {
      _lastError = 'Failed to create new project: $e';
      debugPrint('ProjectOperations: $e');
      return false;
    } finally {
      _setOperationInProgress(false);
    }
  }

  /// Save the current project.
  /// If no path exists, delegates to saveProjectAs.
  Future<bool> saveProject({
    required UILayoutData Function() getUILayout,
    required Future<String?> Function() getSaveAsPath,
  }) async {
    if (_projectManager == null) return false;

    _setOperationInProgress(true);
    _lastError = null;

    try {
      if (_projectManager!.hasProject) {
        // Save to existing path
        await _projectManager!.saveProject(getUILayout());
        return true;
      } else {
        // No existing path, do save as
        _setOperationInProgress(false);
        return await saveProjectAs(
          getUILayout: getUILayout,
          getSaveAsPath: getSaveAsPath,
        );
      }
    } catch (e) {
      _lastError = 'Failed to save project: $e';
      debugPrint('ProjectOperations: $e');
      return false;
    } finally {
      _setOperationInProgress(false);
    }
  }

  /// Save the project to a new location.
  Future<bool> saveProjectAs({
    required UILayoutData Function() getUILayout,
    required Future<String?> Function() getSaveAsPath,
  }) async {
    if (_projectManager == null) return false;

    final path = await getSaveAsPath();
    if (path == null) return false;

    _setOperationInProgress(true);
    _lastError = null;

    try {
      await _projectManager!.saveProjectToPath(path, getUILayout());
      return true;
    } catch (e) {
      _lastError = 'Failed to save project: $e';
      debugPrint('ProjectOperations: $e');
      return false;
    } finally {
      _setOperationInProgress(false);
    }
  }

  /// Load a project from a file.
  Future<ProjectResult> loadProject({
    required String path,
  }) async {
    if (_projectManager == null) {
      return const ProjectResult(
        success: false,
        message: 'Project manager not initialized',
      );
    }

    _setOperationInProgress(true);
    _lastError = null;

    try {
      final result = await _projectManager!.loadProject(path);
      if (!result.result.success) {
        _lastError = result.result.message;
      }
      return result.result;
    } catch (e) {
      _lastError = 'Failed to load project: $e';
      debugPrint('ProjectOperations: $e');
      return ProjectResult(
        success: false,
        message: 'Failed to load project: $e',
      );
    } finally {
      _setOperationInProgress(false);
    }
  }

  void _setOperationInProgress(bool value) {
    _isOperationInProgress = value;
    notifyListeners();
  }
}
