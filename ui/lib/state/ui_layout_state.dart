import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/project_manager.dart';

export '../services/project_manager.dart' show UILayoutData;

/// Snap values for arrangement timeline grid snapping
enum SnapValue {
  off,
  bar,
  beat,
  half,      // 1/2 beat (1/8th note)
  quarter,   // 1/4 beat (1/16th note)
}

extension SnapValueExtension on SnapValue {
  String get displayName {
    switch (this) {
      case SnapValue.off:
        return 'Off';
      case SnapValue.bar:
        return 'Bar';
      case SnapValue.beat:
        return 'Beat';
      case SnapValue.half:
        return '1/2';
      case SnapValue.quarter:
        return '1/4';
    }
  }

  /// Get snap resolution in beats (returns 0 for off)
  double get beatsResolution {
    switch (this) {
      case SnapValue.off:
        return 0.0;
      case SnapValue.bar:
        return 4.0; // 4 beats per bar (4/4 time)
      case SnapValue.beat:
        return 1.0;
      case SnapValue.half:
        return 0.5;
      case SnapValue.quarter:
        return 0.25;
    }
  }
}

/// Holds UI layout state for panel sizes and visibility.
/// Used by DAWScreen to manage resizable panels.
class UILayoutState extends ChangeNotifier {
  // Panel widths
  double _mixerPanelWidth = 380.0;
  double _editorPanelHeight = 250.0;

  // Library panel column widths (stored separately, panel width is computed)
  double _libraryLeftColumnWidth = 130.0;
  double _libraryRightColumnWidth = 170.0;

  // Memory of last size before collapse (for restore on expand)
  double _libraryLastLeftColumnWidth = 130.0;
  double _libraryLastRightColumnWidth = 170.0;
  double _mixerLastWidth = 380.0;
  double _editorLastHeight = 250.0;

  // Panel visibility
  bool _isLibraryPanelCollapsed = false;
  bool _isMixerVisible = true;
  bool _isEditorPanelVisible = true;
  bool _isVirtualPianoVisible = false;
  bool _isVirtualPianoEnabled = false;

  // Arrangement snap setting (independent from Piano Roll snap)
  SnapValue _arrangementSnap = SnapValue.bar;

  // Loop playback state (controls if arrangement playback loops)
  bool _loopPlaybackEnabled = true; // Loop ON by default
  double _loopStartBeats = 0.0;
  double _loopEndBeats = 4.0; // Default 1 bar (4 beats)

  // Auto-follow: loop region automatically tracks longest clip
  // Set to false when user manually adjusts loop region
  bool _loopAutoFollow = true;

  // Fixed minimums (usability floor)
  static const double libraryMinWidth = 208.0; // left min + divider + right min

  // Library panel internal column constraints
  static const double libraryLeftColumnMin = 100.0;
  static const double libraryLeftColumnMax = 250.0;
  static const double libraryLeftColumnDefault = 130.0;
  static const double libraryRightColumnMin = 100.0;
  static const double libraryRightColumnMax = 400.0;
  static const double libraryDividerWidth = 8.0;
  static const double mixerMinWidth = 200.0;
  static const double editorMinHeight = 150.0;

  // Hard maximums (prevent absurdly large panels on big screens)
  static const double libraryHardMax = 600.0;
  static const double mixerHardMax = 500.0;
  static const double editorHardMax = 600.0;

  // Percentage-based constraints
  static const double libraryDefaultPct = 0.15;
  static const double libraryMaxPct = 0.30;
  static const double mixerDefaultPct = 0.25;
  static const double mixerMaxPct = 0.35;
  static const double editorDefaultPct = 0.35;
  static const double editorMaxPct = 0.55;

  // Minimum arrangement view width (protects timeline visibility)
  static const double minArrangementWidth = 200.0;

  // Collapsed library width (icon strip)
  static const double libraryCollapsedWidth = 40.0;

  // Collapse threshold = separate from min (requires dragging further to collapse)
  static double get libraryCollapseThreshold => libraryMinWidth - 50.0;
  static double get mixerCollapseThreshold => mixerMinWidth - 50.0;
  static double get editorCollapseThreshold => editorMinHeight - 50.0;

