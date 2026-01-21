import 'package:flutter/material.dart';
import '../theme/theme_extension.dart';
import '../state/ui_layout_state.dart';
import 'shared/circular_toggle_button.dart';
import 'shared/pill_toggle_button.dart';

/// Button display mode for responsive layout
/// Note: ButtonDisplayMode is also exported from pill_toggle_button.dart for external use
enum _ButtonDisplayMode { wide, narrow }

/// Transport control bar for play/pause/stop/record controls
class TransportBar extends StatefulWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onCaptureMidi;
  final Function(int)? onCountInChanged; // 0 = off, 1 = 1 bar, 2 = 2 bars
  final int countInBars; // Current count-in setting
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onPianoToggle;
  final double playheadPosition; // in seconds
  final bool isPlaying;
  final bool canPlay;
  final bool isRecording;
  final bool isCountingIn;
  final bool metronomeEnabled;
  final bool virtualPianoEnabled;
  final double tempo;
  final Function(double)? onTempoChanged;

  // MIDI device selection
  final List<Map<String, dynamic>> midiDevices;
  final int selectedMidiDeviceIndex;
  final Function(int)? onMidiDeviceSelected;
  final VoidCallback? onRefreshMidiDevices;

  // File menu callbacks
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onSaveNewVersion;
  final VoidCallback? onExportAudio;
  final VoidCallback? onExportMp3;
  final VoidCallback? onExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onAppSettings; // App-wide settings (logo click)
  final VoidCallback? onProjectSettings; // Project-specific settings (song name click)
  final VoidCallback? onCloseProject;

  // Project name for clickable song name
  final String projectName;
  final bool hasProject; // Whether project has been saved (for showing Rename option)

  // View menu callbacks
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;

  // View menu state
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;

  // Help callback
  final VoidCallback? onHelpPressed;

  // Edit menu (Undo/Redo) callbacks
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool canRedo;
  final String? undoDescription;
  final String? redoDescription;

  // Snap control
  final SnapValue arrangementSnap;
  final Function(SnapValue)? onSnapChanged;

  // Loop playback control (controls if arrangement playback loops)
  final bool loopPlaybackEnabled;
  final VoidCallback? onLoopPlaybackToggle;

  // Time signature
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onTimeSignatureChanged;

  final bool isLoading;

  const TransportBar({
    super.key,
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onRecord,
    this.onCaptureMidi,
    this.onCountInChanged,
    this.countInBars = 2,
    this.onMetronomeToggle,
    this.onPianoToggle,
    required this.playheadPosition,
    this.isPlaying = false,
    this.canPlay = false,
    this.isRecording = false,
    this.isCountingIn = false,
    this.metronomeEnabled = true,
    this.virtualPianoEnabled = false,
    this.tempo = 120.0,
    this.onTempoChanged,
    this.midiDevices = const [],
    this.selectedMidiDeviceIndex = -1,
    this.onMidiDeviceSelected,
    this.onRefreshMidiDevices,
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onSaveNewVersion,
    this.onExportAudio,
    this.onExportMp3,
    this.onExportWav,
    this.onExportMidi,
    this.onAppSettings,
    this.onProjectSettings,
    this.onCloseProject,
    this.projectName = 'Untitled',
    this.hasProject = false,
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
    this.libraryVisible = true,
    this.mixerVisible = true,
    this.editorVisible = true,
    this.pianoVisible = false,
    this.onHelpPressed,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.undoDescription,
    this.redoDescription,
    this.arrangementSnap = SnapValue.bar,
    this.onSnapChanged,
    this.loopPlaybackEnabled = false,
    this.onLoopPlaybackToggle,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
    this.onTimeSignatureChanged,
    this.isLoading = false,
  });

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _logoHovered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine display mode based on available width
        final availableWidth = constraints.maxWidth;
        final mode = availableWidth > 1300
            ? _ButtonDisplayMode.wide
            : _ButtonDisplayMode.narrow;
        final isCompact = mode == _ButtonDisplayMode.narrow;
        final isVeryCompact = availableWidth < 1150; // Hide more elements on narrow screens

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: context.colors.standard,
            border: Border(
              bottom: BorderSide(color: context.colors.elevated),
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: isCompact ? 8 : 16),

              // Audio logo image - hide on very compact screens
              // Clickable logo "O" opens settings (Boojy Suite pattern)
              if (!isCompact)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _logoHovered = true),
                  onExit: (_) => setState(() => _logoHovered = false),
                  child: Tooltip(
                    message: 'Settings',
                    child: GestureDetector(
                      onTap: () => widget.onAppSettings?.call(),
                      child: AnimatedScale(
                        scale: _logoHovered ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeInOut,
                        child: Image.asset(
                          'assets/images/boojy_audio_text.png',
                          height: 32,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),

              if (!isCompact) const SizedBox(width: 12),

              // Project name with File menu dropdown
              // Plan: Project name doubles as File menu (always visible, helpful in fullscreen)
              _FileMenuButton(
                projectName: widget.projectName,
                hasProject: widget.hasProject,
                mode: mode,
                onNewProject: widget.onNewProject,
                onOpenProject: widget.onOpenProject,
                onSaveProject: widget.onSaveProject,
                onSaveProjectAs: widget.onSaveProjectAs,
                onRenameProject: widget.onRenameProject,
                onSaveNewVersion: widget.onSaveNewVersion,
                onExportAudio: widget.onExportAudio,
                onExportMp3: widget.onExportMp3,
                onExportWav: widget.onExportWav,
                onExportMidi: widget.onExportMidi,
                onCloseProject: widget.onCloseProject,
              ),

              const SizedBox(width: 4),

              // View menu button (eye icon, stays open when toggling items)
              _ViewMenuButton(
                libraryVisible: widget.libraryVisible,
                mixerVisible: widget.mixerVisible,
                editorVisible: widget.editorVisible,
                pianoVisible: widget.pianoVisible,
                onToggleLibrary: widget.onToggleLibrary,
                onToggleMixer: widget.onToggleMixer,
                onToggleEditor: widget.onToggleEditor,
                onTogglePiano: widget.onTogglePiano,
                onResetPanelLayout: widget.onResetPanelLayout,
              ),

              const SizedBox(width: 4),

              // Undo button (replaces Edit menu)
              IconToggleButton(
                icon: Icons.undo,
                enabled: widget.canUndo,
                onTap: widget.onUndo,
                tooltip: widget.canUndo && widget.undoDescription != null
                    ? 'Undo: ${widget.undoDescription} (⌘Z)'
                    : 'Undo (⌘Z)',
              ),

              const SizedBox(width: 2),

              // Redo button
              IconToggleButton(
                icon: Icons.redo,
                enabled: widget.canRedo,
                onTap: widget.onRedo,
                tooltip: widget.canRedo && widget.redoDescription != null
                    ? 'Redo: ${widget.redoDescription} (⇧⌘Z)'
                    : 'Redo (⇧⌘Z)',
              ),

              SizedBox(width: isCompact ? 8 : 12),

              // === VERTICAL DIVIDER ===
              Container(
                width: 1,
                height: 28,
                color: context.colors.elevated,
              ),

              SizedBox(width: isCompact ? 8 : 12),

              // === CENTER-LEFT: SETUP TOOLS ===

              // Loop playback toggle button (Piano Roll style) - hide on very compact
              if (!isVeryCompact)
                PillToggleButton(
                  icon: Icons.loop,
                  label: 'Loop',
                  isActive: widget.loopPlaybackEnabled,
                  mode: mode == _ButtonDisplayMode.wide ? ButtonDisplayMode.wide : ButtonDisplayMode.narrow,
                  onTap: widget.onLoopPlaybackToggle,
                  tooltip: widget.loopPlaybackEnabled ? 'Loop Playback On (L)' : 'Loop Playback Off (L)',
                  activeColor: context.colors.accent, // BLUE when active (Piano Roll style)
                ),

              if (!isVeryCompact) SizedBox(width: isCompact ? 4 : 8),

              // Snap split button: icon toggles on/off, chevron opens grid menu - hide on very compact
              if (!isVeryCompact)
                _SnapSplitButton(
                  value: widget.arrangementSnap,
                  onChanged: widget.onSnapChanged,
                  mode: mode,
                ),

              if (!isVeryCompact) SizedBox(width: isCompact ? 4 : 8),

              // Metronome split button: icon toggles, chevron opens count-in menu
              _MetronomeSplitButton(
                isActive: widget.metronomeEnabled,
                countInBars: widget.countInBars,
                onToggle: widget.onMetronomeToggle,
                onCountInChanged: widget.onCountInChanged,
                mode: mode,
              ),

              SizedBox(width: isCompact ? 8 : 12),

              // === CENTER: TRANSPORT ===

              // Transport buttons - Play, Stop, Record
              CircularToggleButton(
                icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                enabled: widget.canPlay,
                enabledColor: widget.isPlaying ? const Color(0xFFF97316) : const Color(0xFF22C55E),
                onPressed: widget.canPlay ? (widget.isPlaying ? widget.onPause : widget.onPlay) : null,
                tooltip: widget.isPlaying ? 'Pause (Space)' : 'Play (Space)',
                size: 36,
                iconSize: 18,
              ),

              const SizedBox(width: 4),

              CircularToggleButton(
                icon: Icons.stop,
                enabled: widget.canPlay,
                enabledColor: const Color(0xFFF97316),
                onPressed: widget.canPlay ? widget.onStop : null,
                tooltip: 'Stop',
                size: 36,
                iconSize: 18,
              ),

              const SizedBox(width: 4),

              _RecordButton(
                isRecording: widget.isRecording,
                isCountingIn: widget.isCountingIn,
                countInBars: widget.countInBars,
                onPressed: widget.onRecord,
                onCountInChanged: widget.onCountInChanged,
                size: 36,
              ),

              // Recording indicator with duration
              if (widget.isRecording || widget.isCountingIn)
                _RecordingIndicator(
                  isRecording: widget.isRecording,
                  isCountingIn: widget.isCountingIn,
                  playheadPosition: widget.playheadPosition,
                ),

              SizedBox(width: isCompact ? 8 : 12),

              // Main Position display (bars.beats.subdivision)
              // Styled to match tempo box (dark background with border)
              // Background color changes during recording states
              // Larger text to make it the central focus point
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.isRecording
                      ? const Color(0xFFEF4444) // Red during recording
                      : widget.isCountingIn
                          ? const Color(0xFFFFA600) // Orange during count-in
                          : context.colors.dark, // Match tempo box
                  borderRadius: BorderRadius.circular(2),
                  border: widget.isRecording || widget.isCountingIn
                      ? null
                      : Border.all(color: context.colors.surface, width: 1.5),
                ),
                child: Text(
                  _formatPosition(widget.playheadPosition, widget.tempo),
                  style: TextStyle(
                    color: widget.isRecording || widget.isCountingIn
                        ? Colors.white // White text on colored backgrounds
                        : context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),

              SizedBox(width: isCompact ? 8 : 12),

              // === VERTICAL DIVIDER ===
              Container(
                width: 1,
                height: 28,
                color: context.colors.elevated,
              ),

              SizedBox(width: isCompact ? 8 : 12),

              // === RIGHT: MUSICAL CONTEXT ===

              // Tap tempo button (Piano Roll style) - hide on very compact
              if (!isVeryCompact)
                _TapTempoPill(
                  tempo: widget.tempo,
                  onTempoChanged: widget.onTempoChanged,
                  mode: mode,
                ),

              if (!isVeryCompact) SizedBox(width: isCompact ? 2 : 4),

              // Tempo display [120 BPM] with drag interaction
              _TempoDisplay(
                tempo: widget.tempo,
                onTempoChanged: widget.onTempoChanged,
              ),

              if (!isVeryCompact) SizedBox(width: isCompact ? 4 : 8),

              // Signature display/dropdown - hide on very compact
              if (!isVeryCompact)
                _SignatureDropdown(
                  beatsPerBar: widget.beatsPerBar,
                  beatUnit: widget.beatUnit,
                  onChanged: widget.onTimeSignatureChanged,
                ),

              // Use Spacer to push Help to the right edge
              const Spacer(),

              // Help button
              IconButton(
                icon: Icon(
                  Icons.help_outline,
                  color: context.colors.textSecondary,
                  size: 20,
                ),
                onPressed: widget.onHelpPressed,
                tooltip: 'Keyboard Shortcuts (?)',
              ),

              SizedBox(width: isCompact ? 8 : 16),
            ],
          ),
        );
      },
    );
  }

  String _formatPosition(double seconds, double bpm) {
    // Calculate position in bars.beats.subdivision format
    final beatsPerSecond = bpm / 60.0;
    final totalBeats = seconds * beatsPerSecond;

    // Use project time signature
    final beatsPerBar = widget.beatsPerBar;
    const subdivisionsPerBeat = 4; // 16th notes

    final bar = (totalBeats / beatsPerBar).floor() + 1; // 1-indexed
    final beat = (totalBeats % beatsPerBar).floor() + 1; // 1-indexed
    final subdivision = ((totalBeats % 1) * subdivisionsPerBeat).floor() + 1; // 1-indexed

    return '$bar.$beat.$subdivision';
  }
}

