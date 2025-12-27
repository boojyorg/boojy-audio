import 'package:flutter/material.dart';

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
  final VoidCallback? onMakeCopy;
  final VoidCallback? onExportAudio;
  final VoidCallback? onQuickExportMp3;
  final VoidCallback? onQuickExportWav;
  final VoidCallback? onExportMidi;
  final VoidCallback? onAppSettings; // App-wide settings (logo click)
  final VoidCallback? onProjectSettings; // Project-specific settings (File menu)
  final VoidCallback? onCloseProject;
  final VoidCallback? onCreateSnapshot;
  final VoidCallback? onViewSnapshots;

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
    this.onMakeCopy,
    this.onExportAudio,
    this.onQuickExportMp3,
    this.onQuickExportWav,
    this.onExportMidi,
    this.onAppSettings,
    this.onProjectSettings,
    this.onCloseProject,
    this.onCreateSnapshot,
    this.onViewSnapshots,
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
    this.isLoading = false,
  });

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _logoHovered = false;

  @override
  Widget build(BuildContext context) {
    // Get screen width to determine layout
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 1100; // iPad portrait or smaller windows

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Color(0xFF242424), // Main grey panel
        border: Border(
          bottom: BorderSide(color: Color(0xFF363636)), // Secondary grey border
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

          // File menu button
          PopupMenuButton<String>(
            icon: const Icon(Icons.folder, color: Color(0xFF9E9E9E), size: 20),
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
                case 'make_copy':
                  widget.onMakeCopy?.call();
                  break;
                case 'create_snapshot':
                  widget.onCreateSnapshot?.call();
                  break;
                case 'view_snapshots':
                  widget.onViewSnapshots?.call();
                  break;
                case 'quick_export_mp3':
                  widget.onQuickExportMp3?.call();
                  break;
                case 'quick_export_wav':
                  widget.onQuickExportWav?.call();
                  break;
                case 'export_audio':
                  widget.onExportAudio?.call();
                  break;
                case 'export_midi':
                  widget.onExportMidi?.call();
                  break;
                case 'settings':
                  widget.onProjectSettings?.call();
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
              const PopupMenuItem<String>(
                value: 'make_copy',
                child: Row(
                  children: [
                    Icon(Icons.content_copy, size: 18),
                    SizedBox(width: 8),
                    Text('Make a Copy...'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'create_snapshot',
                child: Row(
                  children: [
                    Icon(Icons.bookmark_add, size: 18),
                    SizedBox(width: 8),
                    Text('New Snapshot...'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'view_snapshots',
                child: Row(
                  children: [
                    Icon(Icons.bookmarks, size: 18),
                    SizedBox(width: 8),
                    Text('Snapshots...'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'quick_export_mp3',
                child: Row(
                  children: [
                    Icon(Icons.music_note, size: 18),
                    SizedBox(width: 8),
                    Text('Quick Export MP3'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'quick_export_wav',
                child: Row(
                  children: [
                    Icon(Icons.audio_file, size: 18),
                    SizedBox(width: 8),
                    Text('Quick Export WAV'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export_audio',
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
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 18),
                    SizedBox(width: 8),
                    Text('Project Settings...'),
                  ],
                ),
              ),
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
            icon: const Icon(Icons.visibility, color: Color(0xFF9E9E9E), size: 20),
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
                    const Text('Library Panel'),
                    const Spacer(),
                    const Text('L', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                    const Text('Mixer Panel'),
                    const Spacer(),
                    const Text('M', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                    const Text('Editor Panel'),
                    const Spacer(),
                    const Text('E', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                    const Text('P', style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                    Text('Reset Panel Layout'),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(width: isCompact ? 8 : 24),
          const VerticalDivider(color: Color(0xFF363636), width: 1),
          SizedBox(width: isCompact ? 8 : 16),

          // Transport buttons group - all same size (40px)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play/Pause button
                _TransportButton(
                  icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: widget.isPlaying ? const Color(0xFFFFC107) : const Color(0xFF4CAF50),
                  onPressed: widget.canPlay ? (widget.isPlaying ? widget.onPause : widget.onPlay) : null,
                  tooltip: widget.isPlaying ? 'Pause (Space)' : 'Play (Space)',
                  size: 40,
                ),

                const SizedBox(width: 4),

                // Stop button
                _TransportButton(
                  icon: Icons.stop,
                  color: const Color(0xFFF44336),
                  onPressed: widget.canPlay ? widget.onStop : null,
                  tooltip: 'Stop',
                  size: 40,
                ),

                const SizedBox(width: 4),

                // Record button with right-click menu for count-in settings
                _RecordButton(
                  isRecording: widget.isRecording,
                  isCountingIn: widget.isCountingIn,
                  countInBars: widget.countInBars,
                  onPressed: widget.onRecord,
                  onCountInChanged: widget.onCountInChanged,
                  size: 40,
                ),

                const SizedBox(width: 4),

                // Capture MIDI button
                _TransportButton(
                  icon: Icons.history,
                  color: const Color(0xFF7FD4A0),
                  onPressed: widget.onCaptureMidi,
                  tooltip: 'Capture MIDI (Cmd+Shift+R)',
                  size: 40,
                ),
              ],
            ),
          ),

          // Recording indicator with duration
          if (widget.isRecording || widget.isCountingIn)
            _RecordingIndicator(
              isRecording: widget.isRecording,
              isCountingIn: widget.isCountingIn,
              playheadPosition: widget.playheadPosition,
            ),

          SizedBox(width: isCompact ? 8 : 24),
          const VerticalDivider(color: Color(0xFF363636), width: 1),
          SizedBox(width: isCompact ? 8 : 16),

          // Metronome toggle
          _MetronomeButton(
            enabled: widget.metronomeEnabled,
            onPressed: widget.onMetronomeToggle,
          ),

          SizedBox(width: isCompact ? 4 : 8),

          // Virtual piano toggle
          _PianoButton(
            enabled: widget.virtualPianoEnabled,
            onPressed: widget.onPianoToggle,
          ),

          SizedBox(width: isCompact ? 4 : 8),

          // MIDI device selector - hide on compact screens
          if (!isCompact)
            _MidiDeviceSelector(
              devices: widget.midiDevices,
              selectedIndex: widget.selectedMidiDeviceIndex,
              onDeviceSelected: widget.onMidiDeviceSelected,
              onRefresh: widget.onRefreshMidiDevices,
            ),

          if (!isCompact) const SizedBox(width: 8),

          // Tempo control with drag and tap
          _TempoControl(
            tempo: widget.tempo,
            onTempoChanged: widget.onTempoChanged,
          ),

          SizedBox(width: isCompact ? 4 : 8),

          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF363636),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF363636)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time,
                  size: 14,
                  color: Color(0xFF9E9E9E),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(widget.playheadPosition),
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: isCompact ? 4 : 8),

          // Position display (bars.beats.subdivision) - hide on very compact screens
          if (!isCompact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF363636),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF363636)),
              ),
              child: Text(
                _formatPosition(widget.playheadPosition, widget.tempo),
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),

          // Use Spacer to push remaining items to the right edge
          const Spacer(),

          // Help button
          IconButton(
            icon: const Icon(
              Icons.help_outline,
              color: Color(0xFF9E9E9E),
              size: 20,
            ),
            onPressed: widget.onHelpPressed,
            tooltip: 'Keyboard Shortcuts (?)',
          ),

          SizedBox(width: isCompact ? 8 : 16),
        ],
      ),
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
    final beatsPerBar = 4;
    final subdivisionsPerBeat = 4; // 16th notes

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
                    : const Color(0xFF363636),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isEnabled
                      ? widget.color
                      : const Color(0xFF363636),
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
                    : const Color(0xFF616161),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Metronome toggle button widget with hover animation
class _MetronomeButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const _MetronomeButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_MetronomeButton> createState() => _MetronomeButtonState();
}

class _MetronomeButtonState extends State<_MetronomeButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    return Tooltip(
      message: widget.enabled ? 'Metronome On' : 'Metronome Off',
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.enabled
                    ? const Color(0xFF00BCD4).withValues(alpha: _isHovered ? 0.3 : 0.2)
                    : Color(0xFF363636).withValues(alpha: _isHovered ? 1.0 : 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.enabled
                      ? const Color(0xFF00BCD4)
                      : const Color(0xFF363636),
                  width: 2,
                ),
                boxShadow: _isHovered && widget.enabled
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00BCD4).withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.graphic_eq,
                size: 20,
                color: widget.enabled
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF616161),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Virtual piano toggle button widget with hover animation
class _PianoButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;

  const _PianoButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_PianoButton> createState() => _PianoButtonState();
}

class _PianoButtonState extends State<_PianoButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.95 : (_isHovered ? 1.05 : 1.0);

    return Tooltip(
      message: widget.enabled ? 'Virtual Piano On (z,x,c,w,e,r...)' : 'Virtual Piano Off',
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.enabled
                    ? const Color(0xFF4CAF50).withValues(alpha: _isHovered ? 0.3 : 0.2)
                    : Color(0xFF363636).withValues(alpha: _isHovered ? 1.0 : 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.enabled
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF363636),
                  width: 2,
                ),
                boxShadow: _isHovered && widget.enabled
                    ? [
                        BoxShadow(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.piano,
                size: 20,
                color: widget.enabled
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF616161),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tempo control widget with drag interaction and tap tempo (Ableton-style)
class _TempoControl extends StatefulWidget {
  final double tempo;
  final Function(double)? onTempoChanged;

  const _TempoControl({
    required this.tempo,
    this.onTempoChanged,
  });

  @override
  State<_TempoControl> createState() => _TempoControlState();
}

class _TempoControlState extends State<_TempoControl> {
  bool _isDragging = false;
  double _dragStartY = 0.0;
  double _dragStartTempo = 120.0;
  List<DateTime> _tapTimes = [];

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
    // Always show integers (tempo is rounded to whole numbers)
    final tempoText = widget.tempo.toStringAsFixed(0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tap tempo button
        InkWell(
          onTap: _onTapTempo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _tapTimes.isNotEmpty &&
                     DateTime.now().difference(_tapTimes.last).inMilliseconds < 500
                  ? const Color(0xFF00BCD4).withValues(alpha: 0.3)
                  : const Color(0xFF363636),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF363636)),
            ),
            child: const Text(
              'Tap',
              style: TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(width: 4),

        // Tempo display with drag interaction
        GestureDetector(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isDragging
                    ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                    : const Color(0xFF363636),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _isDragging
                      ? const Color(0xFF00BCD4)
                      : const Color(0xFF363636),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.speed,
                    size: 14,
                    color: Color(0xFF9E9E9E),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$tempoText BPM',
                    style: const TextStyle(
                      color: Color(0xFFE0E0E0),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// MIDI device selector dropdown widget
class _MidiDeviceSelector extends StatefulWidget {
  final List<Map<String, dynamic>> devices;
  final int selectedIndex;
  final Function(int)? onDeviceSelected;
  final VoidCallback? onRefresh;

  const _MidiDeviceSelector({
    required this.devices,
    required this.selectedIndex,
    this.onDeviceSelected,
    this.onRefresh,
  });

  @override
  State<_MidiDeviceSelector> createState() => _MidiDeviceSelectorState();
}

class _MidiDeviceSelectorState extends State<_MidiDeviceSelector> {
  bool _isHovered = false;

  String get _selectedDeviceName {
    if (widget.devices.isEmpty) {
      return 'No MIDI';
    }
    if (widget.selectedIndex < 0 || widget.selectedIndex >= widget.devices.length) {
      return 'Select MIDI';
    }
    final name = widget.devices[widget.selectedIndex]['name'] as String? ?? 'Unknown';
    // Truncate long names
    return name.length > 16 ? '${name.substring(0, 14)}...' : name;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<int>(
        tooltip: 'MIDI Input Device',
        onSelected: (int index) {
          if (index == -2) {
            // Refresh option
            widget.onRefresh?.call();
          } else {
            widget.onDeviceSelected?.call(index);
          }
        },
        offset: const Offset(0, 40),
        itemBuilder: (BuildContext context) {
          final items = <PopupMenuEntry<int>>[];

          if (widget.devices.isEmpty) {
            items.add(
              const PopupMenuItem<int>(
                enabled: false,
                child: Text(
                  'No MIDI devices found',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          } else {
            for (int i = 0; i < widget.devices.length; i++) {
              final device = widget.devices[i];
              final name = device['name'] as String? ?? 'Unknown';
              final isDefault = device['isDefault'] as bool? ?? false;
              final isSelected = i == widget.selectedIndex;

              items.add(
                PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check : Icons.piano,
                        size: 18,
                        color: isSelected ? const Color(0xFF00BCD4) : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00BCD4) : null,
                            fontWeight: isSelected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF363636),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }
          }

          items.add(const PopupMenuDivider());
          items.add(
            const PopupMenuItem<int>(
              value: -2,
              child: Row(
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Refresh Devices'),
                ],
              ),
            ),
          );

          return items;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF363636)
                : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: widget.selectedIndex >= 0
                  ? const Color(0xFF00BCD4).withValues(alpha: 0.5)
                  : const Color(0xFF363636),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.piano,
                size: 14,
                color: widget.selectedIndex >= 0
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 6),
              Text(
                _selectedDeviceName,
                style: TextStyle(
                  color: widget.selectedIndex >= 0
                      ? const Color(0xFFE0E0E0)
                      : const Color(0xFF9E9E9E),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: widget.selectedIndex >= 0
                    ? const Color(0xFF00BCD4)
                    : const Color(0xFF9E9E9E),
              ),
            ],
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
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.isRecording
                ? const Color(0xFFFF0000)
                : const Color(0xFFFF9800),
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
                    ? const Color(0xFFFF0000)
                    : const Color(0xFFFF9800),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (widget.isRecording) ...[
              const SizedBox(width: 8),
              Text(
                _formatDuration(widget.playheadPosition),
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
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

    final Color color = widget.isRecording || widget.isCountingIn
        ? const Color(0xFFFF0000)
        : const Color(0xFFE91E63);

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
                    : const Color(0xFF363636),
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
                color: isEnabled ? Colors.white : const Color(0xFF9E9E9E),
                size: widget.size * 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