  // Calculate actual max based on window size (percentage OR hard max, whichever is smaller)
  static double getLibraryMaxWidth(double windowWidth) {
    return min(windowWidth * libraryMaxPct, libraryHardMax);
  }

  static double getMixerMaxWidth(double windowWidth) {
    return min(windowWidth * mixerMaxPct, mixerHardMax);
  }

  static double getEditorMaxHeight(double windowHeight) {
    return min(windowHeight * editorMaxPct, editorHardMax);
  }

  // Get default size for initial layout
  static double getLibraryDefaultWidth(double windowWidth) {
    return max(libraryMinWidth, min(windowWidth * libraryDefaultPct, libraryHardMax));
  }

  static double getMixerDefaultWidth(double windowWidth) {
    return max(mixerMinWidth, min(windowWidth * mixerDefaultPct, mixerHardMax));
  }

  static double getEditorDefaultHeight(double windowHeight) {
    return max(editorMinHeight, min(windowHeight * editorDefaultPct, editorHardMax));
  }

  // ============================================
  // ARRANGEMENT WIDTH HELPERS
  // ============================================

  /// Computed total library panel width (left + divider + right)
  double get libraryPanelWidth =>
      _libraryLeftColumnWidth + libraryDividerWidth + _libraryRightColumnWidth;

  /// Get current arrangement view width
  double getArrangementWidth(double windowWidth) {
    final libraryWidth = _isLibraryPanelCollapsed ? libraryCollapsedWidth : libraryPanelWidth;
    final mixerWidth = _isMixerVisible ? _mixerPanelWidth : 0.0;
    return windowWidth - libraryWidth - mixerWidth;
  }

  /// Check if there's room to show library panel (when expanding from collapsed)
  bool canShowLibrary(double windowWidth) {
    final mixerWidth = _isMixerVisible ? _mixerPanelWidth : 0.0;
    final libraryWidth = libraryPanelWidth; // Width it would be if expanded
    final arrangementWidth = windowWidth - libraryWidth - mixerWidth;
    return arrangementWidth >= minArrangementWidth;
  }

  /// Check if there's room to show mixer panel
  bool canShowMixer(double windowWidth) {
    final libraryWidth = _isLibraryPanelCollapsed ? libraryCollapsedWidth : libraryPanelWidth;
    final mixerWidth = _mixerPanelWidth; // Width it would be if expanded
    final arrangementWidth = windowWidth - libraryWidth - mixerWidth;
    return arrangementWidth >= minArrangementWidth;
  }

  // ============================================
  // LIBRARY COLUMN GETTERS AND SETTERS
  // ============================================

  double get libraryLeftColumnWidth => _libraryLeftColumnWidth;
  set libraryLeftColumnWidth(double width) {
    _libraryLeftColumnWidth = width.clamp(libraryLeftColumnMin, libraryLeftColumnMax);
    notifyListeners();
  }

  double get libraryRightColumnWidth => _libraryRightColumnWidth;
  set libraryRightColumnWidth(double width) {
    _libraryRightColumnWidth = width.clamp(libraryRightColumnMin, libraryRightColumnMax);
    notifyListeners();
  }

  /// Resize left column (middle divider) - right column absorbs difference
  void resizeLeftColumn(double delta) {
    _libraryLeftColumnWidth = (_libraryLeftColumnWidth + delta)
        .clamp(libraryLeftColumnMin, libraryLeftColumnMax);
    notifyListeners();
  }

  /// Resize right column (outer divider) - left column stays fixed
  void resizeRightColumn(double delta) {
    final newRight = _libraryRightColumnWidth + delta;
    if (newRight < libraryRightColumnMin - 50) {
      // Below collapse threshold, collapse the panel
      collapseLibrary();
      return;
    }
    _libraryRightColumnWidth = newRight.clamp(libraryRightColumnMin, libraryRightColumnMax);
    notifyListeners();
  }

