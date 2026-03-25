// ignore_for_file: avoid_positional_boolean_parameters
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/animation_constants.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../state/ui_layout_state.dart';
import 'shared/button_hover_mixin.dart';
import 'shared/circular_toggle_button.dart';
import 'shared/pill_toggle_button.dart';
import 'transport_bar/signature_dropdown.dart';
import 'transport_bar/tempo_controls.dart';
import 'transport_bar/snap_split_button.dart';
import 'transport_bar/metronome_split_button.dart';
import 'transport_bar/file_menu_button.dart';

import 'transport_bar/record_controls.dart';
import 'transport_bar/transport_bar_models.dart';

export 'transport_bar/transport_bar_models.dart';

/// Transport control bar for play/pause/stop/record controls
/// Layout: LEFT GROUP | CENTRE GROUP (expanded) | RIGHT GROUP
class TransportBar extends StatefulWidget {
  // Grouped callback objects
  final FileMenuCallbacks fileMenu;
  final TransportCallbacks transport;
  final PanelCallbacks panels;
  final DividerState dividers;

  // Playback state
  final double playheadPosition;
  final bool isPlaying;
  final bool canPlay;
  final bool isRecording;
  final bool isCountingIn;
  final bool metronomeEnabled;
  final bool virtualPianoEnabled;
  final double tempo;
  final Function(double)? onTempoChanged;
  final Function(int)? onCountInChanged;
  final int countInBars;

  // Count-in ring timer data
  final int countInBeat;
  final double countInProgress;

  // MIDI device selection
  final List<Map<String, dynamic>> midiDevices;
  final int selectedMidiDeviceIndex;
  final Function(int)? onMidiDeviceSelected;
  final VoidCallback? onRefreshMidiDevices;

  // Project name
  final String projectName;
  final bool hasProject;

  // Panel visibility state
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;

  // Undo/Redo state
  final bool canUndo;
  final bool canRedo;
  final bool hasArmedTracks;
  final String? undoDescription;
  final String? redoDescription;

  // Snap control
  final SnapValue arrangementSnap;
  final Function(SnapValue)? onSnapChanged;

  // Loop playback
  final bool loopPlaybackEnabled;

  // Punch in/out
  final bool punchInEnabled;
  final bool punchOutEnabled;

  // Time signature
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  final bool isLoading;

  // Engine status (for status dot)
  final bool isEngineReady;

  const TransportBar({
    super.key,
    this.fileMenu = const FileMenuCallbacks(),
    this.transport = const TransportCallbacks(),
    this.panels = const PanelCallbacks(),
    this.dividers = const DividerState(),
    required this.playheadPosition,
    this.isPlaying = false,
    this.canPlay = false,
    this.isRecording = false,
    this.isCountingIn = false,
    this.metronomeEnabled = true,
    this.virtualPianoEnabled = false,
    this.tempo = 120.0,
    this.onTempoChanged,
    this.onCountInChanged,
    this.countInBars = 1,
    this.countInBeat = 0,
    this.countInProgress = 0.0,
    this.midiDevices = const [],
    this.selectedMidiDeviceIndex = -1,
    this.onMidiDeviceSelected,
    this.onRefreshMidiDevices,
    this.projectName = 'Untitled',
    this.hasProject = false,
    this.libraryVisible = true,
    this.mixerVisible = true,
    this.editorVisible = true,
    this.pianoVisible = false,
    this.canUndo = false,
    this.canRedo = false,
    this.hasArmedTracks = true,
    this.undoDescription,
    this.redoDescription,
    this.arrangementSnap = SnapValue.bar,
    this.onSnapChanged,
    this.loopPlaybackEnabled = false,
    this.punchInEnabled = false,
    this.punchOutEnabled = false,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onTimeSignatureChanged,
    this.isLoading = false,
    this.isEngineReady = false,
  });

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _logoHovered = false;
  bool _sidebarHandleHovered = false;
  bool _sidebarHandleDragging = false;
  bool _mixerHandleHovered = false;
  bool _mixerHandleDragging = false;

