// Stub file for conditional imports - used during static analysis
// This file should never be imported directly at runtime

import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
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

/// Stub ProjectManager that throws on all methods
class ProjectManager extends ChangeNotifier {
  ProjectManager(AudioEngine audioEngine) {
    throw UnsupportedError(
      'ProjectManager stub should not be instantiated. '
      'Use conditional imports to get the correct implementation.',
    );
  }

  String? get currentPath => throw UnsupportedError('stub');
  String get currentName => throw UnsupportedError('stub');
  bool get isLoading => throw UnsupportedError('stub');
  bool get hasProject => throw UnsupportedError('stub');

  void newProject() => throw UnsupportedError('stub');

  Future<({ProjectResult result, UILayoutData? uiLayout})> loadProject(
    String path,
  ) => throw UnsupportedError('stub');

  Future<ProjectResult?> saveProject(UILayoutData? uiLayout) =>
      throw UnsupportedError('stub');

  Future<ProjectResult> saveProjectToPath(
    String path,
    UILayoutData? uiLayout, {
    bool updateCurrentPath = true,
  }) => throw UnsupportedError('stub');

  Future<ProjectResult> saveProjectAsCopy(
    String name,
    String parentPath,
    UILayoutData? uiLayout,
  ) => throw UnsupportedError('stub');

  Future<ProjectResult> makeCopy(
    String copyName,
    String parentPath,
    UILayoutData? uiLayout,
  ) => throw UnsupportedError('stub');

  Future<ProjectResult> exportToWav(String path) =>
      throw UnsupportedError('stub');

  void closeProject() => throw UnsupportedError('stub');

  void setProjectName(String name) => throw UnsupportedError('stub');

  void clear() => throw UnsupportedError('stub');
}
