import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/project_view_state.dart';
import '../../../models/project_version.dart';
import '../../../models/version_type.dart';
import '../../../services/project_manager.dart';
import '../../../services/version_manager.dart';
import '../../../services/window_title_service.dart';
import '../../../widgets/settings_dialog.dart';
import '../../../widgets/export_dialog.dart';
import '../../../widgets/project_settings_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_playback_mixin.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';
import 'daw_vst3_mixin.dart';
import 'daw_library_mixin.dart';

/// Mixin containing project-related methods for DAWScreen.
/// Handles new, open, save, export, and version management.
mixin DAWProjectMixin on State<DAWScreen>, DAWScreenStateMixin, DAWPlaybackMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin, DAWClipMixin, DAWVst3Mixin, DAWLibraryMixin {
  // ============================================
  // NEW PROJECT
  // ============================================

  /// Create a new project
  void newProject() {
    // Show confirmation dialog if current project has unsaved changes
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: const Text('Create a new project? Any unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              // Stop playback if active
              if (isPlaying) {
                stopPlayback();
              }

              // Clear all tracks from the audio engine
              audioEngine?.clearAllTracks();

              // Reset project manager state
              projectManager?.newProject();
              midiPlaybackManager?.clear();
              undoRedoManager.clear();

              // Reset loop auto-follow for new project
              uiLayout.resetLoopAutoFollow();

              // Clear automation data
              automationController.clear();

              // Clear window title (back to just "Boojy Audio")
              WindowTitleService.clearProjectName();

              // Refresh track widgets to show empty state (clear clips too)
              refreshTrackWidgets(clearClips: true);

              setState(() {
                loadedClipId = null;
                waveformPeaks = [];
                statusMessage = 'New project created';
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New project created')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // OPEN PROJECT
  // ============================================

  /// Open an existing project
  Future<void> openProject() async {
    try {
      // Get default projects folder
      final defaultFolder = await getDefaultProjectsFolder();

      // Use macOS native file picker with default location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Select Boojy Audio Project (.audio folder)" default location POSIX file "$defaultFolder")'
      ]);

      if (result.exitCode == 0) {
        var path = result.stdout.toString().trim();
        // Remove trailing slash if present
        if (path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }

        if (path.isEmpty) {
          return;
        }

        if (!path.endsWith('.audio')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a .audio folder')),
          );
          return;
        }

        setState(() => isLoading = true);

        // Load via project manager
        final loadResult = await projectManager!.loadProject(path);

        // Clear MIDI clip ID mappings since Rust side has reset
        midiPlaybackManager?.clearClipIdMappings();
        undoRedoManager.clear();

        // Restore MIDI clips from engine for UI display
        midiPlaybackManager?.restoreClipsFromEngine(tempo);

        // Apply UI layout if available
        if (loadResult.uiLayout != null) {
          applyUILayout(loadResult.uiLayout!);
        }

        // Refresh track widgets to show loaded tracks
        refreshTrackWidgets();

        // Add to recent projects
        userSettings.addRecentProject(path, projectManager!.currentName);

        // Update window title and metadata with project name
        WindowTitleService.setProjectName(projectManager!.currentName);

        setState(() {
          projectMetadata = projectMetadata.copyWith(name: projectManager!.currentName);
          statusMessage = 'Project loaded: ${projectManager!.currentName}';
          isLoading = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadResult.result.message)),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  /// Open a project from a specific path (used by Open Recent)
  Future<void> openRecentProject(String path) async {
    // Check if path still exists
    final dir = Directory(path);
    if (!await dir.exists()) {
      userSettings.removeRecentProject(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project no longer exists')),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      // Load via project manager
      final loadResult = await projectManager!.loadProject(path);

      // Clear MIDI clip ID mappings since Rust side has reset
      midiPlaybackManager?.clearClipIdMappings();
      undoRedoManager.clear();

      // Restore MIDI clips from engine for UI display
      midiPlaybackManager?.restoreClipsFromEngine(tempo);

      // Apply UI layout if available
      if (loadResult.uiLayout != null) {
        applyUILayout(loadResult.uiLayout!);
      }

      // Refresh track widgets to show loaded tracks
      refreshTrackWidgets();

      // Update recent projects (moves to top)
      userSettings.addRecentProject(path, projectManager!.currentName);

      // Update window title and metadata with project name
      WindowTitleService.setProjectName(projectManager!.currentName);

      setState(() {
        projectMetadata = projectMetadata.copyWith(name: projectManager!.currentName);
        statusMessage = 'Project loaded: ${projectManager!.currentName}';
        isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadResult.result.message)),
      );
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  // ============================================
  // SAVE PROJECT
  // ============================================

  /// Save current project
  Future<void> saveProject() async {
    if (projectManager?.currentPath != null) {
      saveProjectToPath(projectManager!.currentPath!);
    } else {
      saveProjectAs();
    }
  }

  /// Save project with new name/location
  Future<void> saveProjectAs() async {
    // Show dialog to enter project name
    final nameController = TextEditingController(text: projectManager?.currentName ?? 'Untitled');

    final projectName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Project As'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            hintText: 'Enter project name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (projectName == null || projectName.isEmpty) return;

    // Update project name in manager, metadata, and window title
    projectManager?.setProjectName(projectName);
    WindowTitleService.setProjectName(projectName);
    setState(() {
      projectMetadata = projectMetadata.copyWith(name: projectName);
    });

    try {
      // Get default projects folder
      final defaultFolder = await getDefaultProjectsFolder();

      // Use macOS native file picker for save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Choose location to save project" default location POSIX file "$defaultFolder")'
      ]);

      if (result.exitCode == 0) {
        final parentPath = result.stdout.toString().trim();
        if (parentPath.isNotEmpty) {
          final projectPath = '$parentPath/$projectName.audio';
          saveProjectToPath(projectPath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save project: $e')),
        );
      }
    }
  }

  /// Save project to specific path
  Future<void> saveProjectToPath(String path) async {
    setState(() => isLoading = true);

    final result = await projectManager!.saveProjectToPath(path, getCurrentUILayout());

    // Add to recent projects on successful save
    if (result.success) {
      userSettings.addRecentProject(path, projectManager!.currentName);
    }

    setState(() {
      statusMessage = result.success ? 'Project saved' : result.message;
      isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  /// Save a new version of the project
  Future<void> saveNewVersion() async {
    if (projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save project first before creating a new version')),
        );
      }
      return;
    }

    try {
      final currentPath = projectManager!.currentPath!;
      final currentName = projectManager!.currentName;
      final parentDir = Directory(currentPath).parent.path;

      // Find the next version number
      int nextVersion = 2;
      final baseName = currentName.replaceAll(RegExp(r'_v\d+$'), '');

      while (true) {
        final versionPath = '$parentDir/${baseName}_v$nextVersion.audio';
        if (!await Directory(versionPath).exists()) {
          break;
        }
        nextVersion++;
      }

      // Create new version path
      final newName = '${baseName}_v$nextVersion';
      final newPath = '$parentDir/$newName.audio';

      // Copy project to new path (saveProjectToPath updates internal path)
      await projectManager!.saveProjectToPath(newPath, getCurrentUILayout());

      // Update project name
      projectManager!.setProjectName(newName);
      WindowTitleService.setProjectName(newName);

      setState(() {
        projectMetadata = projectMetadata.copyWith(name: newName);
        statusMessage = 'Saved as version $nextVersion';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved as $newName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save new version: $e')),
        );
      }
    }
  }

  /// Rename current project
  Future<void> renameProject() async {
    if (projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No project open to rename')),
        );
      }
      return;
    }

    final nameController = TextEditingController(text: projectManager!.currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'New Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == projectManager!.currentName) return;

    try {
      final currentPath = projectManager!.currentPath!;
      final parentDir = Directory(currentPath).parent.path;
      final newPath = '$parentDir/$newName.audio';

      // Rename the folder
      final currentDir = Directory(currentPath);
      await currentDir.rename(newPath);

      // Save project to new path (this updates the internal path)
      await projectManager!.saveProjectToPath(newPath, getCurrentUILayout());
      projectManager!.setProjectName(newName);
      WindowTitleService.setProjectName(newName);

      // Update recent projects
      userSettings.removeRecentProject(currentPath);
      userSettings.addRecentProject(newPath, newName);

      setState(() {
        projectMetadata = projectMetadata.copyWith(name: newName);
        statusMessage = 'Project renamed to $newName';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to $newName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename project: $e')),
        );
      }
    }
  }

  /// Close current project
  void closeProject() {
    newProject(); // Same as creating a new project
  }

  // ============================================
  // EXPORT
  // ============================================

  /// Export audio dialog
  void exportAudio() {
    if (audioEngine == null) return;

    ExportDialog.show(
      context,
      audioEngine: audioEngine!,
      defaultName: projectManager?.currentName ?? 'Untitled',
    );
  }

  /// Quick export MP3
  Future<void> quickExportMp3() async {
    if (audioEngine == null) return;

    try {
      final baseName = projectManager?.currentName ?? 'Untitled';

      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose file name with prompt "Export MP3" default name "$baseName.mp3")'
      ]);

      if (result.exitCode != 0) return;

      String? filePath = result.stdout.toString().trim();
      if (filePath.isEmpty) return;

      if (!filePath.endsWith('.mp3')) {
        filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.mp3';
      }

      final bitrate = userSettings.exportMp3Bitrate;
      final sampleRate = userSettings.exportSampleRate;
      final normalize = userSettings.exportNormalize;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting MP3...')),
        );
      }

      final resultJson = audioEngine!.exportMp3WithOptions(
        outputPath: filePath,
        bitrate: bitrate,
        sampleRate: sampleRate,
        normalize: normalize,
      );

      if (mounted) {
        final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parsed['success'] == true ? 'MP3 export complete' : 'Export failed: ${parsed['error']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Quick export WAV
  Future<void> quickExportWav() async {
    if (audioEngine == null) return;

    try {
      final baseName = projectManager?.currentName ?? 'Untitled';

      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose file name with prompt "Export WAV" default name "$baseName.wav")'
      ]);

      if (result.exitCode != 0) return;

      String? filePath = result.stdout.toString().trim();
      if (filePath.isEmpty) return;

      if (!filePath.endsWith('.wav')) {
        filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.wav';
      }

      final bitDepth = userSettings.exportWavBitDepth;
      final sampleRate = userSettings.exportSampleRate;
      final normalize = userSettings.exportNormalize;
      final dither = userSettings.exportDither;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting WAV...')),
        );
      }

      final resultJson = audioEngine!.exportWavWithOptions(
        outputPath: filePath,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
        normalize: normalize,
        dither: dither,
      );

      if (mounted) {
        final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parsed['success'] == true ? 'WAV export complete' : 'Export failed: ${parsed['error']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Export MIDI dialog
  void exportMidi() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export MIDI'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export MIDI functionality coming soon.'),
            SizedBox(height: 16),
            Text('This will export:'),
            Text('- All MIDI tracks as .mid file'),
            Text('- Preserve tempo and time signatures'),
            Text('- Include all note data and velocities'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // PROJECT SETTINGS
  // ============================================

  /// Open project settings dialog
  Future<void> openProjectSettings() async {
    // Initialize version manager if needed
    final projectPath = projectManager?.currentPath;
    if (projectPath != null) {
      final projectFolder = File(projectPath).parent.path;
      versionManager ??= VersionManager(projectFolder);
      await versionManager!.refresh();
    }

    final result = await ProjectSettingsDialog.show(
      context,
      metadata: projectMetadata,
      versions: versionManager?.versions ?? [],
      currentVersionNumber: versionManager?.currentVersionNumber,
      nextVersionNumber: versionManager?.nextVersionNumber ?? 1,
    );

    if (result == null || !mounted) return;

    // Handle metadata changes
    final updatedMetadata = result.metadata;
    final bpmChanged = updatedMetadata.bpm != projectMetadata.bpm;
    final nameChanged = updatedMetadata.name != projectMetadata.name;

    setState(() {
      projectMetadata = updatedMetadata;
    });

    // Update audio engine with new BPM
    if (bpmChanged) {
      audioEngine?.setTempo(updatedMetadata.bpm);
      recordingController.setTempo(updatedMetadata.bpm);
    }

    // Update project name if changed
    if (nameChanged) {
      projectManager?.setProjectName(updatedMetadata.name);
      WindowTitleService.setProjectName(updatedMetadata.name);
    }

    // Handle version actions
    if (result.versionAction == 'create' && result.newVersionData != null) {
      await createVersion(result.newVersionData!);
    } else if (result.versionAction == 'restore' && result.selectedVersion != null) {
      await restoreVersion(result.selectedVersion!);
    }
  }

  /// Create a new version
  Future<void> createVersion(({String name, String? note, VersionType type}) data) async {
    if (projectManager?.currentPath == null || versionManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save the project first')),
      );
      return;
    }

    final projectPath = projectManager!.currentPath!;

    final version = await versionManager!.createVersion(
      name: data.name,
      note: data.note,
      versionType: data.type,
      currentProjectFilePath: projectPath,
    );

    if (version != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Version "${version.name}" created')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create version')),
      );
    }
  }

  /// Restore a version
  Future<void> restoreVersion(ProjectVersion version) async {
    if (projectManager?.currentPath == null || versionManager == null) return;

    final projectPath = projectManager!.currentPath!;

    // Switch to the version
    final success = await versionManager!.switchToVersion(
      version: version,
      currentProjectFilePath: projectPath,
    );

    if (success && mounted) {
      // Reload the project
      await openRecentProject(projectPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored version "${version.name}"')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to restore version')),
      );
    }
  }

  // ============================================
  // CRASH RECOVERY
  // ============================================

  /// Check for crash recovery backup on startup
  Future<void> checkForCrashRecovery() async {
    try {
      final backupPath = await autoSaveService.checkForRecovery();
      if (backupPath == null || !mounted) return;

      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) return;

      final stat = await backupDir.stat();
      final backupDate = stat.modified;

      if (!mounted) return;

      final shouldRecover = await RecoveryDialog.show(
        context,
        backupPath: backupPath,
        backupDate: backupDate,
      );

      if (shouldRecover == true && mounted) {
        final result = await projectManager?.loadProject(backupPath);
        if (result?.result.success == true) {
          midiPlaybackManager?.clearClipIdMappings();
          midiPlaybackManager?.restoreClipsFromEngine(tempo);

          setState(() {
            statusMessage = 'Recovered from backup';
          });
          refreshTrackWidgets();

          if (result?.uiLayout != null) {
            applyUILayout(result!.uiLayout!);
          }
        }
      }

      await autoSaveService.clearRecoveryMarker();
    } catch (e) {
      debugPrint('Failed to check for crash recovery: $e');
    }
  }

  // ============================================
  // UI LAYOUT HELPERS
  // ============================================

  /// Apply UI layout from loaded project
  void applyUILayout(UILayoutData layout) {
    setState(() {
      uiLayout.applyLayout(layout);
    });

    if (userSettings.continueWhereLeftOff && layout.viewState != null) {
      restoreViewState(layout.viewState!);
    }

    if (layout.audioClips != null && layout.audioClips!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final timelineState = timelineKey.currentState;
        if (timelineState != null) {
          timelineState.restoreAudioClips(layout.audioClips!);
        }
      });
    }

    automationController.loadFromJson(layout.automationData);
    syncAllVolumeAutomationToEngine();
  }

  /// Sync all volume automation lanes to engine
  void syncAllVolumeAutomationToEngine() {
    if (audioEngine == null) return;
    for (final trackId in automationController.allTrackIds) {
      syncVolumeAutomationToEngine(trackId);
    }
  }

  /// Restore view state
  void restoreViewState(ProjectViewState viewState) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timelineState = timelineKey.currentState;

      if (timelineState != null) {
        timelineState.setPixelsPerBeat(viewState.zoom);
        timelineState.setScrollOffset(viewState.horizontalScroll);
      }

      setState(() {
        uiLayout.isLibraryPanelCollapsed = !viewState.libraryVisible;
        uiLayout.isMixerVisible = viewState.mixerVisible;
        uiLayout.isEditorPanelVisible = viewState.editorVisible;
        uiLayout.isVirtualPianoEnabled = viewState.virtualPianoVisible;
      });

      if (viewState.selectedTrackId != null) {
        selectedTrackId = viewState.selectedTrackId;
      }

      playheadPosition = viewState.playheadPosition;
    });
  }

  /// Get current UI layout for saving
  UILayoutData getCurrentUILayout() {
    ProjectViewState? viewState;
    if (userSettings.continueWhereLeftOff) {
      final timelineState = timelineKey.currentState;

      viewState = ProjectViewState(
        horizontalScroll: timelineState?.scrollOffset ?? 0.0,
        verticalScroll: 0.0,
        zoom: timelineState?.pixelsPerBeat ?? 25.0,
        libraryVisible: !uiLayout.isLibraryPanelCollapsed,
        mixerVisible: uiLayout.isMixerVisible,
        editorVisible: uiLayout.isEditorPanelVisible,
        virtualPianoVisible: uiLayout.isVirtualPianoEnabled,
        selectedTrackId: selectedTrackId,
        playheadPosition: playheadPosition,
      );
    }

    final timelineState = timelineKey.currentState;
    final audioClips = timelineState?.clips.toList();

    return UILayoutData(
      libraryWidth: uiLayout.libraryPanelWidth,
      mixerWidth: uiLayout.mixerPanelWidth,
      bottomHeight: uiLayout.editorPanelHeight,
      libraryCollapsed: uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !uiLayout.isMixerVisible,
      bottomCollapsed: !(uiLayout.isEditorPanelVisible || uiLayout.isVirtualPianoEnabled),
      viewState: viewState,
      audioClips: audioClips,
      automationData: automationController.toJson(),
    );
  }

  /// Build recent projects menu
  List<PlatformMenuItem> buildRecentProjectsMenu() {
    final recent = userSettings.recentProjects;

    if (recent.isEmpty) {
      return [
        const PlatformMenuItem(
          label: 'No Recent Projects',
          onSelected: null,
        ),
      ];
    }

    return [
      ...recent.map((project) => PlatformMenuItem(
        label: project.name,
        onSelected: () => openRecentProject(project.path),
      )),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Clear Recent Projects',
            onSelected: () {
              userSettings.clearRecentProjects();
              setState(() {});
            },
          ),
        ],
      ),
    ];
  }

  /// Get default projects folder path
  Future<String> getDefaultProjectsFolder() async {
    final homeDir = Platform.environment['HOME'] ?? '/Users';
    final projectsPath = '$homeDir/Documents/Boojy/Audio/Projects';

    final dir = Directory(projectsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return projectsPath;
  }
}
