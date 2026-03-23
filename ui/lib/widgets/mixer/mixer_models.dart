import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import '../../models/track_automation_data.dart';
import '../../models/vst3_plugin_data.dart';
import '../../widgets/instrument_browser.dart';

/// Grouped callbacks for track CRUD operations
class TrackManagementCallbacks {
  final Function(int, int)? onDuplicated; // (sourceTrackId, newTrackId)
  final Function(int)? onDeleted; // (trackId)
  final Function(int trackId)? onMidiTrackCreated;
  final Function(int trackId, String trackType)? onTrackCreated;
  final Function(int oldIndex, int newIndex)? onReordered;
  final Function(List<int> trackIds)? onOrderSync;
  final Function(int trackId)? onDoubleClick;
  final Function(int trackId, String newName)? onNameChanged;
  final Function(int trackId, Color color)? onColorChanged;
  final Function(int trackId, String icon)? onIconChanged;
  final Function(int)? onConvertToSampler;

  const TrackManagementCallbacks({
    this.onDuplicated,
    this.onDeleted,
    this.onMidiTrackCreated,
    this.onTrackCreated,
    this.onReordered,
    this.onOrderSync,
    this.onDoubleClick,
    this.onNameChanged,
    this.onColorChanged,
    this.onIconChanged,
    this.onConvertToSampler,
  });
}

/// Grouped callbacks for instrument-related operations
class MixerInstrumentCallbacks {
  final Function(int, String)? onInstrumentSelected; // (trackId, instrumentId)
  final Function(int trackId, Instrument instrument)? onInstrumentDropped;
  final Function(int trackId, Vst3Plugin plugin)? onVst3InstrumentDropped;
  final Function(int trackId, Vst3Plugin plugin)? onVst3PluginDropped;
  final Function(int)? onFxButtonPressed; // (trackId)
  final Function(int)? onEditPluginsPressed; // (trackId)

  const MixerInstrumentCallbacks({
    this.onInstrumentSelected,
    this.onInstrumentDropped,
    this.onVst3InstrumentDropped,
    this.onVst3PluginDropped,
    this.onFxButtonPressed,
    this.onEditPluginsPressed,
  });
}

/// Grouped state/config for mixer automation controls
class MixerAutomationState {
  final int? visibleTrackId;
  final Function(int trackId)? onToggle;
  final double pixelsPerBeat;
  final double totalBeats;
  final AutomationParameter Function(int trackId)? getSelectedParameter;
  final Function(int trackId, AutomationParameter param)? onParameterChanged;
  final Function(int trackId)? onResetParameter;
  final Function(int trackId)? onAddParameter;
  final ValueNotifier<Map<int, double?>>? previewNotifier;

  const MixerAutomationState({
    this.visibleTrackId,
    this.onToggle,
    this.pixelsPerBeat = 20.0,
    this.totalBeats = 256.0,
    this.getSelectedParameter,
    this.onParameterChanged,
    this.onResetParameter,
    this.onAddParameter,
    this.previewNotifier,
  });
}

/// Grouped state for track selection
class TrackSelectionState {
  final int? selectedTrackId;
  final Set<int>? selectedTrackIds;
  final Function(int?, {bool isShiftHeld})? onTrackSelected;

  const TrackSelectionState({
    this.selectedTrackId,
    this.selectedTrackIds,
    this.onTrackSelected,
  });
}

/// Grouped state for mixer panel layout
class MixerPanelConfig {
  final double panelWidth;
  final VoidCallback? onTogglePanel;
  final bool isEngineReady;
  final bool isRecording;
  final List<int> trackOrder;

  const MixerPanelConfig({
    this.panelWidth = 380.0,
    this.onTogglePanel,
    this.isEngineReady = false,
    this.isRecording = false,
    this.trackOrder = const [],
  });
}
