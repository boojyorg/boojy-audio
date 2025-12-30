import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/project_manager.dart';

export '../services/project_manager.dart' show UILayoutData;

/// Holds UI layout state for panel sizes and visibility.
/// Used by DAWScreen to manage resizable panels.
class UILayoutState extends ChangeNotifier {
  // Panel widths
  double _libraryPanelWidth = 200.0;
  double _mixerPanelWidth = 380.0;
  double _editorPanelHeight = 250.0;

  // Memory of last size before collapse (for restore on expand)
  double _libraryLastWidth = 200.0;
  double _mixerLastWidth = 380.0;
  double _editorLastHeight = 250.0;

  // Panel visibility
  bool _isLibraryPanelCollapsed = false;
  bool _isMixerVisible = true;
  bool _isEditorPanelVisible = true;
  bool _isVirtualPianoVisible = false;
  bool _isVirtualPianoEnabled = false;

  // Fixed minimums (usability floor)
  static const double libraryMinWidth = 150.0;
  static const double mixerMinWidth = 200.0;
  static const double editorMinHeight = 150.0;

  // Hard maximums (prevent absurdly large panels on big screens)
  static const double libraryHardMax = 400.0;
  static const double mixerHardMax = 500.0;
  static const double editorHardMax = 600.0;

  // Percentage-based constraints
  static const double libraryDefaultPct = 0.15;
  static const double libraryMaxPct = 0.30;
  static const double mixerDefaultPct = 0.25;
  static const double mixerMaxPct = 0.35;
  static const double editorDefaultPct = 0.35;
  static const double editorMaxPct = 0.55;

  // Auto-collapse thresholds (window width triggers)
  static const double autoCollapseLibraryWidth = 900.0;
  static const double autoCollapseMixerWidth = 1000.0;

  // Collapse threshold = min (snap collapse when dragged below min)
  static double get libraryCollapseThreshold => libraryMinWidth;
  static double get mixerCollapseThreshold => mixerMinWidth;
  static double get editorCollapseThreshold => editorMinHeight;

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

  // Getters and Setters
  double get libraryPanelWidth => _libraryPanelWidth;
  set libraryPanelWidth(double width) {
    _libraryPanelWidth = width.clamp(libraryMinWidth, libraryHardMax);
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
  void setLibraryPanelWidth(double width) {
    libraryPanelWidth = width;
  }

  void setMixerPanelWidth(double width) {
    mixerPanelWidth = width;
  }

  void setEditorPanelHeight(double height) {
    editorPanelHeight = height;
  }

  // Collapse methods (remember size, then collapse)
  void collapseLibrary() {
    if (!_isLibraryPanelCollapsed) {
      _libraryLastWidth = _libraryPanelWidth;
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
      _libraryPanelWidth = _libraryLastWidth;
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
    if (_isVirtualPianoEnabled) {
      _isVirtualPianoVisible = true;
    } else {
      _isVirtualPianoVisible = false;
      _isEditorPanelVisible = false;
    }
    notifyListeners();
  }

  void setVirtualPianoEnabled(bool enabled) {
    _isVirtualPianoEnabled = enabled;
    _isVirtualPianoVisible = enabled;
    if (!enabled) {
      _isEditorPanelVisible = false;
    }
    notifyListeners();
  }

  void setEditorPanelVisible(bool visible) {
    _isEditorPanelVisible = visible;
    notifyListeners();
  }

  void setLibraryPanelCollapsed(bool collapsed) {
    _isLibraryPanelCollapsed = collapsed;
    notifyListeners();
  }

  void setMixerVisible(bool visible) {
    _isMixerVisible = visible;
    notifyListeners();
  }

  void closeEditorAndPiano() {
    _isEditorPanelVisible = false;
    _isVirtualPianoVisible = false;
    _isVirtualPianoEnabled = false;
    notifyListeners();
  }

  /// Reset all panel sizes and visibility to defaults
  void resetLayout() {
    _libraryPanelWidth = 200.0;
    _mixerPanelWidth = 380.0;
    _editorPanelHeight = 250.0;
    _isLibraryPanelCollapsed = false;
    _isMixerVisible = true;
    _isEditorPanelVisible = true;
    notifyListeners();
  }

  /// Apply layout from loaded project
  void applyLayout(UILayoutData layout) {
    _libraryPanelWidth = layout.libraryWidth.clamp(libraryMinWidth, libraryHardMax);
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
      libraryWidth: _libraryPanelWidth,
      mixerWidth: _mixerPanelWidth,
      bottomHeight: _editorPanelHeight,
      libraryCollapsed: _isLibraryPanelCollapsed,
      mixerCollapsed: !_isMixerVisible,
      bottomCollapsed: !(_isEditorPanelVisible || _isVirtualPianoVisible),
    );
  }
}
