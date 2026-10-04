import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:async';
// Conditional import for platform-specific code
import 'daw_screen_io.dart';
import '../audio_engine.dart';
import '../theme/animation_constants.dart';
import '../theme/theme_extension.dart';
import '../widgets/shared/boojy_notice.dart';
import '../widgets/shared/stable_menu_bar.dart';
import '../widgets/transport_bar.dart';
import '../widgets/timeline/timeline_models.dart';
import '../widgets/timeline_view.dart';
import '../widgets/mixer/mixer_models.dart';
import '../widgets/track_mixer_panel.dart';
import '../widgets/library_panel.dart';
import '../widgets/editor_panel.dart';
import '../widgets/editor/editor_models.dart';
import '../widgets/virtual_piano.dart';
import '../widgets/resizable_divider.dart';
import '../widgets/instrument_browser.dart';
import '../widgets/tour/tour_step.dart';
import '../widgets/tour/tour_controller.dart';
import '../widgets/tour/tour_overlay.dart';
import '../models/midi_note_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../models/clip_data.dart';
import '../models/library_item.dart';
import '../models/track_data.dart';
import '../services/audio_clip_engine_sync.dart';
import '../services/commands/command.dart';
import '../services/user_settings.dart';
import '../services/commands/track_commands.dart';
import '../services/commands/effect_commands.dart';
import '../services/commands/send_commands.dart';
import '../services/commands/project_commands.dart';
import '../widgets/fx_picker_dialog.dart';
import '../services/commands/clip_commands.dart';
import '../services/library_preview_service.dart';
import '../services/vst3_plugin_manager.dart';
import '../services/project_manager.dart';
import '../services/midi_playback_manager.dart';
import '../services/vst3_editor_service.dart';
import '../services/input_health_watcher.dart';
import '../services/plugin_preferences_service.dart';
import '../services/midi_file_service.dart';
import '../widgets/start_screen/start_screen_modal.dart';
import '../state/ui_layout_state.dart';
import 'daw/daw_menu_bar.dart';
import 'daw/mixins/daw_mixins.dart';
import '../utils/logger.dart';
import '../utils/text_focus.dart';

/// Main DAW screen with timeline, transport controls, and file import
class DAWScreen extends StatefulWidget {
  const DAWScreen({super.key});

  @override
  State<DAWScreen> createState() => _DAWScreenState();
}

