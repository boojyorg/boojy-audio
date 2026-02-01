import 'package:flutter/material.dart';
import '../theme/theme_extension.dart';
import '../state/ui_layout_state.dart';
import 'shared/circular_toggle_button.dart';
import 'shared/pill_toggle_button.dart';
import 'transport_bar/signature_dropdown.dart';
import 'transport_bar/tempo_controls.dart';
import 'transport_bar/snap_split_button.dart';
import 'transport_bar/metronome_split_button.dart';
import 'transport_bar/file_menu_button.dart';
import 'transport_bar/view_menu_button.dart';
import 'transport_bar/record_controls.dart';

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

  // Record guard: disable record when no tracks are armed
  final bool hasArmedTracks;
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
    this.hasArmedTracks = true,
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
  int _hidingLevel = 0;
  final GlobalKey _lastElementKey = GlobalKey(); // Key for the last visible element
  final GlobalKey _redLineKey = GlobalKey(); // Key for the red threshold line

  // Store actual measured width deltas for each level transition (level -> delta)
  final Map<int, double> _measuredWidthDeltas = {};
  double? _lastElementRightBeforeHide;

  /// Calculate expected content width based on hiding level
  /// This avoids measuring the Row which doesn't work inside Expanded
  /// Levels: 0=full, 1=icon-only loop/snap, 2=no sig label, 3=no tap tempo, 4=no position, 5=no signature
  double _calculateContentWidth(int level) {
    double width = 8; // left padding

    // Always visible: logo (~100), file menu (~100), view (~32), undo/redo (~64)
    width += 100 + 100 + 32 + 64;
    // Spacing after undo/redo + divider
    width += 24;

    // Loop & Snap always visible
    width += (level >= 1) ? (36 + 50) : (70 + 90); // icon-only vs with labels
    width += 24; // spacing

    // Metronome always visible (~50)
    width += 50;
    width += 24; // spacing + divider

    // Transport (play/stop/record) (~120)
    width += 120;
    width += 12; // spacing

    // Level 0-3: Position display visible (~90)
    if (level < 4) {
      width += 90;
      width += 24; // spacing + divider
    } else {
      width += 12; // just spacing before divider when position hidden
    }

    // Level 0-2: Tap Tempo visible (~40)
    if (level < 3) {
      width += 40;
      width += 8;
    }

    // Tempo display always visible (~80)
    width += 80;

    // Level 0-4: Signature visible
    if (level < 5) {
      width += (level < 2) ? 100 : 50; // with label vs without
      width += 12;
    }

    return width;
  }

  void _checkGapAndAdjust(double availableWidth) {
    if (!mounted) return;

    // Measure actual positions using GlobalKeys
    final lastElementBox = _lastElementKey.currentContext?.findRenderObject() as RenderBox?;
    final redLineBox = _redLineKey.currentContext?.findRenderObject() as RenderBox?;

    if (lastElementBox == null || redLineBox == null) return;

    // Get positions relative to the screen
    final lastElementRight = lastElementBox.localToGlobal(Offset(lastElementBox.size.width, 0)).dx;
    final redLineLeft = redLineBox.localToGlobal(Offset.zero).dx;
    final actualGap = redLineLeft - lastElementRight;

    // DEBUG
    debugPrint('=== GAP CHECK ===');
    debugPrint('lastElementRight: $lastElementRight, redLineLeft: $redLineLeft');
    debugPrint('actualGap: $actualGap, hidingLevel: $_hidingLevel');
    debugPrint('measuredDeltas: $_measuredWidthDeltas');

    const minGap = 5.0; // Same threshold for both hide and show

    if (actualGap < minGap && _hidingLevel < 5) {
      // HIDE: Store lastElementRight before hiding so we can measure delta after
      _lastElementRightBeforeHide = lastElementRight;
      final levelBeforeHide = _hidingLevel;
      debugPrint('ACTION: HIDE (gap $actualGap < $minGap)');
      setState(() => _hidingLevel++);

      // After setState completes, measure the new lastElementRight and calculate actual delta
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final newBox = _lastElementKey.currentContext?.findRenderObject() as RenderBox?;
        if (newBox != null && _lastElementRightBeforeHide != null) {
          final newRight = newBox.localToGlobal(Offset(newBox.size.width, 0)).dx;
          final actualDelta = _lastElementRightBeforeHide! - newRight;
          _measuredWidthDeltas[levelBeforeHide] = actualDelta;
          debugPrint('MEASURED DELTA for level $levelBeforeHide: $actualDelta');
          _lastElementRightBeforeHide = null;
        }
      });
    } else if (_hidingLevel > 0) {
      // SHOW: Use measured delta if available, otherwise use estimate as fallback
      final prevLevel = _hidingLevel - 1;
      final measuredDelta = _measuredWidthDeltas[prevLevel];

      double widthIncrease;
      if (measuredDelta != null) {
        // Use the actual measured delta
        widthIncrease = measuredDelta;
        debugPrint('Using MEASURED delta: $widthIncrease');
      } else {
        // Fallback to estimate (only happens if we never hid from this level)
        final currentWidth = _calculateContentWidth(_hidingLevel);
        final prevWidth = _calculateContentWidth(prevLevel);
        widthIncrease = prevWidth - currentWidth;
        debugPrint('Using ESTIMATED delta: $widthIncrease (no measurement yet)');
      }

      final expectedGapAtPrevLevel = actualGap - widthIncrease;
      debugPrint('expectedGapAtPrevLevel: $expectedGapAtPrevLevel (threshold: $minGap)');

      // Same 5px threshold for show as for hide (no buffer needed with measured deltas)
      if (expectedGapAtPrevLevel >= minGap) {
        debugPrint('ACTION: SHOW (expectedGap $expectedGapAtPrevLevel >= $minGap)');
        setState(() => _hidingLevel--);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Check and adjust hiding level after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkGapAndAdjust(availableWidth);
        });

        // Gap-based responsive: hiding level is adjusted based on calculated content width
        // Hiding levels: 0=full, 1=icon-only loop/snap, 2=no sig label, 3=no tap tempo, 4=no position, 5=no signature
        final isIconOnly = _hidingLevel >= 1;
        final showSignatureLabel = _hidingLevel < 2;
        final showTapTempo = _hidingLevel < 3;
        final showPosition = _hidingLevel < 4;
        final showSignature = _hidingLevel < 5;

        // Always use wide spacing (no compact mode)
        const mode = ButtonDisplayMode.wide;

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
              // All content wrapped in Expanded so Help button stays fixed at right
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(), // Disable scrolling
                  child: Transform.translate(
                    offset: const Offset(4, 0),
                    child: Row(
                      children: [
                      const SizedBox(width: 8),

                      // Audio logo image - always visible (never hidden)
                      // Clickable logo "O" opens settings (Boojy Suite pattern)
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
                      child: Transform.translate(
                        offset: const Offset(0, -3),
                        child: Image.asset(
                          'assets/images/boojy_audio_text.png',
                          height: 32,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Project name with File menu dropdown
              // Plan: Project name doubles as File menu (always visible, helpful in fullscreen)
              FileMenuButton(
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
              ViewMenuButton(
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

              const SizedBox(width: 12),

              // === VERTICAL DIVIDER ===
              Container(
                width: 1,
                height: 28,
                color: context.colors.elevated,
              ),

              const SizedBox(width: 12),

              // === CENTER-LEFT: SETUP TOOLS ===

              // Loop playback toggle button (Piano Roll style)
              PillToggleButton(
                  icon: Icons.loop,
                  label: isIconOnly ? '' : 'Loop', // Icon-only when narrow
                  isActive: widget.loopPlaybackEnabled,
                  mode: mode,
                  onTap: widget.onLoopPlaybackToggle,
                  tooltip: widget.loopPlaybackEnabled ? 'Loop Playback On (L)' : 'Loop Playback Off (L)',
                  activeColor: context.colors.accent, // BLUE when active (Piano Roll style)
                ),

              const SizedBox(width: 8),

              // Snap split button: icon toggles on/off, chevron opens grid menu
              SnapSplitButton(
                value: widget.arrangementSnap,
                onChanged: widget.onSnapChanged,
                mode: mode,
                isIconOnly: isIconOnly,
              ),

              const SizedBox(width: 8),

              // Metronome split button: icon toggles, chevron opens count-in menu
              MetronomeSplitButton(
                isActive: widget.metronomeEnabled,
                countInBars: widget.countInBars,
                onToggle: widget.onMetronomeToggle,
                onCountInChanged: widget.onCountInChanged,
                mode: mode,
              ),

              const SizedBox(width: 12),

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

              RecordButton(
                isRecording: widget.isRecording,
                isCountingIn: widget.isCountingIn,
                countInBars: widget.countInBars,
                onPressed: (widget.hasArmedTracks || widget.isRecording || widget.isCountingIn)
                    ? widget.onRecord
                    : null,
                onCountInChanged: widget.onCountInChanged,
                size: 36,
              ),

              // Recording indicator with duration
              if (widget.isRecording || widget.isCountingIn)
                RecordingIndicator(
                  isRecording: widget.isRecording,
                  isCountingIn: widget.isCountingIn,
                  playheadPosition: widget.playheadPosition,
                ),

              const SizedBox(width: 12),

              // Main Position display (bars.beats.subdivision)
              // Styled to match tempo box (dark background with border)
              // Background color changes during recording states
              // Larger text to make it the central focus point
              // Hidden at level 4 to save space
              if (showPosition)
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

              if (showPosition) const SizedBox(width: 12),

              // === VERTICAL DIVIDER ===
              Container(
                width: 1,
                height: 28,
                color: context.colors.elevated,
              ),

              const SizedBox(width: 12),

              // === RIGHT: MUSICAL CONTEXT ===

              // Tap tempo button (Piano Roll style) - hide when space is tight
              if (showTapTempo)
                TapTempoPill(
                  tempo: widget.tempo,
                  onTempoChanged: widget.onTempoChanged,
                  mode: mode,
                ),

              if (showTapTempo) const SizedBox(width: 4),

              // Tempo display [120 BPM] with drag interaction
              // Gets _lastElementKey when signature is hidden (level 5)
              if (!showSignature)
                KeyedSubtree(
                  key: _lastElementKey,
                  child: TempoDisplay(
                    tempo: widget.tempo,
                    onTempoChanged: widget.onTempoChanged,
                  ),
                )
              else
                TempoDisplay(
                  tempo: widget.tempo,
                  onTempoChanged: widget.onTempoChanged,
                ),

              if (showSignature) const SizedBox(width: 8),

              // Signature display/dropdown - hidden at level 5
              // Gets _lastElementKey when visible
              if (showSignature)
                KeyedSubtree(
                  key: _lastElementKey,
                  child: SignatureDropdown(
                    beatsPerBar: widget.beatsPerBar,
                    beatUnit: widget.beatUnit,
                    onChanged: widget.onTimeSignatureChanged,
                    isLabelHidden: !showSignatureLabel,
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),

            // Help button (fixed position at right edge)
            IconButton(
              icon: Icon(
                Icons.help_outline,
                color: context.colors.textSecondary,
                size: 20,
              ),
              onPressed: widget.onHelpPressed,
              tooltip: 'Keyboard Shortcuts (?)',
            ),

            const SizedBox(width: 8),
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


