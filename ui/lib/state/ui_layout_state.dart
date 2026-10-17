import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/project_persistence.dart';

export '../services/project_persistence.dart' show UILayoutData;

/// Snap values for arrangement timeline grid snapping
enum SnapValue {
  off,
  auto, // Smart snap based on zoom level
  bar,
  beat,
  half, // 1/2 beat (1/8th note)
  quarter, // 1/4 beat (1/16th note)
  eighthTriplet, // 1/3 beat (1/8th triplet)
  sixteenthTriplet, // 1/6 beat (1/16th triplet)
}

extension SnapValueExtension on SnapValue {
  String get displayName {
    switch (this) {
      case SnapValue.off:
        return 'Off';
      case SnapValue.auto:
        return 'Auto';
      case SnapValue.bar:
        return 'Bar';
      case SnapValue.beat:
        return 'Beat';
      case SnapValue.half:
        return '1/2';
      case SnapValue.quarter:
        return '1/4';
      case SnapValue.eighthTriplet:
        return '1/8T';
      case SnapValue.sixteenthTriplet:
        return '1/16T';
    }
  }

  /// Get snap resolution in beats (returns 0 for off and auto)
  double get beatsResolution {
    switch (this) {
      case SnapValue.off:
        return 0.0;
      case SnapValue.auto:
        return 0.0; // Handled dynamically based on zoom level
      case SnapValue.bar:
        return 4.0; // 4 beats per bar (4/4 time)
      case SnapValue.beat:
        return 1.0;
      case SnapValue.half:
        return 0.5;
      case SnapValue.quarter:
        return 0.25;
      case SnapValue.eighthTriplet:
        return 1.0 / 3.0;
      case SnapValue.sixteenthTriplet:
        return 1.0 / 6.0;
    }
  }
}

/// Holds UI layout state for panel sizes and visibility.
/// Used by DAWScreen to manage resizable panels.
class UILayoutState extends ChangeNotifier {
  // Panel widths
  double _mixerPanelWidth = sidePanelDefaultWidth;
  double _editorPanelHeight = 250.0;

  // Library panel column widths (stored separately, panel width is computed)
  // The library is one tree; "left" + divider + "right" is the legacy split
  // that projects and settings persist, and only their sum is shown. Keep the
  // left part at its floor so the sum tracks the right part.
  double _libraryLeftColumnWidth = 60.0;
  double _libraryRightColumnWidth = 212.0; // 280 px panel

  // Memory of last size before collapse (for restore on expand)
  double _libraryLastLeftColumnWidth = 60.0;
  double _libraryLastRightColumnWidth = 212.0;
  double _mixerLastWidth = sidePanelDefaultWidth;
  double _editorLastHeight = 250.0;

  // Panel visibility
  bool _isLibraryPanelCollapsed = false;
  bool _isMixerVisible = true;
  bool _isEditorPanelVisible = true;
  bool _isVirtualPianoVisible = false;
  bool _isVirtualPianoEnabled = false;

  // Loop playback state (controls if arrangement playback loops)
  // Off by default; the region is bars 1-4 and only moves when the user
  // drags it (no auto-follow of clip content).
  static const double defaultLoopStartBeats = 0.0;
  static const double defaultLoopEndBeats = 16.0; // bars 1-4 (4/4)
  bool _loopPlaybackEnabled = false;
  double _loopStartBeats = defaultLoopStartBeats;
  double _loopEndBeats = defaultLoopEndBeats;

  // Library and Mixer share one size range (Tyr, 2026-10-17). Below 200 the
  // Mixer drops track names.
  static const double sidePanelMinWidth = 200.0;
  static const double sidePanelDefaultWidth = 280.0;
  static const double sidePanelMaxWidth = 480.0;
  static const double libraryMinWidth = sidePanelMinWidth;
  static const double mixerMinWidth = sidePanelMinWidth;
  static const double mixerMaxWidth = sidePanelMaxWidth;