class _DAWScreenState extends State<DAWScreen>
    with
        WidgetsBindingObserver,
        DAWScreenStateMixin,
        DAWPlaybackMixin,
        DAWRecordingMixin,
        DAWUIMixin,
        DAWTrackMixin,
        DAWClipMixin,
        DAWVst3Mixin,
        DAWLibraryMixin,
        DAWProjectMixin {
  // Drag state for disabling panel animations during resize
  bool _isDraggingLibrary = false;
  bool _isDraggingMixer = false;
  bool _isDraggingEditor = false;

  // Synchronized divider hover state (shared between transport bar and content)
  final _leftDividerActive = ValueNotifier<bool>(false);
  final _rightDividerActive = ValueNotifier<bool>(false);

  // Cmd+Shift+T cycles Dark ↔ Light (the selectable themes only), persisted
  // exactly like the Settings picker so a relaunch keeps the choice.
  void _cycleAppTheme() {
    final themeProvider = context.themeProvider;
    themeProvider.cycleTheme();
    UserSettings().theme = themeProvider.themeKey;
  }

  @override
  void initState() {
    super.initState();

    // Clean slate on every start (prevents stale undo state from hot restart)
    undoRedoManager.clear();

    // Observe app lifecycle so we can rescan for hot-plugged MIDI keyboards
    // when the user returns focus to Boojy.
    WidgetsBinding.instance.addObserver(this);

    // Transport single-key shortcuts (Space, L, M, I, O) are handled at the
    // hardware-keyboard level so they fire *before* focus dispatch. Otherwise,
    // once focus lands on any Material button (clicking the transport, mixer,
    // a menu…) that button swallows Space via its own activate-on-space
    // binding and the key appears dead. See _handleGlobalTransportKey.
    HardwareKeyboard.instance.addHandler(_handleGlobalTransportKey);

    // Listen for undo/redo state changes to update menu
    undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for controller state changes that require UI rebuilds.
    // Note: playbackController's *per-frame* updates do NOT rebuild here —
    // they flow through playheadNotifier inside TimelineView. We only listen
    // for play/stop *transitions* (gated in _onPlaybackPlayingChanged) so the
    // playhead line can switch grey<->white when playback starts/stops.
    // automationPreviewValues use ValueNotifier listened to by TrackMixerPanel only.
    playbackController.addListener(_onPlaybackPlayingChanged);
    recordingController.addListener(_onRecordingStateChanged);
    trackController.addListener(_onTrackStateChanged);
    midiClipController.addListener(_onMidiClipStateChanged);
    uiLayout.addListener(_onLayoutChanged);

    // Set up vertical scroll sync between timeline and mixer
    timelineVerticalScrollController.addListener(onTimelineVerticalScroll);
    mixerVerticalScrollController.addListener(onMixerVerticalScroll);

    // Load user settings and apply saved panel states
    userSettings.load().then((_) async {
      if (mounted) {
        setState(() {
          // Load visibility states
          uiLayout.isLibraryPanelCollapsed = userSettings.libraryCollapsed;
          uiLayout.isMixerVisible = userSettings.mixerVisible;
          uiLayout.isEditorPanelVisible = userSettings.editorVisible;
          // Load panel sizes (library uses left/right columns, total is computed)
          uiLayout.libraryLeftColumnWidth = userSettings.libraryLeftColumnWidth;
          uiLayout.libraryRightColumnWidth =
              userSettings.libraryRightColumnWidth;
          uiLayout.mixerPanelWidth = userSettings.mixerWidth;
          uiLayout.editorPanelHeight = userSettings.editorHeight;
        });

        // Show start screen modal on launch
        if (mounted) {
          await _showStartScreen();
          // First-run tour auto-start removed for now (current tour isn't
          // good enough yet) — still reachable via Help → Take a Tour.
        }
      }
    });

    // CRITICAL: Schedule audio engine initialization with a delay to prevent UI freeze
    // Even with postFrameCallback, FFI calls to Rust/C++ can block the main thread
    // Use Future.delayed to ensure UI renders multiple frames before any FFI initialization
    // DO NOT move this back to initState() or earlier - it will freeze the app on startup
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _initAudioEngine();
      }
    });
  }

  /// Recording state changed (arm, count-in, recording active).
  void _onRecordingStateChanged() {
    if (mounted) setState(() {});
  }

  /// Track order, heights, or metadata changed.
  void _onTrackStateChanged() {
    _deferSetState(() {});
  }

  /// MIDI clip selection or editing state changed.
  void _onMidiClipStateChanged() {
    if (mounted) setState(() {});
  }

  /// Playback play/stop *transition* — rebuilds so the playhead line's colour
  /// (white while playing, grey at rest) updates. Gated on the bool flipping so
  /// we rebuild ~twice per playback session, never per frame (per-frame
  /// playhead motion stays on playheadNotifier — see initState).
  bool _lastIsPlaying = false;
  void _onPlaybackPlayingChanged() {
    final playing = playbackController.isPlaying;
    if (playing != _lastIsPlaying) {
      _lastIsPlaying = playing;
      if (mounted) setState(() {});
    }
  }

  /// Panel visibility or sizes changed.
  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  void _onUndoRedoChanged() {
    _deferSetState(() {
      // Trigger rebuild to update Edit menu state
    });
    scheduleScreenEngineCheck();
  }

  /// Post-frame setState — avoids parent rebuild during child panel refresh.
  void _deferSetState(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(fn);
    });
  }

  void _onVst3ManagerChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild when VST3 manager state changes
      });
    }
  }

  void _onProjectManagerChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild when project manager state changes
      });
    }
  }

  void _onMidiPlaybackManagerChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild when MIDI playback manager state changes
      });
    }
  }

  InputHealthWatcher? _inputHealthWatcher;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalTransportKey);
    _inputHealthWatcher?.dispose();

    // Remove undo/redo listener
    undoRedoManager.removeListener(_onUndoRedoChanged);

    // Remove controller listeners
    playbackController.removeListener(_onPlaybackPlayingChanged);
    recordingController.removeListener(_onRecordingStateChanged);
    trackController.removeListener(_onTrackStateChanged);
    midiClipController.removeListener(_onMidiClipStateChanged);
    uiLayout.removeListener(_onLayoutChanged);

    // Clear callbacks to prevent memory leaks
    recordingController.onRecordingComplete = null;
    playbackController.onAutoStop = null;
    playbackController.onStreamError = null;

    // Dispose controllers (ChangeNotifiers must be disposed)
    playbackController.dispose();
    recordingController.dispose();
    trackController.dispose();
    midiClipController.dispose();
    automationController.dispose();
    libraryPreviewService?.dispose();
    uiLayout.dispose();

    // Dispose notifiers
    _leftDividerActive.dispose();
    _rightDividerActive.dispose();
    automationPreviewNotifier.dispose();

    // Dispose scroll controllers
    timelineVerticalScrollController.removeListener(onTimelineVerticalScroll);
    mixerVerticalScrollController.removeListener(onMixerVerticalScroll);
    timelineVerticalScrollController.dispose();
    mixerVerticalScrollController.dispose();

    // Remove VST3 manager listener
    vst3PluginManager?.removeListener(_onVst3ManagerChanged);

    // Remove project manager listener
    projectManager?.removeListener(_onProjectManagerChanged);

    // Remove MIDI playback manager listener
    midiPlaybackManager?.removeListener(_onMidiPlaybackManagerChanged);

    // Stop auto-save and record clean exit
    autoSaveService.stop();
    autoSaveService.cleanupBackups();
    userSettings.recordCleanExit();

    // Stop playback
    stopPlayback();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Returning focus to Boojy is a natural moment to pick up a MIDI keyboard
    // that was plugged in while we were in the background.
    if (state == AppLifecycleState.resumed && isAudioGraphInitialized) {
      rescanMidiForHotPlug();
    }
  }

  Future<void> _initAudioEngine() async {
    try {
      // Load plugin preferences early (before any plugin operations)
      await PluginPreferencesService.load();

      // Called after 800ms delay from initState, so UI has rendered
      audioEngine = AudioEngine();
      audioEngine!.initAudioEngine();

      // Initialize audio graph
      final graphResult = audioEngine!.initAudioGraph();
      if (graphResult.startsWith('Error')) {
        throw Exception(graphResult);
      }

      // Initialize recording settings
      try {
        audioEngine!.setCountInBars(
          userSettings.countInBars,
        ); // Use saved setting
        audioEngine!.setTempo(120.0); // Default: 120 BPM
        audioEngine!.setMetronomeEnabled(enabled: true); // Default: enabled
      } catch (e) {
        Log.e('Recording settings initialization failed: $e');
      }

      // Initialize buffer size from user settings
      try {
        final bufferPreset = bufferSizeToPreset(userSettings.bufferSize);
        audioEngine!.setBufferSize(bufferPreset);
      } catch (e) {
        Log.e('Buffer size setting failed: $e');
      }

      // Initialize output device from user settings
      if (userSettings.preferredOutputDevice != null) {
        try {
          audioEngine!.setAudioOutputDevice(
            userSettings.preferredOutputDevice!,
          );
        } catch (e) {
          Log.e('Output device setting failed: $e');
        }
      }

      // Initialize input from user settings ('' follows the system default)
      try {
        audioEngine!.setAudioInputChoice(
          userSettings.preferredInputDevice ?? '',
        );
      } catch (e) {
        Log.e('Input device setting failed: $e');
      }

      if (mounted) {
        setState(() {
          isAudioGraphInitialized = true;
        });
      }

      // Surface output-stream death (device unplugged mid-playback — C99).
      // The controller has already stopped the transport.
      playbackController.onStreamError = (message) {
        Notices.problem(
          'Audio device lost, so playback stopped. Pick an output in Settings.',
          id: 'audio-device-lost',
          error: message,
          action: NoticeAction('Open Settings', appSettings),
        );
      };

      // Initialize undo/redo manager with engine
      undoRedoManager.initialize(audioEngine!);

      // Initialize controllers with audio engine.
      // Set the preferred-MIDI-device reader BEFORE initialize(), which loads
      // MIDI devices and honors the saved preference. It's a lazy callback, so
      // if settings haven't finished loading yet it falls back to the default
      // device and the first focus/arm rescan corrects it.
      playbackController.initialize(audioEngine!);
      recordingController.getPreferredMidiDevice = () =>
          userSettings.preferredMidiInput;
      recordingController.initialize(audioEngine!);
      recordingController.setLiveRecordingNotifier(liveRecordingNotifier);
      // The live MIDI clip goes on the armed MIDI track, else the selected
      // track if it's MIDI (where an unarmed MIDI take lands). Never on an
      // audio track: it drew an empty box there during audio takes.
      recordingController.getFirstArmedMidiTrackId = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        final armed = tracks.where((t) => t.isMidi && t.armed).firstOrNull;
        if (armed != null) return armed.id;
        final selected = tracks
            .where((t) => t.id == selectedTrackId)
            .firstOrNull;
        return selected != null && selected.isMidi ? selected.id : null;
      };
      // Read from the engine: Record → New Audio Track arms the track a
      // moment before the mixer's copy of it refreshes.
      recordingController.getArmedAudioTracks = () => [
        for (final id in audioEngine?.getAllTrackIds() ?? <int>[])
          if (TrackData.fromCSV(audioEngine!.getTrackInfo(id)) case final t?
              when t.isAudio && t.armed)
            (
              trackId: t.id,
              channel: t.inputChannel,
              name: generateClipName(t.id),
            ),
      ];
      recordingController.getRecordingClipName = (trackId) =>
          generateClipName(trackId);
      recordingController.hasArmedAudioTracks = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        return tracks.any((t) => t.isAudio && t.armed);
      };

      // Arming an audio track opens the input (engine); say so when Boojy
      // can't hear it.
      _inputHealthWatcher = InputHealthWatcher(
        readHealth: audioEngine!.getAudioInputHealth,
        hasArmedAudioTrack: () =>
            recordingController.hasArmedAudioTracks?.call() ?? false,
        settingsAction: NoticeAction('Open Settings', appSettings),
      )..start();

      // Initialize VST3 editor service (for platform channel communication)
      VST3EditorService.initialize(audioEngine!);

      // Initialize VST3 plugin manager
      vst3PluginManager = Vst3PluginManager(audioEngine!);
      vst3PluginManager!.addListener(_onVst3ManagerChanged);

      // Initialize project manager
      projectManager = ProjectManager(audioEngine!);
      projectManager!.addListener(_onProjectManagerChanged);

      // Initialize MIDI playback manager
      midiPlaybackManager = MidiPlaybackManager(audioEngine!);
      midiPlaybackManager!.addListener(_onMidiPlaybackManagerChanged);

      // Initialize library preview service
      libraryPreviewService = LibraryPreviewService(audioEngine!);

      // Initialize MIDI clip controller with engine and manager
      midiClipController.initialize(audioEngine!, midiPlaybackManager!);
      midiClipController.setTempo(recordingController.tempo);

      // Scan VST3 plugins after audio graph is ready
      if (!vst3PluginManager!.isScanned && mounted) {
        scanVst3Plugins();
      }

      // Load MIDI devices
      loadMidiDevices();

      // Initialize auto-save service
      autoSaveService.initialize(
        projectManager: projectManager!,
        getUILayout: getCurrentUILayout,
      );
      autoSaveService.start();

      // Check for crash recovery
      checkForCrashRecovery();
    } catch (e) {
      Log.e('Audio engine initialization failed: $e');
      if (mounted) {
        setState(() => engineInitFailed = true);
        _showInitError(e.toString());
      }
    }
  }

  void _showInitError(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audio Engine Error'),
        content: Text('Failed to initialize the audio engine.\n\n$error'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _initAudioEngine(); // Retry
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue Without Audio'),
          ),
        ],
      ),
    );
  }

  /// The track that MIDI input (recording and the computer-keyboard piano)
  /// goes to: the first armed MIDI track, else the selected track.
  int? _midiInputTrackId() {
    final tracks = mixerKey.currentState?.tracks ?? [];
    for (final t in tracks) {
      if (t.isMidi && t.armed) return t.id;
    }
    return selectedTrackId;
  }

  /// App-level handler for transport/loop single-key shortcuts (Space, L, M).
  /// Registered on [HardwareKeyboard] in initState so it runs *before*
  /// focus-based key dispatch — this is what makes Space keep working after
  /// you click a button (a focused Material button would otherwise consume
  /// Space via its activate-on-space binding). Returns true to consume the
  /// event so the focused widget never sees it.
  ///
  /// Other single-key shortcuts (Q, Delete) stay in [_handleSingleKeyShortcut]
  /// because they overlap the timeline's own contextual handling.
  bool _handleGlobalTransportKey(KeyEvent event) {
    // Act on initial press only — never key-repeat or key-up.
    if (event is! KeyDownEvent) return false;

    // Let focused text fields keep their keystrokes (typing names, etc.).
    if (isTextFieldFocused()) return false;

    // A held command modifier means this belongs to a combo shortcut
    // (e.g. Cmd+Shift+T) — leave it for CallbackShortcuts.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        togglePlayPause();
        return true;
      case LogicalKeyboardKey.keyL:
        // L is also a note on the computer-keyboard piano; the piano wins
        // while it is open.
        if (uiLayout.isVirtualPianoEnabled) return false;
        toggleLoop();
        return true;
      case LogicalKeyboardKey.keyM:
        toggleMetronome();
        return true;
      default:
        return false;
    }
  }

  /// Handle single-key shortcuts that should be suppressed when text field is focused.
  /// Returns true if the key was handled, false to let it propagate to text fields.
  KeyEventResult _handleSingleKeyShortcut(KeyEvent event) {
    // Only handle KeyDownEvent, not KeyUpEvent or KeyRepeatEvent
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // If a text field is focused, don't intercept any single-key shortcuts
    if (isTextFieldFocused()) return KeyEventResult.ignored;

    // These are bare single-key shortcuts (L = loop, M = metronome, …). When a
    // command modifier is held the keystroke belongs to a combo shortcut
    // (e.g. Cmd+Shift+T cycles the theme) — bail so it reaches CallbackShortcuts
    // instead of being swallowed here.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    // Handle single-key shortcuts. Space/L/M/I/O are handled globally in
    // _handleGlobalTransportKey (so they survive focus drift to a button);
    // only the timeline-contextual keys remain here.
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyQ:
        quantizeSelectedClip();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        // Safety net: the timeline normally handles clip deletion via its own
        // focus, but if focus drifted to another panel, fall back to deleting
        // the selected clips here. No-op (ignored) when nothing is selected.
        return (timelineKey.currentState?.deleteSelectedClips() ?? false)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  // M2: Recording methods - handled by DAWRecordingMixin
  // (toggleRecording, startRecording, stopRecording, handleRecordingComplete)

  /// Toolbar Count-in toggle: Off ↔ one bar.
  void _toggleCountIn() {
    setCountInBars(userSettings.countInBars > 0 ? 0 : 1);
  }

  // Tempo drag coalescing: live updates during a vertical drag, one undo
  // step on release (same pattern as the time-signature control below —
  // without it every drag tick landed its own BPM on the undo stack, so
  // undoing a tempo change stepped back through dozens of intermediates).
  bool _tempoDragging = false;
  double _tempoDragStartBpm = 120.0;

  /// Apply a tempo to the engine + every dependent (MIDI reschedule, audio
  /// clip rescale + engine re-push, automation re-push, metadata) WITHOUT
  /// registering undo. The engine keeps all positions in real seconds, so
  /// the rescaled values must reach it on every apply — including undo/redo,
  /// which is why the SetTempoCommand callback is this same method.
  void _applyTempo(double newBpm) {
    // Get the current (old) tempo before we change it
    final currentTempo = recordingController.tempo;

    recordingController.setTempo(newBpm);
    midiClipController.setTempo(newBpm);
    midiCaptureBuffer.updateBpm(newBpm);
    midiPlaybackManager?.rescheduleAllClips(newBpm);

    // Re-anchor the playback caches (loop tempo, stop-return positions) so a
    // mid-playback tempo change keeps looping at the same BEAT — without this
    // the loop kept wrapping at the old tempo's wall-clock bounds. The engine
    // itself moves the playhead to the same beat inside set_tempo.
    playbackController.handleTempoChange(currentTempo, newBpm);

    // Adjust audio clip positions to maintain their beat position
    // This prevents audio clips from visually shifting when tempo changes
    timelineKey.currentState?.adjustAudioClipPositionsForTempoChange(
      currentTempo,
      newBpm,
    );

    // Re-push the rescaled positions to the engine — otherwise clips LOOK
    // right after a tempo change but PLAY from their old positions.
    final timelineClips = timelineKey.currentState?.clips;
    if (timelineClips != null) {
      for (final clip in timelineClips) {
        audioEngine?.setClipStartTime(
          clip.trackId,
          clip.clipId,
          clip.startTime,
        );
      }
      // Warped clips follow the new tempo once the change is finished; on
      // every drag step it would re-stretch each clip's audio.
      final engine = audioEngine;
      if (engine != null && !_tempoDragging) {
        pushWarpForTempo(engine, timelineClips);
      }
    }
    syncAllVolumeAutomationToEngine();

    // Keep the metadata BPM in step with the engine tempo — including on
    // undo/redo.
    setState(() {
      projectMetadata = projectMetadata.copyWith(bpm: newBpm);
    });
  }

  Future<void> _onTempoChanged(double bpm) async {
    // During a drag, apply live (engine must follow the gesture so playback
    // tracks the scrub); the single undo step is registered on drag end.
    if (_tempoDragging) {
      _applyTempo(bpm);
      return;
    }
    // Discrete change (scroll step, typed value, tap-tempo, settings dialog):
    // one undo step.
    final oldBpm = recordingController.tempo;
    if (oldBpm == bpm) return;

    final command = SetTempoCommand(
      newBpm: bpm,
      oldBpm: oldBpm,
      onTempoChanged: _applyTempo,
    );
    await undoRedoManager.execute(command);
  }

  void _onTempoDragStart() {
    _tempoDragging = true;
    _tempoDragStartBpm = recordingController.tempo;
  }

  Future<void> _onTempoDragEnd() async {
    _tempoDragging = false;
    final newBpm = recordingController.tempo;
    if (newBpm == _tempoDragStartBpm) return;
    // Value is already applied live; register the whole drag as one undo
    // step (execute re-applies the same value — idempotent).
    await undoRedoManager.execute(
      SetTempoCommand(
        newBpm: newBpm,
        oldBpm: _tempoDragStartBpm,
        onTempoChanged: _applyTempo,
      ),
    );
  }

  // Time-signature drag coalescing: live updates during a vertical drag, one
  // undo step on release (same pattern as the send knob / position scrubber).
  bool _timeSigDragging = false;
  int _timeSigDragStartNum = 4;
  int _timeSigDragStartUnit = 4;

  /// Apply a time signature to the engine + UI metadata WITHOUT registering undo.
  /// The denominator is locked to /4 in v0.6 — the engine has no beat-unit
  /// concept, so any other value was display-only theater (6/8 played as 6/4).
  void _applyTimeSignature(int beatsPerBar, int beatUnit) {
    setState(() {
      projectMetadata = projectMetadata.copyWith(
        timeSignatureNumerator: beatsPerBar,
        timeSignatureDenominator: 4,
      );
    });
    audioEngine?.setTimeSignature(beatsPerBar);
  }

  Future<void> _onTimeSignatureChanged(int beatsPerBar, int beatUnit) async {
    // During a drag, apply live; the single undo step is registered on drag end.
    if (_timeSigDragging) {
      _applyTimeSignature(beatsPerBar, beatUnit);
      return;
    }
    // Discrete change (menu pick): one undo step.
    final oldNum = projectMetadata.timeSignatureNumerator;
    final oldUnit = projectMetadata.timeSignatureDenominator;
    if (oldNum == beatsPerBar && oldUnit == beatUnit) return;
    await undoRedoManager.execute(
      SetTimeSignatureCommand(
        newNumerator: beatsPerBar,
        oldNumerator: oldNum,
        newDenominator: beatUnit,
        oldDenominator: oldUnit,
        onChanged: _applyTimeSignature,
      ),
    );
  }

  void _onTimeSignatureDragStart() {
    _timeSigDragging = true;
    _timeSigDragStartNum = projectMetadata.timeSignatureNumerator;
    _timeSigDragStartUnit = projectMetadata.timeSignatureDenominator;
  }

  Future<void> _onTimeSignatureDragEnd() async {
    _timeSigDragging = false;
    final newNum = projectMetadata.timeSignatureNumerator;
    final newUnit = projectMetadata.timeSignatureDenominator;
    if (newNum == _timeSigDragStartNum && newUnit == _timeSigDragStartUnit) {
      return;
    }
    // Value is already applied live; register the whole drag as one undo step.
    await undoRedoManager.execute(
      SetTimeSignatureCommand(
        newNumerator: newNum,
        oldNumerator: _timeSigDragStartNum,
        newDenominator: newUnit,
        oldDenominator: _timeSigDragStartUnit,
        onChanged: _applyTimeSignature,
      ),
    );
  }

  /// Apply a track colour override (null ARGB clears it → auto colour).
  void _applyTrackColor(int trackId, int? colorArgb) {
    if (colorArgb == null) {
      trackController.clearTrackColorOverride(trackId);
    } else {
      trackController.setTrackColor(trackId, Color(colorArgb));
    }
  }

  Future<void> _onTrackColorChanged(int trackId, Color color) async {
    final oldColor = trackController.trackColorOverrides[trackId];
    if (oldColor == color) return;
    await undoRedoManager.execute(
      SetTrackColorCommand(
        trackId: trackId,
        newColorArgb: color.toARGB32(),
        oldColorArgb: oldColor?.toARGB32(),
        onColorChanged: _applyTrackColor,
      ),
    );
  }

  /// Handle audio clip selection from timeline
  void _onAudioClipSelected(int? clipId, ClipData? clip) {
    setState(() {
      selectedAudioClip = clip;
      if (clip != null) {
        // Also select the track that contains this clip
        selectedTrackId = clip.trackId;
        // Clear MIDI clip selection
        midiPlaybackManager?.selectClip(null, null);
      }
    });
  }

  /// Handle audio clip updates from Audio Editor
  void _onAudioClipUpdated(ClipData clip) {
    setState(() {
      selectedAudioClip = clip;
    });

    // Update the clip in the timeline view so waveform reflects gain changes
    timelineKey.currentState?.updateClip(clip);
  }

  /// Undoable track deletion that snapshots and restores the track's content.
  ///
  /// Lives here (not in the mixer panel) because restoring clips needs the
  /// playback managers. The command owns the engine-side state (mixer, sends,
  /// built-in effects, redo id); these closures own the UI/manager state
  /// (MIDI + audio clips, timeline, selection). VST3 plugins and tweaked synth
  /// params aren't recovered — surfaced via the command's onNotice.
  Future<void> _onDeleteTrackRequested(TrackData track) async {
    // Snapshot the track's content BEFORE the command deletes it.
    final midiSnapshot =
        midiPlaybackManager?.midiClips
            .where((c) => c.trackId == track.id)
            .toList() ??
        const <MidiClipData>[];
    final audioSnapshot =
        timelineKey.currentState?.getAudioClipsOnTrack(track.id) ??
        const <ClipData>[];
    // A VST3 *instrument* (e.g. Serum) lives in the track's InstrumentData
    // (trackController), NOT in vst3PluginManager — that's what the UI's
    // instrument slot reads. Capture its path so undo can route the reloaded
    // plugin back to setTrackInstrument; everything else is a VST3 effect.
    final deletedInstrument = trackController.getTrackInstrument(track.id);
    final instrumentPluginPath = (deletedInstrument?.type == 'vst3')
        ? deletedInstrument?.pluginPath
        : null;
    final command = DeleteTrackCommand(
      trackId: track.id,
      trackName: track.name,
      trackType: track.type,
      volumeDb: track.volumeDb,
      pan: track.pan,
      mute: track.mute,
      solo: track.solo,
      armed: track.armed,
      onVst3Restored: (newTrackId, restored) {
        // The command reloaded these plugins into the engine. A reloaded plugin
        // whose path matches the deleted track's VST3 instrument goes back as
        // the track's instrument (trackController); the rest are VST3 effects
        // and re-register with the plugin manager (editor + count chip).
        for (final r in restored) {
          if (instrumentPluginPath != null && r.path == instrumentPluginPath) {
            trackController.setTrackInstrument(
              newTrackId,
              InstrumentData.vst3Instrument(
                trackId: newTrackId,
                pluginPath: r.path,
                pluginName: r.name,
                effectId: r.effectId,
              ),
            );
          } else {
            vst3PluginManager?.registerRestoredPlugin(
              newTrackId,
              r.effectId,
              path: r.path,
              name: r.name,
            );
          }
        }
      },
      onCleanup: (tid) {
        // The engine drops a track's audio clips with the track, but the
        // timeline UI keeps them — prune them here so redo doesn't leave
        // ghosts. Then run the shared teardown (MIDI clips, plugin windows).
        final timeline = timelineKey.currentState;
        if (timeline != null) {
          for (final clip in timeline.getAudioClipsOnTrack(tid)) {
            timeline.removeClip(clip.clipId);
          }
        }
        onTrackDeleted(tid);
      },
      onRestoreUi: (newTrackId) {
        // MIDI clips: re-stamp onto the recreated track, re-add to the manager
        // and resync to the engine (mirrors DeleteMidiClipFromArrangementCommand).
        for (final clip in midiSnapshot) {
          final restored = clip.copyWith(trackId: newTrackId);
          midiPlaybackManager?.addRecordedClip(restored);
          midiClipController.updateClip(restored, playheadPosition);
        }
        // Audio clips: reload from disk onto the new track and re-apply trim
        // (mirrors DeleteAudioClipCommand.undo).
        for (final clip in audioSnapshot) {
          final newClipId =
              audioEngine?.loadAudioFileToTrack(
                clip.filePath,
                newTrackId,
                startTime: clip.startTime,
              ) ??
              -1;
          if (newClipId >= 0) {
            audioEngine?.setClipOffset(newTrackId, newClipId, clip.offset);
            audioEngine?.setClipDuration(newTrackId, newClipId, clip.duration);
            timelineKey.currentState?.addClip(
              clip.copyWith(clipId: newClipId, trackId: newTrackId),
            );
          }
        }
        refreshTrackWidgets();
        onTrackSelected(newTrackId);
      },
      onNotice: Notices.problem,
    );

    await undoRedoManager.execute(command);
  }

  /// Called when a track is created from the mixer panel - refresh timeline immediately
  void _onTrackCreatedFromMixer(int trackId, String trackType) {
    onTrackSelected(trackId);
    refreshTrackWidgets();
    // New tracks arm themselves — keep arming exclusive (audio included).
    disarmOtherTracks(trackId);
  }

  // VST3 Instrument drop handlers
  Future<void> _onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
      // Checked before the instrument changes (see hasAutomaticName).
      final rename = hasAutomaticName(trackId);

      // Load the VST3 plugin as a track instrument
      final effectId = audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      trackController.setTrackInstrument(
        trackId,
        InstrumentData.vst3Instrument(
          trackId: trackId,
          pluginPath: plugin.path,
          pluginName: plugin.name,
          effectId: effectId,
        ),
      );
      if (rename) audioEngine?.setTrackName(trackId, plugin.name);

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = audioEngine!.vst3SendMidiNote(
        effectId,
        0,
        0,
        60,
        100,
      ); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {}
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || audioEngine == null) return;
        audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });
    } catch (e) {
      Log.e('Failed to preview VST3 instrument: $e');
    }
  }

  // Library double-click handlers
  void _handleLibraryItemDoubleClick(LibraryItem item) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && isMidiTrack(selectedTrack);
    final isEmptyAudio =
        selectedTrack != null && isEmptyAudioTrack(selectedTrack);

    switch (item.type) {
      case LibraryItemType.instrument:
        // Find the matching Instrument from availableInstruments
        final instrument = _findInstrumentByName(item.name);
        if (instrument != null) {
          if (isMidi) {
            // Swap/add instrument on selected MIDI track
            onInstrumentSelected(selectedTrack, instrument.id);
          } else {
            // Create new MIDI track with instrument
            onInstrumentDroppedOnEmpty(instrument);
          }
        }
        break;

      case LibraryItemType.preset:
        if (item is PresetItem) {
          // Find the instrument for this preset
          final instrument = _findInstrumentById(item.instrumentId);
          if (instrument != null) {
            if (isMidi) {
              // Swap/add instrument on selected MIDI track
              onInstrumentSelected(selectedTrack, instrument.id);
              // Preset loading deferred to v0.5.0 (Stock Instruments milestone)
            } else {
              // Create new MIDI track with instrument
              onInstrumentDroppedOnEmpty(instrument);
              // Preset loading deferred to v0.5.0 (Stock Instruments milestone)
            }
          }
        }
        break;

      case LibraryItemType.sample:
        if (item is SampleItem && item.filePath.isNotEmpty) {
          if (isEmptyAudio) {
            // Add clip to selected empty audio track
            _addAudioClipToTrack(selectedTrack, item.filePath);
          } else {
            // Create new audio track with clip
            onAudioFileDroppedOnEmpty(item.filePath);
          }
        } else {
          Notices.info("That sample isn't available yet");
        }
        break;

      case LibraryItemType.audioFile:
        if (item is AudioFileItem) {
          if (isEmptyAudio) {
            // Add clip to selected empty audio track
            _addAudioClipToTrack(selectedTrack, item.filePath);
          } else {
            // Create new audio track with clip
            onAudioFileDroppedOnEmpty(item.filePath);
          }
        }
        break;

      case LibraryItemType.effect:
        if (selectedTrack != null) {
          // Add effect to selected track
          if (item is EffectItem) {
            _addBuiltInEffectToTrack(selectedTrack, item.effectType);
          }
        } else {
          Notices.info('Select a track first to add effects');
        }
        break;

      case LibraryItemType.vst3Instrument:
      case LibraryItemType.vst3Effect:
        // Handled by _handleVst3DoubleClick
        break;

      case LibraryItemType.midiFile:
        if (item is MidiFileItem) {
          if (isMidi) {
            onMidiFileDroppedOnTrack(selectedTrack, item.filePath, 0.0);
          } else {
            onMidiFileDroppedOnEmpty(item.filePath, 0.0);
          }
        }
        break;

      case LibraryItemType.folder:
        // Folders are not double-clickable for adding
        break;
    }
  }

  void _handleVst3DoubleClick(Vst3Plugin plugin) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && isMidiTrack(selectedTrack);

    if (plugin.isInstrument) {
      if (isMidi) {
        // Swap/add VST3 instrument on selected MIDI track
        _onVst3InstrumentDropped(selectedTrack, plugin);
      } else {
        // Create new MIDI track with VST3 instrument
        onVst3InstrumentDroppedOnEmpty(plugin);
      }
    } else {
      // VST3 effect
      if (selectedTrack != null) {
        onVst3PluginDropped(selectedTrack, plugin);
      } else {
        Notices.info('Select a track first to add effects');
      }
    }
  }

  /// Open an audio file in a new Sampler track
  void _handleOpenInSampler(LibraryItem item) {
    if (audioEngine == null) return;

    // Get the file path
    String? filePath;
    if (item is SampleItem) {
      filePath = item.filePath;
    } else if (item is AudioFileItem) {
      filePath = item.filePath;
    }

    if (filePath == null || filePath.isEmpty) {
      Notices.problem("Couldn't find the audio file to open in the sampler");
      return;
    }

    // Create a new Sampler track
    createSamplerTrackWithSample(filePath, item.name);
  }

  // Helper: Find instrument by name
  Instrument? _findInstrumentByName(String name) {
    try {
      return availableInstruments.firstWhere(
        (inst) => inst.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  // Helper: Find instrument by ID
  Instrument? _findInstrumentById(String id) {
    try {
      return availableInstruments.firstWhere((inst) => inst.id == id);
    } catch (e) {
      return null;
    }
  }

  // Helper: Add audio clip to existing track
  Future<void> _addAudioClipToTrack(int trackId, String filePath) async {
    if (audioEngine == null) return;

    try {
      // Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

      final clipId = audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      final duration = audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = audioEngine!.getWaveformPeaks(clipId, peakResolution);

      timelineKey.currentState?.addClip(
        ClipData(
          clipId: clipId,
          trackId: trackId,
          filePath: finalPath, // Use the copied path
          startTime: 0.0,
          duration: duration,
          waveformPeaks: peaks,
        ),
      );
    } catch (e) {
      // Silently fail
    }
  }

  // Helper: Add built-in effect to track
  void _addBuiltInEffectToTrack(int trackId, String effectType) {
    if (audioEngine == null) return;

    try {
      final effectId = audioEngine!.addEffectToTrack(trackId, effectType);
      if (effectId < 0) {
        Notices.problem("Couldn't add the $effectType effect");
      }
    } catch (e) {
      Log.e('Failed to add effect to track: $e');
    }
  }

  // M10: VST3 Plugin methods - delegating to Vst3PluginManager

  void _showVst3PluginBrowser(int trackId) {
    _showFxPicker(trackId);
  }

  /// Refresh mixer/timeline after send/return changes.
  /// Post-frame avoids setState during FX picker dialog teardown.
  void _deferSendMutationRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      mixerKey.currentState?.refreshTracks();
      timelineKey.currentState?.refreshTracks();
    });
  }

  Future<void> _showFxPicker(int trackId) async {
    if (audioEngine == null) return;

    final trackInfo = audioEngine!.getTrackInfo(trackId);
    final track = TrackData.fromCSV(trackInfo);
    if (track == null) return;

    final isMaster = track.type.toLowerCase() == 'master';
    final result = await showFxPickerDialog(
      context: context,
      trackName: track.name,
      insertOnly: isMaster,
    );
    if (result == null || !mounted) return;

    if (result.mode == FxPickerMode.shared) {
      final cmd = AddSharedSendCommand(
        sourceTrackId: trackId,
        sourceTrackName: track.name,
        effectType: result.effectType,
        effectLabel: result.effectName,
      );
      await undoRedoManager.execute(cmd);
      if (!mounted) return;
      if (cmd.returnTrackId != null) {
        _deferSendMutationRefresh();
      } else {
        Notices.problem("Couldn't add the ${result.effectName} send");
      }
      return;
    }

    await undoRedoManager.execute(
      AddEffectCommand(
        trackId: trackId,
        trackName: track.name,
        effectType: result.effectType,
        effectName: result.effectName,
        isVst3: false,
      ),
    );
    if (mounted) setState(() {});
  }

  List<Vst3PluginInstance> _getTrackVst3Plugins(int trackId) {
    return vst3PluginManager?.getTrackPlugins(trackId) ?? [];
  }

  /// Open the editor panel (double-click on a clip). Leaves it open if it
  /// already is; never closes it.
  void _openEditorPanel() {
    if (uiLayout.isEditorPanelVisible) return;
    setState(() {
      uiLayout.isEditorPanelVisible = true;
      userSettings.editorVisible = true;
    });
  }

  // M8: MIDI clip methods - delegating to MidiClipController
  void _onMidiClipSelected(int? clipId, MidiClipData? clipData) {
    final trackId = midiClipController.selectClip(clipId, clipData);
    if (clipId != null && clipData != null) {
      // Selecting never opens the editor panel: it opens on a double-click
      // of the clip, the editor chevron, or the View menu.
      selectedTrackId = trackId ?? clipData.trackId;
    }
  }

  void _onMidiClipUpdated(MidiClipData updatedClip) {
    midiClipController.updateClip(updatedClip, playheadPosition);
  }

  /// Export a MIDI clip as a Standard MIDI File (.mid)
  Future<void> _exportMidiClip(MidiClipData clip) async {
    final defaultName = clip.name.replaceAll(RegExp(r'[^\w\s\-]'), '');
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export MIDI File',
      fileName: '$defaultName.mid',
      type: FileType.custom,
      allowedExtensions: ['mid'],
    );
    if (result == null) return;

    final path = result.endsWith('.mid') ? result : '$result.mid';
    final bytes = MidiFileService.encode(clip.notes, tempo: tempo);
    await File(path).writeAsBytes(bytes);
  }

  /// Batch delete multiple MIDI clips (eraser tool - single undo action)
  void _deleteMidiClipsBatch(List<(int clipId, int trackId)> clipsToDelete) {
    if (clipsToDelete.isEmpty) return;

    // Build individual delete commands for each clip
    final commands = <Command>[];
    for (final (clipId, trackId) in clipsToDelete) {
      final clip = midiPlaybackManager?.midiClips.firstWhere(
        (c) => c.clipId == clipId,
        orElse: () => MidiClipData(
          clipId: clipId,
          trackId: trackId,
          startTime: 0,
          duration: 4,
          name: 'Deleted Clip',
        ),
      );

      if (clip != null) {
        commands.add(
          DeleteMidiClipFromArrangementCommand(
            clipData: clip,
            onClipRemoved: (cId, tId) {
              midiClipController.deleteClip(cId, tId);
            },
            onClipRestored: (restoredClip) {
              midiPlaybackManager?.addRecordedClip(restoredClip);
              midiClipController.updateClip(restoredClip, playheadPosition);
            },
          ),
        );
      }
    }

    if (commands.isEmpty) return;

    // Wrap in CompositeCommand for single undo action
    final compositeCommand = CompositeCommand(
      commands,
      'Delete ${clipsToDelete.length} MIDI clip${clipsToDelete.length > 1 ? 's' : ''}',
    );
    undoRedoManager.execute(compositeCommand);
    if (mounted) setState(() {});
  }

  // ========================================================================
  // Undo/Redo methods
  // ========================================================================

  // M5: Project file methods

  // ========================================================================
  // End Snapshot Methods
  // ========================================================================

  /// Start the guided first-run tour
  void _startTour() {
    final controller = TourController(
      steps: [
        TourStep(
          title: 'Transport Controls',
          description:
              'Play, stop, and record your music. Toggle loop mode and set your tempo here.',
          targetKey: tourTransportKey,
          placement: TourPlacement.below,
        ),
        TourStep(
          title: 'Instrument Library',
          description:
              'Browse instruments, audio samples, and plugins. Drag or double-click to add to your project.',
          targetKey: tourLibraryKey,
          placement: TourPlacement.right,
        ),
        TourStep(
          title: 'Timeline',
          description:
              'This is your canvas. Drag instruments from the library to create tracks and arrange your song.',
          targetKey: tourTimelineKey,
          placement: TourPlacement.below,
        ),
        TourStep(
          title: 'Mixer',
          description: 'Adjust volume, pan, and effects for each track.',
          targetKey: tourMixerKey,
          placement: TourPlacement.above,
        ),
        TourStep(
          title: 'Editor',
          description:
              'Edit MIDI notes in the piano roll or tweak audio clips. Select a clip to start editing.',
          targetKey: tourEditorKey,
          placement: TourPlacement.above,
        ),
        const TourStep(
          title: 'Keyboard Shortcuts',
          description:
              'Press ? anytime to see all shortcuts. Space to play/pause, R to record.',
        ),
      ],
    );

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => TourOverlay(
        controller: controller,
        onComplete: () {
          overlayEntry.remove();
          userSettings.hasCompletedTour = true;
        },
        onSkip: () {
          overlayEntry.remove();
          userSettings.hasCompletedTour = true;
        },
      ),
    );

    Overlay.of(context).insert(overlayEntry);
    controller.start();
  }

  Future<void> _showStartScreen() async {
    final result = await StartScreenModal.show(context, userSettings);
    if (!mounted || result == null) return;

    switch (result.action) {
      case StartScreenAction.newProject:
        executeNewProject();
      case StartScreenAction.openProject:
        openProject();
      case StartScreenAction.openRecent:
        if (result.projectPath != null) {
          openRecentProject(result.projectPath!);
        }
      case StartScreenAction.openSettings:
        await appSettings();
        // Return to the launcher after settings closes so the user can still
        // pick New / Open / a recent project.
        if (mounted) await _showStartScreen();
      case StartScreenAction.dismissed:
        break;
    }
  }

  void _closeProject() {
    // Show confirmation dialog if current project has unsaved changes
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Project'),
        content: const Text(
          'Are you sure you want to close the current project?\n\nAny unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              // Stop playback if active
              if (isPlaying) {
                stopPlayback();
              }

              // Clear all tracks from the audio engine
              audioEngine?.clearAllTracks();

              // Clear project state via manager
              projectManager?.closeProject();
              midiPlaybackManager?.clear();
              undoRedoManager.clear();
              // Track numbering restarts at 1, so per-track UI data from this
              // project must not survive into the next one.
              resetPerTrackUiState();

              // Refresh track widgets to show empty state (clear clips too)
              refreshTrackWidgets(clearClips: true);

              setState(() {
                loadedClipId = null;
                waveformPeaks = [];
              });

              // Show start screen after closing
              _showStartScreen();
            },
            child: Text('Close', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportBar() {
    // Rebuild on the controller's discrete state changes (play / pause / stop)
    // AND on the 60fps playhead notifier. The playhead notifier alone is not
    // enough: pause() stops the playhead timer, so without listening to the
    // controller the bar would never rebuild after a pause and the play/pause
    // button would stay stuck on the "pause" icon — unable to resume until a
    // Stop nudged the playhead notifier.
    return ListenableBuilder(
      listenable: playbackController,
      builder: (context, _) => ValueListenableBuilder<double>(
        valueListenable: playbackController.playheadNotifier,
        builder: (context, playheadPos, _) => TransportBar(
          // Grouped callbacks
          fileMenu: FileMenuCallbacks(
            onNewProject: newProject,
            onOpenProject: openProject,
            onSaveProject: saveProject,
            onSaveProjectAs: saveProjectAs,
            onRenameProject: renameProject,
            onExportAudio: exportAudio,
            onAppSettings: appSettings,
            onCloseProject: _closeProject,
            onStartScreen: _showStartScreen,
            onKeyboardShortcuts: showKeyboardShortcuts,
          ),
          transport: TransportCallbacks(
            onPlay: playWithLoopCheck,
            onPause: pause,
            onStop: stopPlayback,
            onRecord: toggleRecording,
            onRecordNewMidiTrack: () => _recordIntoNewTrack('midi'),
            onRecordNewAudioTrack: () => _recordIntoNewTrack('audio'),
            onPauseRecording: pauseRecording,
            onStopRecording: stopRecordingAndReturn,
            onUndo: undoRedoManager.canUndo ? performUndo : null,
            onRedo: undoRedoManager.canRedo ? performRedo : null,
            onMetronomeToggle: toggleMetronome,
            onPianoToggle: toggleVirtualPiano,
            onLoopPlaybackToggle: toggleLoop,
            onPositionChanged: (seconds) {
              playbackController.seek(seconds);
            },
            onCaptureMidi: captureMidi,
          ),
          panels: PanelCallbacks(
            onToggleLibrary: toggleLibraryPanel,
            onToggleMixer: toggleMixer,
            onToggleEditor: toggleEditor,
            onTogglePiano: toggleVirtualPiano,
            onResetPanelLayout: resetPanelLayout,
          ),
          // Remaining individual parameters
          playheadPosition: playheadPos,
          isPlaying: isPlaying,
          canPlay: true, // Always allow transport controls
          isRecording: isRecording,
          isCountingIn: isCountingIn,
          countInBeat: recordingController.countInBeat,
          countInProgress: recordingController.countInProgress,
          hasArmedTracks: () =>
              mixerKey.currentState?.tracks.any((t) => t.armed) ?? false,
          metronomeEnabled: isMetronomeEnabled,
          virtualPianoEnabled: uiLayout.isVirtualPianoEnabled,
          tempo: tempo,
          onTempoChanged: _onTempoChanged,
          onTempoDragStart: _onTempoDragStart,
          onTempoDragEnd: _onTempoDragEnd,
          countInEnabled: userSettings.countInBars > 0,
          onCountInToggle: _toggleCountIn,
          projectName: projectMetadata.name,
          hasProject: projectManager?.hasProject ?? false,
          libraryVisible: !uiLayout.isLibraryPanelCollapsed,
          mixerVisible: uiLayout.isMixerVisible,
          editorVisible: uiLayout.isEditorPanelVisible,
          pianoVisible: uiLayout.isVirtualPianoEnabled,
          canUndo: undoRedoManager.canUndo,
          canRedo: undoRedoManager.canRedo,
          undoDescription: undoRedoManager.undoDescription,
          redoDescription: undoRedoManager.redoDescription,
          loopPlaybackEnabled: uiLayout.loopPlaybackEnabled,
          beatsPerBar: projectMetadata.timeSignatureNumerator,
          onTimeSignatureChanged: _onTimeSignatureChanged,
          onTimeSignatureDragStart: _onTimeSignatureDragStart,
          onTimeSignatureDragEnd: _onTimeSignatureDragEnd,
          isLoading: isLoading,
          engineFailed: engineInitFailed,
        ),
      ),
    );
  }

  /// Create MIDI track with default 1-bar clip and open Piano Roll.
  Future<void> _addMidiTrackWithClip() async {
    final command = CreateTrackCommand(trackType: 'midi', trackName: 'MIDI 1');
    await undoRedoManager.execute(command);
    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) return;

    createDefaultMidiClip(trackId);
    onTrackSelected(trackId, autoSelectClip: true);
    // Adding a track from the empty-timeline button is deliberate: open its editor.
    uiLayout.isEditorPanelVisible = true;
    refreshTrackWidgets();
  }

  /// Create an audio track (undoable, matching the MIDI path — no default clip).
  Future<void> _addAudioTrack() async {
    final command = CreateTrackCommand(
      trackType: 'audio',
      trackName: 'Audio 1',
    );
    await undoRedoManager.execute(command);
    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) return;

    onTrackSelected(trackId);
    refreshTrackWidgets();
  }

  /// Record pressed with nothing armed: create a new track of [trackType], arm
  /// it, and roll (count-in honoured). Lets the record button always be live.
  Future<void> _recordIntoNewTrack(String trackType) async {
    if (audioEngine == null) return;
    final command = CreateTrackCommand(
      trackType: trackType,
      trackName: trackType == 'midi' ? 'MIDI 1' : 'Audio 1',
    );
    await undoRedoManager.execute(command);
    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) return;

    if (trackType == 'midi') {
      createDefaultMidiClip(trackId);
    }

    // Arm via the engine (source of truth) so recording targets the new track;
    // the refresh propagates the armed flag into the mixer + hasArmedTracks.
    audioEngine!.setTrackArmed(trackId, armed: true);
    onTrackSelected(trackId, autoSelectClip: trackType == 'midi');
    refreshTrackWidgets();

    // Roll. startRecording reads the engine-armed track set synchronously above.
    startRecording(isAlreadyPlaying: playbackController.isPlaying);
  }

  Widget _buildLibrarySection() {
    return AnimatedContainer(
      duration: _isDraggingLibrary
          ? Duration.zero
          : AnimationConstants.panelDuration,
      curve: Curves.easeInOut,
      width: uiLayout.isLibraryPanelCollapsed
          ? 0
          : uiLayout.libraryPanelWidth + 4,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: uiLayout.libraryPanelWidth + 4,
        minWidth: uiLayout.libraryPanelWidth + 4,
        child: Row(
          children: [
            SizedBox(
              width: uiLayout.libraryPanelWidth,
              child: libraryPreviewService != null
                  ? ChangeNotifierProvider<LibraryPreviewService>.value(
                      value: libraryPreviewService!,
                      child: LibraryPanel(
                        isCollapsed: false,
                        onToggle: toggleLibraryPanel,
                        availableVst3Plugins:
                            vst3PluginManager?.availablePlugins ?? [],
                        libraryService: libraryService,
                        onItemDoubleClick: _handleLibraryItemDoubleClick,
                        onVst3DoubleClick: _handleVst3DoubleClick,
                        onOpenInSampler: _handleOpenInSampler,
                      ),
                    )
                  : LibraryPanel(
                      isCollapsed: false,
                      onToggle: toggleLibraryPanel,
                      availableVst3Plugins:
                          vst3PluginManager?.availablePlugins ?? [],
                      libraryService: libraryService,
                      onItemDoubleClick: _handleLibraryItemDoubleClick,
                      onVst3DoubleClick: _handleVst3DoubleClick,
                      onOpenInSampler: _handleOpenInSampler,
                    ),
            ),

            // Divider: Library/Timeline
            ResizableDivider(
              orientation: DividerOrientation.vertical,
              isCollapsed: uiLayout.isLibraryPanelCollapsed,
              activeNotifier: _leftDividerActive,
              onDragStart: () => setState(() => _isDraggingLibrary = true),
              onDragEnd: () => setState(() => _isDraggingLibrary = false),
              onDrag: (delta) {
                setState(() {
                  uiLayout.resizeRightColumn(delta);
                  userSettings.libraryRightColumnWidth =
                      uiLayout.libraryRightColumnWidth;
                  userSettings.libraryCollapsed =
                      uiLayout.isLibraryPanelCollapsed;
                });
              },
              onDoubleClick: () {
                setState(() {
                  uiLayout.toggleLibraryPanel();
                  userSettings.libraryCollapsed =
                      uiLayout.isLibraryPanelCollapsed;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return Expanded(
      child: NoticeAnchor(
        child: RepaintBoundary(
          key: screenshotKey,
          child: TimelineView(
            key: timelineKey,
            beatsPerBar: projectMetadata.timeSignatureNumerator,
            playheadNotifier: playbackController.playheadNotifier,
            clipDuration: clipDuration,
            waveformPeaks: waveformPeaks,
            audioEngine: audioEngine,
            tempo: tempo,
            selectedMidiTrackId: selectedTrackId,
            selectedMidiClipId: midiPlaybackManager?.selectedClipId,
            currentEditingClip: midiPlaybackManager?.currentEditingClip,
            midiClips: midiPlaybackManager?.midiClips ?? [],
            liveAudioClips: liveRecordingNotifier.buildLiveAudioClips(),
            onMidiTrackSelected: onTrackSelected,
            getRustClipId: (dartClipId) =>
                midiPlaybackManager?.dartToRustClipIds[dartClipId] ??
                dartClipId,
            midiClipCallbacks: MidiClipCallbacks(
              onSelected: _onMidiClipSelected,
              onOpenEditor: _openEditorPanel,
              onUpdated: _onMidiClipUpdated,
              onCopied: onMidiClipCopied,
              onDeleted: deleteMidiClip,
              onBatchDeleted: _deleteMidiClipsBatch,
              onExported: _exportMidiClip,
              onSplit: onMidiClipSplit,
              onJoinSelected: joinSelectedClips,
              buildMidiOverlapCommand: (result) => ResolveMidiOverlapCommand(
                result: result,
                tempo: tempo,
                deleteClip: (cId, tId) =>
                    midiClipController.deleteClip(cId, tId),
                updateClipInPlace: (clip) =>
                    midiPlaybackManager?.updateClipInPlace(clip),
                rescheduleClip: (clip, t) =>
                    midiPlaybackManager?.rescheduleClip(clip, t),
                addClip: (clip) => midiPlaybackManager?.addRecordedClip(clip),
              ),
            ),
            audioClipCallbacks: AudioClipCallbacks(
              onSelected: _onAudioClipSelected,
              onOpenEditor: _openEditorPanel,
              onCopied: onAudioClipCopied,
              onBatchDeleted: deleteAudioClipsBatch,
              onJoinSelected: joinSelectedClips,
            ),
            dragDropCallbacks: DragDropCallbacks(
              onInstrumentDropped: onInstrumentDropped,
              onInstrumentDroppedOnEmpty: onInstrumentDroppedOnEmpty,
              onVst3InstrumentDropped: _onVst3InstrumentDropped,
              onVst3InstrumentDroppedOnEmpty: onVst3InstrumentDroppedOnEmpty,
              onMidiFileDroppedOnEmpty: onMidiFileDroppedOnEmpty,
              onMidiFileDroppedOnTrack: onMidiFileDroppedOnTrack,
              onAudioFileDroppedOnEmpty: onAudioFileDroppedOnEmpty,
              onAudioFileDroppedOnTrack: onAudioFileDroppedOnTrack,
              onCreateTrackWithClip: onCreateTrackWithClip,
              onCreateClipOnTrack: onCreateClipOnTrack,
            ),
            automationCallbacks: AutomationCallbacks(
              onPointAdded: onAutomationPointAdded,
              onPointUpdated: onAutomationPointUpdated,
              onPointDragEnd: onAutomationPointDragEnd,
              onPointDeleted: onAutomationPointDeleted,
              onPreviewValue: onAutomationPreviewValue,
              getAutomationLane: (trackId) => automationController.getLane(
                trackId,
                automationController.visibleParameter,
              ),
            ),
            trackHeightState: TrackHeightState(
              clipHeights: clipHeights,
              automationHeights: automationHeights,
              masterTrackHeight: masterTrackHeight,
              onClipHeightChanged: setClipHeight,
              onAutomationHeightChanged: setAutomationHeight,
              onSendCountChanged: trackController.syncSendCount,
            ),
            trackOrder: trackController.trackOrder,
            getTrackColor: getTrackColor,
            onSeek: (position) {
              audioEngine?.transportSeek(position);
              playheadPosition = position;
              // Update the notifier so ValueListenableBuilder rebuilds immediately
              playbackController.playheadNotifier.value = position;
            },
            // Loop playback state
            loopPlaybackEnabled: uiLayout.loopPlaybackEnabled,
            loopStartBeats: uiLayout.loopStartBeats,
            loopEndBeats: uiLayout.loopEndBeats,
            onLoopRegionChanged: (start, end) {
              uiLayout.setLoopRegion(start, end);
              // Update playback controller in real-time during playback
              playbackController.updateLoopBounds(
                loopStartBeats: start,
                loopEndBeats: end,
              );
            },
            // Vertical scroll sync with mixer panel
            verticalScrollController: timelineVerticalScrollController,
            // Tool mode (shared with piano roll)
            toolMode: currentToolMode,
            onToolModeChanged: (mode) => setState(() => currentToolMode = mode),
            // Playback state (for playhead glow)
            isPlaying: isPlaying,
            // Empty timeline: add track callbacks
            onAddMidiTrack: _addMidiTrackWithClip,
            onAddAudioTrack: _addAudioTrack,
            // Recording state (for auto-scroll)
            isRecording: isRecording,
            // Automation state
            automationVisibleTrackIds: automationController.visibleTrackIds,
            automationScrollController:
                timelineKey.currentState?.scrollController,
          ),
        ),
      ),
    );
  }

  Widget _buildMixerSection() {
    return AnimatedContainer(
      duration: _isDraggingMixer
          ? Duration.zero
          : AnimationConstants.panelDuration,
      curve: Curves.easeInOut,
      width: uiLayout.isMixerVisible ? uiLayout.mixerPanelWidth + 4 : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: OverflowBox(
        alignment: Alignment.centerRight,
        maxWidth: uiLayout.mixerPanelWidth + 4,
        minWidth: uiLayout.mixerPanelWidth + 4,
        child: Row(
          children: [
            // Divider: Timeline/Mixer
            ResizableDivider(
              orientation: DividerOrientation.vertical,
              isCollapsed: !uiLayout.isMixerVisible,
              activeNotifier: _rightDividerActive,
              onDragStart: () => setState(() => _isDraggingMixer = true),
              onDragEnd: () => setState(() => _isDraggingMixer = false),
              onDrag: (delta) {
                final windowWidth = MediaQuery.of(context).size.width;
                final maxWidth = UILayoutState.getMixerMaxWidth(windowWidth);
                setState(() {
                  final newWidth = uiLayout.mixerPanelWidth - delta;
                  // Snap collapse if dragged below threshold
                  if (newWidth < UILayoutState.mixerCollapseThreshold) {
                    uiLayout.collapseMixer();
                    userSettings.mixerVisible = false;
                  } else {
                    uiLayout.mixerPanelWidth = newWidth.clamp(
                      UILayoutState.mixerMinWidth,
                      maxWidth,
                    );
                    userSettings.mixerWidth = uiLayout.mixerPanelWidth;
                  }
                });
              },
              onDoubleClick: () {
                setState(() {
                  uiLayout.toggleMixer();
                  userSettings.mixerVisible = uiLayout.isMixerVisible;
                });
              },
            ),

            SizedBox(
              width: uiLayout.mixerPanelWidth,
              child: TrackMixerPanel(
                key: mixerKey,
                audioEngine: audioEngine,
                scrollController: mixerVerticalScrollController,
                trackInstruments: trackInstruments,
                trackVst3PluginCounts: getTrackVst3PluginCounts(), // M10
                onAudioFileDropped: (path) => onAudioFileDroppedOnEmpty(path),
                getTrackColor: getTrackColor,
                config: MixerPanelConfig(
                  isEngineReady: isAudioGraphInitialized,
                  panelWidth: uiLayout.mixerPanelWidth,
                  onTogglePanel: toggleMixer,
                  isRecording:
                      recordingController.isRecording ||
                      recordingController.isCountingIn,
                  trackOrder: trackController.trackOrder,
                  onTrackArmed: rescanMidiForHotPlug,
                ),
                selectionState: TrackSelectionState(
                  selectedTrackId: selectedTrackId,
                  selectedTrackIds: selectedTrackIds,
                  onTrackSelected: onTrackSelected,
                ),
                trackCallbacks: TrackManagementCallbacks(
                  onDuplicateRequested: onDuplicateTrackRequested,
                  onDeleted: onTrackDeleted,
                  onDeleteRequested: _onDeleteTrackRequested,
                  onMidiTrackCreated: createDefaultMidiClip,
                  onTrackCreated: _onTrackCreatedFromMixer,
                  onAddMidiTrack: _addMidiTrackWithClip,
                  onAddAudioTrack: _addAudioTrack,
                  onReordered: onTrackReordered,
                  onOrderSync: trackController.syncTrackOrder,
                  onDoubleClick: (trackId) {
                    // Select track and open editor
                    onTrackSelected(trackId);
                    if (!uiLayout.isEditorPanelVisible) {
                      toggleEditor();
                    }
                  },
                  onColorChanged: _onTrackColorChanged,
                  onConvertToSampler: convertAudioTrackToSampler,
                ),
                instrumentCallbacks: MixerInstrumentCallbacks(
                  onInstrumentSelected: onInstrumentSelected,
                  onInstrumentDropped:
                      onInstrumentDropped, // Swap built-in instrument
                  onVst3InstrumentDropped:
                      _onVst3InstrumentDropped, // Swap VST3 instrument
                  onVst3PluginDropped: onVst3PluginDropped, // M10
                  onBuiltInEffectDropped: (trackId, effect) =>
                      _addBuiltInEffectToTrack(trackId, effect.effectType),
                  onFxButtonPressed: _showVst3PluginBrowser, // M10
                  onEditPluginsPressed: showVst3PluginEditor, // M10
                ),
                trackHeightState: TrackHeightState(
                  clipHeights: clipHeights,
                  automationHeights: automationHeights,
                  masterTrackHeight: masterTrackHeight,
                  onClipHeightChanged: setClipHeight,
                  onAutomationHeightChanged: setAutomationHeight,
                  onSendCountChanged: trackController.syncSendCount,
                ),
                onMasterTrackHeightChanged: setMasterTrackHeight,
                automationCallbacks: AutomationCallbacks(
                  onPointAdded: onAutomationPointAdded,
                  onPointUpdated: onAutomationPointUpdated,
                  onPointDragEnd: onAutomationPointDragEnd,
                  onPointDeleted: onAutomationPointDeleted,
                  onPreviewValue: onAutomationPreviewValue,
                  getAutomationLane: (trackId) => automationController.getLane(
                    trackId,
                    automationController.visibleParameter,
                  ),
                ),
                automationState: MixerAutomationState(
                  isVisible: automationController.isVisible,
                  onToggleVisible: (trackId) {
                    setState(() {
                      automationController.toggleTrackVisible(trackId);
                    });
                  },
                  parameter: automationController.visibleParameter,
                  onParameterChanged: (param) {
                    setState(() {
                      automationController.setVisibleParameter(param);
                    });
                  },
                  onReset: onAutomationLaneCleared,
                  previewNotifier: automationPreviewNotifier,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowSize = MediaQuery.of(context).size;

    // Initialize panel sizes based on window size on first launch
    if (!hasInitializedPanelSizes && userSettings.isLoaded) {
      hasInitializedPanelSizes = true;
      if (!userSettings.hasSavedPanelSettings) {
        // First launch: use percentage-based sizing for all resizable panels.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              uiLayout.resetSizesToDefaults(
                windowSize.width,
                windowSize.height,
              );
            });
          }
        });
      }
    }

    // Auto-collapse panels if arrangement width falls below minimum
    // Close mixer first (if visible), then library
    final arrangementWidth = uiLayout.getArrangementWidth(windowSize.width);
    if (arrangementWidth < UILayoutState.minArrangementWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (uiLayout.isMixerVisible) {
          uiLayout.collapseMixer();
        } else if (!uiLayout.isLibraryPanelCollapsed) {
          uiLayout.collapseLibrary();
        }
      });
    }

    return StableMenuBar(
      menus: buildDawMenus(
        context,
        DawMenuConfig(
          // File menu callbacks
          onNewProject: newProject,
          onOpenProject: openProject,
          onSaveProject: saveProject,
          onSaveProjectAs: saveProjectAs,
          onRenameProject: renameProject,
          onExportAudio: exportAudio,
          onCloseProject: _closeProject,
          onStartScreen: _showStartScreen,
          recentProjectsMenu: buildRecentProjectsMenu(),
          // Edit menu state and callbacks
          undoRedoManager: undoRedoManager,
          onDelete: midiPlaybackManager?.selectedClipId != null
              ? () {
                  final clipId = midiPlaybackManager!.selectedClipId!;
                  final clip = midiPlaybackManager!.currentEditingClip;
                  if (clip != null) {
                    deleteMidiClip(clipId, clip.trackId);
                  }
                }
              : null,
          onDuplicate: duplicateSelectedClip,
          onSelectAll: selectAllClips,
          onSplitAtPlayhead:
              (midiPlaybackManager?.selectedClipId != null ||
                  timelineKey.currentState?.selectedAudioClipId != null)
              ? splitSelectedClipAtPlayhead
              : null,
          onQuantizeClip:
              (midiPlaybackManager?.selectedClipId != null ||
                  timelineKey.currentState?.selectedAudioClipId != null)
              ? quantizeSelectedClip
              : null,
          onJoinClips:
              (timelineKey.currentState?.selectedMidiClipIds.length ?? 0) >= 2
              ? joinSelectedClips
              : null,
          hasSelectedMidiClip: midiPlaybackManager?.selectedClipId != null,
          hasSelectedAudioClip:
              timelineKey.currentState?.selectedAudioClipId != null,
          selectedMidiClipCount:
              timelineKey.currentState?.selectedMidiClipIds.length ?? 0,
          // View menu state and callbacks
          uiLayout: uiLayout,
          onToggleLibrary: toggleLibraryPanel,
          onToggleMixer: toggleMixer,
          onToggleEditor: toggleEditor,
          onTogglePiano: toggleVirtualPiano,
          onResetPanelLayout: resetPanelLayout,
          onAppSettings: appSettings,
          // Undo/redo callbacks
          onUndo: performUndo,
          onRedo: performRedo,
          onStartTour: _startTour,
        ),
      ),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // ? key (Shift + /) to show keyboard shortcuts
          const SingleActivator(LogicalKeyboardKey.slash, shift: true):
              showKeyboardShortcuts,
          // Cmd+E splits the selected clip at the playhead
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
              splitSelectedClipAtPlayhead,
          // Cmd+D to duplicate clip
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
              duplicateSelectedClip,
          // Cmd+A to select all clips (in timeline view)
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
              selectAllClips,
          // Cmd+J to join selected clips into one
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true):
              joinSelectedClips,
          // Cmd+Shift+T cycles the app theme (Dark ↔ Light)
          const SingleActivator(
            LogicalKeyboardKey.keyT,
            meta: true,
            shift: true,
          ): _cycleAppTheme,
        },
        // Transport keys (Space, L, M) are handled globally via
        // HardwareKeyboard (_handleGlobalTransportKey) so they survive focus
        // drift onto buttons. Q/Delete stay here on Focus.onKeyEvent. Both
        // paths skip text fields so they don't interfere with typing.
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleSingleKeyShortcut(event),
          child: Scaffold(
            key: const ValueKey('daw'),
            backgroundColor: context.colors.dark,
            body: Stack(
              children: [
                Column(
                  children: [
                    // Reserve space for the transport bar (rendered in the
                    // Stack above).
                    const SizedBox(height: kTopBarHeight),

                    // Main content area - 3-column layout
                    Expanded(
                      child: Column(
                        children: [
                          // Top section: Library + Timeline + Mixer
                          Expanded(
                            child: Row(
                              children: [
                                // Left: Library panel (animated width)
                                _buildLibrarySection(),

                                // Center: Timeline area
                                // PERFORMANCE: Playhead notifier is listened to locally inside TimelineView
                                // so playhead updates at 60fps do NOT rebuild the entire timeline
                                _buildTimelineSection(),

                                // Right: Track mixer panel (animated width)
                                _buildMixerSection(),
                              ],
                            ),
                          ),

                          // Editor panel: Piano Roll / Effects / Instrument
                          // Always render - shows collapsed toolbar bar when not visible
                          if (uiLayout.isEditorPanelVisible) ...[
                            // Resizable divider above editor (only when expanded)
                            ResizableDivider(
                              orientation: DividerOrientation.horizontal,
                              isCollapsed: false,
                              onDragStart: () =>
                                  setState(() => _isDraggingEditor = true),
                              onDragEnd: () =>
                                  setState(() => _isDraggingEditor = false),
                              onDrag: (delta) {
                                final windowHeight = MediaQuery.of(
                                  context,
                                ).size.height;
                                final maxHeight =
                                    UILayoutState.getEditorMaxHeight(
                                      windowHeight,
                                    );
                                setState(() {
                                  final newHeight =
                                      uiLayout.editorPanelHeight - delta;
                                  // Snap collapse if dragged below threshold
                                  if (newHeight <
                                      UILayoutState.editorCollapseThreshold) {
                                    uiLayout.collapseEditor();
                                    userSettings.editorVisible = false;
                                  } else {
                                    uiLayout.editorPanelHeight = newHeight
                                        .clamp(
                                          UILayoutState.editorMinHeight,
                                          maxHeight,
                                        );
                                    userSettings.editorHeight =
                                        uiLayout.editorPanelHeight;
                                  }
                                });
                              },
                              onDoubleClick: () {
                                setState(() {
                                  uiLayout.collapseEditor();
                                  userSettings.editorVisible = false;
                                });
                              },
                            ),
                          ],

                          // Editor panel content (full when visible, collapsed bar when hidden)
                          AnimatedContainer(
                            duration: _isDraggingEditor
                                ? Duration.zero
                                : AnimationConstants.panelDuration,
                            curve: Curves.easeInOut,
                            height: uiLayout.isEditorPanelVisible
                                ? uiLayout.editorPanelHeight
                                : 40,
                            clipBehavior: Clip.hardEdge,
                            decoration: const BoxDecoration(),
                            child: EditorPanel(
                              audioEngine: audioEngine,
                              virtualPianoEnabled:
                                  uiLayout.isVirtualPianoEnabled,
                              trackContext: EditorPanelContext(
                                selectedTrackId: selectedTrackId,
                                selectedTrackName: getSelectedTrackName(),
                                selectedTrackType: getSelectedTrackType(),
                                currentInstrumentData: selectedTrackId != null
                                    ? trackInstruments[selectedTrackId]
                                    : null,
                                floatedPluginEffectIds: floatedPluginEffectIds,
                              ),
                              callbacks: EditorPanelCallbacks(
                                onVirtualPianoClose: toggleVirtualPiano,
                                onVirtualPianoToggle: toggleVirtualPiano,
                                onClosePanel: () {
                                  setState(() {
                                    uiLayout.isEditorPanelVisible = false;
                                  });
                                },
                                onExpandPanel: () {
                                  setState(() {
                                    uiLayout.isEditorPanelVisible = true;
                                  });
                                },
                                onToolModeChanged: (mode) =>
                                    setState(() => currentToolMode = mode),
                                // Mirror the editor chain fader into the mixer
                                // strip's TrackData immediately — the strip
                                // reads track.volumeDb, which otherwise only
                                // catches up on the mixer's slow track refresh.
                                onTrackVolumeChanged: (db) {
                                  final tracks =
                                      mixerKey.currentState?.tracks ?? [];
                                  for (final t in tracks) {
                                    if (t.id == selectedTrackId) {
                                      t.volumeDb = db;
                                      break;
                                    }
                                  }
                                  setState(() {});
                                },
                              ),
                              vst3Callbacks: Vst3EditorCallbacks(
                                onVst3ParameterChanged:
                                    onVst3ParameterChanged, // M10
                                onVst3PluginRemoved: removeVst3Plugin, // M10
                                onFloatPlugin: onFloatPlugin,
                                onEmbedPlugin: onEmbedPlugin,
                                onVst3InstrumentDropped: (plugin) {
                                  if (selectedTrackId != null) {
                                    _onVst3InstrumentDropped(
                                      selectedTrackId!,
                                      plugin,
                                    );
                                  }
                                },
                              ),
                              currentEditingClip:
                                  midiPlaybackManager?.currentEditingClip,
                              onMidiClipUpdated: _onMidiClipUpdated,
                              undoManager: undoRedoManager,
                              playheadNotifier:
                                  playbackController.playheadNotifier,
                              isPlaying: isPlaying,
                              onSeek: playbackController.seek,
                              onInstrumentParameterChanged:
                                  onInstrumentParameterChanged,
                              currentEditingAudioClip: selectedAudioClip,
                              onAudioClipUpdated: _onAudioClipUpdated,
                              currentTrackPlugins:
                                  selectedTrackId !=
                                      null // M10
                                  ? _getTrackVst3Plugins(selectedTrackId!)
                                  : null,
                              availableVst3Plugins:
                                  vst3PluginManager?.availablePlugins ??
                                  const [],
                              onInstrumentDropped: (instrument) {
                                if (selectedTrackId != null) {
                                  onInstrumentDropped(
                                    selectedTrackId!,
                                    instrument,
                                  );
                                }
                              },
                              onBuiltInEffectDropped: (effectType) {
                                if (selectedTrackId != null) {
                                  _addBuiltInEffectToTrack(
                                    selectedTrackId!,
                                    effectType,
                                  );
                                }
                              },
                              onVst3EffectDropped: (plugin) {
                                if (selectedTrackId != null) {
                                  onVst3PluginDropped(selectedTrackId!, plugin);
                                }
                              },
                              isCollapsed: !uiLayout.isEditorPanelVisible,
                              toolMode: currentToolMode,
                              beatsPerBar:
                                  projectMetadata.timeSignatureNumerator,
                              beatUnit:
                                  projectMetadata.timeSignatureDenominator,
                              projectTempo: projectMetadata.bpm,
                              onProjectTempoChanged: _onTempoChanged,
                              isRecording: isRecording,
                              trackColor: selectedTrackId != null
                                  ? getTrackColor(
                                      selectedTrackId!,
                                      getSelectedTrackType() ?? '',
                                    )
                                  : null,
                              onCreateSamplerFromClip: (clipPath) {
                                // Extract filename for track name
                                final name = clipPath
                                    .split('/')
                                    .last
                                    .split('.')
                                    .first;
                                createSamplerTrackWithSample(clipPath, name);
                              },
                            ),
                          ),

                          // Virtual Piano - independent panel, always below editor
                          if (uiLayout.isVirtualPianoEnabled)
                            VirtualPiano(
                              audioEngine: audioEngine,
                              isEnabled: uiLayout.isVirtualPianoEnabled,
                              onClose: toggleVirtualPiano,
                              targetTrackId: _midiInputTrackId,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Transport bar: rendered in Stack (after Column) so its shadow
                // paints on top. On macOS it is the top chrome (native title
                // hidden): it insets past the traffic lights itself.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTransportBar(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
