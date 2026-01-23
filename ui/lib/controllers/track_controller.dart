import 'package:flutter/material.dart';
import '../models/instrument_data.dart';
import '../utils/track_colors.dart';

/// Manages track state including heights, colors, selection, and instruments.
class TrackController extends ChangeNotifier {
  // Track selection (single and multi)
  int? _selectedTrackId;
  final Set<int> _selectedTrackIds = {};

  // Clip area height state (synced between mixer and timeline)
  final Map<int, double> _clipHeights = {};
  double _masterTrackHeight = 50.0;

  // Automation lane height state (per-track, when automation is visible)
  final Map<int, double> _automationHeights = {};

  // Clip height constraints
  static const double defaultClipHeight = 100.0;
  static const double minClipHeight = 40.0;
  static const double maxClipHeight = 400.0;

  // Automation height constraints
  static const double defaultAutomationHeight = 60.0;
  static const double minAutomationHeight = 40.0;
  static const double maxAutomationHeight = 200.0;

  // Track color state (auto-detected with manual override)
  final Map<int, Color> _trackColorOverrides = {};

  // Track instruments
  final Map<int, InstrumentData> _trackInstruments = {};

  // Track name user-edited state (false = auto-generated, true = user edited)
  final Map<int, bool> _trackNameUserEdited = {};

  // Track display order (list of track IDs, excluding Master)
  List<int> _trackOrder = [];

  // Getters
  int? get selectedTrackId => _selectedTrackId;
  Set<int> get selectedTrackIds => Set.unmodifiable(_selectedTrackIds);
  List<int> get trackOrder => List.unmodifiable(_trackOrder);
  Map<int, double> get clipHeights => Map.unmodifiable(_clipHeights);
  Map<int, double> get automationHeights => Map.unmodifiable(_automationHeights);
  double get masterTrackHeight => _masterTrackHeight;
  Map<int, InstrumentData> get trackInstruments => Map.unmodifiable(_trackInstruments);

  /// Check if track name was manually edited by user
  bool isTrackNameUserEdited(int trackId) {
    return _trackNameUserEdited[trackId] ?? false;
  }

  /// Mark track name as user-edited or auto-generated
  void markTrackNameUserEdited(int trackId, {required bool edited}) {
    _trackNameUserEdited[trackId] = edited;
    notifyListeners();
  }

  /// Initialize a new track with auto-generated name state
  void initTrackNameState(int trackId) {
    _trackNameUserEdited[trackId] = false;
  }

  /// Get clip area height, returning default if not set
  double getClipHeight(int trackId) {
    return _clipHeights[trackId] ?? defaultClipHeight;
  }

  /// Set clip area height
  void setClipHeight(int trackId, double height) {
    _clipHeights[trackId] = height.clamp(minClipHeight, maxClipHeight);
    notifyListeners();
  }

  /// Get automation lane height, returning default if not set
  double getAutomationHeight(int trackId) {
    return _automationHeights[trackId] ?? defaultAutomationHeight;
  }

  /// Set automation lane height
  void setAutomationHeight(int trackId, double height) {
    _automationHeights[trackId] = height.clamp(minAutomationHeight, maxAutomationHeight);
    notifyListeners();
  }

  /// Set master track height
  void setMasterTrackHeight(double height) {
    _masterTrackHeight = height.clamp(minClipHeight, maxClipHeight);
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

  /// Select a track (with optional multi-select via shift key)
  void selectTrack(int? trackId, {bool isShiftHeld = false}) {
    if (trackId == null) {
      _selectedTrackId = null;
      _selectedTrackIds.clear();
      notifyListeners();
      return;
    }

    if (isShiftHeld) {
      // Multi-select: toggle this track in the selection set
      if (_selectedTrackIds.contains(trackId)) {
        _selectedTrackIds.remove(trackId);
        // Update primary selection to another selected track, or null
        _selectedTrackId = _selectedTrackIds.isNotEmpty ? _selectedTrackIds.first : null;
      } else {
        _selectedTrackIds.add(trackId);
        // If no primary selection, make this the primary
        _selectedTrackId ??= trackId;
      }
    } else {
      // Single select: clear multi-selection and select only this track
      _selectedTrackIds.clear();
      _selectedTrackIds.add(trackId);
      _selectedTrackId = trackId;
    }
    notifyListeners();
  }

  /// Update track order from a list of track IDs
  /// This syncs the order when tracks are loaded from engine
  void syncTrackOrder(List<int> trackIds) {
    // Keep existing order for tracks that still exist, add new ones at end
    final existingIds = trackIds.toSet();
    final newOrder = <int>[];

    // Preserve existing order for tracks that still exist
    for (final id in _trackOrder) {
      if (existingIds.contains(id)) {
        newOrder.add(id);
      }
    }

    // Add any new tracks that weren't in the order
    for (final id in trackIds) {
      if (!newOrder.contains(id)) {
        newOrder.add(id);
      }
    }

    _trackOrder = newOrder;
    // Don't notify here - this is called during load, caller will handle rebuild
  }

  /// Reorder tracks (from drag-and-drop)
  void reorderTrack(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _trackOrder.length) return;
    if (newIndex < 0 || newIndex >= _trackOrder.length) return;

    final trackId = _trackOrder.removeAt(oldIndex);
    _trackOrder.insert(newIndex, trackId);
    notifyListeners();
  }

  /// Get ordered list of track IDs
  List<int> getOrderedTrackIds() {
    return List.from(_trackOrder);
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
    _clipHeights.remove(trackId);
    _automationHeights.remove(trackId);
    _trackColorOverrides.remove(trackId);
    _trackNameUserEdited.remove(trackId);
    _selectedTrackIds.remove(trackId);

    if (_selectedTrackId == trackId) {
      _selectedTrackId = _selectedTrackIds.isNotEmpty ? _selectedTrackIds.first : null;
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

    // Copy clip height
    if (_clipHeights.containsKey(sourceTrackId)) {
      _clipHeights[newTrackId] = _clipHeights[sourceTrackId]!;
    }

    // Copy automation height
    if (_automationHeights.containsKey(sourceTrackId)) {
      _automationHeights[newTrackId] = _automationHeights[sourceTrackId]!;
    }

    // Copy color override if present
    if (_trackColorOverrides.containsKey(sourceTrackId)) {
      _trackColorOverrides[newTrackId] = _trackColorOverrides[sourceTrackId]!;
    }

    // Copy user-edited name state
    if (_trackNameUserEdited.containsKey(sourceTrackId)) {
      _trackNameUserEdited[newTrackId] = _trackNameUserEdited[sourceTrackId]!;
    }

    notifyListeners();
  }

  /// Clear all track state (for new project)
  void clear() {
    _selectedTrackId = null;
    _selectedTrackIds.clear();
    _clipHeights.clear();
    _automationHeights.clear();
    _trackColorOverrides.clear();
    _trackInstruments.clear();
    _trackNameUserEdited.clear();
    _trackOrder.clear();
    _masterTrackHeight = 50.0;
    notifyListeners();
  }

  @override
  void dispose() {
    // Clear all state before disposing
    _selectedTrackIds.clear();
    _clipHeights.clear();
    _automationHeights.clear();
    _trackColorOverrides.clear();
    _trackInstruments.clear();
    _trackNameUserEdited.clear();
    _trackOrder.clear();
    super.dispose();
  }
}