  // Library panel internal column constraints. The one-tree Library keeps the
  // left column at its default; the right column carries the rest of the
  // shared range.
  static const double libraryLeftColumnMin = 60.0;
  static const double libraryLeftColumnMax = 250.0;
  static const double libraryLeftColumnDefault = 60.0;
  static const double libraryDividerWidth = 8.0;
  static const double libraryRightColumnMin =
      sidePanelMinWidth - libraryLeftColumnDefault - libraryDividerWidth;
  static const double libraryRightColumnMax =
      sidePanelMaxWidth - libraryLeftColumnDefault - libraryDividerWidth;
  static const double editorMinHeight = 150.0;
  static const double editorHardMax = 800.0;
  static const double editorDefaultPct = 0.32;
  static const double editorMaxPct = 0.65;

  // Minimum arrangement view width (protects timeline visibility): the empty
  // project's prompt card is ~330 wide (270 of buttons + padding)
  static const double minArrangementWidth = 340.0;

  // Room each visible side panel's section keeps for its resize divider
  static const double sidePanelDividerWidth = 4.0;

  static double getEditorMaxHeight(double windowHeight) {
    return min(windowHeight * editorMaxPct, editorHardMax);
  }

  // Get default size for initial layout
  static double getEditorDefaultHeight(double windowHeight) {
    return max(
      editorMinHeight,
      min(windowHeight * editorDefaultPct, editorHardMax),
    );
  }

  /// Reset all resizable panels (library, mixer, editor) to their baseline
  /// sizes (the editor's is proportional to the window). Called on new-project creation and on
  /// first launch so every new project opens at a consistent size instead of
  /// inheriting the last drag. Per-project sizes are still restored separately
  /// via [applyLayout] when an existing project is opened.
  void resetSizesToDefaults(double windowWidth, double windowHeight) {
    _setSidePanelDefaults();
    _editorPanelHeight = getEditorDefaultHeight(windowHeight);
    notifyListeners();
  }

  // ============================================
  // ARRANGEMENT WIDTH HELPERS
  // ============================================

  /// Computed total library panel width (left + divider + right)
  double get libraryPanelWidth =>
      _libraryLeftColumnWidth + libraryDividerWidth + _libraryRightColumnWidth;

  void _setSidePanelDefaults() {
    _libraryLeftColumnWidth = libraryLeftColumnDefault;
    _libraryRightColumnWidth =
        sidePanelDefaultWidth - libraryLeftColumnDefault - libraryDividerWidth;
    _mixerPanelWidth = sidePanelDefaultWidth;
  }

  /// The Library and Mixer widths as drawn in a window [windowWidth] wide
  /// (0 while hidden). Each keeps the width the user chose; when both don't
  /// fit beside a [minArrangementWidth] timeline, the wider one gives way
  /// first, then both together, never below [sidePanelMinWidth]. Panels never
  /// close for lack of room: the window's minimum size fits both at minimum.
  ({double library, double mixer}) displayedPanelWidths(double windowWidth) {
    var library = _isLibraryPanelCollapsed ? 0.0 : libraryPanelWidth;
    var mixer = _isMixerVisible ? _mixerPanelWidth : 0.0;
    var excess = library + mixer - _roomForSidePanels(windowWidth);
    if (excess > 0 && library != mixer) {
      // The wider one gives way, down to the narrower one's width
      final floor = max(min(library, mixer), sidePanelMinWidth);
      if (library > mixer) {
        final cut = min(excess, max(0.0, library - floor));
        library -= cut;
        excess -= cut;
      } else {
        final cut = min(excess, max(0.0, mixer - floor));
        mixer -= cut;
        excess -= cut;
      }
    }
    if (excess > 0) {
      final shown = (library > 0 ? 1 : 0) + (mixer > 0 ? 1 : 0);
      final each = excess / shown;
      if (library > 0) library = max(sidePanelMinWidth, library - each);
      if (mixer > 0) mixer = max(sidePanelMinWidth, mixer - each);
    }
    return (library: library, mixer: mixer);
  }

