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

  // Panel visibility
  bool _isLibraryPanelCollapsed = false;
  bool _isMixerVisible = true;
  bool _isEditorPanelVisible = true;
  bool _isVirtualPianoVisible = false;
  bool _isVirtualPianoEnabled = false;

  // Constraints
  static const double libraryMinWidth = 40.0;
  static const double libraryMaxWidth = 400.0;
  static const double mixerMinWidth = 200.0;
  static const double mixerMaxWidth = 600.0;
  static const double editorMinHeight = 100.0;
  static const double editorMaxHeight = 500.0;

  // Getters and Setters
  double get libraryPanelWidth => _libraryPanelWidth;
  set libraryPanelWidth(double width) {
    _libraryPanelWidth = width.clamp(libraryMinWidth, libraryMaxWidth);
    notifyListeners();
  }

  double get mixerPanelWidth => _mixerPanelWidth;
  set mixerPanelWidth(double width) {
    _mixerPanelWidth = width.clamp(mixerMinWidth, mixerMaxWidth);
    notifyListeners();
  }

  double get editorPanelHeight => _editorPanelHeight;
  set editorPanelHeight(double height) {
    _editorPanelHeight = height.clamp(editorMinHeight, editorMaxHeight);
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

  // Toggle methods
  void toggleLibraryPanel() {
    _isLibraryPanelCollapsed = !_isLibraryPanelCollapsed;
    notifyListeners();
  }

  void toggleMixer() {
    _isMixerVisible = !_isMixerVisible;
    notifyListeners();
  }

  void toggleEditor() {
    _isEditorPanelVisible = !_isEditorPanelVisible;
    notifyListeners();
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
    _libraryPanelWidth = layout.libraryWidth.clamp(libraryMinWidth, libraryMaxWidth);
    _mixerPanelWidth = layout.mixerWidth.clamp(mixerMinWidth, mixerMaxWidth);
    _editorPanelHeight = layout.bottomHeight.clamp(editorMinHeight, editorMaxHeight);
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
