/// Represents the view state of a project (zoom, scroll, panel visibility)
/// Used to restore the user's view when reopening a project
class ProjectViewState {
  // Arrangement view scroll and zoom
  final double horizontalScroll;
  final double verticalScroll;
  final double zoom;

  // Panel visibility
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool virtualPianoVisible;

  // Selected track and playhead position
  final int? selectedTrackId;
  final double playheadPosition; // in beats

  const ProjectViewState({
    this.horizontalScroll = 0.0,
    this.verticalScroll = 0.0,
    this.zoom = 1.0,
    this.libraryVisible = true,
    this.mixerVisible = false,
    this.editorVisible = true,
    this.virtualPianoVisible = false,
    this.selectedTrackId,
    this.playheadPosition = 0.0,
  });

  /// Create default view state
  factory ProjectViewState.defaultState() {
    return const ProjectViewState();
  }

  /// Create ProjectViewState from JSON
  factory ProjectViewState.fromJson(Map<String, dynamic> json) {
    return ProjectViewState(
      horizontalScroll: (json['horizontalScroll'] as num?)?.toDouble() ?? 0.0,
      verticalScroll: (json['verticalScroll'] as num?)?.toDouble() ?? 0.0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      libraryVisible: json['libraryVisible'] as bool? ?? true,
      mixerVisible: json['mixerVisible'] as bool? ?? false,
      editorVisible: json['editorVisible'] as bool? ?? true,
      virtualPianoVisible: json['virtualPianoVisible'] as bool? ?? false,
      selectedTrackId: json['selectedTrackId'] as int?,
      playheadPosition: (json['playheadPosition'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert ProjectViewState to JSON
  Map<String, dynamic> toJson() {
    return {
      'horizontalScroll': horizontalScroll,
      'verticalScroll': verticalScroll,
      'zoom': zoom,
      'libraryVisible': libraryVisible,
      'mixerVisible': mixerVisible,
      'editorVisible': editorVisible,
      'virtualPianoVisible': virtualPianoVisible,
      'selectedTrackId': selectedTrackId,
      'playheadPosition': playheadPosition,
    };
  }

  /// Create a copy with updated fields
  ProjectViewState copyWith({
    double? horizontalScroll,
    double? verticalScroll,
    double? zoom,
    bool? libraryVisible,
    bool? mixerVisible,
    bool? editorVisible,
    bool? virtualPianoVisible,
    int? selectedTrackId,
    double? playheadPosition,
  }) {
    return ProjectViewState(
      horizontalScroll: horizontalScroll ?? this.horizontalScroll,
      verticalScroll: verticalScroll ?? this.verticalScroll,
      zoom: zoom ?? this.zoom,
      libraryVisible: libraryVisible ?? this.libraryVisible,
      mixerVisible: mixerVisible ?? this.mixerVisible,
      editorVisible: editorVisible ?? this.editorVisible,
      virtualPianoVisible: virtualPianoVisible ?? this.virtualPianoVisible,
      selectedTrackId: selectedTrackId ?? this.selectedTrackId,
      playheadPosition: playheadPosition ?? this.playheadPosition,
    );
  }

  @override
  String toString() {
    return 'ProjectViewState(scroll: ($horizontalScroll, $verticalScroll), '
        'zoom: $zoom, panels: L=$libraryVisible M=$mixerVisible E=$editorVisible P=$virtualPianoVisible)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProjectViewState &&
        other.horizontalScroll == horizontalScroll &&
        other.verticalScroll == verticalScroll &&
        other.zoom == zoom &&
        other.libraryVisible == libraryVisible &&
        other.mixerVisible == mixerVisible &&
        other.editorVisible == editorVisible &&
        other.virtualPianoVisible == virtualPianoVisible &&
        other.selectedTrackId == selectedTrackId &&
        other.playheadPosition == playheadPosition;
  }

  @override
  int get hashCode {
    return Object.hash(
      horizontalScroll,
      verticalScroll,
      zoom,
      libraryVisible,
      mixerVisible,
      editorVisible,
      virtualPianoVisible,
      selectedTrackId,
      playheadPosition,
    );
  }
}
