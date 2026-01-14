import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/undo_redo_manager.dart';
import '../../state/ui_layout_state.dart';

/// Configuration object for DAW menu bar callbacks and state
class DawMenuConfig {
  // File menu callbacks
  final VoidCallback onNewProject;
  final VoidCallback onOpenProject;
  final VoidCallback onSaveProject;
  final VoidCallback onSaveProjectAs;
  final VoidCallback onMakeCopy;
  final VoidCallback onExportAudio;
  final VoidCallback onExportMidi;
  final VoidCallback onProjectSettings;
  final VoidCallback onCloseProject;
  final List<PlatformMenuItem> recentProjectsMenu;

  // Edit menu callbacks and state
  final UndoRedoManager undoRedoManager;
  final VoidCallback? onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback? onSplitAtMarker;
  final VoidCallback? onQuantizeClip;
  final VoidCallback? onConsolidateClips;
  final VoidCallback? onBounceMidiToAudio;
  final bool hasSelectedMidiClip;
  final bool hasSelectedAudioClip;
  final int selectedMidiClipCount;

  // View menu callbacks and state
  final UILayoutState uiLayout;
  final VoidCallback onToggleLibrary;
  final VoidCallback onToggleMixer;
  final VoidCallback onToggleEditor;
  final VoidCallback onTogglePiano;
  final VoidCallback onResetPanelLayout;
  final VoidCallback onAppSettings;

  // Undo/redo callbacks
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  const DawMenuConfig({
    required this.onNewProject,
    required this.onOpenProject,
    required this.onSaveProject,
    required this.onSaveProjectAs,
    required this.onMakeCopy,
    required this.onExportAudio,
    required this.onExportMidi,
    required this.onProjectSettings,
    required this.onCloseProject,
    required this.recentProjectsMenu,
    required this.undoRedoManager,
    required this.onDelete,
    required this.onDuplicate,
    required this.onSplitAtMarker,
    required this.onQuantizeClip,
    required this.onConsolidateClips,
    required this.onBounceMidiToAudio,
    required this.hasSelectedMidiClip,
    required this.hasSelectedAudioClip,
    required this.selectedMidiClipCount,
    required this.uiLayout,
    required this.onToggleLibrary,
    required this.onToggleMixer,
    required this.onToggleEditor,
    required this.onTogglePiano,
    required this.onResetPanelLayout,
    required this.onAppSettings,
    this.onUndo,
    this.onRedo,
  });
}