  /// Makes the drawn widths the chosen ones. Called when a drag starts, so a
  /// drag never squeezes the other panel to make room.
  void keepDisplayedWidths(double windowWidth) {
    final shown = displayedPanelWidths(windowWidth);
    if (shown.library > 0) {
      _libraryRightColumnWidth =
          (shown.library - _libraryLeftColumnWidth - libraryDividerWidth).clamp(
            libraryRightColumnMin,
            libraryRightColumnMax,
          );
    }
    if (shown.mixer > 0) _mixerPanelWidth = shown.mixer;
    notifyListeners();
  }

  /// The widest the Library can be dragged: the shared max, or less so the
  /// Mixer (as drawn) and a [minArrangementWidth] timeline still fit.
  double libraryDragMax(double windowWidth) => _dragMax(
    windowWidth,
    otherPanel: displayedPanelWidths(windowWidth).mixer,
  );

  /// The widest the Mixer can be dragged; see [libraryDragMax].
  double mixerDragMax(double windowWidth) => _dragMax(
    windowWidth,
    otherPanel: displayedPanelWidths(windowWidth).library,
  );

  double _dragMax(double windowWidth, {required double otherPanel}) => max(
    sidePanelMinWidth,
    min(sidePanelMaxWidth, _roomForSidePanels(windowWidth) - otherPanel),
  );

  /// Window width left for the visible side panels beside a
  /// [minArrangementWidth] timeline and their dividers.
  double _roomForSidePanels(double windowWidth) {
    final shown =
        (_isLibraryPanelCollapsed ? 0 : 1) + (_isMixerVisible ? 1 : 0);
    return windowWidth - minArrangementWidth - shown * sidePanelDividerWidth;
  }

  // ============================================
  // LIBRARY COLUMN GETTERS AND SETTERS
  // ============================================

  double get libraryLeftColumnWidth => _libraryLeftColumnWidth;
  set libraryLeftColumnWidth(double width) {
    _libraryLeftColumnWidth = width.clamp(
      libraryLeftColumnMin,
      libraryLeftColumnMax,
    );
    notifyListeners();
  }

  double get libraryRightColumnWidth => _libraryRightColumnWidth;
  set libraryRightColumnWidth(double width) {
    _libraryRightColumnWidth = width.clamp(
      libraryRightColumnMin,
      libraryRightColumnMax,
    );
    notifyListeners();
  }

  /// Restores saved widths. The Library is one tree now, so the left column
  /// has no divider of its own: anything over its default moves to the right
  /// column, which the outer divider can shrink. A left column widened in the
  /// old two-column layout would otherwise keep the panel from going narrower.
  void restoreLibraryWidths(double left, double right) {
    final extra = max(0.0, left - libraryLeftColumnDefault);
    _libraryLeftColumnWidth = libraryLeftColumnDefault;
    _libraryRightColumnWidth = (right + extra).clamp(
      libraryRightColumnMin,
      libraryRightColumnMax,
    );
    notifyListeners();
  }

  /// Resize left column (middle divider) - right column absorbs difference
  void resizeLeftColumn(double delta) {
    _libraryLeftColumnWidth = (_libraryLeftColumnWidth + delta).clamp(
      libraryLeftColumnMin,
      libraryLeftColumnMax,
    );
    notifyListeners();
  }

  /// Resize right column (outer divider) - left column stays fixed. Stops at
  /// the minimum: only the Library button hides the panel, so it never
  /// vanishes mid-drag. [maxWidth] caps the whole panel ([libraryDragMax]).
  void resizeRightColumn(double delta, {double maxWidth = sidePanelMaxWidth}) {
    final rightMax = min(
      libraryRightColumnMax,
      maxWidth - _libraryLeftColumnWidth - libraryDividerWidth,
    );
    _libraryRightColumnWidth = (_libraryRightColumnWidth + delta).clamp(
      libraryRightColumnMin,
      max(libraryRightColumnMin, rightMax),
    );
    notifyListeners();
  }

