import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import '../models/tool_mode.dart';
import '../services/tool_mode_resolver.dart';
import 'piano_roll.dart';
import 'audio_editor/audio_editor.dart';
import 'sampler_editor/sampler_editor.dart';
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

  // Project tempo (for warp calculations in Audio Editor)
  final double projectTempo;
  final Function(double)? onProjectTempoChanged;

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
    this.projectTempo = 120.0,
    this.onProjectTempoChanged,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Track if user manually selected a tab (vs auto-switching)
  bool _userManuallySelectedTab = false;

  // Track last track/clip IDs to detect changes
  int? _lastTrackId;
  int? _lastClipId;

  // Flag to indicate we just switched to Piano Roll expecting clip data
  // This prevents showing "Click to create clip" placeholder during transition
  bool _switchedToPianoRollAwaitingData = false;

  // Temporary tool mode when holding modifier keys (Alt, Cmd)
  ToolMode? _tempToolMode;

  // Highlighted note from Virtual Piano (for Piano Roll sync)
  int? _highlightedNote;

  /// Whether the selected track is an audio track
  bool get _isAudioTrack => widget.selectedTrackType?.toLowerCase() == 'audio';

  /// Whether the selected track is a sampler track
  bool get _isSamplerTrack => widget.selectedTrackType?.toLowerCase() == 'sampler';

  /// Whether the selected track is a MIDI track (not sampler)
  bool get _isMidiTrack => widget.selectedTrackType?.toLowerCase() == 'midi';

  /// Get the first tab label based on track type
  /// For audio tracks, shows the clip filename (truncated if needed)
  /// For sampler tracks, shows "Sampler" or sample filename
  /// For MIDI tracks, shows the pattern name (e.g., "Serum" or "Synthesizer")
  String get _firstTabLabel {
    if (_isAudioTrack) {
      final clipName = widget.currentEditingAudioClip?.fileName;
      if (clipName != null && clipName.isNotEmpty) {
        return clipName.length > 20 ? '${clipName.substring(0, 17)}...' : clipName;
      }
      return 'Audio Editor';
    }

    if (_isSamplerTrack) {
      return 'Sampler';
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
  IconData get _firstTabIcon {
    if (_isAudioTrack) return Icons.audio_file;
    if (_isSamplerTrack) return Icons.music_note;
    return Icons.piano;
  }

  /// Get the number of tabs based on track type
  /// Audio: 2 tabs (Editor, Effects)
  /// MIDI: 3 tabs (Piano Roll, Effects, Instrument)
  /// Sampler: 3 tabs (Sampler, Piano Roll, Effects)
  int get _tabCount {
    if (_isAudioTrack) return 2;
    if (_isSamplerTrack) return 3;
    return 3; // MIDI
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
    // Listen for modifier key changes
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  /// Get the current clip ID (MIDI or audio)
  int? _getCurrentClipId() {
    return widget.currentEditingClip?.clipId ?? widget.currentEditingAudioClip?.clipId;
  }

  /// Handle user manually tapping a tab
  void _onManualTabTap(int index) {
    _userManuallySelectedTab = true;
    _switchedToPianoRollAwaitingData = false; // Reset awaiting flag on manual selection
    _tabController.index = index;
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if track type changed (switching between audio, MIDI, or sampler tracks)
    final oldType = oldWidget.selectedTrackType?.toLowerCase();
    final newType = widget.selectedTrackType?.toLowerCase();
    if (oldType != newType) {
      // Recreate tab controller with new length - wrap in setState to ensure rebuild
      setState(() {
        _tabController.dispose();
        _tabController = TabController(length: _tabCount, vsync: this);
        _tabController.addListener(() {
          setState(() {
            _selectedTabIndex = _tabController.index;
          });
        });
        _selectedTabIndex = 0; // Reset to first tab
        _userManuallySelectedTab = false; // Reset manual flag on track type change
        _switchedToPianoRollAwaitingData = false; // Reset awaiting flag
      });
      _lastTrackId = widget.selectedTrackId;
      _lastClipId = _getCurrentClipId();
      return; // Exit early to avoid setting index on newly created controller
    }

    final trackChanged = widget.selectedTrackId != _lastTrackId;
    final currentClipId = _getCurrentClipId();
    final clipChanged = currentClipId != _lastClipId;

    // Track changed → reset to Instrument tab (tab 0) for MIDI/Sampler
    if (trackChanged && widget.selectedTrackId != null) {
      _userManuallySelectedTab = false; // Reset manual flag on track change
      _switchedToPianoRollAwaitingData = false; // Reset awaiting flag
      if (_isMidiTrack || _isSamplerTrack) {
        _tabController.index = 0; // Instrument/Sampler tab
      } else if (_isAudioTrack) {
        _tabController.index = 0; // Audio Editor tab
      }
    }
    // Clip selected (and user hasn't manually chosen a tab) → Piano Roll
    else if (clipChanged && currentClipId != null && !_userManuallySelectedTab) {
      if (_isMidiTrack || _isSamplerTrack) {
        // Set flag to prevent showing "Click to create clip" placeholder during transition
        // This handles the case where tab switches but clip data takes a frame to propagate
        _switchedToPianoRollAwaitingData = widget.currentEditingClip == null;
        _tabController.index = 1; // Piano Roll tab
      } else if (_isAudioTrack) {
        _tabController.index = 0; // Audio Editor tab
      }
    }
    // Clip deselected → back to Instrument tab
    else if (clipChanged && currentClipId == null && _lastClipId != null) {
      _userManuallySelectedTab = false; // Reset manual flag when clip deselected
      _switchedToPianoRollAwaitingData = false; // Reset awaiting flag
      if (_isMidiTrack || _isSamplerTrack) {
        _tabController.index = 0; // Instrument/Sampler tab
      }
    }

    // Update tracking state
    _lastTrackId = widget.selectedTrackId;
    _lastClipId = currentClipId;
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
                    children: _buildTabButtons(),
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
                      // Virtual Piano toggle - for MIDI and Sampler tracks
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
              children: _buildTabContent(),
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
              children: _buildCollapsedTabButtons(),
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
                // Virtual Piano toggle - for MIDI and Sampler tracks
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

  /// Build the collapsed tab buttons based on track type
  List<Widget> _buildCollapsedTabButtons() {
    if (_isAudioTrack) {
      return [
        _buildCollapsedTabButton(0, _firstTabIcon, _firstTabLabel),
        const SizedBox(width: 4),
        _buildCollapsedTabButton(1, Icons.equalizer, 'Effects'),
      ];
    }

    if (_isSamplerTrack) {
      return [
        _buildCollapsedTabButton(0, Icons.music_note, 'Sampler'),
        const SizedBox(width: 4),
        _buildCollapsedTabButton(1, Icons.piano, 'Piano Roll'),
        const SizedBox(width: 4),
        _buildCollapsedTabButton(2, Icons.equalizer, 'Effects'),
      ];
    }

    // MIDI track: [Synthesizer] [Piano Roll] [Effects]
    return [
      _buildCollapsedTabButton(0, Icons.music_note, _getInstrumentTabLabel()),
      const SizedBox(width: 4),
      _buildCollapsedTabButton(1, _firstTabIcon, _firstTabLabel),
      const SizedBox(width: 4),
      _buildCollapsedTabButton(2, Icons.equalizer, 'Effects'),
    ];
  }

  /// Build collapsed tab button - clicking expands panel and switches to tab
  /// Shows both icon and label text for clarity when panel is collapsed
  Widget _buildCollapsedTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _onManualTabTap(index);
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

  /// Build the tab buttons based on track type
  /// Audio: [Editor, Effects]
  /// MIDI: [Piano Roll, Effects, Instrument]
  /// Sampler: [Sampler, Piano Roll, Effects]
  List<Widget> _buildTabButtons() {
    if (_isAudioTrack) {
      return [
        _buildTabButton(0, _firstTabIcon, _firstTabLabel),
        const SizedBox(width: 4),
        _buildTabButton(1, Icons.equalizer, 'Effects'),
      ];
    }

    if (_isSamplerTrack) {
      return [
        _buildTabButton(0, Icons.music_note, 'Sampler'),
        const SizedBox(width: 4),
        _buildTabButton(1, Icons.piano, 'Piano Roll'),
        const SizedBox(width: 4),
        _buildTabButton(2, Icons.equalizer, 'Effects'),
      ];
    }

    // MIDI track: [Synthesizer] [Piano Roll] [Effects]
    return [
      _buildTabButton(0, Icons.music_note, _getInstrumentTabLabel()),
      const SizedBox(width: 4),
      _buildTabButton(1, _firstTabIcon, _firstTabLabel),
      const SizedBox(width: 4),
      _buildTabButton(2, Icons.equalizer, 'Effects'),
    ];
  }

  /// Build the tab content based on track type
  /// Audio: [AudioEditor, FXChain]
  /// MIDI: [PianoRoll, FXChain, Instrument]
  /// Sampler: [SamplerEditor, PianoRoll, FXChain]
  List<Widget> _buildTabContent() {
    if (_isAudioTrack) {
      return [
        _buildEditorTab(),
        _buildFXChainTab(),
      ];
    }

    if (_isSamplerTrack) {
      return [
        _buildSamplerEditorTab(),
        _buildPianoRollTab(),
        _buildFXChainTab(),
      ];
    }

    // MIDI track: [Synthesizer] [Piano Roll] [Effects]
    return [
      _buildInstrumentTab(),
      _buildEditorTab(),
      _buildFXChainTab(),
    ];
  }

  /// Build the Sampler Editor tab
  /// Shows audio waveform with sampler-specific controls (Attack, Release, Root Note)
  Widget _buildSamplerEditorTab() {
    return SamplerEditor(
      audioEngine: widget.audioEngine,
      trackId: widget.selectedTrackId,
      onClose: widget.onClosePanel,
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
            _onManualTabTap(index);
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
      projectTempo: widget.projectTempo,
      onProjectTempoChanged: widget.onProjectTempoChanged,
    );
  }

  Widget _buildPianoRollTab() {
    // Check if we have a real clip selected
    final clipData = widget.currentEditingClip;

    // Clear the awaiting flag if clip data has arrived
    if (clipData != null && _switchedToPianoRollAwaitingData) {
      _switchedToPianoRollAwaitingData = false;
    }

    // Track selected but no clip - show "Click to create" message
    // BUT: if we just switched to Piano Roll expecting clip data, show empty state
    // to avoid flashing the placeholder while data propagates
    if (clipData == null && widget.selectedTrackId != null) {
      // If we're awaiting clip data (just switched tabs), show minimal empty state
      if (_switchedToPianoRollAwaitingData) {
        return ColoredBox(color: context.colors.dark, child: const SizedBox());
      }
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
