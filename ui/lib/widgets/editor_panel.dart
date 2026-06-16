import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../theme/animation_constants.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../models/tool_mode.dart';
import '../services/tool_mode_resolver.dart';
import '../utils/logger.dart';
import '../services/undo_redo_manager.dart';
import 'drum_kit_editor/drum_kit_editor.dart';
import 'editor_button_variant.dart';
import 'piano_roll.dart';
import 'audio_editor/audio_editor.dart';
import 'device_chain/device_chain_view.dart';
import 'device_chain/device_dropdown.dart';
import 'sampler_editor/sampler_editor.dart';
import 'preset_nav.dart';
import 'preset_browser_dropdown.dart';
import 'instrument_browser.dart';
import '../models/midi_note_data.dart';
import '../models/clip_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import 'editor/editor_models.dart';

/// Editor panel widget - tabbed interface for Piano Roll/Audio Editor, Effects, Instrument
class EditorPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool virtualPianoEnabled;

  // Grouped: track context
  final EditorPanelContext trackContext;

  // Grouped: panel UI callbacks
  final EditorPanelCallbacks callbacks;

  // Grouped: VST3-specific callbacks
  final Vst3EditorCallbacks vst3Callbacks;

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

  /// All installed VST3 plugins (from Vst3PluginManager.availablePlugins).
  /// Forwarded to the device chain so the picker can show plugin rows.
  final List<Map<String, String>> availableVst3Plugins;

  // Collapsed bar mode
  final bool isCollapsed;

  // Instrument swap via drag-and-drop (non-VST3)
  final Function(Instrument)? onInstrumentDropped;

  // Effect drag-and-drop callbacks from device chain
  final Function(String effectType)? onBuiltInEffectDropped;
  final Function(Vst3Plugin plugin)? onVst3EffectDropped;

  // Tool mode (shared with arrangement view)
  final ToolMode toolMode;

  // Visual language for the tabs + tool palette (dev UI Labs A/B/C, Cmd+Shift+E)
  final EditorButtonVariant editorButtonVariant;

  // Time signature (from project settings)
  final int beatsPerBar;
  final int beatUnit;

  // Commits a piano-roll Signature edit to the project time signature
  // (same undoable command as the transport-bar control).
  final void Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  // Coalesce the Signature drag-to-scrub into one undo step (same contract
  // as the transport-bar control).
  final VoidCallback? onTimeSignatureDragStart;
  final VoidCallback? onTimeSignatureDragEnd;

  // Project tempo (for warp calculations in Audio Editor)
  final double projectTempo;
  final Function(double)? onProjectTempoChanged;

  // Whether recording is active (piano roll becomes read-only)
  final bool isRecording;

  // Track color for MIDI note rendering in Piano Roll
  final Color? trackColor;

  // Create sampler from audio clip
  final Function(String clipPath)? onCreateSamplerFromClip;

  // Shared undo manager — drum-kit step toggles execute commands on it so
  // Cmd+Z reverts them through the app's normal undo path.
  final UndoRedoManager? undoManager;

  // Playback position in seconds — drives the drum step sequencer's playing
  // column highlight (same notifier the timeline playhead uses).
  final ValueListenable<double>? playheadNotifier;

  // Whether transport is playing — drives the piano-roll playhead *line*
  // colour (white playing / grey at rest); the grabber stays calm grey.
  final bool isPlaying;

  // Seek the transport to a global position (seconds) — wired so the
  // piano-roll ruler drag moves the playhead, matching the arrangement.
  final void Function(double seconds)? onSeek;

  const EditorPanel({
    super.key,
    this.audioEngine,
    this.virtualPianoEnabled = false,
    this.trackContext = const EditorPanelContext(),
    this.callbacks = const EditorPanelCallbacks(),
    this.vst3Callbacks = const Vst3EditorCallbacks(),
    this.currentEditingClip,
    this.onMidiClipUpdated,
    this.onInstrumentParameterChanged,
    this.ghostNotes = const [],
    this.currentEditingAudioClip,
    this.onAudioClipUpdated,
    this.currentTrackPlugins,
    this.availableVst3Plugins = const [],
    this.isCollapsed = false,
    this.onInstrumentDropped,
    this.onBuiltInEffectDropped,
    this.onVst3EffectDropped,
    this.toolMode = ToolMode.draw,
    this.editorButtonVariant = EditorButtonVariant.outline,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onTimeSignatureChanged,
    this.onTimeSignatureDragStart,
    this.onTimeSignatureDragEnd,
    this.projectTempo = 120.0,
    this.onProjectTempoChanged,
    this.isRecording = false,
    this.trackColor,
    this.onCreateSamplerFromClip,
    this.undoManager,
    this.playheadNotifier,
    this.isPlaying = false,
    this.onSeek,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel>
    with TickerProviderStateMixin {
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

  // Which tool button the pointer is currently over (drives the inactive-hover
  // tint, matching the top-bar split buttons). Null when nothing is hovered.
  ToolMode? _hoveredTool;

  // Same for the editor tab buttons — inactive tabs had no hover feedback.
  int? _hoveredTabIndex;

  // Highlighted note from Virtual Piano (for Piano Roll sync)
  int? _highlightedNote;

  // Preset state
  List<PresetFolder> _presetFolders = [];
  int? _currentPresetListId;
  int? _currentPresetIndex;
  String _currentPresetName = '- Init -';
  bool _presetDropdownOpen = false;
  final LayerLink _presetLayerLink = LayerLink();
  OverlayEntry? _presetOverlayEntry;

  // Callback for resetting VST3 instrument to default state
  VoidCallback? _resetPluginToDefault;

  // Key for instrument tab button (used to position dropdown)
  final _instrumentTabKey = GlobalKey();

  /// Whether the selected track is an audio track
  bool get _isAudioTrack =>
      widget.trackContext.selectedTrackType?.toLowerCase() == 'audio';

  /// Whether the selected track has a sampler instrument (checked via engine)
  bool get _isSamplerTrack =>
      widget.audioEngine != null &&
      widget.trackContext.selectedTrackId != null &&
      widget.audioEngine!.isSamplerTrack(widget.trackContext.selectedTrackId!);

  /// Whether the selected track holds a drum-kit instrument (checked via engine)
  bool get _isDrumKitTrack =>
      widget.audioEngine != null &&
      widget.trackContext.selectedTrackId != null &&
      widget.audioEngine!.isDrumKitTrack(widget.trackContext.selectedTrackId!);

  /// Whether the selected track is a MIDI track without a sampler/drum-kit
  bool get _isMidiTrack =>
      widget.trackContext.selectedTrackType?.toLowerCase() == 'midi' &&
      !_isSamplerTrack &&
      !_isDrumKitTrack;

  /// Whether the selected track is the Master bus (effects chain only — no
  /// instrument, no piano roll).
  bool get _isMasterTrack =>
      widget.trackContext.selectedTrackType?.toLowerCase() == 'master';

  /// Get the first tab label based on track type
  /// For audio tracks, shows the clip filename (truncated if needed)
  /// For sampler tracks, shows "Sampler" or sample filename
  /// For MIDI tracks, shows the pattern name (e.g., "Serum" or "Synthesizer")
  String get _firstTabLabel {
    if (_isAudioTrack) {
      final clipName = widget.currentEditingAudioClip?.fileName;
      if (clipName != null && clipName.isNotEmpty) {
        return clipName.length > 20
            ? '${clipName.substring(0, 17)}...'
            : clipName;
      }
      return 'Audio Editor';
    }

    // MIDI / sampler tracks: show pattern name from clip
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

  /// The single source of truth for the editor's tabs.
  ///
  /// The expanded tab strip, the collapsed tab strip, the TabBarView content,
  /// and the TabController length are ALL derived from this list, so they can
  /// never disagree on tab count or order. (The collapsed strip used to build
  /// its own per-track-type list and drifted: a phantom third "Effects" button
  /// for MIDI tracks, and no master-track branch at all — both pointed past
  /// the real controller and threw RangeErrors. Bug-hunt #7.)
  ///
  /// Audio:    [Audio Editor] [Effects]
  /// MIDI:     [Instrument]   [MIDI]
  /// Sampler:  [Instrument]   [Sampler]  [MIDI]
  /// Drum kit: [Drum Kit]     [MIDI]
  /// Master:   [Effects]
  List<_EditorTab> get _tabs {
    if (_isMasterTrack) {
      // Master: effects chain only (no instrument, no piano roll)
      return [
        _EditorTab(
          icon: BI.lightning,
          label: 'Effects',
          content: _buildChainTab,
        ),
      ];
    }

    if (_isAudioTrack) {
      return [
        _EditorTab(
          icon: BI.audioFile,
          label: 'Audio',
          // Collapsed bar has room for the clip filename
          collapsedLabel: _firstTabLabel,
          content: _buildAudioEditorTab,
        ),
        _EditorTab(
          icon: BI.lightning,
          label: 'Effects',
          content: _buildChainTab,
        ),
      ];
    }

    if (_isSamplerTrack) {
      // Sampler tracks: device chain (with Sampler placeholder block) +
      // dedicated Sampler editor + MIDI piano roll. Three tabs so the chain
      // remains the default view and the instrument slot stays visible after
      // a synth→sampler swap.
      return [
        _EditorTab(
          icon: BI.piano,
          label: 'Instrument',
          buttonKey: _instrumentTabKey,
          content: _buildChainTab,
        ),
        _EditorTab(
          icon: BI.musicNote,
          label: 'Sampler',
          content: _buildSamplerTab,
        ),
        _EditorTab(
          icon: BI.piano,
          label: 'MIDI',
          collapsedLabel: _firstTabLabel,
          content: _buildPianoRollTab,
        ),
      ];
    }

    if (_isDrumKitTrack) {
      return [
        _EditorTab(
          icon: BI.gridOn,
          label: 'Drum Kit',
          buttonKey: _instrumentTabKey,
          content: _buildDrumKitTab,
        ),
        _EditorTab(
          icon: BI.piano,
          // Same label expanded and collapsed — it read "MIDI" in one bar and
          // "Piano Roll" in the other for the same tab.
          label: 'MIDI',
          content: _buildPianoRollTab,
        ),
      ];
    }

    // Plain MIDI track: instrument + effects chain, then piano roll
    return [
      _EditorTab(
        icon: _instrumentTabIcon,
        label: _getInstrumentTabLabel(),
        buttonKey: _instrumentTabKey,
        content: _buildChainTab,
      ),
      _EditorTab(
        icon: BI.piano,
        label: 'MIDI',
        // Collapsed bar has room for the clip/pattern name
        collapsedLabel: _firstTabLabel,
        content: _buildEditorTab,
      ),
    ];
  }

  /// Number of tabs for the current track type — derived from [_tabs] so the
  /// TabController length always matches what the strips render.
  int get _tabCount => _tabs.length;

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
    return widget.currentEditingClip?.clipId ??
        widget.currentEditingAudioClip?.clipId;
  }

  /// Handle user manually tapping a tab.
  /// If already on the instrument tab (index 0) and not audio track,
  /// open the instrument dropdown instead of no-op. The Master track is
  /// excluded too: its single Effects tab has no instrument dropdown (and no
  /// buttonKey to anchor one), so re-tapping it would only do a pointless
  /// RenderBox lookup that returns silently.
  void _onManualTabTap(int index) {
    if (_selectedTabIndex == index &&
        index == 0 &&
        !_isAudioTrack &&
        !_isMasterTrack) {
      _showInstrumentDropdownFromTab();
      return;
    }
    _userManuallySelectedTab = true;
    _switchedToPianoRollAwaitingData = false;
    _tabController.index = index;
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if track type changed (switching between audio, MIDI, or sampler tracks)
    final oldType = oldWidget.trackContext.selectedTrackType?.toLowerCase();
    final newType = widget.trackContext.selectedTrackType?.toLowerCase();
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
        _userManuallySelectedTab =
            false; // Reset manual flag on track type change
        _switchedToPianoRollAwaitingData = false; // Reset awaiting flag
      });
      _lastTrackId = widget.trackContext.selectedTrackId;
      _lastClipId = _getCurrentClipId();
      return; // Exit early to avoid setting index on newly created controller
    }

    // Handle synth↔sampler conversion: track type stays 'midi' but the sampler
    // 3-tab layout (Instrument | Sampler | MIDI) differs from the synth 2-tab
    // layout (Instrument | MIDI). Recreate the controller when the count drifts.
    if (_tabController.length != _tabCount) {
      setState(() {
        _tabController.dispose();
        _tabController = TabController(length: _tabCount, vsync: this);
        _tabController.addListener(() {
          setState(() {
            _selectedTabIndex = _tabController.index;
          });
        });
        _selectedTabIndex = 0;
        _userManuallySelectedTab = false;
        _switchedToPianoRollAwaitingData = false;
      });
      _lastTrackId = widget.trackContext.selectedTrackId;
      _lastClipId = _getCurrentClipId();
      return;
    }

    final trackChanged = widget.trackContext.selectedTrackId != _lastTrackId;
    final currentClipId = _getCurrentClipId();
    final clipChanged = currentClipId != _lastClipId;

    // Track changed → choose appropriate default tab
    if (trackChanged && widget.trackContext.selectedTrackId != null) {
      _userManuallySelectedTab = false;
      _switchedToPianoRollAwaitingData = false;
      _loadPresets();
      // Always default to Instrument/Effects tab (tab 0) on track change.
      // User clicks MIDI/Piano Roll tab when they want to edit notes.
      _tabController.index = 0;
    }
    // Clip selected (and user hasn't manually chosen a tab) → MIDI tab
    else if (clipChanged &&
        currentClipId != null &&
        !_userManuallySelectedTab) {
      // Drum-kit tracks keep tab 0 (the step sequencer is the primary editor);
      // only MIDI/sampler jump to the piano roll on clip select.
      if (_isMidiTrack) {
        _switchedToPianoRollAwaitingData = widget.currentEditingClip == null;
        _tabController.index = 1; // MIDI tab
      } else if (_isSamplerTrack) {
        _switchedToPianoRollAwaitingData = widget.currentEditingClip == null;
        _tabController.index = 2; // MIDI is 3rd tab in sampler's 3-tab layout
      }
    }
    // Clip deselected → back to chain tab
    else if (clipChanged && currentClipId == null && _lastClipId != null) {
      _userManuallySelectedTab = false;
      _switchedToPianoRollAwaitingData = false;
      if (_isMidiTrack || _isSamplerTrack) {
        _tabController.index = 0; // Chain tab
      }
    }

    // Update tracking state
    _lastTrackId = widget.trackContext.selectedTrackId;
    _lastClipId = currentClipId;
  }

  @override
  void dispose() {
    // Remove overlay directly without setState (widget is being disposed)
    _presetOverlayEntry?.remove();
    _presetOverlayEntry = null;
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

    // Expanded but nothing selected (e.g. after deselecting via an empty mixer
    // click): keep the panel open at its height and show a placeholder rather
    // than the tabs/content, which assume a track. No tab bar or tools here —
    // there's nothing to act on until a track is picked.
    if (widget.trackContext.selectedTrackId == null) {
      return _buildNoSelectionState();
    }

    // Check if current track is MIDI (can accept instrument drops)
    // Note: selectedTrackType can be 'MIDI', 'midi', 'Audio', etc.
    final isMidiTrack =
        widget.trackContext.selectedTrackType?.toLowerCase() == 'midi';

    // Evaluate the tab list once per frame: the getter runs the FFI-backed
    // sampler/drum-kit track checks, so each extra read is 2 engine
    // round-trips.
    final tabs = _tabs;

    // Wrap with DragTargets for instrument swapping
    return DragTarget<Vst3Plugin>(
      onWillAcceptWithDetails: (details) {
        // Only accept VST3 instruments on MIDI tracks
        return isMidiTrack && details.data.isInstrument;
      },
      onAcceptWithDetails: (details) {
        widget.vst3Callbacks.onVst3InstrumentDropped?.call(details.data);
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
                border: Border(top: BorderSide(color: context.colors.divider)),
              ),
              child: Column(
                children: [
                  // Custom tab bar with icons and pill-style active indicator
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.colors.dark,
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
                            children: _buildTabButtons(tabs),
                          ),
                        ),
                        // Center: Tool buttons (truly centered across full width)
                        Positioned.fill(child: Center(child: _buildToolRow())),
                        // Right side: Preset nav + Piano toggle + Collapse button
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Preset navigation - for VST3 instruments with presets
                              if (_shouldShowPresetNav) ...[
                                CompositedTransformTarget(
                                  link: _presetLayerLink,
                                  child: PresetNav(
                                    currentPresetName: _currentPresetName,
                                    hasPrevious:
                                        _currentPresetIndex != null &&
                                        _currentPresetIndex! > 0,
                                    hasNext:
                                        _currentPresetIndex != null &&
                                        _currentPresetListId != null &&
                                        _presetFolders
                                            .where(
                                              (f) =>
                                                  f.listId ==
                                                  _currentPresetListId,
                                            )
                                            .any(
                                              (f) =>
                                                  _currentPresetIndex! <
                                                  f.programCount - 1,
                                            ),
                                    onPrevious: _onPreviousPreset,
                                    onNext: _onNextPreset,
                                    onDropdownTap: _showPresetBrowser,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // Virtual Piano toggle removed from toolbar (v0.2.1)
                              // Still accessible via P key and View menu
                              // Collapse chevron (rightmost)
                              _buildCollapseChevron(isCollapsed: false),
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
                      children: _buildTabContent(tabs),
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
  /// The centered Draw/Select/Erase/Duplicate/Slice tool buttons. Shared by the
  /// expanded editor and the no-selection state — the tools aren't track-bound,
  /// so they stay available (and keep their active mode) even with no selection.
  Widget _buildToolRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToolButton(ToolMode.draw, BI.pencil, 'Draw (Z)'),
        const SizedBox(width: 4),
        _buildToolButton(ToolMode.select, BI.selection, 'Select (X)'),
        const SizedBox(width: 4),
        _buildToolButton(ToolMode.eraser, BI.eraser, 'Erase (C) • Hold Alt'),
        const SizedBox(width: 4),
        _buildToolButton(
          ToolMode.duplicate,
          BI.copy,
          'Duplicate (V) • Cmd+Drag',
        ),
        const SizedBox(width: 4),
        _buildToolButton(ToolMode.slice, BI.cut, 'Slice (B) • Cmd+Click'),
      ],
    );
  }

  /// Shown when the panel is open but no track is selected. Keeps the toolbar
  /// (tool buttons + collapse chevron) so the panel stays put and the tools stay
  /// reachable; the tabs and preset nav are track-specific, so they're omitted.
  /// The content area below shows a centered "pick a track" hint.
  Widget _buildNoSelectionState() {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.dark,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Column(
        children: [
          // Toolbar — same 40px bar as the expanded view, minus tabs/preset nav.
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: colors.dark,
              border: Border(bottom: BorderSide(color: colors.surface)),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: Center(child: _buildToolRow())),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [_buildCollapseChevron(isCollapsed: false)],
                  ),
                ),
              ],
            ),
          ),
          // Empty content area with a centered hint.
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(BI.musicNote, size: 28, color: colors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'No track selected',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                      fontWeight: BT.weightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a track to edit its instrument and notes',
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedBar() {
    // Single per-frame evaluation of the FFI-backed tab list (see build()).
    final tabs = _tabs;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.dark,
        border: Border(top: BorderSide(color: context.colors.divider)),
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
              children: _buildCollapsedTabButtons(tabs),
            ),
          ),
          // Center: Tool buttons (truly centered)
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolButton(ToolMode.draw, BI.pencil, 'Draw (Z)'),
                const SizedBox(width: 4),
                _buildToolButton(ToolMode.select, BI.selection, 'Select (X)'),
                const SizedBox(width: 4),
                _buildToolButton(
                  ToolMode.eraser,
                  BI.eraser,
                  'Erase (C) • Hold Alt',
                ),
                const SizedBox(width: 4),
                _buildToolButton(
                  ToolMode.duplicate,
                  BI.copy,
                  'Duplicate (V) • Cmd+Drag',
                ),
                const SizedBox(width: 4),
                _buildToolButton(
                  ToolMode.slice,
                  BI.cut,
                  'Slice (B) • Cmd+Click',
                ),
              ],
            ),
          ),
          // Right side: Expand button
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Virtual Piano toggle hidden from the collapsed bar for now
                // (the _buildPianoToggle widget is kept for easy restore).
                // Expand chevron (rightmost)
                _buildCollapseChevron(isCollapsed: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Chevron toggle at the right edge of the toolbar.
  /// ▼ when expanded (click to collapse), ▲ when collapsed (click to expand).
  Widget _buildCollapseChevron({required bool isCollapsed}) {
    return Tooltip(
      message: isCollapsed ? 'Expand Editor' : 'Collapse Panel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCollapsed
              ? widget.callbacks.onExpandPanel
              : widget.callbacks.onClosePanel,
          borderRadius: BorderRadius.circular(6),
          // Bare glyph — no box/border, just the caret (matches the lighter
          // tool-icon row). The 28×28 keeps the hit target; the InkWell still
          // gives a hover ripple within the rounded area.
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              // Thin two-stroke chevrons (^ / ⌄) in both states — not the
              // filled triangle arrow_drop_down the expanded state used before.
              isCollapsed ? BI.expandLess : BI.expandMore,
              size: 20,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// Build the collapsed tab buttons — derived from [_tabs] (passed in from
  /// [_buildCollapsedBar], see [_buildTabButtons]), same list the expanded
  /// strip and the TabBarView use, so the strips can never disagree.
  /// (The collapsed buttons deliberately don't carry [_EditorTab.buttonKey]:
  /// the instrument-dropdown anchor belongs to the expanded strip only.)
  List<Widget> _buildCollapsedTabButtons(List<_EditorTab> tabs) {
    return [
      for (var i = 0; i < tabs.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        _buildCollapsedTabButton(
          i,
          tabs[i].icon,
          tabs[i].collapsedLabel ?? tabs[i].label,
        ),
      ],
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
          widget.callbacks.onTabAndExpand?.call(index);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.selectionFill
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? context.colors.selectionBorder
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? context.colors.accent
                    : context.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected
                      ? BT.weightSemiBold
                      : FontWeight.normal,
                  color: isSelected
                      ? context.colors.accent
                      : context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get dynamic instrument tab icon based on current instrument
  /// VST3 third-party → plugin icon, built-in → piano icon
  IconData get _instrumentTabIcon {
    if (widget.trackContext.currentInstrumentData?.isVst3 == true) {
      return BI.plugin;
    }
    return BI.piano;
  }

  /// Get dynamic instrument tab label based on current instrument
  String _getInstrumentTabLabel() {
    if (widget.trackContext.currentInstrumentData == null) {
      return 'Instrument';
    }
    if (widget.trackContext.currentInstrumentData!.isVst3) {
      final name =
          widget.trackContext.currentInstrumentData!.pluginName ?? 'Plugin';
      // Truncate to max 15 characters with ellipsis
      return name.length > 15 ? '${name.substring(0, 12)}...' : name;
    }
    return 'Synthesizer';
  }

  /// Whether the current track's VST3 plugin is in a floating window
  bool get _isCurrentPluginFloated {
    final effectId = widget.trackContext.currentInstrumentData?.effectId;
    return effectId != null &&
        widget.trackContext.floatedPluginEffectIds.contains(effectId);
  }

  /// Whether preset nav should be shown — disabled for v0.1.8
  bool get _shouldShowPresetNav => false;

  /// Load presets for the current VST3 instrument
  void _loadPresets() {
    final instrument = widget.trackContext.currentInstrumentData;
    if (instrument == null ||
        !instrument.isVst3 ||
        widget.audioEngine == null) {
      _presetFolders = [];
      _currentPresetListId = null;
      _currentPresetIndex = null;
      _currentPresetName = '- Init -';
      return;
    }

    final json = widget.audioEngine!.getVst3Presets(instrument.effectId!);
    if (json.startsWith('Error') || json == '[]') {
      _presetFolders = [];
      return;
    }

    try {
      final List<dynamic> lists = jsonDecode(json) as List<dynamic>;
      _presetFolders = lists.map((dynamic item) {
        final map = item as Map<String, dynamic>;
        final presets = (map['presets'] as List<dynamic>)
            .map((p) => p as String)
            .toList();
        return PresetFolder(
          listId: map['listId'] as int,
          name: map['name'] as String,
          programCount: map['programCount'] as int,
          presets: presets,
        );
      }).toList();
    } catch (e) {
      // A malformed engine preset payload must leave a trace, not just an
      // unexplained empty preset list.
      Log.e('EditorPanel: preset folder parse failed: $e');
      _presetFolders = [];
    }
  }

  /// Navigate to previous preset in current folder
  void _onPreviousPreset() {
    if (_currentPresetListId == null || _currentPresetIndex == null) return;
    if (_currentPresetIndex! <= 0) return;
    _selectPreset(_currentPresetListId!, _currentPresetIndex! - 1);
  }

  /// Navigate to next preset in current folder
  void _onNextPreset() {
    if (_currentPresetListId == null || _currentPresetIndex == null) return;
    final folder = _presetFolders
        .where((f) => f.listId == _currentPresetListId)
        .firstOrNull;
    if (folder == null) return;
    if (_currentPresetIndex! >= folder.programCount - 1) return;
    _selectPreset(_currentPresetListId!, _currentPresetIndex! + 1);
  }

  /// Select a preset by list ID and index
  void _selectPreset(int listId, int presetIndex) {
    final instrument = widget.trackContext.currentInstrumentData;
    if (instrument == null ||
        !instrument.isVst3 ||
        widget.audioEngine == null) {
      return;
    }

    final result = widget.audioEngine!.setVst3Program(
      instrument.effectId!,
      listId,
      presetIndex,
    );
    if (result.isEmpty || !result.startsWith('Error')) {
      final folder = _presetFolders
          .where((f) => f.listId == listId)
          .firstOrNull;
      setState(() {
        _currentPresetListId = listId;
        _currentPresetIndex = presetIndex;
        _currentPresetName =
            folder != null && presetIndex < folder.presets.length
            ? folder.presets[presetIndex]
            : '- Init -';
      });
    }
  }

  /// Show the preset browser dropdown
  void _showPresetBrowser() {
    if (_presetDropdownOpen) {
      _dismissPresetBrowser();
      return;
    }
    setState(() => _presetDropdownOpen = true);

    _presetOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Dismiss backdrop
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissPresetBrowser,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          // Positioned dropdown
          CompositedTransformFollower(
            link: _presetLayerLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: PresetBrowserDropdown(
              folders: _presetFolders,
              currentListId: _currentPresetListId,
              currentPresetIndex: _currentPresetIndex,
              onPresetSelected: _selectPreset,
              onResetToDefault: () => _resetPluginToDefault?.call(),
              onDismiss: _dismissPresetBrowser,
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_presetOverlayEntry!);
  }

  /// Dismiss the preset browser dropdown
  void _dismissPresetBrowser() {
    _presetOverlayEntry?.remove();
    _presetOverlayEntry = null;
    if (mounted) {
      setState(() => _presetDropdownOpen = false);
    }
  }

  /// Show instrument dropdown positioned below the instrument tab button.
  /// Called when the user clicks the instrument tab while already on it.
  Future<void> _showInstrumentDropdownFromTab() async {
    final box =
        _instrumentTabKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final position = box.localToGlobal(Offset(0, box.size.height));
    final instrumentName = _getInstrumentTabLabel();

    final action = await DeviceDropdown.showForInstrument(
      context,
      position,
      currentName: instrumentName,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case ResetAction():
        _resetPluginToDefault?.call();
      case SwapAction():
        // Future: swap instrument implementation
        break;
      case DeleteAction():
        // Future: remove instrument from track
        break;
    }
  }

  /// Build the expanded tab buttons — derived from [_tabs] (evaluated once in
  /// `build()` and passed in, so the FFI-backed track-type checks behind the
  /// getter run once per frame), same list the collapsed strip and the
  /// TabBarView use.
  List<Widget> _buildTabButtons(List<_EditorTab> tabs) {
    return [
      for (var i = 0; i < tabs.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        _buildTabButton(
          i,
          tabs[i].icon,
          tabs[i].label,
          buttonKey: tabs[i].buttonKey,
        ),
      ],
    ];
  }

  /// Build the TabBarView children — derived from [_tabs] (passed in from
  /// `build()`, see [_buildTabButtons]), so content always lines up
  /// index-for-index with both tab strips.
  List<Widget> _buildTabContent(List<_EditorTab> tabs) {
    return [for (final tab in tabs) tab.content()];
  }

  /// Combined device chain view — instrument (if any) + effects in one row.
  /// Used as tab 0 for all track types.
  Widget _buildChainTab() {
    return DeviceChainView(
      selectedTrackId: widget.trackContext.selectedTrackId,
      audioEngine: widget.audioEngine,
      instrumentData: widget.trackContext.currentInstrumentData,
      isFloated: _isCurrentPluginFloated,
      trackName: widget.trackContext.selectedTrackName,
      onFloatPlugin: widget.vst3Callbacks.onFloatPlugin,
      onEmbedPlugin: widget.vst3Callbacks.onEmbedPlugin,
      onResetRegistered: (resetFn) => _resetPluginToDefault = resetFn,
      onInstrumentParameterChanged: widget.onInstrumentParameterChanged,
      onTrackVolumeChanged: widget.callbacks.onTrackVolumeChanged,
      onBuiltInEffectDropped: (effectType, {insertIndex}) {
        widget.onBuiltInEffectDropped?.call(effectType);
      },
      onVst3EffectDropped: (plugin, {insertIndex}) {
        widget.onVst3EffectDropped?.call(plugin);
      },
      onInstrumentDropped: widget.onInstrumentDropped,
      onVst3InstrumentDropped: widget.vst3Callbacks.onVst3InstrumentDropped,
      availableVst3Plugins: widget.availableVst3Plugins,
      isSamplerTrack: _isSamplerTrack,
    );
  }

  /// Build the Sampler Editor tab — the real sampler UI (waveform, loop markers,
  /// root note, attack/release, and the Load button for picking a sample).
  Widget _buildSamplerTab() {
    return SamplerEditor(
      audioEngine: widget.audioEngine,
      trackId: widget.trackContext.selectedTrackId,
      undoManager: widget.undoManager,
    );
  }

  Widget _buildTabButton(
    int index,
    IconData icon,
    String label, {
    Key? buttonKey,
  }) {
    final isSelected = _selectedTabIndex == index;
    final style = resolveEditorButtonStyle(
      widget.editorButtonVariant,
      context.colors,
      selected: isSelected,
      onAccentContent: Colors.white,
      inactiveContent: context.colors.textSecondary,
      inactiveBackground: context.colors.surface.withValues(alpha: 0.5),
      inactiveBorder: context.colors.divider.withValues(alpha: 0.5),
    );
    // Inactive tabs gain the same hover tint the tool buttons use; the
    // selected tab already carries its accent fill.
    var background = style.background;
    if (_hoveredTabIndex == index && !isSelected) {
      background = Color.alphaBlend(
        context.colors.textPrimary.withValues(alpha: BT.opacitySubtle),
        background,
      );
    }
    return Tooltip(
      key: buttonKey,
      message: label,
      child: MouseRegion(
        onEnter: (_) {
          if (_hoveredTabIndex != index) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hoveredTabIndex = index);
            });
          }
        },
        onExit: (_) {
          if (_hoveredTabIndex == index) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hoveredTabIndex = null);
            });
          }
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _onManualTabTap(index);
            },
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: AnimationConstants.hoverDuration,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: style.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: style.content),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? BT.weightSemiBold
                          : BT.weightMedium,
                      color: style.content,
                    ),
                  ),
                ],
              ),
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

    // The selected look follows the active editor-button variant; the inactive
    // look is shared (surface bg + divider border so the tool stands out from
    // the toolbar). A temporary hold-modifier preview reuses the selected style
    // at half-strength fill.
    final style = resolveEditorButtonStyle(
      widget.editorButtonVariant,
      context.colors,
      selected: isActive || isTempActive,
      onAccentContent: context.colors.elevated,
      inactiveContent: context.colors.textPrimary,
      inactiveBackground: context.colors.surface,
    );
    var bgColor = isTempActive
        ? style.background.withValues(alpha: 0.5)
        : style.background;
    final iconColor = style.content;
    final border = Border.all(color: style.border);

    // Inactive tools gain the same hover tint the top-bar split buttons use
    // (textPrimary @ subtle alpha) so the toolbar reads as interactive too. The
    // active/temp tool already carries its accent fill, so it's left as-is.
    final isHovered = _hoveredTool == mode;
    if (isHovered && !isActive && !isTempActive) {
      bgColor = Color.alphaBlend(
        context.colors.textPrimary.withValues(alpha: BT.opacitySubtle),
        bgColor,
      );
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => widget.callbacks.onToolModeChanged?.call(mode),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            if (_hoveredTool != mode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hoveredTool = mode);
              });
            }
          },
          onExit: (_) {
            if (_hoveredTool == mode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hoveredTool = null);
              });
            }
          },
          child: Container(
            // 30px matches the [Synth]/[MIDI] tab height (16px icon + 6px
            // vertical padding + border) so the toolbar reads as one family —
            // the tools previously sat at 28px and looked slightly recessed.
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(4),
              border: border,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }

  /// Build the Virtual Piano toggle button.
  /// Currently not rendered (hidden from the collapsed bar) but kept so it can
  /// be dropped back in without rebuilding it.
  // ignore: unused_element
  Widget _buildPianoToggle() {
    final isActive = widget.virtualPianoEnabled;

    return Tooltip(
      message: 'Virtual Piano (P)',
      child: GestureDetector(
        onTap: widget.callbacks.onVirtualPianoToggle,
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
                  BI.keyboard,
                  size: 16,
                  color: isActive
                      ? context.colors.elevated
                      : context.colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Piano',
                  style: TextStyle(
                    fontSize: BT.fontLabel,
                    fontWeight: BT.weightMedium,
                    color: isActive
                        ? context.colors.elevated
                        : context.colors.textPrimary,
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
        color: context.colors.darkest,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Select a track to start editing',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: BT.fontBody,
                  fontWeight: BT.weightMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Click a track in the mixer or a clip in the arrangement',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: BT.fontLabel,
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
      onToolModeChanged: widget.callbacks.onToolModeChanged,
      projectTempo: widget.projectTempo,
      onProjectTempoChanged: widget.onProjectTempoChanged,
      onCreateSamplerFromClip: widget.onCreateSamplerFromClip != null
          ? () => widget.onCreateSamplerFromClip?.call(clipData.filePath)
          : null,
    );
  }

  /// Tab 0 for a drum-kit track: the Layout-A editor (detail panel + step grid).
  Widget _buildDrumKitTab() {
    return DrumKitEditor(
      audioEngine: widget.audioEngine,
      trackId: widget.trackContext.selectedTrackId,
      clipData: widget.currentEditingClip,
      onClipUpdated: widget.onMidiClipUpdated,
      undoManager: widget.undoManager,
      beatsPerBar: widget.beatsPerBar,
      tempo: widget.projectTempo,
      playheadNotifier: widget.playheadNotifier,
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
    if (clipData == null && widget.trackContext.selectedTrackId != null) {
      // If we're awaiting clip data (just switched tabs), show minimal empty state
      if (_switchedToPianoRollAwaitingData) {
        return ColoredBox(
          color: context.colors.darkest,
          child: const SizedBox(),
        );
      }
      return ColoredBox(
        color: context.colors.darkest,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(BI.piano, size: 64, color: context.colors.textMuted),
              const SizedBox(height: 16),
              Text(
                'Click to create MIDI clip',
                style: TextStyle(color: context.colors.textMuted, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // No track selected - show empty state
    if (clipData == null) {
      return ColoredBox(
        color: context.colors.darkest,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Select a track to start editing',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: BT.fontBody,
                  fontWeight: BT.weightMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Click a track in the mixer or a clip in the arrangement',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: BT.fontLabel,
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
      onToolModeChanged: widget.callbacks.onToolModeChanged,
      highlightedNote: _highlightedNote,
      virtualPianoVisible: widget.virtualPianoEnabled,
      onVirtualPianoToggle: widget.callbacks.onVirtualPianoToggle,
      beatsPerBar: widget.beatsPerBar,
      beatUnit: widget.beatUnit,
      onTimeSignatureChanged: widget.onTimeSignatureChanged,
      onTimeSignatureDragStart: widget.onTimeSignatureDragStart,
      onTimeSignatureDragEnd: widget.onTimeSignatureDragEnd,
      isRecording: widget.isRecording,
      trackColor: widget.trackColor,
      playheadNotifier: widget.playheadNotifier,
      isPlaying: widget.isPlaying,
      tempo: widget.projectTempo,
      onSeek: widget.onSeek,
      onClose: () {
        // Back to the instrument tab. (This used to jump to index 3 — the
        // long-removed Virtual Piano tab — which is out of range on the
        // 2-tab controller and threw a RangeError.)
        _tabController.index = 0;
      },
    );
  }
}

/// One editor tab: how it renders in the expanded strip, the collapsed strip,
/// and what content it shows. See [_EditorPanelState._tabs] — the single list
/// every tab surface derives from.
class _EditorTab {
  final IconData icon;

  /// Label in the expanded tab strip.
  final String label;

  /// Label in the collapsed bar (falls back to [label]); the collapsed bar
  /// has room for longer names like the editing clip's filename.
  final String? collapsedLabel;

  /// Anchor key for the instrument dropdown (expanded strip only).
  final Key? buttonKey;

  /// Builds the TabBarView child for this tab.
  final Widget Function() content;

  const _EditorTab({
    required this.icon,
    required this.label,
    this.collapsedLabel,
    this.buttonKey,
    required this.content,
  });
}
