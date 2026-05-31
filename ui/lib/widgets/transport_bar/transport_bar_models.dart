import 'package:flutter/foundation.dart';

/// Top-bar layout variants explored live via the dev "UI Labs" switcher
/// (Cmd+Shift+L). Phase 3 ships A (inline) and B (LCD panel); C/D follow later.
enum TopBarVariant {
  /// A — one row, position promoted to a hero-sized readout. Fits the 54px bar.
  inline,

  /// B — bordered "LCD panel": position over dim tempo/sig satellites. Costs
  /// ~14px of bar height in exchange for the hardware-instrument look.
  lcd,
}

extension TopBarVariantInfo on TopBarVariant {
  /// Bar height the variant needs. The bar's own `Container` and the spacer
  /// that reserves room for it under the Stack both read this, so they can
  /// never drift apart.
  double get barHeight {
    switch (this) {
      case TopBarVariant.inline:
        return 54.0;
      case TopBarVariant.lcd:
        return 68.0;
    }
  }

  /// Letter + name shown on the UI Labs chip.
  String get labLabel {
    switch (this) {
      case TopBarVariant.inline:
        return 'A · Inline';
      case TopBarVariant.lcd:
        return 'B · LCD Panel';
    }
  }

  /// Persisted token (matches the enum identifier).
  String get token => name;
}

/// Parse a persisted token back to a variant, defaulting to [TopBarVariant.inline]
/// so an unknown or removed value can never crash startup.
TopBarVariant topBarVariantFromName(String? s) {
  switch (s) {
    case 'lcd':
      return TopBarVariant.lcd;
    default:
      return TopBarVariant.inline;
  }
}

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
