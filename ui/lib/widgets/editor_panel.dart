import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import 'piano_roll.dart';
import 'synthesizer_panel.dart';
import 'vst3_plugin_parameter_panel.dart';
import 'fx_chain/fx_chain_view.dart';
import '../models/midi_note_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';

/// Editor panel widget - tabbed interface for Piano Roll, Effects, Instrument, and Virtual Piano
class EditorPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool virtualPianoEnabled;
  final int? selectedTrackId; // Unified track selection
  final String? selectedTrackName; // Track name for display
  final InstrumentData? currentInstrumentData;
  final VoidCallback? onVirtualPianoClose;
  final VoidCallback? onVirtualPianoToggle; // Toggle virtual piano visibility
  final VoidCallback? onClosePanel; // Close the entire editor panel
  final MidiClipData? currentEditingClip;
  final Function(MidiClipData)? onMidiClipUpdated;
  final Function(InstrumentData)? onInstrumentParameterChanged;

  /// Ghost notes from other MIDI tracks to display in Piano Roll
  final List<MidiNoteData> ghostNotes;

  // M10: VST3 Plugin support
  final List<Vst3PluginInstance>? currentTrackPlugins;
  final Function(int effectId, int paramIndex, double value)? onVst3ParameterChanged;
  final Function(int effectId)? onVst3PluginRemoved;

  // Collapsed bar mode
  final bool isCollapsed;
  final VoidCallback? onExpandPanel;
  final Function(int tabIndex)? onTabAndExpand; // Select tab AND expand

  const EditorPanel({
    super.key,
    this.audioEngine,
    this.virtualPianoEnabled = false,
    this.selectedTrackId,
    this.selectedTrackName,
    this.currentInstrumentData,
    this.onVirtualPianoClose,
    this.onVirtualPianoToggle,
    this.onClosePanel,
    this.currentEditingClip,
    this.onMidiClipUpdated,
    this.onInstrumentParameterChanged,
    this.ghostNotes = const [],
    this.currentTrackPlugins,
    this.onVst3ParameterChanged,
    this.onVst3PluginRemoved,
    this.isCollapsed = false,
    this.onExpandPanel,
    this.onTabAndExpand,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Tool mode state for Piano Roll (managed here so tools can be in tab bar)
  ToolMode _currentToolMode = ToolMode.draw;

  // Temporary tool mode when holding modifier keys (Alt, Cmd)
  ToolMode? _tempToolMode;

  // Highlighted note from Virtual Piano (for Piano Roll sync)
  int? _highlightedNote;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
    // Listen for modifier key changes
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only auto-switch tabs if this is the first track selection (from null)
    // Otherwise, preserve the current tab when switching between tracks
    if (widget.selectedTrackId != oldWidget.selectedTrackId) {
      if (oldWidget.selectedTrackId == null && widget.selectedTrackId != null) {
        // First selection: auto-switch to appropriate tab
        if (widget.currentInstrumentData != null) {
          _tabController.index = 2; // Instrument tab
        } else {
          _tabController.index = 0; // Piano Roll tab
        }
      }
      // If switching from one track to another, preserve current tab
    }

    // Auto-switch to Piano Roll tab when clip selected
    if (widget.currentEditingClip != null && oldWidget.currentEditingClip == null) {
      _tabController.index = 0;
    }

    // Auto-switch to Instrument tab when instrument data first appears
    if (widget.currentInstrumentData != null && oldWidget.currentInstrumentData == null) {
      _tabController.index = 2;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _tabController.dispose();
    super.dispose();
  }

  /// Handle keyboard events for modifier key tracking (visual feedback for hold modifiers)
  bool _onKeyEvent(KeyEvent event) {
    // Check if Alt or Cmd/Ctrl modifiers changed
    if (event.logicalKey == LogicalKeyboardKey.alt ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight ||
        event.logicalKey == LogicalKeyboardKey.meta ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight ||
        event.logicalKey == LogicalKeyboardKey.control ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      _updateTempToolMode();
    }
    return false; // Don't consume the event
  }

  /// Update temporary tool mode based on held modifiers
  void _updateTempToolMode() {
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final isCtrlOrCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    setState(() {
      if (isAltPressed) {
        _tempToolMode = ToolMode.eraser;
      } else if (isCtrlOrCmd) {
        _tempToolMode = ToolMode.duplicate; // or slice depending on context
      } else {
        _tempToolMode = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show collapsed bar when collapsed
    if (widget.isCollapsed) {
      return _buildCollapsedBar();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.dark,
        border: Border(
          top: BorderSide(color: context.colors.divider),
        ),
      ),
      child: Column(
        children: [
          // Custom tab bar with icons and pill-style active indicator
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.standard,
              border: Border(
                bottom: BorderSide(color: context.colors.surface),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                // Tab buttons (left side)
                _buildTabButton(0, Icons.piano_outlined, 'Piano Roll'),
                const SizedBox(width: 4),
                _buildTabButton(1, Icons.equalizer, 'Effects'),
                const SizedBox(width: 4),
                _buildTabButton(2, Icons.music_note, 'Instrument'),
                // Centered tool buttons (always visible)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildToolButton(ToolMode.draw, Icons.edit, 'Draw (Z)'),
                      const SizedBox(width: 4),
                      _buildToolButton(ToolMode.select, Icons.open_with, 'Select (X)'),
                      const SizedBox(width: 4),
                      _buildToolButton(ToolMode.eraser, Icons.backspace_outlined, 'Erase (C) • Hold Alt'),
                      const SizedBox(width: 4),
                      _buildToolButton(ToolMode.duplicate, Icons.copy, 'Duplicate (V) • Cmd+Drag'),
                      const SizedBox(width: 4),
                      _buildToolButton(ToolMode.slice, Icons.content_cut, 'Slice (B) • Cmd+Click'),
                    ],
                  ),
                ),
                // Virtual Piano toggle (right side, before collapse button)
                _buildPianoToggle(),
                const SizedBox(width: 8),
                // Collapse button (down arrow)
                Tooltip(
                  message: 'Collapse Panel',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onClosePanel,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // Tab content expands to fill available space
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPianoRollTab(),
                _buildFXChainTab(),
                _buildInstrumentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build collapsed bar with tab buttons and expand arrow
  Widget _buildCollapsedBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.standard,
        border: Border(
          top: BorderSide(color: context.colors.divider),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // Tab buttons (clickable, expand panel and switch to that tab)
          _buildCollapsedTabButton(0, Icons.piano_outlined, 'Piano Roll'),
          const SizedBox(width: 4),
          _buildCollapsedTabButton(1, Icons.equalizer, 'Effects'),
          const SizedBox(width: 4),
          _buildCollapsedTabButton(2, Icons.music_note, 'Instrument'),
          // Centered tool buttons (always visible)
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildToolButton(ToolMode.draw, Icons.edit, 'Draw (Z)'),
                const SizedBox(width: 4),
                _buildToolButton(ToolMode.select, Icons.open_with, 'Select (X)'),
                const SizedBox(width: 4),
                _buildToolButton(ToolMode.eraser, Icons.backspace_outlined, 'Erase (C) • Hold Alt'),
                const SizedBox(width: 4),
                _buildToolButton(ToolMode.duplicate, Icons.copy, 'Duplicate (V) • Cmd+Drag'),
                const SizedBox(width: 4),
                _buildToolButton(ToolMode.slice, Icons.content_cut, 'Slice (B) • Cmd+Click'),
              ],
            ),
          ),
          // Virtual Piano toggle (right side, before expand button)
          _buildPianoToggle(),
          const SizedBox(width: 8),
          // Expand arrow (up arrow)
          Tooltip(
            message: 'Expand Editor',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onExpandPanel,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    color: context.colors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Build collapsed tab button - clicking expands panel and switches to tab
  Widget _buildCollapsedTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.index = index;
            widget.onTabAndExpand?.call(index);
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? context.colors.accent.withValues(alpha: 0.3) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isSelected ? context.colors.accent : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.index = index;
          },
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? context.colors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : context.colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build a tool button for the Piano Roll toolbar
  /// Shows full highlight for active sticky tool, dimmer highlight for temporary hold modifier
  Widget _buildToolButton(ToolMode mode, IconData icon, String tooltip) {
    final isActive = _currentToolMode == mode;
    final isTempActive = _tempToolMode == mode && !isActive;

    // Determine background color:
    // - Full accent for sticky active tool
    // - Dimmer accent (50% opacity) for temporary hold modifier
    // - Dark for inactive
    Color bgColor;
    Color iconColor;
    if (isActive) {
      bgColor = context.colors.accent;
      iconColor = context.colors.elevated;
    } else if (isTempActive) {
      bgColor = context.colors.accent.withValues(alpha: 0.5);
      iconColor = context.colors.elevated;
    } else {
      bgColor = context.colors.dark;
      iconColor = context.colors.textPrimary;
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => setState(() => _currentToolMode = mode),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 16,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the Virtual Piano toggle button
  Widget _buildPianoToggle() {
    final isActive = widget.virtualPianoEnabled;

    return Tooltip(
      message: 'Virtual Piano (P)',
      child: GestureDetector(
        onTap: widget.onVirtualPianoToggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? context.colors.accent : context.colors.dark,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard,
                  size: 16,
                  color: isActive ? context.colors.elevated : context.colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Piano',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isActive ? context.colors.elevated : context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPianoRollTab() {
    // Use real clip data if available, otherwise create an empty clip for the selected track
    final clipData = widget.currentEditingClip ?? (widget.selectedTrackId != null
      ? MidiClipData(
          clipId: -1, // -1 indicates a new, unsaved clip
          trackId: widget.selectedTrackId!,
          startTime: 0.0,
          duration: 16.0,
          name: 'New MIDI Clip',
          notes: [],
        )
      : null);

    if (clipData == null) {
      // No track selected - show empty state
      return ColoredBox(
        color: context.colors.dark,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.piano_outlined,
                size: 64,
                color: context.colors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Piano Roll',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a MIDI track or clip to start editing',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return PianoRoll(
      audioEngine: widget.audioEngine,
      clipData: clipData,
      onClipUpdated: widget.onMidiClipUpdated,
      ghostNotes: widget.ghostNotes,
      toolMode: _currentToolMode,
      onToolModeChanged: (mode) => setState(() => _currentToolMode = mode),
      highlightedNote: _highlightedNote,
      virtualPianoVisible: widget.virtualPianoEnabled,
      onVirtualPianoToggle: widget.onVirtualPianoToggle,
      onClose: () {
        // Switch back to another tab or close bottom panel
        _tabController.index = 3; // Switch to Virtual Piano tab
      },
    );
  }

  Widget _buildFXChainTab() {
    // Use the new horizontal FxChainView
    return FxChainView(
      selectedTrackId: widget.selectedTrackId,
      audioEngine: widget.audioEngine,
      trackName: widget.selectedTrackName,
      onVst3PopOut: (effectId) {
        // TODO: Handle VST3 pop-out to floating window
      },
      onVst3BringBack: (effectId) {
        // TODO: Handle VST3 bring back from floating window
      },
    );
  }

  Widget _buildInstrumentTab() {
    if (widget.selectedTrackId == null || widget.currentInstrumentData == null) {
      return ColoredBox(
        color: context.colors.dark,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.piano,
                size: 64,
                color: context.colors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Instrument',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a track with an instrument to edit',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Check if this is a VST3 instrument
    if (widget.currentInstrumentData!.isVst3) {
      // Create Vst3PluginInstance from the track's instrument data
      // This ensures the Instruments panel shows the VST3 instrument,
      // not the FX chain plugins
      final effectId = widget.currentInstrumentData!.effectId!;

      // Fetch parameter count and info from the audio engine
      final paramCount = widget.audioEngine?.getVst3ParameterCount(effectId) ?? 0;
      final parameters = <int, Vst3ParameterInfo>{};
      final parameterValues = <int, double>{};


      for (int i = 0; i < paramCount; i++) {
        final info = widget.audioEngine?.getVst3ParameterInfo(effectId, i);
        if (info != null) {
          parameters[i] = Vst3ParameterInfo(
            index: i,
            name: info['name'] as String? ?? 'Parameter $i',
            min: (info['min'] as num?)?.toDouble() ?? 0.0,
            max: (info['max'] as num?)?.toDouble() ?? 1.0,
            defaultValue: (info['default'] as num?)?.toDouble() ?? 0.5,
            unit: '',
          );
          parameterValues[i] = widget.audioEngine?.getVst3ParameterValue(effectId, i) ?? 0.5;
        }
      }

      final vst3Instrument = Vst3PluginInstance(
        effectId: effectId,
        pluginName: widget.currentInstrumentData!.pluginName ?? 'VST3 Instrument',
        pluginPath: widget.currentInstrumentData!.pluginPath ?? '',
        parameters: parameters,
        parameterValues: parameterValues,
      );

      // Show VST3 plugin parameter panel for VST3 instruments
      return Vst3PluginParameterPanel(
        audioEngine: widget.audioEngine,
        trackId: widget.selectedTrackId!,
        plugins: [vst3Instrument],
        onParameterChanged: widget.onVst3ParameterChanged,
        onRemovePlugin: widget.onVst3PluginRemoved,
      );
    }

    // Show synthesizer panel for built-in instruments
    return SynthesizerPanel(
      audioEngine: widget.audioEngine,
      trackId: widget.selectedTrackId!,
      instrumentData: widget.currentInstrumentData,
      onParameterChanged: (instrumentData) {
        widget.onInstrumentParameterChanged?.call(instrumentData);
      },
      onClose: () {
        // Parent widget handles clearing selectedTrackId
      },
    );
  }

}