  double get mixerPanelWidth => _mixerPanelWidth;
  set mixerPanelWidth(double width) {
    _mixerPanelWidth = width.clamp(mixerMinWidth, mixerMaxWidth);
    notifyListeners();
  }

  double get editorPanelHeight => _editorPanelHeight;
  set editorPanelHeight(double height) {
    _editorPanelHeight = height.clamp(editorMinHeight, editorHardMax);
    notifyListeners();
  }

  bool get isLibraryPanelCollapsed => _isLibraryPanelCollapsed;
  set isLibraryPanelCollapsed(bool value) {
    _isLibraryPanelCollapsed = value;
    notifyListeners();
  }

  bool get isMixerVisible => _isMixerVisible;
  set isMixerVisible(bool value) {
    _isMixerVisible = value;
    notifyListeners();
  }

  bool get isEditorPanelVisible => _isEditorPanelVisible;
  set isEditorPanelVisible(bool value) {
    _isEditorPanelVisible = value;
    notifyListeners();
  }

  bool get isVirtualPianoVisible => _isVirtualPianoVisible;
  set isVirtualPianoVisible(bool value) {
    _isVirtualPianoVisible = value;
    notifyListeners();
  }

  bool get isVirtualPianoEnabled => _isVirtualPianoEnabled;
  set isVirtualPianoEnabled(bool value) {
    _isVirtualPianoEnabled = value;
    notifyListeners();
  }

  // Collapse methods (remember size, then collapse)
  void collapseLibrary() {
    if (!_isLibraryPanelCollapsed) {
      _libraryLastLeftColumnWidth = _libraryLeftColumnWidth;
      _libraryLastRightColumnWidth = _libraryRightColumnWidth;
      _isLibraryPanelCollapsed = true;
      notifyListeners();
    }
  }

  void collapseMixer() {
    if (_isMixerVisible) {
      _mixerLastWidth = _mixerPanelWidth;
      _isMixerVisible = false;
      notifyListeners();
    }
  }

  void collapseEditor() {
    if (_isEditorPanelVisible) {
      _editorLastHeight = _editorPanelHeight;
      _isEditorPanelVisible = false;
      notifyListeners();
    }
  }

  // Expand methods (restore to last size)
  void expandLibrary() {
    if (_isLibraryPanelCollapsed) {
      _libraryLeftColumnWidth = _libraryLastLeftColumnWidth;
      _libraryRightColumnWidth = _libraryLastRightColumnWidth;
      _isLibraryPanelCollapsed = false;
      notifyListeners();
    }
  }

  void expandMixer() {
    if (!_isMixerVisible) {
      _mixerPanelWidth = _mixerLastWidth;
      _isMixerVisible = true;
      notifyListeners();
    }
  }

  void expandEditor() {
    if (!_isEditorPanelVisible) {
      _editorPanelHeight = _editorLastHeight;
      _isEditorPanelVisible = true;
      notifyListeners();
    }
  }

  // Toggle methods (use collapse/expand with size memory)
  void toggleLibraryPanel() {
    if (_isLibraryPanelCollapsed) {
      expandLibrary();
    } else {
      collapseLibrary();
    }
  }

  void toggleMixer() {
    if (_isMixerVisible) {
      collapseMixer();
    } else {
      expandMixer();
    }
  }

  void toggleEditor() {
    if (_isEditorPanelVisible) {
      collapseEditor();
    } else {
      expandEditor();
    }
  }

  void toggleVirtualPiano() {
    _isVirtualPianoEnabled = !_isVirtualPianoEnabled;
    _isVirtualPianoVisible = _isVirtualPianoEnabled;
    // Don't close the editor panel - just hide the virtual piano keyboard
    notifyListeners();
  }

