import 'package:flutter/foundation.dart';

/// Grouped callbacks for file menu operations
class FileMenuCallbacks {
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onSaveNewVersion;
  final VoidCallback? onExportAudio;
  final VoidCallback? onExportMp3;
  final VoidCallback? onExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onAppSettings;
  final VoidCallback? onProjectSettings;
  final VoidCallback? onCloseProject;

  const FileMenuCallbacks({
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onSaveNewVersion,
    this.onExportAudio,
    this.onExportMp3,
    this.onExportWav,
    this.onExportMidi,
    this.onAppSettings,
    this.onProjectSettings,
    this.onCloseProject,
  });
}

/// Grouped callbacks for transport play/record operations
class TransportCallbacks {
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onPauseRecording;
  final VoidCallback? onStopRecording;
  final VoidCallback? onCaptureMidi;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onPianoToggle;
  final VoidCallback? onLoopPlaybackToggle;
  final VoidCallback? onPunchInToggle;
  final VoidCallback? onPunchOutToggle;
  final Function(double seconds)? onPositionChanged;

  const TransportCallbacks({
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onRecord,
    this.onPauseRecording,
    this.onStopRecording,
    this.onCaptureMidi,
    this.onUndo,
    this.onRedo,
    this.onMetronomeToggle,
    this.onPianoToggle,
    this.onLoopPlaybackToggle,
    this.onPunchInToggle,
    this.onPunchOutToggle,
    this.onPositionChanged,
  });
}

/// Grouped callbacks for panel toggle operations
class PanelCallbacks {
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;
  final VoidCallback? onHelpPressed;

  const PanelCallbacks({
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
    this.onHelpPressed,
  });
}

/// Grouped state and callbacks for panel dividers
class DividerState {
  final double sidebarWidth;
  final double mixerWidth;
  final ValueNotifier<bool>? leftDividerNotifier;
  final ValueNotifier<bool>? rightDividerNotifier;
  final Function(double delta)? onSidebarDividerDrag;
  final VoidCallback? onSidebarDividerDoubleClick;
  final VoidCallback? onSidebarDividerDragStart;
  final VoidCallback? onSidebarDividerDragEnd;
  final Function(double delta)? onMixerDividerDrag;
  final VoidCallback? onMixerDividerDoubleClick;
  final VoidCallback? onMixerDividerDragStart;
  final VoidCallback? onMixerDividerDragEnd;

  const DividerState({
    this.sidebarWidth = 208.0,
    this.mixerWidth = 200.0,
    this.leftDividerNotifier,
    this.rightDividerNotifier,
    this.onSidebarDividerDrag,
    this.onSidebarDividerDoubleClick,
    this.onSidebarDividerDragStart,
    this.onSidebarDividerDragEnd,
    this.onMixerDividerDrag,
    this.onMixerDividerDoubleClick,
    this.onMixerDividerDragStart,
    this.onMixerDividerDragEnd,
  });
}
