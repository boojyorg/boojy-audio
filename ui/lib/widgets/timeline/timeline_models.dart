import 'package:flutter/foundation.dart';

import '../../constants/ui_constants.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../models/track_automation_data.dart';
import '../../models/vst3_plugin_data.dart';
import '../../services/commands/command.dart';
import '../../utils/clip_overlap_handler.dart';
import '../instrument_browser.dart';

/// Grouped callbacks for MIDI clip operations
class MidiClipCallbacks {
  final Function(int?, MidiClipData?)? onSelected;
  final Function(MidiClipData)? onUpdated;
  final Function(MidiClipData sourceClip, double newStartTime)? onCopied;
  final Function(int clipId, int trackId)? onDeleted;
  final Function(List<(int clipId, int trackId)>)? onBatchDeleted;
  final Function(MidiClipData clip)? onExported;

  /// Split [clip] at [splitPointBeats] (relative to the clip start), undoably.
  /// The daw layer builds a [SplitMidiClipCommand] with engine+manager
  /// primitives — the timeline must route ALL split gestures (slice tool,
  /// right-click) through here, never through onCopied/onDeleted (which would
  /// nest commands and destroy the right region on undo).
  final Function(MidiClipData clip, double splitPointBeats)? onSplit;

  /// Join the currently selected clips into one, undoably (same path as
  /// Cmd+J / Edit → Join Clips). Operates on the timeline selection, so no
  /// clip argument is needed.
  final VoidCallback? onJoinSelected;

  /// Build an undoable command that resolves the given MIDI overlap (H-11).
  /// Returns null if no command is available. The caller composes the returned
  /// command into the move's undo step instead of applying the overlap
  /// destructively, so one Ctrl+Z restores any trimmed/removed neighbour.
  final Command? Function(MidiOverlapResult result)? buildMidiOverlapCommand;

  const MidiClipCallbacks({
    this.onSelected,
    this.onUpdated,
    this.onCopied,
    this.onDeleted,
    this.onBatchDeleted,
    this.onExported,
    this.onSplit,
    this.onJoinSelected,
    this.buildMidiOverlapCommand,
  });
}

/// Grouped callbacks for audio clip operations
class AudioClipCallbacks {
  final Function(int?, ClipData?)? onSelected;
  final Function(ClipData sourceClip, double newStartTime)? onCopied;
  final Function(List<ClipData>)? onBatchDeleted;

  /// Join the currently selected audio clips into one, undoably (same path as
  /// Cmd+J / Edit → Join Clips). Operates on the timeline selection, so no clip
  /// argument is needed.
  final VoidCallback? onJoinSelected;

  const AudioClipCallbacks({
    this.onSelected,
    this.onCopied,
    this.onBatchDeleted,
    this.onJoinSelected,
  });
}

/// Grouped callbacks for instrument/file drag-drop operations
class DragDropCallbacks {
  final Function(int trackId, Instrument instrument)? onInstrumentDropped;
  final Function(Instrument instrument)? onInstrumentDroppedOnEmpty;
  final Function(int trackId, Vst3Plugin plugin)? onVst3InstrumentDropped;
  final Function(Vst3Plugin plugin)? onVst3InstrumentDroppedOnEmpty;
  final Function(String filePath, double startTimeBeats)?
  onMidiFileDroppedOnEmpty;
  final Function(int trackId, String filePath, double startTimeBeats)?
  onMidiFileDroppedOnTrack;
  final Function(String filePath, double startTimeBeats)?
  onAudioFileDroppedOnEmpty;
  final Function(int trackId, String filePath, double startTimeBeats)?
  onAudioFileDroppedOnTrack;
  final Function(String trackType, double startBeats, double durationBeats)?
  onCreateTrackWithClip;
  final Function(int trackId, double startBeats, double durationBeats)?
  onCreateClipOnTrack;

  const DragDropCallbacks({
    this.onInstrumentDropped,
    this.onInstrumentDroppedOnEmpty,
    this.onVst3InstrumentDropped,
    this.onVst3InstrumentDroppedOnEmpty,
    this.onMidiFileDroppedOnEmpty,
    this.onMidiFileDroppedOnTrack,
    this.onAudioFileDroppedOnEmpty,
    this.onAudioFileDroppedOnTrack,
    this.onCreateTrackWithClip,
    this.onCreateClipOnTrack,
  });
}

/// Grouped callbacks for automation operations
class AutomationCallbacks {
  final Function(int trackId, AutomationPoint point)? onPointAdded;
  final Function(int trackId, String pointId, AutomationPoint point)?
  onPointUpdated;
  final Function(int trackId, String pointId)? onPointDragEnd;
  final Function(int trackId, String pointId)? onPointDeleted;
  final Function(int trackId, double? value)? onPreviewValue;
  final TrackAutomationLane? Function(int trackId)? getAutomationLane;

  const AutomationCallbacks({
    this.onPointAdded,
    this.onPointUpdated,
    this.onPointDragEnd,
    this.onPointDeleted,
    this.onPreviewValue,
    this.getAutomationLane,
  });
}

/// Grouped track height maps and callbacks
class TrackHeightState {
  final Map<int, double> clipHeights;
  final Map<int, double> automationHeights;
  final double masterTrackHeight;
  final Function(int trackId, double height)? onClipHeightChanged;
  final Function(int trackId, double height)? onAutomationHeightChanged;
  final Function(int trackId, int sendCount)? onSendCountChanged;

  const TrackHeightState({
    this.clipHeights = const {},
    this.automationHeights = const {},
    this.masterTrackHeight = UIConstants.defaultMasterTrackHeight,
    this.onClipHeightChanged,
    this.onAutomationHeightChanged,
    this.onSendCountChanged,
  });
}