  void setVirtualPianoEnabled({required bool enabled}) {
    _isVirtualPianoEnabled = enabled;
    _isVirtualPianoVisible = enabled;
    // Don't close the editor panel - just hide the virtual piano keyboard
    notifyListeners();
  }

  void closeEditorAndPiano() {
    _isEditorPanelVisible = false;
    _isVirtualPianoVisible = false;
    _isVirtualPianoEnabled = false;
    notifyListeners();
  }

  // ============================================
  // LOOP PLAYBACK (Arrangement loop - controls if playback loops)
  // ============================================

  bool get loopPlaybackEnabled => _loopPlaybackEnabled;
  set loopPlaybackEnabled(bool value) {
    _loopPlaybackEnabled = value;
    notifyListeners();
  }

  double get loopStartBeats => _loopStartBeats;
  set loopStartBeats(double value) {
    _loopStartBeats = value;
    notifyListeners();
  }

  double get loopEndBeats => _loopEndBeats;
  set loopEndBeats(double value) {
    _loopEndBeats = value;
    notifyListeners();
  }

  /// Toggle loop playback on/off
  void toggleLoopPlayback() {
    _loopPlaybackEnabled = !_loopPlaybackEnabled;
    notifyListeners();
  }

  /// Set loop region (start and end in beats)
  void setLoopRegion(double startBeats, double endBeats) {
    _loopStartBeats = startBeats;
    _loopEndBeats = endBeats;
    notifyListeners();
  }

  /// Reset the loop to its defaults: off, bars 1-4 (called on new project)
  void resetLoop() {
    _loopPlaybackEnabled = false;
    _loopStartBeats = defaultLoopStartBeats;
    _loopEndBeats = defaultLoopEndBeats;
    notifyListeners();
  }

  /// Get loop duration in beats
  double get loopDurationBeats => _loopEndBeats - _loopStartBeats;

  /// Reset all panel sizes and visibility to defaults
  void resetLayout() {
    _setSidePanelDefaults();
    _editorPanelHeight = 250.0;
    _isLibraryPanelCollapsed = false;
    _isMixerVisible = true;
    _isEditorPanelVisible = true;
    notifyListeners();
  }

  /// Apply layout from loaded project
  void applyLayout(UILayoutData layout) {
    // Backwards compatible: split total width into left + right columns
    final totalWidth = layout.libraryWidth.clamp(
      libraryMinWidth,
      sidePanelMaxWidth,
    );
    // The saved left-column split is ignored: the one-tree Library keeps the
    // left column at its default so the outer divider can shrink the whole
    // panel (see [restoreLibraryWidths]). The total width is kept.
    restoreLibraryWidths(
      libraryLeftColumnDefault,
      totalWidth - libraryLeftColumnDefault - libraryDividerWidth,
    );
    _mixerPanelWidth = layout.mixerWidth.clamp(mixerMinWidth, mixerMaxWidth);
    _editorPanelHeight = layout.bottomHeight.clamp(
      editorMinHeight,
      editorHardMax,
    );
    _isLibraryPanelCollapsed = layout.libraryCollapsed;
    _isMixerVisible = !layout.mixerCollapsed;
    // Don't auto-open bottom panel on load
    notifyListeners();
  }

  /// Get current layout for saving (panel sizes only)
  UILayoutData getCurrentLayout() {
    return ProjectPersistence.collect(
      libraryWidth: libraryPanelWidth,
      libraryLeftWidth: _libraryLeftColumnWidth,
      mixerWidth: _mixerPanelWidth,
      bottomHeight: _editorPanelHeight,
      libraryCollapsed: _isLibraryPanelCollapsed,
      mixerCollapsed: !_isMixerVisible,
      bottomCollapsed: !(_isEditorPanelVisible || _isVirtualPianoVisible),
      loopEnabled: loopPlaybackEnabled,
      loopStartBeats: loopStartBeats,
      loopEndBeats: loopEndBeats,
    );
  }
}
