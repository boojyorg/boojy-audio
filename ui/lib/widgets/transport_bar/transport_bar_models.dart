import 'package:flutter/foundation.dart';

/// Height of the top bar. The bar's own `Container` and the spacer that
/// reserves room for it under the DAW screen's Stack both read this, so they
/// can never drift apart.
const double kTopBarHeight = 54.0;

/// Grouped callbacks for file menu operations
class FileMenuCallbacks {
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onExportAudio;
  final VoidCallback? onAppSettings;
  final VoidCallback? onCloseProject;

  /// Open the Start screen (an "Audio" menu item).
  final VoidCallback? onStartScreen;

  /// Show the keyboard-shortcuts sheet (an "Audio" menu item; also the ? key).
  final VoidCallback? onKeyboardShortcuts;

  const FileMenuCallbacks({
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onExportAudio,
    this.onAppSettings,
    this.onCloseProject,
    this.onStartScreen,
    this.onKeyboardShortcuts,
  });
}

/// Grouped callbacks for transport play/record operations
class TransportCallbacks {
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;

  /// Pressed record with nothing armed — create a new track of this type,
  /// arm it, and start recording (with count-in). Lets record always be live.
  final VoidCallback? onRecordNewMidiTrack;
  final VoidCallback? onRecordNewAudioTrack;
  final VoidCallback? onPauseRecording;
  final VoidCallback? onStopRecording;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onPianoToggle;
  final VoidCallback? onLoopPlaybackToggle;
  final Function(double seconds)? onPositionChanged;

  /// Capture what was played unarmed — opens the CaptureMidiDialog.
  /// Backend is in daw_clip_mixin.dart:captureMidi(); the button sits right
  /// of Record.
  final VoidCallback? onCaptureMidi;

  const TransportCallbacks({
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onRecord,
    this.onRecordNewMidiTrack,
    this.onRecordNewAudioTrack,
    this.onPauseRecording,
    this.onStopRecording,
    this.onUndo,
    this.onRedo,
    this.onMetronomeToggle,
    this.onPianoToggle,
    this.onLoopPlaybackToggle,
    this.onPositionChanged,
    this.onCaptureMidi,
  });
}

/// Grouped callbacks for panel toggle operations
class PanelCallbacks {
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;

  const PanelCallbacks({
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
  });
}
