import 'package:flutter/material.dart';
import '../theme/theme_extension.dart';
import '../state/ui_layout_state.dart';

/// Button display mode for responsive layout
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
  final VoidCallback? onExportAudio;
  final VoidCallback? onExportMp3;
  final VoidCallback? onExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onAppSettings; // App-wide settings (logo click)
  final VoidCallback? onProjectSettings; // Project-specific settings (song name click)
  final VoidCallback? onCloseProject;

  // Project name for clickable song name
  final String projectName;

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

  // Snap control
  final SnapValue arrangementSnap;
  final Function(SnapValue)? onSnapChanged;

  // Loop control
  final bool isLoopEnabled;
  final VoidCallback? onLoopToggle;

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
    this.onExportAudio,
    this.onExportMp3,
    this.onExportWav,
    this.onExportMidi,
    this.onAppSettings,
    this.onProjectSettings,
    this.onCloseProject,
    this.projectName = 'Untitled',
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
    this.arrangementSnap = SnapValue.bar,
    this.onSnapChanged,
    this.isLoopEnabled = false,
    this.onLoopToggle,
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
        final mode = constraints.maxWidth > 900
            ? _ButtonDisplayMode.wide
            : _ButtonDisplayMode.narrow;
        final isCompact = mode == _ButtonDisplayMode.narrow;

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

              // Clickable project name - opens Project Settings
              _ProjectNameButton(
                name: widget.projectName,
                onTap: widget.onProjectSettings,
                mode: mode,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // File menu button
              PopupMenuButton<String>(
                icon: Icon(Icons.folder, color: context.colors.textSecondary, size: 20),
                tooltip: 'File',
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
                    case 'export_mp3':
                      widget.onExportMp3?.call();
                      break;
                    case 'export_wav':
                      widget.onExportWav?.call();
                      break;
                    case 'export_settings':
                      widget.onExportAudio?.call();
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
                      ],
                    ),
                  ),
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
                    value: 'export_settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, size: 18),
                        SizedBox(width: 8),
                        Text('Export Settings...'),
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
              ),

              const SizedBox(width: 4),

              // View menu button
              PopupMenuButton<String>(
                icon: Icon(Icons.visibility, color: context.colors.textSecondary, size: 20),
                tooltip: 'View',
                onSelected: (String value) {
                  switch (value) {
                    case 'library':
                      widget.onToggleLibrary?.call();
                      break;
                    case 'mixer':
                      widget.onToggleMixer?.call();
                      break;
                    case 'editor':
                      widget.onToggleEditor?.call();
                      break;
                    case 'piano':
                      widget.onTogglePiano?.call();
                      break;
                    case 'reset':
                      widget.onResetPanelLayout?.call();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'library',
                    child: Row(
                      children: [
                        Icon(
                          widget.libraryVisible ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Library'),
                        const Spacer(),
                        Text('L', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'mixer',
                    child: Row(
                      children: [
                        Icon(
                          widget.mixerVisible ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Mixer'),
                        const Spacer(),
                        Text('M', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'editor',
                    child: Row(
                      children: [
                        Icon(
                          widget.editorVisible ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Editor'),
                        const Spacer(),
                        Text('E', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'piano',
                    child: Row(
                      children: [
                        Icon(
                          widget.pianoVisible ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Virtual Piano'),
                        const Spacer(),
                        Text('P', style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'reset',
                    child: Row(
                      children: [
                        Icon(Icons.restart_alt, size: 18),
                        SizedBox(width: 8),
                        Text('Reset Layout'),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(width: isCompact ? 4 : 12),

              // Transport buttons - Play, Stop, Record
              _TransportButton(
                icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                color: widget.isPlaying ? const Color(0xFFF97316) : const Color(0xFF22C55E),
                onPressed: widget.canPlay ? (widget.isPlaying ? widget.onPause : widget.onPlay) : null,
                tooltip: widget.isPlaying ? 'Pause (Space)' : 'Play (Space)',
                size: 36,
              ),

              const SizedBox(width: 4),

              _TransportButton(
                icon: Icons.stop,
                color: const Color(0xFFF97316),
                onPressed: widget.canPlay ? widget.onStop : null,
                tooltip: 'Stop',
                size: 36,
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

              SizedBox(width: isCompact ? 8 : 16),

              // MIDI Capture pill button
              _PillButton(
                icon: Icons.history,
                label: 'MIDI',
                isActive: false,
                mode: mode,
                onTap: widget.onCaptureMidi,
                tooltip: 'Capture MIDI (Cmd+Shift+R)',
                activeColor: context.colors.accent,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Loop toggle pill button
              _PillButton(
                icon: Icons.loop,
                label: 'Loop',
                isActive: widget.isLoopEnabled,
                mode: mode,
                onTap: widget.onLoopToggle,
                tooltip: widget.isLoopEnabled ? 'Loop On (L)' : 'Loop Off (L)',
                activeColor: const Color(0xFFF97316), // Orange for loop
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Snap dropdown
              _SnapDropdown(
                value: widget.arrangementSnap,
                onChanged: widget.onSnapChanged,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Metronome toggle pill button
              _PillButton(
                icon: Icons.graphic_eq,
                label: 'Metronome',
                isActive: widget.metronomeEnabled,
                mode: mode,
                onTap: widget.onMetronomeToggle,
                tooltip: widget.metronomeEnabled ? 'Metronome On' : 'Metronome Off',
                activeColor: context.colors.accent,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Tap tempo pill button
              _TapTempoPill(
                tempo: widget.tempo,
                onTempoChanged: widget.onTempoChanged,
                mode: mode,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Tempo display with drag interaction
              _TempoDisplay(
                tempo: widget.tempo,
                onTempoChanged: widget.onTempoChanged,
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Time display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.elevated,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _formatTime(widget.playheadPosition),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),

              SizedBox(width: isCompact ? 4 : 8),

              // Position display (bars.beats.subdivision)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.elevated,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _formatPosition(widget.playheadPosition, widget.tempo),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),

              // Use Spacer to push remaining items to the right edge
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

  String _formatTime(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();

    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  String _formatPosition(double seconds, double bpm) {
    // Calculate position in bars.beats.subdivision format
    final beatsPerSecond = bpm / 60.0;
    final totalBeats = seconds * beatsPerSecond;

    // Assuming 4/4 time signature
    const beatsPerBar = 4;
    const subdivisionsPerBeat = 4; // 16th notes

    final bar = (totalBeats / beatsPerBar).floor() + 1; // 1-indexed
    final beat = (totalBeats % beatsPerBar).floor() + 1; // 1-indexed
    final subdivision = ((totalBeats % 1) * subdivisionsPerBeat).floor() + 1; // 1-indexed

    return '$bar.$beat.$subdivision';
  }
}

/// Individual transport button widget with hover animation
class _TransportButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  const _TransportButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
    this.size = 40,
  });

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    return Tooltip(
      message: widget.tooltip,
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
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: isEnabled
                    ? widget.color.withValues(alpha: _isHovered ? 0.3 : 0.2)
                    : context.colors.elevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isEnabled
                      ? widget.color
                      : context.colors.elevated,
                  width: 2,
                ),
                boxShadow: _isHovered && isEnabled
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: widget.size * 0.5,
                color: isEnabled
                    ? widget.color
                    : context.colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clickable project name button that opens Project Settings
class _ProjectNameButton extends StatefulWidget {
  final String name;
  final VoidCallback? onTap;
  final _ButtonDisplayMode mode;

  const _ProjectNameButton({
    required this.name,
    this.onTap,
    required this.mode,
  });

  @override
  State<_ProjectNameButton> createState() => _ProjectNameButtonState();
}

class _ProjectNameButtonState extends State<_ProjectNameButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // Truncate based on mode: narrow = shorter truncation
    final maxLength = widget.mode == _ButtonDisplayMode.narrow ? 8 : 20;
    final displayName = widget.name.length > maxLength
        ? '${widget.name.substring(0, maxLength - 2)}...'
        : widget.name;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: 'Project Settings',
        child: GestureDetector(
          onTap: widget.onTap,
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
      ),
    );
  }
}

/// Pill-style button that shows icon+text in wide mode, icon-only in narrow mode
class _PillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final _ButtonDisplayMode mode;
  final VoidCallback? onTap;
  final String tooltip;
  final Color activeColor;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.mode,
    this.onTap,
    required this.tooltip,
    required this.activeColor,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0);
    final bgColor = widget.isActive
        ? widget.activeColor
        : (_isHovered ? context.colors.elevated : context.colors.dark);
    final textColor = widget.isActive ? Colors.black : context.colors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onTap?.call();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: textColor),
                  if (widget.mode == _ButtonDisplayMode.wide) ...[
                    const SizedBox(width: 4),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 16, color: textColor),
                  if (widget.mode == _ButtonDisplayMode.wide) ...[
                    const SizedBox(width: 4),
                    Text(
                      'Tap',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
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

/// Tempo display with drag-to-adjust functionality
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

  @override
  Widget build(BuildContext context) {
    final tempoText = widget.tempo.toStringAsFixed(0);

    return GestureDetector(
      onVerticalDragStart: (details) {
        setState(() {
          _isDragging = true;
          _dragStartY = details.globalPosition.dy;
          _dragStartTempo = widget.tempo;
        });
      },
      onVerticalDragUpdate: (details) {
        if (widget.onTempoChanged != null) {
          // Drag up = increase tempo, drag down = decrease tempo
          final deltaY = _dragStartY - details.globalPosition.dy;
          // ~0.5 BPM per pixel (like Ableton)
          final deltaTempo = deltaY * 0.5;
          final newTempo = (_dragStartTempo + deltaTempo).clamp(20.0, 300.0).roundToDouble();
          widget.onTempoChanged!(newTempo);
        }
      },
      onVerticalDragEnd: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _isDragging
                ? context.colors.accent.withValues(alpha: 0.2)
                : context.colors.elevated,
            borderRadius: BorderRadius.circular(2),
            border: _isDragging
                ? Border.all(color: context.colors.accent, width: 1)
                : null,
          ),
          child: Text(
            '$tempoText BPM',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
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

class _RecordButtonState extends State<_RecordButton> {
  bool _isHovered = false;
  bool _isPressed = false;

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

    // Record button color: Red per spec (#EF4444)
    const recordColor = Color(0xFFEF4444);
    final Color color = widget.isRecording || widget.isCountingIn
        ? recordColor
        : recordColor;

    String tooltip = widget.isRecording
        ? 'Stop Recording (R)'
        : (widget.isCountingIn ? 'Counting In...' : 'Record (R)');

    // Add count-in info to tooltip
    if (!widget.isRecording && !widget.isCountingIn) {
      final countInText = widget.countInBars == 0
          ? 'Off'
          : widget.countInBars == 1
              ? '1 Bar'
              : '2 Bars';
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: isEnabled
                    ? color.withValues(alpha: _isHovered ? 0.9 : 0.7)
                    : context.colors.elevated,
                shape: BoxShape.circle,
                boxShadow: _isHovered && isEnabled
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.fiber_manual_record,
                color: isEnabled ? context.colors.textPrimary : context.colors.textSecondary,
                size: widget.size * 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Snap value dropdown selector
class _SnapDropdown extends StatefulWidget {
  final SnapValue value;
  final Function(SnapValue)? onChanged;

  const _SnapDropdown({
    required this.value,
    this.onChanged,
  });

  @override
  State<_SnapDropdown> createState() => _SnapDropdownState();
}

class _SnapDropdownState extends State<_SnapDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<SnapValue>(
        tooltip: 'Snap to Grid',
        onSelected: (SnapValue value) {
          widget.onChanged?.call(value);
        },
        offset: const Offset(0, 40),
        itemBuilder: (BuildContext context) {
          return SnapValue.values.map((snapValue) {
            final isSelected = snapValue == widget.value;
            return PopupMenuItem<SnapValue>(
              value: snapValue,
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.check : Icons.grid_on,
                    size: 18,
                    color: isSelected ? context.colors.accent : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    snapValue.displayName,
                    style: TextStyle(
                      color: isSelected ? context.colors.accent : null,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? context.colors.elevated
                : context.colors.standard,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.value != SnapValue.off
                  ? context.colors.accent.withValues(alpha: 0.5)
                  : context.colors.elevated,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.grid_on,
                size: 14,
                color: widget.value != SnapValue.off
                    ? context.colors.accent
                    : context.colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Snap ${widget.value.displayName}',
                style: TextStyle(
                  color: widget.value != SnapValue.off
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: widget.value != SnapValue.off
                    ? context.colors.accent
                    : context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
