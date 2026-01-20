// Stub file for conditional imports - used during static analysis
// This file should never be imported directly at runtime

import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import '../models/clip_data.dart';
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
  final List<ClipData>? audioClips;

  const UILayoutData({
    this.libraryWidth = 200.0,
    this.mixerWidth = 380.0,
    this.bottomHeight = 250.0,
    this.libraryCollapsed = false,
    this.mixerCollapsed = false,
    this.bottomCollapsed = true,
    this.viewState,
    this.audioClips,
  });

  Map<String, dynamic> toJson() => throw UnsupportedError('stub');

  factory UILayoutData.fromJson(Map<String, dynamic> json) =>
      throw UnsupportedError('stub');
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

  Future<({ProjectResult result, UILayoutData? uiLayout})> loadProject(String path) =>
      throw UnsupportedError('stub');

  Future<ProjectResult?> saveProject(UILayoutData? uiLayout) =>
      throw UnsupportedError('stub');

  Future<ProjectResult> saveProjectToPath(String path, UILayoutData? uiLayout) =>
      throw UnsupportedError('stub');

  Future<ProjectResult> saveProjectAsCopy(String name, String parentPath, UILayoutData? uiLayout) =>
      throw UnsupportedError('stub');

  Future<ProjectResult> makeCopy(String copyName, String parentPath, UILayoutData? uiLayout) =>
      throw UnsupportedError('stub');

  Future<ProjectResult> exportToWav(String path) =>
      throw UnsupportedError('stub');

  void closeProject() => throw UnsupportedError('stub');

  void setProjectName(String name) => throw UnsupportedError('stub');

  void clear() => throw UnsupportedError('stub');
}