/// Builds the platform menu bar for the DAW screen
List<PlatformMenu> buildDawMenus(BuildContext context, DawMenuConfig config) {
  return [
    // Standard macOS app menu (Audio)
    PlatformMenu(
      label: 'Audio',
      menus: [
        PlatformMenuItem(
          label: 'About Audio',
          onSelected: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('About Audio'),
                content: const Text('Audio\nVersion M6.2\n\nA modern, cross-platform DAW'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
        if (Platform.isMacOS)
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu),
        if (Platform.isMacOS)
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
        if (Platform.isMacOS)
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
        if (Platform.isMacOS)
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
        PlatformMenuItem(
          label: 'Quit Audio',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
          onSelected: () => exit(0),
        ),
      ],
    ),

    // File Menu
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItem(
          label: 'New Project',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
          onSelected: config.onNewProject,
        ),
        PlatformMenuItem(
          label: 'Open Project...',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
          onSelected: config.onOpenProject,
        ),
        PlatformMenu(
          label: 'Open Recent',
          menus: config.recentProjectsMenu,
        ),
        PlatformMenuItem(
          label: 'Save',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
          onSelected: config.onSaveProject,
        ),
        PlatformMenuItem(
          label: 'Save As...',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
          onSelected: config.onSaveProjectAs,
        ),
        PlatformMenuItem(
          label: 'Make a Copy...',
          onSelected: config.onMakeCopy,
        ),
        PlatformMenuItem(
          label: 'Export Audio...',
          onSelected: config.onExportAudio,
        ),
        PlatformMenuItem(
          label: 'Export MIDI...',
          onSelected: config.onExportMidi,
        ),
        PlatformMenuItem(
          label: 'Project Settings...',
          shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
          onSelected: config.onProjectSettings,
        ),
        PlatformMenuItem(
          label: 'Close Project',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
          onSelected: config.onCloseProject,
        ),
      ],
    ),

    // Edit Menu
    PlatformMenu(
      label: 'Edit',
      menus: [
        PlatformMenuItem(
          label: config.undoRedoManager.canUndo
              ? 'Undo - ${config.undoRedoManager.undoDescription ?? "Action"}'
              : 'Undo',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
          onSelected: config.undoRedoManager.canUndo ? config.onUndo : null,
        ),
        PlatformMenuItem(
          label: config.undoRedoManager.canRedo
              ? 'Redo - ${config.undoRedoManager.redoDescription ?? "Action"}'
              : 'Redo',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
          onSelected: config.undoRedoManager.canRedo ? config.onRedo : null,
        ),
        const PlatformMenuItem(
          label: 'Cut',
          shortcut: SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          onSelected: null, // Disabled - future feature
        ),
        const PlatformMenuItem(
          label: 'Copy',
          shortcut: SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          onSelected: null, // Disabled - future feature
        ),
        const PlatformMenuItem(
          label: 'Paste',
          shortcut: SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          onSelected: null, // Disabled - future feature
        ),
        PlatformMenuItem(
          label: 'Delete',
          shortcut: const SingleActivator(LogicalKeyboardKey.delete),
          onSelected: config.onDelete,
        ),
        PlatformMenuItem(
          label: 'Duplicate',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
          onSelected: config.onDuplicate,
        ),
        PlatformMenuItem(
          label: 'Split at Marker',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
          onSelected: config.onSplitAtMarker,
        ),
        PlatformMenuItem(
          label: 'Quantize Clip',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyQ),
          onSelected: config.onQuantizeClip,
        ),
        PlatformMenuItem(
          label: 'Consolidate Clips',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
          onSelected: config.onConsolidateClips,
        ),
        PlatformMenuItem(
          label: 'Bounce MIDI to Audio',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyB, meta: true),
          onSelected: config.onBounceMidiToAudio,
        ),
        const PlatformMenuItem(
          label: 'Select All',
          shortcut: SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          onSelected: null, // Disabled - future feature
        ),
      ],
    ),

    // View Menu
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformMenuItem(
          label: !config.uiLayout.isLibraryPanelCollapsed ? '✓ Show Library Panel' : 'Show Library Panel',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
          onSelected: config.onToggleLibrary,
        ),
        PlatformMenuItem(
          label: config.uiLayout.isMixerVisible ? '✓ Show Mixer Panel' : 'Show Mixer Panel',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
          onSelected: config.onToggleMixer,
        ),
        PlatformMenuItem(
          label: config.uiLayout.isEditorPanelVisible ? '✓ Show Editor Panel' : 'Show Editor Panel',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
          onSelected: config.onToggleEditor,
        ),
        PlatformMenuItem(
          label: config.uiLayout.isVirtualPianoEnabled ? '✓ Show Virtual Piano' : 'Show Virtual Piano',
          shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
          onSelected: config.onTogglePiano,
        ),
        PlatformMenuItem(
          label: 'Reset Panel Layout',
          onSelected: config.onResetPanelLayout,
        ),
        PlatformMenuItem(
          label: 'Settings...',
          onSelected: config.onAppSettings,
        ),
        const PlatformMenuItem(
          label: 'Zoom In',
          shortcut: SingleActivator(LogicalKeyboardKey.equal, meta: true),
          onSelected: null, // Disabled - future feature
        ),
        const PlatformMenuItem(
          label: 'Zoom Out',
          shortcut: SingleActivator(LogicalKeyboardKey.minus, meta: true),
          onSelected: null, // Disabled - future feature
        ),
        const PlatformMenuItem(
          label: 'Zoom to Fit',
          shortcut: SingleActivator(LogicalKeyboardKey.digit0, meta: true),
          onSelected: null, // Disabled - future feature
        ),
      ],
    ),
  ];
}
