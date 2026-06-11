import 'package:flutter/material.dart';

import '../models/clip_data.dart';
import '../models/midi_note_data.dart';
import '../models/project_view_state.dart';

/// UI-only project data saved alongside the Rust engine's `project.json`.
///
/// Stored in `ui_layout.json` inside each `.audio` project folder.
/// See [ProjectPersistence.collect] for the canonical field checklist.
class UILayoutData {
  final double libraryWidth;

  /// Library panel left (categories) column width. Nullable so layouts saved
  /// before this field existed fall back to the default split.
  final double? libraryLeftWidth;
  final double mixerWidth;
  final double bottomHeight;
  final bool libraryCollapsed;
  final bool mixerCollapsed;
  final bool bottomCollapsed;
  final ProjectViewState? viewState;
  final List<ClipData>? audioClips;

  /// MIDI clip UI metadata (name, colour, offset, loop, mute, automation).
  /// Notes themselves live in the engine's `project.json`; this only carries
  /// the UI-owned fields, matched back by `(trackId, startTime)` on load.
  final List<MidiClipData>? midiClips;
  final Map<String, dynamic>? automationData;
  final Map<int, int>? trackColors;

  /// Custom track icon overrides, keyed by track id. Values are stable icon
  /// keys from `utils/track_icons.dart` (e.g. 'mic', 'piano'), never glyphs.
  final Map<int, String>? trackIcons;
  final bool? loopEnabled;
  final double? loopStartBeats;
  final double? loopEndBeats;

  /// Time signature — display-only metadata (the engine is quarter-note based
  /// and owns the numerator for bar math separately). Persisted so 3/4, 6/8,
  /// etc. survive reload instead of reverting to 4/4.
  final int? timeSignatureNumerator;
  final int? timeSignatureDenominator;

  const UILayoutData({
    this.libraryWidth = 200.0,
    this.libraryLeftWidth,
    this.mixerWidth = 380.0,
    this.bottomHeight = 250.0,
    this.libraryCollapsed = false,
    this.mixerCollapsed = false,
    this.bottomCollapsed = true,
    this.viewState,
    this.audioClips,
    this.midiClips,
    this.automationData,
    this.trackColors,
    this.trackIcons,
    this.loopEnabled,
    this.loopStartBeats,
    this.loopEndBeats,
    this.timeSignatureNumerator,
    this.timeSignatureDenominator,
  });

