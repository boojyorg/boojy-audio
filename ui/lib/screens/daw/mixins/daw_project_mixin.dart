import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../utils/logger.dart';
import '../../../utils/native_dialogs.dart';
import '../../../models/clip_data.dart';
import '../../../utils/audio_clips_info.dart';
import '../../../models/project_view_state.dart';
import '../../../services/project_manager.dart';
import '../../../services/project_persistence.dart';
import '../../../services/window_title_service.dart';
import '../../../widgets/settings_dialog.dart';
import '../../../widgets/export_dialog.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_playback_mixin.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';
import 'daw_vst3_mixin.dart';
import 'daw_library_mixin.dart';
import '../../../widgets/shared/boojy_notice.dart';

/// Mixin containing project-related methods for DAWScreen.
/// Handles new, open, save, export, and version management.
mixin DAWProjectMixin
    on
        State<DAWScreen>,
        DAWScreenStateMixin,
        DAWPlaybackMixin,
        DAWRecordingMixin,
        DAWUIMixin,
        DAWTrackMixin,
        DAWClipMixin,
        DAWVst3Mixin,
        DAWLibraryMixin {
  // ============================================
  // NEW PROJECT
  // ============================================

  /// Create a new project
  void newProject() {
    // Skip confirmation if there's no active project with content
    final hasActiveProject =
        projectManager?.currentPath != null || undoRedoManager.canUndo;
    if (!hasActiveProject) {
      executeNewProject();
      return;
    }

    // Show confirmation dialog if current project has unsaved changes
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: const Text(
          'Create a new project? Any unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              executeNewProject();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  /// Execute the new project creation (shared by confirmed and unconfirmed paths)
  void executeNewProject() {
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

    // Track ids restart at 1 in every new project, so anything the UI keeps per
    // track id (colours, instruments, VST3 chips, automation) from the old
    // project would attach to the new project's tracks.
    resetPerTrackUiState();

    // Loop back to its defaults (off, bars 1-4) for the new project
    uiLayout.resetLoop();
    playbackController.updateLoopBounds(
      loopStartBeats: uiLayout.loopStartBeats,
      loopEndBeats: uiLayout.loopEndBeats,
    );

    // Reset panel sizes to a consistent proportional baseline so a new project
    // doesn't inherit the last drag. Per-project sizes are still restored from
    // the saved file when an existing project is opened.
    final windowSize = MediaQuery.of(context).size;
    uiLayout.resetSizesToDefaults(windowSize.width, windowSize.height);

    // Clear window title (back to just "Boojy Audio")
    WindowTitleService.clearProjectName();

    // Refresh track widgets to show empty state (clear clips too)
    refreshTrackWidgets(clearClips: true);

    setState(() {
      loadedClipId = null;
      waveformPeaks = [];
    });
  }

  // ============================================
  // OPEN PROJECT
  // ============================================

  /// Open an existing project
  Future<void> openProject() async {
    try {
      // Get default projects folder
      final defaultFolder = await getDefaultProjectsFolder();

      // Native folder picker (AppleScript on macOS, file_picker elsewhere)
      final path = await pickFolder(
        title: 'Select Boojy Audio Project (.audio folder)',
        initialDirectory: defaultFolder,
      );
      if (path == null) return;

      if (!path.endsWith('.audio')) {
        Notices.info('Choose a project folder (its name ends in .audio)');
        return;
      }

      setState(() => isLoading = true);
      await _loadAndApplyProject(path);
    } catch (e) {
      setState(() => isLoading = false);
      Notices.problem("Couldn't open the project", error: e);
    }
  }

  /// Open a project from a specific path (used by Open Recent)
  Future<void> openRecentProject(String path) async {
    // Check if path still exists
    final dir = Directory(path);
    if (!await dir.exists()) {
      userSettings.removeRecentProject(path);
      Notices.problem(
        "Couldn't find that project. It may have been moved or deleted.",
      );
      return;
    }

    try {
      setState(() => isLoading = true);
      await _loadAndApplyProject(path);
    } catch (e) {
      setState(() => isLoading = false);
      Notices.problem("Couldn't open the project", error: e);
    }
  }

  /// Shared project loading logic used by both openProject and openRecentProject
  Future<void> _loadAndApplyProject(String path) async {
    final loadResult = await projectManager!.loadProject(path);

    // A failed engine load returns success: false (e.g. corrupt project.json or
    // missing referenced files). Bail before wiping undo history or restoring
    // clips against a half-loaded engine, and surface the reason.
    if (!loadResult.result.success) {
      setState(() => isLoading = false);
      Notices.problem(
        "Couldn't open the project",
        error: loadResult.result.message,
      );
      return;
    }

    // Rebuild every piece of UI state from the freshly loaded engine project.
    applyLoadedProject(loadResult.uiLayout);

    // Add/update recent projects with metadata
    userSettings.addRecentProject(
      path,
      projectManager!.currentName,
      bpm: tempo,
    );

    // Update window title and metadata with project name
    WindowTitleService.setProjectName(projectManager!.currentName);

    // The master timeline row is gone from the UI. A project saved while it
    // was visible (or one the engine flags visible because the master has
    // volume automation) is forced hidden so the engine flag can't disagree.
    audioEngine?.setMasterTimelineVisible(visible: false);

    setState(() {
      projectMetadata = projectMetadata.copyWith(
        name: projectManager!.currentName,
        // Keep the metadata BPM on the loaded engine tempo — the project
        // settings dialog seeds its BPM field from here.
        bpm: tempo,
      );
      isLoading = false;
    });
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
    final nameController = TextEditingController(
      text: projectManager?.currentName ?? 'Untitled',
    );

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

      // Native folder picker (AppleScript on macOS, file_picker elsewhere)
      final parentPath = await pickFolder(
        title: 'Choose location to save project',
        initialDirectory: defaultFolder,
      );

      if (parentPath != null) {
        // Strip characters Windows forbids in folder names — the project name
        // becomes the .audio folder's name.
        final safeName = sanitizeFileName(projectName);
        final projectPath =
            '$parentPath${Platform.pathSeparator}$safeName.audio';
        saveProjectToPath(projectPath);
      }
    } catch (e) {
      Notices.problem("Couldn't save the project", error: e);
    }
  }

  /// Save project to specific path
  Future<void> saveProjectToPath(String path) async {
    setState(() => isLoading = true);

    final result = await projectManager!.saveProjectToPath(
      path,
      getCurrentUILayout(),
    );

    // Add to recent projects and generate thumbnail on successful save
    if (result.success) {
      userSettings.addRecentProject(
        path,
        projectManager!.currentName,
        bpm: tempo,
      );
      // Capture thumbnail after frame completes (non-blocking)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        captureScreenshot(path);
      });
    }

    setState(() => isLoading = false);

    if (!result.success) {
      Notices.problem("Couldn't save the project", error: result.message);
    }
  }

  /// Capture the arrangement view as a thumbnail for the start screen.
  /// Uses low pixelRatio and a timeout to avoid freezing on complex projects.
  Future<void> captureScreenshot(String projectPath) async {
    try {
      final boundary =
          screenshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Low resolution + 3s timeout to prevent UI freeze
      final image = await boundary
          .toImage(pixelRatio: 0.25)
          .timeout(const Duration(seconds: 3));
      final byteData = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 3));
      if (byteData == null) return;

      final file = File('$projectPath/thumbnail.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
    } catch (_) {
      // Non-critical — silently skip on timeout or error
    }
  }

  /// Rename current project
  Future<void> renameProject() async {
    if (projectManager?.currentPath == null) {
      Notices.info('Save the project before renaming it');
      return;
    }

    final nameController = TextEditingController(
      text: projectManager!.currentName,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'New Name'),
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

    if (newName == null ||
        newName.isEmpty ||
        newName == projectManager!.currentName) {
      return;
    }

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
      });
    } catch (e) {
      Notices.problem("Couldn't rename the project", error: e);
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
          applyLoadedProject(result?.uiLayout);
        }
      }

      await autoSaveService.clearRecoveryMarker();
    } catch (e) {
      Log.e('Failed to check for crash recovery: $e');
    }
  }

  // ============================================
  // UI LAYOUT HELPERS
  // ============================================

  /// Drop everything the UI keeps per track id.
  ///
  /// A project keeps its track ids across save and reopen, and every new
  /// project starts numbering at 1 again, so per-track data left over from the
  /// previous project (colour overrides, instruments, VST3 chips, automation)
  /// would silently attach itself to the next project's tracks.
  void resetPerTrackUiState() {
    trackController.clearAllTrackOverrides(); // colours + instruments
    vst3PluginManager?.clear();
    automationController.clear();
  }

  /// Turn a freshly loaded engine project into UI state. Shared by Open,
  /// Open Recent and crash recovery so they can't drift apart.
  ///
  /// [uiLayout] is the project's `ui_layout.json`, if it has one. The engine
  /// owns *what exists* (tracks, MIDI and audio clips); the layout only adds
  /// UI extras (colours, clip names, loop settings, zoom, ...) filed under the
  /// same ids.
  void applyLoadedProject(UILayoutData? uiLayout) {
    // Clip id mappings belong to the previous project.
    midiPlaybackManager?.clearClipIdMappings();
    undoRedoManager.clear();

    // Drop the previous project's per-track UI data BEFORE applying the loaded
    // layout; the new project reuses the same small track ids.
    resetPerTrackUiState();
    trackController.selectTrack(null);

    // Sync the engine's tempo into the UI before restoring clips. MIDI clip
    // start/end are stored in beats and converted using `tempo`; restoring at
    // the stale default (120) would shift every note off the grid for any
    // project saved at a different BPM (e.g. 140).
    recordingController.setTempo(audioEngine!.getTempo());

    // The project file also carries a count-in value which the engine has just
    // restored; the user's preference is the single source of truth, so push
    // it back (otherwise a project saved with 2 or 4 bars counts in longer
    // than the toolbar says).
    audioEngine!.setCountInBars(userSettings.countInBars);

    // Restore MIDI clips from engine for UI display, merging the saved UI
    // metadata (name/colour/offset/loop/mute) from ui_layout.json.
    midiPlaybackManager?.restoreClipsFromEngine(
      tempo,
      savedMetadata: uiLayout?.midiClips,
    );

    // Rebuild audio clips from the engine too. Always, even when the layout has
    // none: a project without audio must not keep the previous one's clips.
    restoreAudioClipsFromEngine(uiLayout?.audioClips ?? const []);

    if (uiLayout != null) {
      applyUILayout(uiLayout);
    }

    // Refresh track widgets to show loaded tracks
    refreshTrackWidgets();
  }

  /// Rebuild the arrangement's audio clips from the engine's copy of the song,
  /// merging the UI extras saved in `ui_layout.json` ([savedClips]) by clip id.
  ///
  /// This is what makes audio you can hear always visible: clips come from the
  /// engine, not from the layout file, so a layout that is out of step with the
  /// engine (older projects damaged by id drift) can no longer hide them.
  void restoreAudioClipsFromEngine(List<ClipData> savedClips) {
    final engine = audioEngine;
    if (engine == null) return;

    final rebuilt = rebuildAudioClips(
      engineClips: parseAudioClipsInfo(engine.getAllAudioClipsInfo()),
      savedClips: savedClips,
      // A quick low-res waveform for the first paint; sharpened below.
      peaksFor: (clipId, fileDuration) => engine.getWaveformPeaks(clipId, 1000),
    );

    // The engine stores clip position but not edit parameters (gain, warp,
    // transpose, reverse): re-push the saved ones now that ids line up.
    _syncAudioClipEditDataToEngine(rebuilt);

    // Old layout files carried full-resolution peaks; everything else needs the
    // sharper waveform computed once the clip is on screen.
    final hadSavedPeaks = {
      for (final c in savedClips)
        if (c.waveformPeaks.isNotEmpty) c.clipId,
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timelineState = timelineKey.currentState;
      if (timelineState == null) return;
      timelineState.restoreAudioClips(rebuilt);
      for (final clip in rebuilt) {
        if (!hadSavedPeaks.contains(clip.clipId)) {
          timelineState.scheduleWaveformUpgrade(clip.clipId);
        }
      }
    });
    // Nothing else may schedule a frame (a project with no layout file).
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Apply UI layout from loaded project
  void applyUILayout(UILayoutData layout) {
    setState(() {
      uiLayout.applyLayout(layout);
    });

    // Restore the time-signature numerator and re-push it to the engine
    // (without this, 3/4 projects silently reopened in 4/4). The denominator
    // is locked to /4 in v0.6: the engine is quarter-note based, so a saved
    // 6/8 always *played* as 6/4 — displaying it as 6/8 was dishonest, and
    // it now flattens to x/4 (the audible result is unchanged).
    final tsNum = layout.timeSignatureNumerator;
    if (tsNum != null) {
      setState(() {
        projectMetadata = projectMetadata.copyWith(
          timeSignatureNumerator: tsNum,
          timeSignatureDenominator: 4,
        );
      });
      audioEngine?.setTimeSignature(tsNum);
    }

    if (layout.viewState != null) {
      restoreViewState(layout.viewState!);
    }

    automationController.loadFromJson(layout.automationData);
    syncAllVolumeAutomationToEngine();

    // Restore track color overrides
    if (layout.trackColors != null) {
      for (final entry in layout.trackColors!.entries) {
        trackController.setTrackColor(entry.key, Color(entry.value));
      }
    }

    // Restore the saved loop. A project saved without one (older files) gets
    // the defaults rather than inheriting the previously open project's loop.
    uiLayout.resetLoop();
    if (layout.loopEnabled != null) {
      uiLayout.loopPlaybackEnabled = layout.loopEnabled!;
    }
    if (layout.loopStartBeats != null && layout.loopEndBeats != null) {
      uiLayout.setLoopRegion(layout.loopStartBeats!, layout.loopEndBeats!);
    }
    // Keep playback's cached loop bounds in step (no-op unless loop-cycling).
    playbackController.updateLoopBounds(
      loopStartBeats: uiLayout.loopStartBeats,
      loopEndBeats: uiLayout.loopEndBeats,
    );
  }

  /// Re-push per-clip edit parameters (gain/warp/transpose/reverse) to the
  /// engine after load. The engine's own project file only stores clip
  /// position; edit params live in ui_layout.json, so without this re-push
  /// saved processing is silently absent from playback until the user opens
  /// the audio editor for that clip.
  void _syncAudioClipEditDataToEngine(List<ClipData> clips) {
    final engine = audioEngine;
    if (engine == null) return;
    for (final clip in clips) {
      final edit = clip.editData;
      if (edit == null) continue;
      engine.setAudioClipGain(clip.trackId, clip.clipId, edit.gainDb);
      engine.setAudioClipWarp(
        clip.trackId,
        clip.clipId,
        edit.syncEnabled,
        edit.stretchFactor,
      );
      engine.setAudioClipTranspose(
        clip.trackId,
        clip.clipId,
        edit.transposeSemitones,
        edit.fineCents,
      );
      engine.setAudioClipReverse(
        clip.trackId,
        clip.clipId,
        reversed: edit.reversed,
      );
    }
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
    final timelineState = timelineKey.currentState;

    final viewState = ProjectViewState(
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

    return ProjectPersistence.collect(
      libraryWidth: uiLayout.libraryPanelWidth,
      libraryLeftWidth: uiLayout.libraryLeftColumnWidth,
      mixerWidth: uiLayout.mixerPanelWidth,
      bottomHeight: uiLayout.editorPanelHeight,
      libraryCollapsed: uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !uiLayout.isMixerVisible,
      bottomCollapsed:
          !(uiLayout.isEditorPanelVisible || uiLayout.isVirtualPianoEnabled),
      loopEnabled: uiLayout.loopPlaybackEnabled,
      loopStartBeats: uiLayout.loopStartBeats,
      loopEndBeats: uiLayout.loopEndBeats,
      viewState: viewState,
      audioClips: timelineState?.clips.toList(),
      // Finalized clips only — never persist the in-flight recording clip (C74).
      midiClips: midiPlaybackManager?.persistableMidiClips.toList(),
      automationData: automationController.toJson(),
      trackColorOverrides: trackController.trackColorOverrides,
      timeSignatureNumerator: projectMetadata.timeSignatureNumerator,
      timeSignatureDenominator: projectMetadata.timeSignatureDenominator,
    );
  }

  /// Build recent projects menu
  List<PlatformMenuItem> buildRecentProjectsMenu() {
    final recent = userSettings.recentProjects;

    if (recent.isEmpty) {
      return [
        const PlatformMenuItem(label: 'No Recent Projects', onSelected: null),
      ];
    }

    return [
      ...recent.map(
        (project) => PlatformMenuItem(
          label: project.name,
          onSelected: () => openRecentProject(project.path),
        ),
      ),
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
    // HOME is unset on Windows (it's USERPROFILE there) — falling back to a
    // bare '/Users' path made every save land in an unwritable location.
    final homeDir =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/Users';
    final sep = Platform.pathSeparator;
    final projectsPath =
        '$homeDir${sep}Documents${sep}Boojy${sep}Audio${sep}Projects';

    final dir = Directory(projectsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return projectsPath;
  }
}