  double get mixerPanelWidth => _mixerPanelWidth;
  set mixerPanelWidth(double width) {
    _mixerPanelWidth = width.clamp(mixerMinWidth, mixerHardMax);
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

  // Setters with clamping (method style - for explicit calls)
  void setMixerPanelWidth(double width) {
    mixerPanelWidth = width;
  }

  void setEditorPanelHeight(double height) {
    editorPanelHeight = height;
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

  void setEditorPanelVisible({required bool visible}) {
    _isEditorPanelVisible = visible;
    notifyListeners();
  }

  void setLibraryPanelCollapsed({required bool collapsed}) {
    _isLibraryPanelCollapsed = collapsed;
    notifyListeners();
  }

  void setMixerVisible({required bool visible}) {
    _isMixerVisible = visible;
    notifyListeners();
  }

  void closeEditorAndPiano() {
    _isEditorPanelVisible = false;
    _isVirtualPianoVisible = false;
    _isVirtualPianoEnabled = false;
    notifyListeners();
  }

  // ============================================
  // ARRANGEMENT SNAP
  // ============================================

  SnapValue get arrangementSnap => _arrangementSnap;
  set arrangementSnap(SnapValue value) {
    _arrangementSnap = value;
    notifyListeners();
  }

  void setArrangementSnap(SnapValue value) {
    arrangementSnap = value;
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
  /// If manual is true, disables auto-follow (user explicitly set the loop)
  void setLoopRegion(double startBeats, double endBeats, {bool manual = false}) {
    if (manual) {
      _loopAutoFollow = false; // User override - disable auto-follow
    }
    _loopStartBeats = startBeats;
    _loopEndBeats = endBeats;
    notifyListeners();
  }

  /// Whether the loop region auto-follows the longest clip
  bool get loopAutoFollow => _loopAutoFollow;

  /// Reset loop auto-follow (called on new project)
  void resetLoopAutoFollow() {
    _loopAutoFollow = true;
    _loopStartBeats = 0.0;
    _loopEndBeats = 4.0;
    notifyListeners();
  }

  /// Get loop duration in beats
  double get loopDurationBeats => _loopEndBeats - _loopStartBeats;

  /// Reset all panel sizes and visibility to defaults
  void resetLayout() {
    _libraryLeftColumnWidth = libraryLeftColumnDefault;
    _libraryRightColumnWidth = libraryRightColumnMin;
    _mixerPanelWidth = 380.0;
    _editorPanelHeight = 250.0;
    _isLibraryPanelCollapsed = false;
    _isMixerVisible = true;
    _isEditorPanelVisible = true;
    notifyListeners();
  }

  /// Apply layout from loaded project
  void applyLayout(UILayoutData layout) {
    // Backwards compatible: split total width into left + right columns
    final totalWidth = layout.libraryWidth.clamp(libraryMinWidth, libraryHardMax);
    _libraryLeftColumnWidth = libraryLeftColumnDefault;
    _libraryRightColumnWidth = (totalWidth - _libraryLeftColumnWidth - libraryDividerWidth)
        .clamp(libraryRightColumnMin, libraryRightColumnMax);
    _mixerPanelWidth = layout.mixerWidth.clamp(mixerMinWidth, mixerHardMax);
    _editorPanelHeight = layout.bottomHeight.clamp(editorMinHeight, editorHardMax);
    _isLibraryPanelCollapsed = layout.libraryCollapsed;
    _isMixerVisible = !layout.mixerCollapsed;
    // Don't auto-open bottom panel on load
    notifyListeners();
  }

  /// Get current layout for saving
  UILayoutData getCurrentLayout() {
    return UILayoutData(
      libraryWidth: libraryPanelWidth, // Use computed getter
      mixerWidth: _mixerPanelWidth,
      bottomHeight: _editorPanelHeight,
      libraryCollapsed: _isLibraryPanelCollapsed,
      mixerCollapsed: !_isMixerVisible,
      bottomCollapsed: !(_isEditorPanelVisible || _isVirtualPianoVisible),
    );
  }
}