  void _onLeftNotifierChanged() {
    if (mounted) setState(() {});
  }

  void _onRightNotifierChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.dividers.leftDividerNotifier?.addListener(_onLeftNotifierChanged);
    widget.dividers.rightDividerNotifier?.addListener(_onRightNotifierChanged);
  }

  @override
  void didUpdateWidget(TransportBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dividers.leftDividerNotifier !=
        widget.dividers.leftDividerNotifier) {
      oldWidget.dividers.leftDividerNotifier?.removeListener(
        _onLeftNotifierChanged,
      );
      widget.dividers.leftDividerNotifier?.addListener(_onLeftNotifierChanged);
    }
    if (oldWidget.dividers.rightDividerNotifier !=
        widget.dividers.rightDividerNotifier) {
      oldWidget.dividers.rightDividerNotifier?.removeListener(
        _onRightNotifierChanged,
      );
      widget.dividers.rightDividerNotifier?.addListener(
        _onRightNotifierChanged,
      );
    }
  }

  @override
  void dispose() {
    widget.dividers.leftDividerNotifier?.removeListener(_onLeftNotifierChanged);
    widget.dividers.rightDividerNotifier?.removeListener(
      _onRightNotifierChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.dark,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 8,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      child: Row(
        children: [
          // === LEFT GROUP: constrained to sidebar width (min 150px) ===
          SizedBox(
            width: math.max(widget.dividers.sidebarWidth, 200),
            child: _buildLeftGroup(colors),
          ),

          // === LEFT DIVIDER (aligned with content divider below) ===
          _buildSidebarHandle(colors),

          // === CENTRE GROUP (expanded) ===
          Expanded(child: _buildCentreGroup(colors)),

          // === RIGHT DIVIDER (aligned with mixer divider below) ===
          _buildMixerHandle(colors),

          // === RIGHT GROUP: constrained to mixer width ===
          SizedBox(
            width: widget.dividers.mixerWidth,
            child: _buildRightGroup(colors),
          ),
        ],
      ),
    );
  }

  void _setSidebarHandleActive(bool hovered, bool dragging) {
    setState(() {
      _sidebarHandleHovered = hovered;
      _sidebarHandleDragging = dragging;
    });
    widget.dividers.leftDividerNotifier?.value = hovered || dragging;
  }

  void _setMixerHandleActive(bool hovered, bool dragging) {
    setState(() {
      _mixerHandleHovered = hovered;
      _mixerHandleDragging = dragging;
    });
    widget.dividers.rightDividerNotifier?.value = hovered || dragging;
  }

  Widget _buildDividerHandle({
    required BoojyColors colors,
    required bool isActive,
    required Function(double) onDrag,
    required VoidCallback onDoubleClick,
    required void Function(bool hovered, bool dragging) setActive,
    required bool isHovered,
    required bool isDragging,
    VoidCallback? onDragStart,
    VoidCallback? onDragEnd,
  }) {
    return GestureDetector(
      onPanStart: (_) {
        setActive(isHovered, true);
        onDragStart?.call();
      },
      onPanUpdate: (details) => onDrag(details.delta.dx),
      onPanEnd: (_) {
        setActive(isHovered, false);
        onDragEnd?.call();
      },
      onDoubleTap: onDoubleClick,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setActive(true, isDragging),
        onExit: (_) => setActive(false, isDragging),
        child: Container(
          width: 4,
          color: isActive ? colors.accent : colors.dark,
          child: isActive
              ? null
              : Center(
                  child: SizedBox(
                    width: 1,
                    height: double.infinity,
                    child: ColoredBox(color: colors.divider),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSidebarHandle(BoojyColors colors) {
    final isActive =
        _sidebarHandleHovered ||
        _sidebarHandleDragging ||
        (widget.dividers.leftDividerNotifier?.value ?? false);

    return _buildDividerHandle(
      colors: colors,
      isActive: isActive,
      onDrag: (delta) => widget.dividers.onSidebarDividerDrag?.call(delta),
      onDoubleClick: () => widget.dividers.onSidebarDividerDoubleClick?.call(),
      setActive: _setSidebarHandleActive,
      isHovered: _sidebarHandleHovered,
      isDragging: _sidebarHandleDragging,
      onDragStart: widget.dividers.onSidebarDividerDragStart,
      onDragEnd: widget.dividers.onSidebarDividerDragEnd,
    );
  }

  Widget _buildMixerHandle(BoojyColors colors) {
    final isActive =
        _mixerHandleHovered ||
        _mixerHandleDragging ||
        (widget.dividers.rightDividerNotifier?.value ?? false);

    return _buildDividerHandle(
      colors: colors,
      isActive: isActive,
      onDrag: (delta) => widget.dividers.onMixerDividerDrag?.call(delta),
      onDoubleClick: () => widget.dividers.onMixerDividerDoubleClick?.call(),
      setActive: _setMixerHandleActive,
      isHovered: _mixerHandleHovered,
      isDragging: _mixerHandleDragging,
      onDragStart: widget.dividers.onMixerDividerDragStart,
      onDragEnd: widget.dividers.onMixerDividerDragEnd,
    );
  }

  // ============================================
  // LEFT GROUP
  // ============================================

  Widget _buildLeftGroup(BoojyColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;

          // Fixed: O(19)+gap(8)+gap(5)+undo(25)+gap(2)+redo(25)+minGap(5)+toggle(27)
          const fixedWidth = 116.0;
          const maxAudiClip = 77.5;
          const nameComfortWidth = 120.0;

          // Shrink priority: 1) spacer  2) audi clip  3) name truncate
          final flexSpace = available - fixedWidth;
          final audiClipWidth = math.min(
            maxAudiClip,
            math.max(0.0, flexSpace - nameComfortWidth),
          );
          final spacerWidth = math.max(
            0.0,
            flexSpace - nameComfortWidth - audiClipWidth,
          );

          return Row(
            children: [
              _buildLogo(colors, audiClipWidth: audiClipWidth),

              const SizedBox(width: 8),

              // Project name — only flexible item, truncates with ellipsis
              Flexible(
                child: FileMenuButton(
                  projectName: widget.projectName,
                  hasProject: widget.hasProject,
                  mode: ButtonDisplayMode.wide,
                  onNewProject: widget.fileMenu.onNewProject,
                  onOpenProject: widget.fileMenu.onOpenProject,
                  onSaveProject: widget.fileMenu.onSaveProject,
                  onSaveProjectAs: widget.fileMenu.onSaveProjectAs,
                  onRenameProject: widget.fileMenu.onRenameProject,
                  onSaveNewVersion: widget.fileMenu.onSaveNewVersion,
                  onExportAudio: widget.fileMenu.onExportAudio,
                  onExportMp3: widget.fileMenu.onExportMp3,
                  onExportWav: widget.fileMenu.onExportWav,
                  onExportMidi: widget.fileMenu.onExportMidi,
                  onCloseProject: widget.fileMenu.onCloseProject,
                ),
              ),

              const SizedBox(width: 5),

              // Undo button
              _SvgIconButton(
                assetPath: 'assets/icons/undo.svg',
                enabled: widget.canUndo,
                onTap: widget.transport.onUndo,
                tooltip: widget.canUndo && widget.undoDescription != null
                    ? 'Undo: ${widget.undoDescription} (⌘Z)'
                    : 'Undo (⌘Z)',
              ),

              const SizedBox(width: 2),

              // Redo button
              _SvgIconButton(
                assetPath: 'assets/icons/redo.svg',
                enabled: widget.canRedo,
                onTap: widget.transport.onRedo,
                tooltip: widget.canRedo && widget.redoDescription != null
                    ? 'Redo: ${widget.redoDescription} (⇧⌘Z)'
                    : 'Redo (⇧⌘Z)',
              ),

              // Spacer between redo and toggle — shrinks first
              SizedBox(width: 5 + spacerWidth),

              // Sidebar toggle [|]
              _PanelToggleButton(
                assetPath: 'assets/icons/sidebar_toggle.svg',
                isActive: widget.libraryVisible,
                onTap: widget.panels.onToggleLibrary,
                tooltip: widget.libraryVisible
                    ? 'Hide Library'
                    : 'Show Library',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogo(BoojyColors colors, {required double audiClipWidth}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Audi" text: always rendered, smoothly clipped to available width
        ClipRect(
          child: SizedBox(
            width: audiClipWidth,
            child: OverflowBox(
              alignment: AlignmentDirectional.centerStart,
              maxWidth: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: SvgPicture.asset(
                  'assets/images/boojy_audio_audi.svg',
                  height: 27,
                ),
              ),
            ),
          ),
        ),
        // Blue circle "O" — settings button
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _logoHovered = true),
          onExit: (_) => setState(() => _logoHovered = false),
          child: Tooltip(
            message: 'Settings',
            child: GestureDetector(
              onTap: () => widget.fileMenu.onAppSettings?.call(),
              child: AnimatedScale(
                scale: _logoHovered ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                child: Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================
  // CENTRE GROUP
  // ============================================

  Widget _buildCentreGroup(BoojyColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine what to show based on available width
        final width = constraints.maxWidth;
        final showPosition = width > 500;
        final showTapTempo = width > 420;
        final showSignature = width > 340;
        final showSignatureLabel = width > 550;
        final isIconOnly = width < 600;

        const mode = ButtonDisplayMode.wide;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Punch In button (→|)
                _PunchButton(
                  label: '→|',
                  isActive: widget.punchInEnabled,
                  onTap: widget.transport.onPunchInToggle,
                  tooltip: widget.punchInEnabled
                      ? 'Punch In On (I)'
                      : 'Punch In Off (I)',
                  mode: mode,
                ),

                const SizedBox(width: 2),

                // Loop playback toggle
                PillToggleButton(
                  icon: Icons.loop,
                  label: isIconOnly ? '' : 'Loop',
                  isActive: widget.loopPlaybackEnabled,
                  mode: mode,
                  onTap: widget.transport.onLoopPlaybackToggle,
                  tooltip: widget.loopPlaybackEnabled
                      ? 'Loop Playback On (L)'
                      : 'Loop Playback Off (L)',
                  activeColor: colors.accent,
                ),

                const SizedBox(width: 2),

                // Punch Out button (|→)
                _PunchButton(
                  label: '|→',
                  isActive: widget.punchOutEnabled,
                  onTap: widget.transport.onPunchOutToggle,
                  tooltip: widget.punchOutEnabled
                      ? 'Punch Out On (O)'
                      : 'Punch Out Off (O)',
                  mode: mode,
                ),

                const SizedBox(width: 8),

                // Snap split button
                SnapSplitButton(
                  value: widget.arrangementSnap,
                  onChanged: widget.onSnapChanged,
                  mode: mode,
                  isIconOnly: isIconOnly,
                ),

                const SizedBox(width: 8),

                // Metronome split button
                MetronomeSplitButton(
                  isActive: widget.metronomeEnabled,
                  countInBars: widget.countInBars,
                  onToggle: widget.transport.onMetronomeToggle,
                  onCountInChanged: widget.onCountInChanged,
                  mode: mode,
                ),

                const SizedBox(width: 12),

                // Transport buttons - Play/Pause, Stop, Record
                CircularToggleButton(
                  icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  enabled:
                      widget.canPlay ||
                      widget.isRecording ||
                      widget.isCountingIn,
                  enabledColor: widget.isPlaying
                      ? const Color(0xFFF97316)
                      : const Color(0xFF22C55E),
                  onPressed: () {
                    if (widget.isRecording || widget.isCountingIn) {
                      widget.transport.onPauseRecording?.call();
                    } else if (widget.isPlaying) {
                      widget.transport.onPause?.call();
                    } else {
                      widget.transport.onPlay?.call();
                    }
                  },
                  tooltip: widget.isPlaying ? 'Pause (Space)' : 'Play (Space)',
                  size: 32,
                  iconSize: 16,
                ),

                const SizedBox(width: 4),

                CircularToggleButton(
                  icon: Icons.stop,
                  enabled:
                      widget.canPlay ||
                      widget.isRecording ||
                      widget.isCountingIn,
                  enabledColor: const Color(0xFFF97316),
                  onPressed: () {
                    if (widget.isRecording || widget.isCountingIn) {
                      widget.transport.onStopRecording?.call();
                    } else {
                      widget.transport.onStop?.call();
                    }
                  },
                  tooltip: 'Stop',
                  size: 32,
                  iconSize: 16,
                ),

                const SizedBox(width: 4),

                RecordButton(
                  isRecording: widget.isRecording,
                  isCountingIn: widget.isCountingIn,
                  countInBars: widget.countInBars,
                  countInBeat: widget.countInBeat,
                  countInProgress: widget.countInProgress,
                  beatsPerBar: widget.beatsPerBar,
                  onPressed:
                      (widget.hasArmedTracks ||
                          widget.isRecording ||
                          widget.isCountingIn)
                      ? widget.transport.onRecord
                      : null,
                  onCountInChanged: widget.onCountInChanged,
                  size: 32,
                ),

                const SizedBox(width: 12),

                // Position display
                if (showPosition)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.darkest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.divider, width: 1),
                    ),
                    child: Text(
                      _formatPosition(widget.playheadPosition, widget.tempo),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),

                if (showPosition) const SizedBox(width: 12),

                // Tap tempo
                if (showTapTempo)
                  TapTempoPill(
                    tempo: widget.tempo,
                    onTempoChanged: widget.onTempoChanged,
                    mode: mode,
                  ),

                if (showTapTempo) const SizedBox(width: 4),

                // Tempo display
                TempoDisplay(
                  tempo: widget.tempo,
                  onTempoChanged: widget.onTempoChanged,
                ),

                if (showSignature) const SizedBox(width: 8),

                // Signature display/dropdown
                if (showSignature)
                  SignatureDropdown(
                    beatsPerBar: widget.beatsPerBar,
                    beatUnit: widget.beatUnit,
                    onChanged: widget.onTimeSignatureChanged,
                    isLabelHidden: !showSignatureLabel,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // RIGHT GROUP
  // ============================================

  Widget _buildRightGroup(BoojyColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Mixer toggle (mirrored sidebar icon)
          _PanelToggleButton(
            assetPath: 'assets/icons/sidebar_toggle.svg',
            isActive: widget.mixerVisible,
            onTap: widget.panels.onToggleMixer,
            tooltip: widget.mixerVisible ? 'Hide Mixer' : 'Show Mixer',
            mirrored: true,
          ),

          const SizedBox(width: 12),

          // Status dot
          Tooltip(
            message: widget.isEngineReady ? 'Ready' : 'Initializing...',
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.isEngineReady ? colors.success : colors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),

          const Spacer(),

          // Help button — far right
          _HelpButton(onTap: widget.panels.onHelpPressed),
        ],
      ),
    );
  }

  String _formatPosition(double seconds, double bpm) {
    final beatsPerSecond = bpm / 60.0;
    final totalBeats = seconds * beatsPerSecond;

    final beatsPerBar = widget.beatsPerBar;
    const subdivisionsPerBeat = 4;

    final bar = (totalBeats / beatsPerBar).floor() + 1;
    final beat = (totalBeats % beatsPerBar).floor() + 1;
    final subdivision = ((totalBeats % 1) * subdivisionsPerBeat).floor() + 1;

    return '$bar.$beat.$subdivision';
  }
}

// ============================================
// HELPER WIDGETS
// ============================================

/// SVG icon button for undo/redo
class _SvgIconButton extends StatefulWidget {
  final String assetPath;
  final bool enabled;
  final VoidCallback? onTap;
  final String tooltip;

  const _SvgIconButton({
    required this.assetPath,
    required this.enabled,
    this.onTap,
    required this.tooltip,
  });

  @override
  State<_SvgIconButton> createState() => _SvgIconButtonState();
}

class _SvgIconButtonState extends State<_SvgIconButton> with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final opacity = widget.enabled ? 1.0 : 0.3;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled ? handleHoverEnter : null,
        onExit: widget.enabled ? handleHoverExit : null,
        child: GestureDetector(
          onTapDown: widget.enabled ? handleTapDown : null,
          onTapUp: widget.enabled
              ? (details) {
                  handleTapUp(details);
                  widget.onTap?.call();
                }
              : null,
          onTapCancel: widget.enabled ? handleTapCancel : null,
          child: AnimatedScale(
            scale: widget.enabled ? scale : 1.0,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(
                opacity: opacity,
                child: SvgPicture.asset(
                  widget.assetPath,
                  width: 16.5,
                  height: 16.5,
                  colorFilter: ColorFilter.mode(
                    colors.textPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel toggle button using SVG sidebar icon
class _PanelToggleButton extends StatefulWidget {
  final String assetPath;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;
  final bool mirrored;

  const _PanelToggleButton({
    required this.assetPath,
    required this.isActive,
    this.onTap,
    required this.tooltip,
    this.mirrored = false,
  });

  @override
  State<_PanelToggleButton> createState() => _PanelToggleButtonState();
}

class _PanelToggleButtonState extends State<_PanelToggleButton>
    with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconOpacity = widget.isActive ? 1.0 : 0.5;

    Widget svgIcon = SvgPicture.asset(
      widget.assetPath,
      width: 16.5,
      height: 16.5,
      colorFilter: ColorFilter.mode(
        isHovered ? colors.textPrimary : colors.textMuted,
        BlendMode.srcIn,
      ),
    );

    if (widget.mirrored) {
      svgIcon = Transform.flip(flipX: true, child: svgIcon);
    }

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Opacity(opacity: iconOpacity, child: svgIcon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Help button with consistent sizing.
class _HelpButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _HelpButton({this.onTap});

  @override
  State<_HelpButton> createState() => _HelpButtonState();
}

class _HelpButtonState extends State<_HelpButton> with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Tooltip(
      message: 'Keyboard Shortcuts (?)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isHovered ? colors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.help_outline,
                size: 16.5,
                color: isHovered ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Punch In/Out toggle button with bold text label.
class _PunchButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final String tooltip;
  final ButtonDisplayMode mode;

  const _PunchButton({
    required this.label,
    required this.isActive,
    this.onTap,
    required this.tooltip,
    required this.mode,
  });

  @override
  State<_PunchButton> createState() => _PunchButtonState();
}

class _PunchButtonState extends State<_PunchButton> with ButtonHoverMixin {
  @override
  double get hoverScale => AnimationConstants.subtleHoverScale;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeColor = colors.accent;

    final bgColor = widget.isActive
        ? activeColor
        : (isHovered ? colors.elevated : colors.dark);

    final textColor = widget.isActive ? colors.elevated : colors.textPrimary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: handleHoverEnter,
        onExit: handleHoverExit,
        child: GestureDetector(
          onTapDown: handleTapDown,
          onTapUp: (details) {
            handleTapUp(details);
            widget.onTap?.call();
          },
          onTapCancel: handleTapCancel,
          child: AnimatedScale(
            scale: scale,
            duration: AnimationConstants.pressDuration,
            curve: AnimationConstants.standardCurve,
            child: AnimatedContainer(
              duration: AnimationConstants.pressDuration,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