/// Clickable project name button that opens Project Settings
/// File menu button that displays project name with dropdown
/// According to plan: Project name doubles as File menu (always visible, helpful in fullscreen)
class _FileMenuButton extends StatefulWidget {
  final String projectName;
  final bool hasProject;
  final _ButtonDisplayMode mode;
  final VoidCallback? onNewProject;
  final VoidCallback? onOpenProject;
  final VoidCallback? onSaveProject;
  final VoidCallback? onSaveProjectAs;
  final VoidCallback? onRenameProject;
  final VoidCallback? onSaveNewVersion;
  final VoidCallback? onExportAudio;
  final VoidCallback? onExportMp3;
  final VoidCallback? onExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onCloseProject;

  const _FileMenuButton({
    required this.projectName,
    this.hasProject = false,
    required this.mode,
    this.onNewProject,
    this.onOpenProject,
    this.onSaveProject,
    this.onSaveProjectAs,
    this.onRenameProject,
    this.onSaveNewVersion,
    this.onExportAudio,
    this.onExportMp3,
    this.onExportWav,
    this.onExportMidi,
    this.onCloseProject,
  });

  @override
  State<_FileMenuButton> createState() => _FileMenuButtonState();
}

class _FileMenuButtonState extends State<_FileMenuButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Truncate based on mode: narrow = shorter truncation
    final maxLength = widget.mode == _ButtonDisplayMode.narrow ? 8 : 20;
    final displayName = widget.projectName.length > maxLength
        ? '${widget.projectName.substring(0, maxLength - 2)}...'
        : widget.projectName;

    return PopupMenuButton<String>(
      tooltip: 'File Menu',
      offset: const Offset(0, 40),
      onSelected: (String value) {
        switch (value) {
          case 'new':
            widget.onNewProject?.call();
            break;
          case 'open':
            widget.onOpenProject?.call();
            break;
          case 'save':
            widget.onSaveProject?.call();
            break;
          case 'save_as':
            widget.onSaveProjectAs?.call();
            break;
          case 'rename':
            widget.onRenameProject?.call();
            break;
          case 'save_new_version':
            widget.onSaveNewVersion?.call();
            break;
          case 'export_audio':
            widget.onExportAudio?.call();
            break;
          case 'export_mp3':
            widget.onExportMp3?.call();
            break;
          case 'export_wav':
            widget.onExportWav?.call();
            break;
          case 'export_midi':
            widget.onExportMidi?.call();
            break;
          case 'close':
            widget.onCloseProject?.call();
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'new',
          child: Row(
            children: [
              Icon(Icons.description, size: 18),
              SizedBox(width: 8),
              Text('New Project'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18),
              SizedBox(width: 8),
              Text('Open Project...'),
            ],
          ),
        ),
        // TODO: Open Recent submenu would go here
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save, size: 18),
              SizedBox(width: 8),
              Text('Save'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'save_as',
          child: Row(
            children: [
              Icon(Icons.save_as, size: 18),
              SizedBox(width: 8),
              Text('Save As...'),
              Spacer(),
              Text('⇧⌘S', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Only show Rename and Save New Version when project has been saved
        if (widget.hasProject)
          const PopupMenuItem<String>(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline, size: 18),
                SizedBox(width: 8),
                Text('Rename...'),
              ],
            ),
          ),
        if (widget.hasProject)
          const PopupMenuItem<String>(
            value: 'save_new_version',
            child: Row(
              children: [
                Icon(Icons.history, size: 18),
                SizedBox(width: 8),
                Text('Save New Version...'),
              ],
            ),
          ),
        if (widget.hasProject)
          const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'export_mp3',
          child: Row(
            children: [
              Icon(Icons.music_note, size: 18),
              SizedBox(width: 8),
              Text('Export MP3'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_wav',
          child: Row(
            children: [
              Icon(Icons.audio_file, size: 18),
              SizedBox(width: 8),
              Text('Export WAV'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_audio',
          child: Row(
            children: [
              Icon(Icons.settings, size: 18),
              SizedBox(width: 8),
              Text('Export Audio...'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'export_midi',
          child: Row(
            children: [
              Icon(Icons.piano, size: 18),
              SizedBox(width: 8),
              Text('Export MIDI...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close, size: 18),
              SizedBox(width: 8),
              Text('Close Project'),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.mode == _ButtonDisplayMode.narrow ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? context.colors.elevated
                : Colors.transparent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            displayName,
            style: TextStyle(
              color: _isHovered
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Snap split button: icon toggles on/off, chevron opens grid size menu
class _SnapSplitButton extends StatefulWidget {
  final SnapValue value;
  final Function(SnapValue)? onChanged;
  final _ButtonDisplayMode mode;

  const _SnapSplitButton({
    required this.value,
    this.onChanged,
    required this.mode,
  });

  @override
  State<_SnapSplitButton> createState() => _SnapSplitButtonState();
}

class _SnapSplitButtonState extends State<_SnapSplitButton> {
  bool _isIconHovered = false;
  bool _isChevronHovered = false;
  SnapValue? _lastNonOffValue; // Remember last grid size for toggle
  final GlobalKey _buttonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Remember initial value if not off
    if (widget.value != SnapValue.off) {
      _lastNonOffValue = widget.value;
    } else {
      _lastNonOffValue = SnapValue.beat; // Default to beat if starting off
    }
  }

  @override
  void didUpdateWidget(_SnapSplitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Remember when user selects a non-off value
    if (widget.value != SnapValue.off) {
      _lastNonOffValue = widget.value;
    }
  }

  void _toggleSnap() {
    if (widget.value == SnapValue.off) {
      // Turn on: restore last value
      widget.onChanged?.call(_lastNonOffValue ?? SnapValue.beat);
    } else {
      // Turn off
      widget.onChanged?.call(SnapValue.off);
    }
  }

  void _showSnapMenu(BuildContext context, Color accentColor) {
    final RenderBox button = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    showMenu<SnapValue>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: SnapValue.values.map((snapValue) {
        final isSelected = snapValue == widget.value;
        return PopupMenuItem<SnapValue>(
          value: snapValue,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check : Icons.grid_on,
                size: 18,
                color: isSelected ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                snapValue.displayName,
                style: TextStyle(
                  color: isSelected ? accentColor : null,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isActive = widget.value != SnapValue.off;
    final bgColor = isActive ? colors.accent : colors.dark;
    final textColor = isActive ? colors.elevated : colors.textPrimary;

    final tooltip = isActive
        ? 'Snap: ${widget.value.displayName} (click to toggle)'
        : 'Snap Off (click to enable)';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        key: _buttonKey,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left side: Label (clickable for toggle)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isIconHovered = true),
              onExit: (_) => setState(() => _isIconHovered = false),
              child: GestureDetector(
                onTap: _toggleSnap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isIconHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      bottomLeft: Radius.circular(2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_on, size: 14, color: textColor),
                      const SizedBox(width: 5),
                      Text(
                        isActive ? 'Snap ${widget.value.displayName}' : 'Snap',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Divider line
            Container(
              width: 1,
              height: 17,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),
            // Right side: Dropdown arrow
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isChevronHovered = true),
              onExit: (_) => setState(() => _isChevronHovered = false),
              child: GestureDetector(
                onTap: () => _showSnapMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isChevronHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 17,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metronome split button: icon toggles metronome, chevron opens count-in menu
class _MetronomeSplitButton extends StatefulWidget {
  final bool isActive;
  final int countInBars;
  final VoidCallback? onToggle;
  final Function(int)? onCountInChanged;
  final _ButtonDisplayMode mode;

  const _MetronomeSplitButton({
    required this.isActive,
    required this.countInBars,
    this.onToggle,
    this.onCountInChanged,
    required this.mode,
  });

  @override
  State<_MetronomeSplitButton> createState() => _MetronomeSplitButtonState();
}

class _MetronomeSplitButtonState extends State<_MetronomeSplitButton> {
  bool _isIconHovered = false;
  bool _isChevronHovered = false;
  final GlobalKey _buttonKey = GlobalKey();

  void _showCountInMenu(BuildContext context, Color accentColor) {
    final RenderBox button = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    final countInBars = widget.countInBars;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(
                countInBars == 0 ? Icons.check : Icons.close,
                size: 16,
                color: countInBars == 0 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: Off',
                style: TextStyle(
                  color: countInBars == 0 ? accentColor : null,
                  fontWeight: countInBars == 0 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(
                countInBars == 1 ? Icons.check : Icons.looks_one,
                size: 16,
                color: countInBars == 1 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 1 Bar',
                style: TextStyle(
                  color: countInBars == 1 ? accentColor : null,
                  fontWeight: countInBars == 1 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(
                countInBars == 2 ? Icons.check : Icons.looks_two,
                size: 16,
                color: countInBars == 2 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 2 Bars',
                style: TextStyle(
                  color: countInBars == 2 ? accentColor : null,
                  fontWeight: countInBars == 2 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(
                countInBars == 4 ? Icons.check : Icons.looks_4,
                size: 16,
                color: countInBars == 4 ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Count-in: 4 Bars',
                style: TextStyle(
                  color: countInBars == 4 ? accentColor : null,
                  fontWeight: countInBars == 4 ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onCountInChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bgColor = widget.isActive ? colors.accent : colors.dark;
    final textColor = widget.isActive ? colors.elevated : colors.textPrimary;

    // Build tooltip with count-in info
    final countInText = widget.countInBars == 0
        ? 'Off'
        : widget.countInBars == 1
            ? '1 Bar'
            : '2 Bars';
    final tooltip = widget.isActive
        ? 'Metronome On | Count-in: $countInText'
        : 'Metronome Off | Count-in: $countInText';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        key: _buttonKey,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left side: Icon (clickable for toggle)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isIconHovered = true),
              onExit: (_) => setState(() => _isIconHovered = false),
              child: GestureDetector(
                onTap: widget.onToggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isIconHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(2),
                      bottomLeft: Radius.circular(2),
                    ),
                  ),
                  child: Image.asset(
                    'assets/images/metronome.png',
                    width: 14,
                    height: 14,
                    color: textColor,
                  ),
                ),
              ),
            ),
            // Divider line
            Container(
              width: 1,
              height: 17,
              color: colors.textPrimary.withValues(alpha: 0.2),
            ),
            // Right side: Dropdown arrow
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isChevronHovered = true),
              onExit: (_) => setState(() => _isChevronHovered = false),
              child: GestureDetector(
                onTap: () => _showCountInMenu(context, colors.accent),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isChevronHovered
                        ? colors.textPrimary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(2),
                      bottomRight: Radius.circular(2),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 17,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tap tempo pill button with tap-to-set-tempo functionality
class _TapTempoPill extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;
  final _ButtonDisplayMode mode;

  const _TapTempoPill({
    required this.tempo,
    this.onTempoChanged,
    required this.mode,
  });

  @override
  State<_TapTempoPill> createState() => _TapTempoPillState();
}

class _TapTempoPillState extends State<_TapTempoPill> {
  bool _isHovered = false;
  bool _isPressed = false;
  final List<DateTime> _tapTimes = [];

  void _onTapTempo() {
    final now = DateTime.now();
    setState(() {
      // Remove taps older than 3 seconds
      _tapTimes.removeWhere((time) => now.difference(time).inSeconds > 3);

      // Add current tap
      _tapTimes.add(now);

      // Need at least 2 taps to calculate tempo
      if (_tapTimes.length >= 2) {
        // Calculate average interval between taps
        double totalInterval = 0.0;
        for (int i = 1; i < _tapTimes.length; i++) {
          totalInterval += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
        }
        final avgInterval = totalInterval / (_tapTimes.length - 1);

        // Convert interval to BPM (60000ms = 1 minute)
        final bpm = (60000.0 / avgInterval).clamp(20.0, 300.0).roundToDouble();
        widget.onTempoChanged?.call(bpm);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0);
    final isRecentTap = _tapTimes.isNotEmpty &&
        DateTime.now().difference(_tapTimes.last).inMilliseconds < 500;
    final bgColor = isRecentTap
        ? context.colors.accent.withValues(alpha: 0.3)
        : (_isHovered ? context.colors.elevated : context.colors.dark);
    final textColor = context.colors.textSecondary;

    return Tooltip(
      message: 'Tap Tempo',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            _onTapTempo();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 13, color: textColor),
                  if (widget.mode == _ButtonDisplayMode.wide) ...[
                    const SizedBox(width: 3),
                    Text(
                      'Tap',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tempo display with drag-to-adjust functionality - shows [120 BPM] format
/// Dragging snaps to whole BPM values; double-tap opens dialog for decimal input.
class _TempoDisplay extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;

  const _TempoDisplay({
    required this.tempo,
    this.onTempoChanged,
  });

  @override
  State<_TempoDisplay> createState() => _TempoDisplayState();
}

class _TempoDisplayState extends State<_TempoDisplay> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartTempo = 120.0;

  /// Format tempo for display:
  /// - If whole number (120.0), show as "120 BPM"
  /// - If has decimal (120.5), show as "120.50 BPM"
  String _formatTempo(double tempo) {
    if (tempo == tempo.roundToDouble()) {
      return '${tempo.round()} BPM';
    } else {
      return '${tempo.toStringAsFixed(2)} BPM';
    }
  }

  void _showTempoDialog(BuildContext context) {
    // Show current value - if whole number, show without decimal
    final initialText = widget.tempo == widget.tempo.roundToDouble()
        ? widget.tempo.round().toString()
        : widget.tempo.toStringAsFixed(2);
    final controller = TextEditingController(text: initialText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Project Tempo'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'BPM (20 - 300)',
          ),
          autofocus: true,
          onSubmitted: (_) {
            final value = double.tryParse(controller.text) ?? 120.0;
            widget.onTempoChanged?.call(value.clamp(20, 300));
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 120.0;
              widget.onTempoChanged?.call(value.clamp(20, 300));
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tempoText = _formatTempo(widget.tempo);

    return Tooltip(
      message: 'Tempo (drag to adjust, double-click for precise input)',
      child: GestureDetector(
        onVerticalDragStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartY = details.globalPosition.dy;
            // Snap start position to whole BPM for cleaner dragging
            _dragStartTempo = widget.tempo.roundToDouble();
          });
        },
        onVerticalDragUpdate: (details) {
          if (widget.onTempoChanged != null) {
            // Drag up = increase tempo, drag down = decrease tempo
            final deltaY = _dragStartY - details.globalPosition.dy;
            // ~0.5 BPM per pixel, then round to whole BPM
            final deltaTempo = (deltaY * 0.5).roundToDouble();
            final newTempo = (_dragStartTempo + deltaTempo).clamp(20.0, 300.0);
            widget.onTempoChanged!(newTempo);
          }
        },
        onVerticalDragEnd: (details) {
          setState(() {
            _isDragging = false;
          });
        },
        onDoubleTap: () => _showTempoDialog(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: _isDragging
                  ? context.colors.accent.withValues(alpha: 0.2)
                  : context.colors.dark,
              borderRadius: BorderRadius.circular(2),
              border: _isDragging
                  ? Border.all(color: context.colors.accent, width: 1.5)
                  : Border.all(color: context.colors.surface, width: 1.5),
            ),
            child: Text(
              tempoText,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Recording indicator with pulsing REC label and duration
class _RecordingIndicator extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final double playheadPosition;

  const _RecordingIndicator({
    required this.isRecording,
    required this.isCountingIn,
    required this.playheadPosition,
  });

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.colors.standard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.isRecording
                ? context.colors.recordActive
                : context.colors.warning,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing REC indicator
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isRecording
                        ? Color.fromRGBO(255, 0, 0, _pulseAnimation.value)
                        : Color.fromRGBO(255, 152, 0, _pulseAnimation.value),
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            Text(
              widget.isCountingIn ? 'COUNT-IN' : 'REC',
              style: TextStyle(
                color: widget.isRecording
                    ? context.colors.recordActive
                    : context.colors.warning,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (widget.isRecording) ...[
              const SizedBox(width: 8),
              Text(
                _formatDuration(widget.playheadPosition),
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Record button with right-click context menu for count-in settings
class _RecordButton extends StatefulWidget {
  final bool isRecording;
  final bool isCountingIn;
  final int countInBars;
  final VoidCallback? onPressed;
  final Function(int)? onCountInChanged;
  final double size;

  const _RecordButton({
    required this.isRecording,
    required this.isCountingIn,
    required this.countInBars,
    required this.onPressed,
    required this.onCountInChanged,
    this.size = 40,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    // Blink animation for count-in state (500ms on/off cycle)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Start blinking if already counting in
    if (widget.isCountingIn) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start/stop blink animation based on count-in state
    if (widget.isCountingIn && !oldWidget.isCountingIn) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.isCountingIn && oldWidget.isCountingIn) {
      _blinkController.stop();
      _blinkController.reset();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  void _showCountInMenu(BuildContext context, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              Icon(Icons.close, size: 16),
              SizedBox(width: 8),
              Text('Count-in: Off'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              Icon(Icons.looks_one, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 1 Bar'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(Icons.looks_two, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 2 Bars'),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: 4,
          child: Row(
            children: [
              Icon(Icons.looks_4, size: 16),
              SizedBox(width: 8),
              Text('Count-in: 4 Bars'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        widget.onCountInChanged?.call(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    // Record button color: Bright red (same intensity as play/stop)
    const recordColor = Color(0xFFFF4444);

    String tooltip = widget.isRecording
        ? 'Stop Recording (R)'
        : (widget.isCountingIn ? 'Counting In...' : 'Record (R)');

    // Add count-in info to tooltip
    if (!widget.isRecording && !widget.isCountingIn) {
      final countInText = widget.countInBars == 0
          ? 'Off'
          : widget.countInBars == 1
              ? '1 Bar'
              : widget.countInBars == 2
                  ? '2 Bars'
                  : '4 Bars';
      tooltip += ' | Right-click: Count-in ($countInText)';
    }

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onPressed?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          onSecondaryTapDown: (details) {
            // Right-click: show count-in menu
            _showCountInMenu(context, details.globalPosition);
          },
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _blinkController,
              builder: (context, child) {
                // Traffic Light System:
                // - Idle: Grey/red fill with small red circle in center
                // - Count-In: Blinking red (animated)
                // - Recording: Solid red fill with glow

                final bool isCountingIn = widget.isCountingIn;
                final bool isRecording = widget.isRecording;

                // Calculate fill color based on state
                Color fillColor;
                if (!isEnabled) {
                  fillColor = context.colors.elevated;
                } else if (isRecording) {
                  // Solid red when recording
                  fillColor = recordColor.withValues(alpha: _isHovered ? 0.95 : 0.85);
                } else if (isCountingIn) {
                  // Blinking: interpolate between dim and bright
                  final blinkValue = _blinkController.value;
                  fillColor = recordColor.withValues(alpha: 0.3 + (blinkValue * 0.55));
                } else {
                  // Idle: match play/stop button alpha values (0.2 idle, 0.3 hover)
                  fillColor = recordColor.withValues(alpha: _isHovered ? 0.3 : 0.2);
                }

                // Border for all states when enabled (match play/stop - no alpha reduction)
                final Border? border = isEnabled
                    ? Border.all(
                        color: recordColor,
                        width: 2,
                      )
                    : null;

                // Glow effect when hovering or recording
                final List<BoxShadow>? shadows = (_isHovered || isRecording) && isEnabled
                    ? [
                        BoxShadow(
                          color: recordColor.withValues(alpha: isRecording ? 0.5 : 0.3),
                          blurRadius: isRecording ? 12 : 8,
                          spreadRadius: isRecording ? 3 : 2,
                        ),
                      ]
                    : null;

                return Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: fillColor,
                    shape: BoxShape.circle,
                    border: border,
                    boxShadow: shadows,
                  ),
                  child: Center(
                    // Always show inner red circle, varying in brightness
                    child: Container(
                      width: widget.size * 0.36,
                      height: widget.size * 0.36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: !isEnabled
                            ? context.colors.textSecondary
                            : isRecording
                                ? Colors.white.withValues(alpha: 0.9)
                                : isCountingIn
                                    ? recordColor.withValues(alpha: 0.5 + (_blinkController.value * 0.5))
                                    : recordColor.withValues(alpha: _isHovered ? 0.8 : 0.6),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// View menu button that stays open when toggling items
/// Uses custom overlay instead of PopupMenuButton
class _ViewMenuButton extends StatefulWidget {
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;

  const _ViewMenuButton({
    required this.libraryVisible,
    required this.mixerVisible,
    required this.editorVisible,
    required this.pianoVisible,
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
  });

  @override
  State<_ViewMenuButton> createState() => _ViewMenuButtonState();
}

class _ViewMenuButtonState extends State<_ViewMenuButton> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _showMenu() {
    if (_isOpen) {
      _hideMenu();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _ViewMenuOverlay(
        layerLink: _layerLink,
        libraryVisible: widget.libraryVisible,
        mixerVisible: widget.mixerVisible,
        editorVisible: widget.editorVisible,
        pianoVisible: widget.pianoVisible,
        onToggleLibrary: () {
          widget.onToggleLibrary?.call();
          _rebuildOverlay();
        },
        onToggleMixer: () {
          widget.onToggleMixer?.call();
          _rebuildOverlay();
        },
        onToggleEditor: () {
          widget.onToggleEditor?.call();
          _rebuildOverlay();
        },
        onTogglePiano: () {
          widget.onTogglePiano?.call();
          _rebuildOverlay();
        },
        onResetPanelLayout: () {
          widget.onResetPanelLayout?.call();
          _hideMenu();
        },
        onDismiss: _hideMenu,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _rebuildOverlay() {
    // Rebuild the overlay with updated state
    _overlayEntry?.markNeedsBuild();
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  @override
  void didUpdateWidget(_ViewMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If any visibility changed while menu is open, rebuild it after frame
    if (_isOpen && _overlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayEntry != null) {
          _overlayEntry!.markNeedsBuild();
        }
      });
    }
  }

  @override
  void dispose() {
    _hideMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon: Icon(
          Icons.visibility,
          color: _isOpen ? context.colors.accent : context.colors.textSecondary,
          size: 20,
        ),
        onPressed: _showMenu,
        tooltip: 'View',
      ),
    );
  }
}

/// Overlay content for the View menu
class _ViewMenuOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final bool libraryVisible;
  final bool mixerVisible;
  final bool editorVisible;
  final bool pianoVisible;
  final VoidCallback? onToggleLibrary;
  final VoidCallback? onToggleMixer;
  final VoidCallback? onToggleEditor;
  final VoidCallback? onTogglePiano;
  final VoidCallback? onResetPanelLayout;
  final VoidCallback onDismiss;

  const _ViewMenuOverlay({
    required this.layerLink,
    required this.libraryVisible,
    required this.mixerVisible,
    required this.editorVisible,
    required this.pianoVisible,
    this.onToggleLibrary,
    this.onToggleMixer,
    this.onToggleEditor,
    this.onTogglePiano,
    this.onResetPanelLayout,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dismiss layer - tapping outside closes the menu
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // Menu positioned below the button
        CompositedTransformFollower(
          link: layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: context.colors.elevated,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  _ViewMenuItem(
                    icon: Icons.library_music,
                    label: 'Show Library',
                    isChecked: libraryVisible,
                    onTap: onToggleLibrary,
                  ),
                  _ViewMenuItem(
                    icon: Icons.tune,
                    label: 'Show Mixer',
                    isChecked: mixerVisible,
                    onTap: onToggleMixer,
                  ),
                  _ViewMenuItem(
                    icon: Icons.piano,
                    label: 'Show Editor',
                    isChecked: editorVisible,
                    onTap: onToggleEditor,
                  ),
                  _ViewMenuItem(
                    icon: Icons.keyboard,
                    label: 'Show Virtual Piano',
                    isChecked: pianoVisible,
                    onTap: onTogglePiano,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Divider(height: 1, color: context.colors.surface),
                  ),
                  _ViewMenuItem(
                    icon: Icons.refresh,
                    label: 'Reset Panel Layout',
                    isChecked: false,
                    showCheckbox: false,
                    onTap: onResetPanelLayout,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual menu item in View menu
class _ViewMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isChecked;
  final bool showCheckbox;
  final VoidCallback? onTap;

  const _ViewMenuItem({
    required this.icon,
    required this.label,
    required this.isChecked,
    this.showCheckbox = true,
    this.onTap,
  });

  @override
  State<_ViewMenuItem> createState() => _ViewMenuItemState();
}

class _ViewMenuItemState extends State<_ViewMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _isHovered ? context.colors.surface : Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showCheckbox) ...[
                SizedBox(
                  width: 20,
                  child: widget.isChecked
                      ? Icon(Icons.check, size: 16, color: context.colors.accent)
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Icon(widget.icon, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Time signature dropdown with "Signature" label (matches piano roll style)
class _SignatureDropdown extends StatefulWidget {
  final int beatsPerBar;
  final int beatUnit;
  final Function(int beatsPerBar, int beatUnit)? onChanged;

  const _SignatureDropdown({
    required this.beatsPerBar,
    required this.beatUnit,
    this.onChanged,
  });

  @override
  State<_SignatureDropdown> createState() => _SignatureDropdownState();
}

class _SignatureDropdownState extends State<_SignatureDropdown> {
  bool _isHovered = false;

  void _showSignatureMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = button.localToGlobal(Offset(0, button.size.height), ancestor: overlay);

    // Capture colors before showing menu (to avoid provider access in overlay)
    final accentColor = context.colors.accent;
    final beatsPerBar = widget.beatsPerBar;
    final beatUnit = widget.beatUnit;

    final signatures = [
      (4, 4, '4/4'),
      (3, 4, '3/4'),
      (6, 8, '6/8'),
      (2, 4, '2/4'),
    ];

    showMenu<(int, int)>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: signatures.map((sig) {
        final isSelected = sig.$1 == beatsPerBar && sig.$2 == beatUnit;
        return PopupMenuItem<(int, int)>(
          value: (sig.$1, sig.$2),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check : Icons.music_note,
                size: 16,
                color: isSelected ? accentColor : null,
              ),
              const SizedBox(width: 8),
              Text(
                sig.$3,
                style: TextStyle(
                  color: isSelected ? accentColor : null,
                  fontWeight: isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        widget.onChanged?.call(value.$1, value.$2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Time Signature',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: () => _showSignatureMenu(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Signature',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: _isHovered ? context.colors.surface : context.colors.dark,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: context.colors.surface, width: 1.5),
                ),
                child: Text(
                  '${widget.beatsPerBar}/${widget.beatUnit}',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
