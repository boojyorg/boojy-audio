import 'package:flutter/foundation.dart';
import '../../models/instrument_data.dart';
import '../../models/tool_mode.dart';
import '../../models/vst3_plugin_data.dart';
import '../instrument_browser.dart';

/// Track context information for the editor panel
class EditorPanelContext {
  final int? selectedTrackId;
  final String? selectedTrackName;
  final String? selectedTrackType;
  final InstrumentData? currentInstrumentData;

  const EditorPanelContext({
    this.selectedTrackId,
    this.selectedTrackName,
    this.selectedTrackType,
    this.currentInstrumentData,
  });
}

/// Grouped callbacks for editor panel UI operations
class EditorPanelCallbacks {
  final VoidCallback? onClosePanel;
  final VoidCallback? onExpandPanel;
  final Function(int tabIndex)? onTabAndExpand;
  final VoidCallback? onVirtualPianoClose;
  final VoidCallback? onVirtualPianoToggle;
  final Function(ToolMode)? onToolModeChanged;

  const EditorPanelCallbacks({
    this.onClosePanel,
    this.onExpandPanel,
    this.onTabAndExpand,
    this.onVirtualPianoClose,
    this.onVirtualPianoToggle,
    this.onToolModeChanged,
  });
}

/// Grouped callbacks for VST3 plugin operations in the editor
class Vst3EditorCallbacks {
  final Function(int effectId, int paramIndex, double value)? onVst3ParameterChanged;
  final Function(int effectId)? onVst3PluginRemoved;
  final Function(Vst3Plugin)? onVst3InstrumentDropped;

  const Vst3EditorCallbacks({
    this.onVst3ParameterChanged,
    this.onVst3PluginRemoved,
    this.onVst3InstrumentDropped,
  });
}
