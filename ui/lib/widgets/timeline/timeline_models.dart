import '../../constants/ui_constants.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../models/track_automation_data.dart';
import '../../models/vst3_plugin_data.dart';
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
  final Function(MidiOverlapResult result)? onOverlapResolved;

  const MidiClipCallbacks({
    this.onSelected,
    this.onUpdated,
    this.onCopied,
    this.onDeleted,
    this.onBatchDeleted,
    this.onExported,
    this.onOverlapResolved,
  });
}

/// Grouped callbacks for audio clip operations
class AudioClipCallbacks {
  final Function(int?, ClipData?)? onSelected;
  final Function(ClipData sourceClip, double newStartTime)? onCopied;
  final Function(List<ClipData>)? onBatchDeleted;

  const AudioClipCallbacks({
    this.onSelected,
    this.onCopied,
    this.onBatchDeleted,
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
  final Function(int trackId, String pointId)? onPointDeleted;
  final Function(int trackId, double? value)? onPreviewValue;
  final TrackAutomationLane? Function(int trackId)? getAutomationLane;

  const AutomationCallbacks({
    this.onPointAdded,
    this.onPointUpdated,
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

  const TrackHeightState({
    this.clipHeights = const {},
    this.automationHeights = const {},
    this.masterTrackHeight = UIConstants.defaultMasterTrackHeight,
    this.onClipHeightChanged,
    this.onAutomationHeightChanged,
  });
}
