/// Utility class for timeline clip selection operations.
/// Manages multi-selection of MIDI and audio clips.
class TimelineSelectionManager {
  final Set<int> _selectedMidiClipIds = {};
  final Set<int> _selectedAudioClipIds = {};
  int? _primaryAudioClipId;

  /// Get all selected MIDI clip IDs.
  Set<int> get selectedMidiClipIds => Set.unmodifiable(_selectedMidiClipIds);

  /// Get all selected audio clip IDs.
  Set<int> get selectedAudioClipIds => Set.unmodifiable(_selectedAudioClipIds);

  /// Get the primary selected audio clip ID.
  int? get primaryAudioClipId => _primaryAudioClipId;

  /// Check if a MIDI clip is selected.
  bool isMidiClipSelected(int clipId) => _selectedMidiClipIds.contains(clipId);

  /// Check if an audio clip is selected.
  bool isAudioClipSelected(int clipId) => _selectedAudioClipIds.contains(clipId);

  /// Check if any clips are selected.
  bool get hasSelection => _selectedMidiClipIds.isNotEmpty || _selectedAudioClipIds.isNotEmpty;

  /// Get total number of selected clips.
  int get selectionCount => _selectedMidiClipIds.length + _selectedAudioClipIds.length;

  /// Select a MIDI clip with multi-selection support.
  /// - Normal click: Select only this clip (clear others)
  /// - Shift+click (addToSelection): Add to selection
  /// - Cmd+click (toggleSelection): Toggle selection
  void selectMidiClip(int clipId, {bool addToSelection = false, bool toggleSelection = false}) {
    if (toggleSelection) {
      if (_selectedMidiClipIds.contains(clipId)) {
        _selectedMidiClipIds.remove(clipId);
      } else {
        _selectedMidiClipIds.add(clipId);
      }
    } else if (addToSelection) {
      _selectedMidiClipIds.add(clipId);
    } else {
      _selectedMidiClipIds.clear();
      _selectedMidiClipIds.add(clipId);
    }
    // Clear audio selection when selecting MIDI
    _selectedAudioClipIds.clear();
    _primaryAudioClipId = null;
  }

  /// Select an audio clip with multi-selection support.
  /// - Normal click: Select only this clip (clear others)
  /// - Shift+click (addToSelection): Add to selection
  /// - Cmd+click (toggleSelection): Toggle selection
  void selectAudioClip(int clipId, {bool addToSelection = false, bool toggleSelection = false}) {
    if (toggleSelection) {
      if (_selectedAudioClipIds.contains(clipId)) {
        _selectedAudioClipIds.remove(clipId);
        if (_primaryAudioClipId == clipId) {
          _primaryAudioClipId = _selectedAudioClipIds.isEmpty ? null : _selectedAudioClipIds.first;
        }
      } else {
        _selectedAudioClipIds.add(clipId);
        _primaryAudioClipId = clipId;
      }
    } else if (addToSelection) {
      _selectedAudioClipIds.add(clipId);
      _primaryAudioClipId = clipId;
    } else {
      _selectedAudioClipIds.clear();
      _selectedAudioClipIds.add(clipId);
      _primaryAudioClipId = clipId;
    }
    // Clear MIDI selection when selecting audio
    _selectedMidiClipIds.clear();
  }

  /// Clear all clip selections.
  void clearSelection() {
    _selectedMidiClipIds.clear();
    _selectedAudioClipIds.clear();
    _primaryAudioClipId = null;
  }

  /// Select all clips from given lists.
  void selectAll(List<int> midiClipIds, List<int> audioClipIds) {
    _selectedMidiClipIds.clear();
    _selectedMidiClipIds.addAll(midiClipIds);

    _selectedAudioClipIds.clear();
    _selectedAudioClipIds.addAll(audioClipIds);

    _primaryAudioClipId = audioClipIds.isNotEmpty ? audioClipIds.first : null;
  }

  /// Remove a clip from selection (useful when clip is deleted).
  void removeFromSelection(int clipId, {required bool isMidi}) {
    if (isMidi) {
      _selectedMidiClipIds.remove(clipId);
    } else {
      _selectedAudioClipIds.remove(clipId);
      if (_primaryAudioClipId == clipId) {
        _primaryAudioClipId = _selectedAudioClipIds.isEmpty ? null : _selectedAudioClipIds.first;
      }
    }
  }
}
