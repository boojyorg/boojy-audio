import 'package:flutter/material.dart';
import '../models/track_automation_data.dart';

/// Manages track automation state including lanes, points, and visibility.
/// Visibility is global (GarageBand model): one toggle shows every track's
/// lane at once.
class AutomationController extends ChangeNotifier {
  // Automation data per track: Map<trackId, Map<parameter, lane>>
  final Map<int, Map<AutomationParameter, TrackAutomationLane>>
  _trackAutomation = {};

  // Global visibility (all tracks at once)
  bool _visible = false;
  AutomationParameter _visibleParameter = AutomationParameter.volume;

  // Getters
  bool get visible => _visible;
  AutomationParameter get visibleParameter => _visibleParameter;

  /// Get all track IDs that have automation data
  Iterable<int> get allTrackIds => _trackAutomation.keys;

  /// Get automation lane for a track/parameter
  TrackAutomationLane? getLane(int trackId, AutomationParameter param) {
    return _trackAutomation[trackId]?[param];
  }

  /// Check if a track has any automation points
  bool hasAutomation(int trackId) {
    final trackLanes = _trackAutomation[trackId];
    if (trackLanes == null) return false;
    return trackLanes.values.any((lane) => lane.hasAutomation);
  }

  /// Check if a specific parameter has automation
  bool hasAutomationForParameter(int trackId, AutomationParameter param) {
    return _trackAutomation[trackId]?[param]?.hasAutomation ?? false;
  }

  /// Show/hide automation lanes for all tracks
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  /// Toggle global automation lane visibility
  void toggleVisible() => visible = !_visible;

  /// Set the visible parameter (Volume, Pan)
  void setVisibleParameter(AutomationParameter param) {
    _visibleParameter = param;
    notifyListeners();
  }

  /// Ensure lanes exist for a track
  void _ensureLanesExist(int trackId) {
    _trackAutomation[trackId] ??= {};
    for (final param in AutomationParameter.values) {
      _trackAutomation[trackId]![param] ??= TrackAutomationLane.empty(
        trackId,
        param,
      );
    }
  }

  // ============================================
  // POINT OPERATIONS
  // ============================================

  /// Add a point to a lane
  void addPoint(int trackId, AutomationParameter param, AutomationPoint point) {
    _ensureLanesExist(trackId);
    _trackAutomation[trackId]![param] = _trackAutomation[trackId]![param]!
        .addPoint(point);
    notifyListeners();
  }

  /// Remove a point from a lane
  void removePoint(int trackId, AutomationParameter param, String pointId) {
    final lane = _trackAutomation[trackId]?[param];
    if (lane == null) return;
    _trackAutomation[trackId]![param] = lane.removePoint(pointId);
    notifyListeners();
  }

  /// Update a point in a lane
  void updatePoint(
    int trackId,
    AutomationParameter param,
    String pointId,
    AutomationPoint newPoint,
  ) {
    final lane = _trackAutomation[trackId]?[param];
    if (lane == null) return;
    _trackAutomation[trackId]![param] = lane.updatePoint(pointId, newPoint);
    notifyListeners();
  }

  /// Clear all points from a lane
  void clearLane(int trackId, AutomationParameter param) {
    final lane = _trackAutomation[trackId]?[param];
    if (lane == null) return;
    _trackAutomation[trackId]![param] = lane.clear();
    notifyListeners();
  }

  /// Clear all automation for a track
  void clearTrackAutomation(int trackId) {
    _trackAutomation.remove(trackId);
    notifyListeners();
  }

  /// Get value at time for a track parameter (linear interpolation)
  double getValueAtTime(int trackId, AutomationParameter param, double time) {
    final lane = _trackAutomation[trackId]?[param];
    if (lane == null) return param.defaultValue;
    return lane.getValueAtTime(time);
  }

  // ============================================
  // TRACK LIFECYCLE
  // ============================================

  /// Handle track deletion - clean up automation
  void onTrackDeleted(int trackId) {
    clearTrackAutomation(trackId);
  }

  /// Handle track duplication - copy automation
  void onTrackDuplicated(int sourceTrackId, int newTrackId) {
    final sourceLanes = _trackAutomation[sourceTrackId];
    if (sourceLanes == null) return;

    _trackAutomation[newTrackId] = {};
    for (final entry in sourceLanes.entries) {
      final param = entry.key;
      final lane = entry.value;
      // Create a new lane with copied points (new IDs generated)
      final newPoints = lane.points
          .map((p) => AutomationPoint(time: p.time, value: p.value))
          .toList();
      _trackAutomation[newTrackId]![param] = TrackAutomationLane(
        trackId: newTrackId,
        parameter: param,
        points: newPoints,
      );
    }
    notifyListeners();
  }

  // ============================================
  // SERIALIZATION
  // ============================================

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() {
    final automation = <String, dynamic>{};
    for (final entry in _trackAutomation.entries) {
      final trackId = entry.key;
      final lanes = entry.value;
      final trackJson = <String, dynamic>{};
      for (final laneEntry in lanes.entries) {
        final param = laneEntry.key;
        final lane = laneEntry.value;
        // Only save lanes that have points
        if (lane.hasAutomation) {
          trackJson[param.name] = lane.toJson();
        }
      }
      if (trackJson.isNotEmpty) {
        automation[trackId.toString()] = trackJson;
      }
    }
    return {'automation': automation};
  }

  /// Load from JSON
  void loadFromJson(Map<String, dynamic>? json) {
    _trackAutomation.clear();
    _visible = false;
    _visibleParameter = AutomationParameter.volume;

    if (json == null) return;

    // Load automation data
    final automation = json['automation'] as Map<String, dynamic>?;
    if (automation == null) return;

    for (final entry in automation.entries) {
      final trackId = int.tryParse(entry.key);
      if (trackId == null) continue;

      final trackData = entry.value as Map<String, dynamic>;
      _trackAutomation[trackId] = {};

      for (final paramEntry in trackData.entries) {
        final paramName = paramEntry.key;
        final laneJson = paramEntry.value as Map<String, dynamic>;

        final param = AutomationParameter.values.firstWhere(
          (p) => p.name == paramName,
          orElse: () => AutomationParameter.volume,
        );

        _trackAutomation[trackId]![param] = TrackAutomationLane.fromJson(
          laneJson,
        );
      }
    }

    notifyListeners();
  }

  /// Clear all state (for new project)
  void clear() {
    _trackAutomation.clear();
    _visible = false;
    _visibleParameter = AutomationParameter.volume;
    notifyListeners();
  }

  @override
  void dispose() {
    _trackAutomation.clear();
    super.dispose();
  }
}