  Map<String, dynamic> toJson() => {
    'version': '1.2',
    'panel_sizes': {
      'library_width': libraryWidth,
      if (libraryLeftWidth != null) 'library_left_width': libraryLeftWidth,
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
    if (midiClips != null && midiClips!.isNotEmpty)
      'midi_clips': midiClips!.map((c) => c.toUiLayoutJson()).toList(),
    if (automationData != null && automationData!.isNotEmpty)
      'automation': automationData,
    if (trackColors != null && trackColors!.isNotEmpty)
      'track_colors': trackColors!.map((k, v) => MapEntry(k.toString(), v)),
    if (trackIcons != null && trackIcons!.isNotEmpty)
      'track_icons': trackIcons!.map((k, v) => MapEntry(k.toString(), v)),
    if (loopEnabled != null) 'loop_enabled': loopEnabled,
    if (loopStartBeats != null) 'loop_start_beats': loopStartBeats,
    if (loopEndBeats != null) 'loop_end_beats': loopEndBeats,
    if (timeSignatureNumerator != null)
      'time_sig_numerator': timeSignatureNumerator,
    if (timeSignatureDenominator != null)
      'time_sig_denominator': timeSignatureDenominator,
  };

  factory UILayoutData.fromJson(Map<String, dynamic> json) {
    final panelSizes = json['panel_sizes'] as Map<String, dynamic>? ?? {};
    final panelCollapsed =
        json['panel_collapsed'] as Map<String, dynamic>? ?? {};
    final viewStateJson = json['view_state'] as Map<String, dynamic>?;
    final audioClipsJson = json['audio_clips'] as List<dynamic>?;
    final midiClipsJson = json['midi_clips'] as List<dynamic>?;
    final automationJson = json['automation'] as Map<String, dynamic>?;
    final trackColorsJson = json['track_colors'] as Map<String, dynamic>?;
    final trackIconsJson = json['track_icons'] as Map<String, dynamic>?;

    return UILayoutData(
      libraryWidth: (panelSizes['library_width'] as num?)?.toDouble() ?? 200.0,
      libraryLeftWidth: (panelSizes['library_left_width'] as num?)?.toDouble(),
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
      midiClips: midiClipsJson
          ?.map((c) => MidiClipData.fromUiLayoutJson(c as Map<String, dynamic>))
          .toList(),
      automationData: automationJson,
      trackColors: _parseTrackColors(trackColorsJson),
      trackIcons: _parseTrackIcons(trackIconsJson),
      loopEnabled: json['loop_enabled'] as bool?,
      loopStartBeats: (json['loop_start_beats'] as num?)?.toDouble(),
      loopEndBeats: (json['loop_end_beats'] as num?)?.toDouble(),
      timeSignatureNumerator: (json['time_sig_numerator'] as num?)?.toInt(),
      timeSignatureDenominator: (json['time_sig_denominator'] as num?)?.toInt(),
    );
  }

  /// Parse the `track_colors` map defensively.
  ///
  /// One malformed entry (a non-integer key, or a non-numeric value) must not
  /// throw — the loader catches any exception and discards the *entire* saved
  /// layout, so a single corrupt colour would silently wipe panel sizes, view
  /// state, clips, automation and loop settings too. Bad entries are skipped;
  /// every well-formed colour (and the rest of the layout) survives. (C80)
  static Map<int, int>? _parseTrackColors(Map<String, dynamic>? json) {
    if (json == null) return null;
    final result = <int, int>{};
    json.forEach((key, value) {
      final trackId = int.tryParse(key);
      if (trackId != null && value is num) {
        result[trackId] = value.toInt();
      }
    });
    return result.isEmpty ? null : result;
  }

  /// Parse the `track_icons` map defensively, mirroring [_parseTrackColors]:
  /// a malformed entry is skipped, never fatal to the whole layout (C80).
  static Map<int, String>? _parseTrackIcons(Map<String, dynamic>? json) {
    if (json == null) return null;
    final result = <int, String>{};
    json.forEach((key, value) {
      final trackId = int.tryParse(key);
      if (trackId != null && value is String && value.isNotEmpty) {
        result[trackId] = value;
      }
    });
    return result.isEmpty ? null : result;
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
    double? libraryLeftWidth,
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
    List<MidiClipData>? midiClips,
    Map<String, dynamic>? automationData,
    Map<int, Color>? trackColorOverrides,
    Map<int, String>? trackIconOverrides,
    int? timeSignatureNumerator,
    int? timeSignatureDenominator,
  }) {
    Map<int, int>? trackColors;
    if (trackColorOverrides != null && trackColorOverrides.isNotEmpty) {
      trackColors = trackColorOverrides.map(
        (trackId, color) => MapEntry(trackId, color.toARGB32()),
      );
    }

    Map<int, String>? trackIcons;
    if (trackIconOverrides != null && trackIconOverrides.isNotEmpty) {
      trackIcons = Map<int, String>.from(trackIconOverrides);
    }

    return UILayoutData(
      libraryWidth: libraryWidth,
      libraryLeftWidth: libraryLeftWidth,
      mixerWidth: mixerWidth,
      bottomHeight: bottomHeight,
      libraryCollapsed: libraryCollapsed,
      mixerCollapsed: mixerCollapsed,
      bottomCollapsed: bottomCollapsed,
      viewState: viewState,
      audioClips: audioClips,
      midiClips: midiClips,
      automationData: automationData,
      trackColors: trackColors,
      trackIcons: trackIcons,
      loopEnabled: loopEnabled,
      loopStartBeats: loopStartBeats,
      loopEndBeats: loopEndBeats,
      timeSignatureNumerator: timeSignatureNumerator,
      timeSignatureDenominator: timeSignatureDenominator,
    );
  }
}
