import 'package:flutter/material.dart';

import '../models/clip_data.dart';
import '../models/project_view_state.dart';

/// UI-only project data saved alongside the Rust engine's `project.json`.
///
/// Stored in `ui_layout.json` inside each `.audio` project folder.
/// See [ProjectPersistence.collect] for the canonical field checklist.
class UILayoutData {
  final double libraryWidth;
  final double mixerWidth;
  final double bottomHeight;
  final bool libraryCollapsed;
  final bool mixerCollapsed;
  final bool bottomCollapsed;
  final ProjectViewState? viewState;
  final List<ClipData>? audioClips;
  final Map<String, dynamic>? automationData;
  final Map<int, int>? trackColors;
  final bool? loopEnabled;
  final double? loopStartBeats;
  final double? loopEndBeats;

  const UILayoutData({
    this.libraryWidth = 200.0,
    this.mixerWidth = 380.0,
    this.bottomHeight = 250.0,
    this.libraryCollapsed = false,
    this.mixerCollapsed = false,
    this.bottomCollapsed = true,
    this.viewState,
    this.audioClips,
    this.automationData,
    this.trackColors,
    this.loopEnabled,
    this.loopStartBeats,
    this.loopEndBeats,
  });

  Map<String, dynamic> toJson() => {
    'version': '1.2',
    'panel_sizes': {
      'library_width': libraryWidth,
      'mixer_width': mixerWidth,
      'bottom_height': bottomHeight,
    },
    'panel_collapsed': {
      'library': libraryCollapsed,
      'mixer': mixerCollapsed,
      'bottom': bottomCollapsed,
    },
    if (viewState != null) 'view_state': viewState!.toJson(),
    if (audioClips != null && audioClips!.isNotEmpty)
      'audio_clips': audioClips!.map((c) => c.toJson()).toList(),
    if (automationData != null && automationData!.isNotEmpty)
      'automation': automationData,
    if (trackColors != null && trackColors!.isNotEmpty)
      'track_colors': trackColors!.map((k, v) => MapEntry(k.toString(), v)),
    if (loopEnabled != null) 'loop_enabled': loopEnabled,
    if (loopStartBeats != null) 'loop_start_beats': loopStartBeats,
    if (loopEndBeats != null) 'loop_end_beats': loopEndBeats,
  };

  factory UILayoutData.fromJson(Map<String, dynamic> json) {
    final panelSizes = json['panel_sizes'] as Map<String, dynamic>? ?? {};
    final panelCollapsed =
        json['panel_collapsed'] as Map<String, dynamic>? ?? {};
    final viewStateJson = json['view_state'] as Map<String, dynamic>?;
    final audioClipsJson = json['audio_clips'] as List<dynamic>?;
    final automationJson = json['automation'] as Map<String, dynamic>?;
    final trackColorsJson = json['track_colors'] as Map<String, dynamic>?;

    return UILayoutData(
      libraryWidth: (panelSizes['library_width'] as num?)?.toDouble() ?? 200.0,
      mixerWidth: (panelSizes['mixer_width'] as num?)?.toDouble() ?? 380.0,
      bottomHeight: (panelSizes['bottom_height'] as num?)?.toDouble() ?? 250.0,
      libraryCollapsed: panelCollapsed['library'] as bool? ?? false,
      mixerCollapsed: panelCollapsed['mixer'] as bool? ?? false,
      bottomCollapsed: panelCollapsed['bottom'] as bool? ?? true,
      viewState: viewStateJson != null
          ? ProjectViewState.fromJson(viewStateJson)
          : null,
      audioClips: audioClipsJson
          ?.map((c) => ClipData.fromJson(c as Map<String, dynamic>))
          .toList(),
      automationData: automationJson,
      trackColors: trackColorsJson?.map(
        (k, v) => MapEntry(int.parse(k), (v as num).toInt()),
      ),
      loopEnabled: json['loop_enabled'] as bool?,
      loopStartBeats: (json['loop_start_beats'] as num?)?.toDouble(),
      loopEndBeats: (json['loop_end_beats'] as num?)?.toDouble(),
    );
  }
}

/// Centralizes which UI fields are persisted in `ui_layout.json`.
///
/// Engine state (tracks, clips, tempo, effects) lives in Rust `project.json`.
/// All UI-only fields must go through [collect] so save/load/auto-save stay in sync.
class ProjectPersistence {
  ProjectPersistence._();

  /// Build the full UI layout snapshot for save, auto-save, and crash recovery.
  static UILayoutData collect({
    required double libraryWidth,
    required double mixerWidth,
    required double bottomHeight,
    required bool libraryCollapsed,
    required bool mixerCollapsed,
    required bool bottomCollapsed,
    required bool loopEnabled,
    required double loopStartBeats,
    required double loopEndBeats,
    ProjectViewState? viewState,
    List<ClipData>? audioClips,
    Map<String, dynamic>? automationData,
    Map<int, Color>? trackColorOverrides,
  }) {
    Map<int, int>? trackColors;
    if (trackColorOverrides != null && trackColorOverrides.isNotEmpty) {
      trackColors = trackColorOverrides.map(
        (trackId, color) => MapEntry(trackId, color.toARGB32()),
      );
    }

    return UILayoutData(
      libraryWidth: libraryWidth,
      mixerWidth: mixerWidth,
      bottomHeight: bottomHeight,
      libraryCollapsed: libraryCollapsed,
      mixerCollapsed: mixerCollapsed,
      bottomCollapsed: bottomCollapsed,
      viewState: viewState,
      audioClips: audioClips,
      automationData: automationData,
      trackColors: trackColors,
      loopEnabled: loopEnabled,
      loopStartBeats: loopStartBeats,
      loopEndBeats: loopEndBeats,
    );
  }
}
