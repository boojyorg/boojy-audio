import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import '../models/tool_mode.dart';
import '../services/tool_mode_resolver.dart';
import 'piano_roll.dart';
import 'audio_editor/audio_editor.dart';
import 'synthesizer_panel.dart';
import 'vst3_plugin_parameter_panel.dart';
import 'fx_chain/fx_chain_view.dart';
import 'instrument_browser.dart';
import '../models/midi_note_data.dart';
import '../models/clip_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';

/// Editor panel widget - tabbed interface for Piano Roll/Audio Editor, Effects, Instrument
class EditorPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool virtualPianoEnabled;
  final int? selectedTrackId; // Unified track selection
  final String? selectedTrackName; // Track name for display
  final String? selectedTrackType; // Track type: "MIDI", "Audio", or "Master"
  final InstrumentData? currentInstrumentData;
  final VoidCallback? onVirtualPianoClose;
  final VoidCallback? onVirtualPianoToggle; // Toggle virtual piano visibility
  final VoidCallback? onClosePanel; // Close the entire editor panel
  final MidiClipData? currentEditingClip;
  final Function(MidiClipData)? onMidiClipUpdated;
  final Function(InstrumentData)? onInstrumentParameterChanged;

  /// Ghost notes from other MIDI tracks to display in Piano Roll
  final List<MidiNoteData> ghostNotes;

  // Audio clip editing
  final ClipData? currentEditingAudioClip;
  final Function(ClipData)? onAudioClipUpdated;

  // M10: VST3 Plugin support
  final List<Vst3PluginInstance>? currentTrackPlugins;
  final Function(int effectId, int paramIndex, double value)? onVst3ParameterChanged;
  final Function(int effectId)? onVst3PluginRemoved;

  // Collapsed bar mode
  final bool isCollapsed;
  final VoidCallback? onExpandPanel;
  final Function(int tabIndex)? onTabAndExpand; // Select tab AND expand

  // Instrument swap via drag-and-drop
  final Function(Vst3Plugin)? onVst3InstrumentDropped;
  final Function(Instrument)? onInstrumentDropped;

  // Tool mode (shared with arrangement view)
  final ToolMode toolMode;
  final Function(ToolMode)? onToolModeChanged;

  // Time signature (from project settings)
  final int beatsPerBar;
  final int beatUnit;

  const EditorPanel({
    super.key,
    this.audioEngine,
    this.virtualPianoEnabled = false,
    this.selectedTrackId,
    this.selectedTrackName,
    this.selectedTrackType,
    this.currentInstrumentData,
    this.onVirtualPianoClose,
    this.onVirtualPianoToggle,
    this.onClosePanel,
    this.currentEditingClip,
    this.onMidiClipUpdated,
    this.onInstrumentParameterChanged,
    this.ghostNotes = const [],
    this.currentEditingAudioClip,
    this.onAudioClipUpdated,
    this.currentTrackPlugins,
    this.onVst3ParameterChanged,
    this.onVst3PluginRemoved,
    this.isCollapsed = false,
    this.onExpandPanel,
    this.onTabAndExpand,
    this.onVst3InstrumentDropped,
    this.onInstrumentDropped,
    this.toolMode = ToolMode.draw,
    this.onToolModeChanged,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Temporary tool mode when holding modifier keys (Alt, Cmd)
  ToolMode? _tempToolMode;

  // Highlighted note from Virtual Piano (for Piano Roll sync)
  int? _highlightedNote;

  /// Whether the selected track is an audio track
  bool get _isAudioTrack => widget.selectedTrackType?.toLowerCase() == 'audio';

  /// Get the first tab label based on track type
  /// For audio tracks, shows the clip filename (truncated if needed)
  /// For MIDI tracks, shows the pattern name (e.g., "Serum" or "Synthesizer")
  String get _firstTabLabel {
    if (_isAudioTrack) {
      final clipName = widget.currentEditingAudioClip?.fileName;
      if (clipName != null && clipName.isNotEmpty) {
        return clipName.length > 20 ? '${clipName.substring(0, 17)}...' : clipName;
      }
      return 'Audio Editor';
    }

    // MIDI track: show pattern name from clip
    if (widget.currentEditingClip != null) {
      final clipName = widget.currentEditingClip!.name;
      // Truncate if too long
      if (clipName.length > 20) {
        return '${clipName.substring(0, 17)}...';
      }
      return clipName;
    }

    return 'Piano Roll';
  }

  /// Get the first tab icon based on track type
  IconData get _firstTabIcon => _isAudioTrack ? Icons.audio_file : Icons.piano;

  @override
  void initState() {
    super.initState();
    // Audio tracks have 2 tabs (Editor, Effects), MIDI tracks have 3 (Piano Roll, Effects, Instrument)
    final tabCount = _isAudioTrack ? 2 : 3;
    _tabController = TabController(length: tabCount, vsync: this);
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

    // Check if track type changed (switching between audio and MIDI tracks)
    final oldIsAudio = oldWidget.selectedTrackType?.toLowerCase() == 'audio';
    final newIsAudio = _isAudioTrack;
    if (oldIsAudio != newIsAudio) {
      // Recreate tab controller with new length - wrap in setState to ensure rebuild
      setState(() {
        final newTabCount = newIsAudio ? 2 : 3;
        _tabController.dispose();
        _tabController = TabController(length: newTabCount, vsync: this);
        _tabController.addListener(() {
          setState(() {
            _selectedTabIndex = _tabController.index;
          });
        });
        _selectedTabIndex = 0; // Reset to first tab
      });
      return; // Exit early to avoid setting index on newly created controller
    }

    // Only auto-switch tabs if this is the first track selection (from null)
    // Otherwise, preserve the current tab when switching between tracks
    if (widget.selectedTrackId != oldWidget.selectedTrackId) {
      if (oldWidget.selectedTrackId == null && widget.selectedTrackId != null) {
        // First selection: auto-switch to appropriate tab
        if (!_isAudioTrack && widget.currentInstrumentData != null) {
          _tabController.index = 2; // Instrument tab (only for MIDI tracks)
        } else {
          _tabController.index = 0; // Piano Roll/Audio Editor tab
        }
      }
      // If switching from one track to another, preserve current tab
    }

    // Auto-switch to Piano Roll tab when MIDI clip selected
    if (widget.currentEditingClip != null && oldWidget.currentEditingClip == null) {
      _tabController.index = 0;
    }

    // Auto-switch to Audio Editor tab when audio clip selected
    if (widget.currentEditingAudioClip != null && oldWidget.currentEditingAudioClip == null) {
      _tabController.index = 0;
    }

    // Auto-switch to Instrument tab when instrument data first appears (MIDI tracks only)
    if (!_isAudioTrack && widget.currentInstrumentData != null && oldWidget.currentInstrumentData == null) {
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
    // Check if Shift, Alt, or Cmd/Ctrl modifiers changed
    if (ToolModeResolver.isModifierKey(event.logicalKey)) {
      _updateTempToolMode();
    }
    return false; // Don't consume the event
  }

  /// Update temporary tool mode based on held modifiers
  void _updateTempToolMode() {
    final modifiers = ModifierKeyState.current();
    setState(() {
      _tempToolMode = modifiers.getOverrideToolMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show collapsed bar when collapsed
    if (widget.isCollapsed) {
      return _buildCollapsedBar();
    }

    // Check if current track is MIDI (can accept instrument drops)
    // Note: selectedTrackType can be 'MIDI', 'midi', 'Audio', etc.
    final isMidiTrack = widget.selectedTrackType?.toLowerCase() == 'midi';

    // Wrap with DragTargets for instrument swapping
    return DragTarget<Vst3Plugin>(
      onWillAcceptWithDetails: (details) {
        // Only accept VST3 instruments on MIDI tracks
        return isMidiTrack && details.data.isInstrument;
      },
      onAcceptWithDetails: (details) {
        widget.onVst3InstrumentDropped?.call(details.data);
      },
      builder: (context, candidateVst3, rejectedVst3) {
        return DragTarget<Instrument>(
          onWillAcceptWithDetails: (_) => isMidiTrack,
          onAcceptWithDetails: (details) {
            widget.onInstrumentDropped?.call(details.data);
          },
          builder: (context, candidateInstrument, rejectedInstrument) {
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
            child: Stack(
              children: [
                // Left side: Tab buttons
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabButton(0, _firstTabIcon, _firstTabLabel),
                      const SizedBox(width: 4),
                      _buildTabButton(1, Icons.equalizer, 'Effects'),
                      // Instrument tab only shown for MIDI tracks
                      if (!_isAudioTrack) ...[
                        const SizedBox(width: 4),
                        _buildTabButton(2, Icons.music_note, _getInstrumentTabLabel()),
                      ],
                    ],
                  ),
                ),
                // Center: Tool buttons (truly centered)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                // Right side: Virtual Piano toggle + Collapse button
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Virtual Piano toggle - only for MIDI tracks
                      if (!_isAudioTrack) ...[
                        _buildPianoToggle(),
                        const SizedBox(width: 8),
                      ],
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
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab content expands to fill available space
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEditorTab(), // Context-sensitive: Audio Editor or Piano Roll
                _buildFXChainTab(),
                // Instrument tab only for MIDI tracks
                if (!_isAudioTrack) _buildInstrumentTab(),
              ],
            ),
          ),
        ],
      ),
    );
          },
        );
      },
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
      child: Stack(
        children: [
          // Left side: Tab buttons
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCollapsedTabButton(0, _firstTabIcon, _firstTabLabel),
                const SizedBox(width: 4),
                _buildCollapsedTabButton(1, Icons.equalizer, 'Effects'),
                // Instrument tab only shown for MIDI tracks
                if (!_isAudioTrack) ...[
                  const SizedBox(width: 4),
                  _buildCollapsedTabButton(2, Icons.music_note, _getInstrumentTabLabel()),
                ],
              ],
            ),
          ),
          // Center: Tool buttons (truly centered)
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
          // Right side: Virtual Piano toggle + Expand button
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Virtual Piano toggle - only for MIDI tracks
                if (!_isAudioTrack) ...[
                  _buildPianoToggle(),
                  const SizedBox(width: 8),
                ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build collapsed tab button - clicking expands panel and switches to tab
  /// Shows both icon and label text for clarity when panel is collapsed
  Widget _buildCollapsedTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Material(
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? context.colors.accent : context.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? context.colors.accent : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get dynamic instrument tab label based on current instrument
  String _getInstrumentTabLabel() {
    if (widget.currentInstrumentData == null) {
      return 'Instrument';
    }
    if (widget.currentInstrumentData!.isVst3) {
      final name = widget.currentInstrumentData!.pluginName ?? 'Plugin';
      // Truncate to max 15 characters with ellipsis
      return name.length > 15 ? '${name.substring(0, 12)}...' : name;
    }
    return 'Synthesizer';
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
  /// Shows full highlight for active sticky tool, dimmer highlight for temporary hold modifier.
  /// Tools are always enabled - they work in Arrangement View for both MIDI and audio clips.
  Widget _buildToolButton(ToolMode mode, IconData icon, String tooltip) {
    final isActive = widget.toolMode == mode;
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
        onTap: () => widget.onToolModeChanged?.call(mode),
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

  /// Build the first tab content - switches between Audio Editor and Piano Roll
  /// based on the selected track type.
  Widget _buildEditorTab() {
    if (_isAudioTrack) {
      return _buildAudioEditorTab();
    } else {
      return _buildPianoRollTab();
    }
  }

  /// Build the Audio Editor tab for audio tracks
  Widget _buildAudioEditorTab() {
    final clipData = widget.currentEditingAudioClip;

    if (clipData == null) {
      // No audio clip selected - show empty state
      return ColoredBox(
        color: context.colors.dark,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.audio_file,
                size: 64,
                color: context.colors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Audio Editor',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select an audio clip to start editing',
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

    return AudioEditor(
      audioEngine: widget.audioEngine,
      clipData: clipData,
      onClipUpdated: widget.onAudioClipUpdated,
      toolMode: widget.toolMode,
      onToolModeChanged: widget.onToolModeChanged,
    );
  }

  Widget _buildPianoRollTab() {
    // Check if we have a real clip selected
    final clipData = widget.currentEditingClip;

    // Track selected but no clip - show "Click to create" message
    if (clipData == null && widget.selectedTrackId != null) {
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
                'Click to create MIDI clip',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No track selected - show empty state
    if (clipData == null) {
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
      toolMode: widget.toolMode,
      onToolModeChanged: widget.onToolModeChanged,
      highlightedNote: _highlightedNote,
      virtualPianoVisible: widget.virtualPianoEnabled,
      onVirtualPianoToggle: widget.onVirtualPianoToggle,
      beatsPerBar: widget.beatsPerBar,
      beatUnit: widget.beatUnit,
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
