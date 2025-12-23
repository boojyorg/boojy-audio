import 'package:flutter/material.dart';
import '../models/instrument_data.dart';
import '../utils/track_colors.dart';

/// Manages track state including heights, colors, selection, and instruments.
class TrackController extends ChangeNotifier {
  // Track selection
  int? _selectedTrackId;

  // Track height state (synced between mixer and timeline)
  final Map<int, double> _trackHeights = {};
  double _masterTrackHeight = 60.0;

  // Height constraints
  static const double defaultTrackHeight = 100.0;
  static const double minTrackHeight = 50.0;
  static const double maxTrackHeight = 300.0;

  // Track color state (auto-detected with manual override)
  final Map<int, Color> _trackColorOverrides = {};

  // Track instruments
  final Map<int, InstrumentData> _trackInstruments = {};

  // Getters
  int? get selectedTrackId => _selectedTrackId;
  Map<int, double> get trackHeights => Map.unmodifiable(_trackHeights);
  double get masterTrackHeight => _masterTrackHeight;
  Map<int, InstrumentData> get trackInstruments => Map.unmodifiable(_trackInstruments);

  /// Get track height, returning default if not set
  double getTrackHeight(int trackId) {
    return _trackHeights[trackId] ?? defaultTrackHeight;
  }

  /// Set track height
  void setTrackHeight(int trackId, double height) {
    _trackHeights[trackId] = height.clamp(minTrackHeight, maxTrackHeight);
    notifyListeners();
  }

  /// Set master track height
  void setMasterTrackHeight(double height) {
    _masterTrackHeight = height.clamp(minTrackHeight, maxTrackHeight);
    notifyListeners();
  }

  /// Get track color with auto-detection (respects manual overrides)
  Color getTrackColor(int trackId, String trackName, String trackType) {
    // Check for user override first
    if (_trackColorOverrides.containsKey(trackId)) {
      return _trackColorOverrides[trackId]!;
    }

    // Get instrument/plugin info for detection
    final instrument = _trackInstruments[trackId];
    final instrumentType = instrument?.type;
    final pluginName = instrument?.pluginName;

    // Auto-detect category based on keywords
    final category = TrackColors.detectCategory(
      trackName,
      trackType,
      instrumentType: instrumentType,
      pluginName: pluginName,
    );

    return TrackColors.getColorForCategory(category);
  }

  /// Set track color (manual override)
  void setTrackColor(int trackId, Color color) {
    _trackColorOverrides[trackId] = color;
    notifyListeners();
  }

  /// Clear track color override (revert to auto-detection)
  void clearTrackColorOverride(int trackId) {
    _trackColorOverrides.remove(trackId);
    notifyListeners();
  }

  /// Select a track
  void selectTrack(int? trackId) {
    _selectedTrackId = trackId;
    notifyListeners();
  }

  /// Set instrument for a track
  void setTrackInstrument(int trackId, InstrumentData instrument) {
    _trackInstruments[trackId] = instrument;
    notifyListeners();
  }

  /// Get instrument for a track
  InstrumentData? getTrackInstrument(int trackId) {
    return _trackInstruments[trackId];
  }

  /// Check if track has an instrument assigned
  bool hasInstrument(int trackId) {
    return _trackInstruments.containsKey(trackId);
  }

  /// Remove instrument mapping for a track
  void removeTrackInstrument(int trackId) {
    _trackInstruments.remove(trackId);
    notifyListeners();
  }

  /// Handle track deletion - clean up all related state
  void onTrackDeleted(int trackId) {
    _trackInstruments.remove(trackId);
    _trackHeights.remove(trackId);
    _trackColorOverrides.remove(trackId);

    if (_selectedTrackId == trackId) {
      _selectedTrackId = null;
    }
    notifyListeners();
  }

  /// Handle track duplication - copy state from source to new track
  void onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy instrument mapping
    if (_trackInstruments.containsKey(sourceTrackId)) {
      final sourceInstrument = _trackInstruments[sourceTrackId]!;
      _trackInstruments[newTrackId] = InstrumentData(
        trackId: newTrackId,
        type: sourceInstrument.type,
        parameters: Map.from(sourceInstrument.parameters),
      );
    }

    // Copy track height
    if (_trackHeights.containsKey(sourceTrackId)) {
      _trackHeights[newTrackId] = _trackHeights[sourceTrackId]!;
    }

    // Copy color override if present
    if (_trackColorOverrides.containsKey(sourceTrackId)) {
      _trackColorOverrides[newTrackId] = _trackColorOverrides[sourceTrackId]!;
    }

    notifyListeners();
  }

  /// Clear all track state (for new project)
  void clear() {
    _selectedTrackId = null;
    _trackHeights.clear();
    _trackColorOverrides.clear();
    _trackInstruments.clear();
    _masterTrackHeight = 60.0;
    notifyListeners();
  }
}
