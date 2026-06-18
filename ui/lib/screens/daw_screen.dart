import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:async';
// Conditional import for platform-specific code
// ignore: unnecessary_import
import 'daw_screen_io.dart'
    if (dart.library.js_interop) 'daw_screen_io_web.dart';
import '../audio_engine.dart';
import '../theme/animation_constants.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import '../widgets/transport_bar.dart';
import '../widgets/transport_bar/title_strip.dart';
import '../widgets/dev_tools/palette_editor.dart';
import '../widgets/dev_tools/ui_labs_switcher.dart';
import '../widgets/dev_tools/editor_button_switcher.dart';
import '../widgets/dev_tools/playhead_lab.dart';
import '../widgets/canvas_bg_variant.dart';
import '../widgets/editor_button_variant.dart';
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
import '../widgets/keyboard_shortcuts_overlay.dart';
import '../widgets/tour/tour_step.dart';
import '../widgets/tour/tour_controller.dart';
import '../widgets/tour/tour_overlay.dart';
import '../models/midi_note_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../models/clip_data.dart';
import '../models/library_item.dart';
import '../models/track_data.dart';
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
import '../services/plugin_preferences_service.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/app_settings_dialog.dart';
import '../widgets/project_settings_dialog.dart';
import '../widgets/export_dialog.dart';
import '../services/version_manager.dart';
import '../services/midi_file_service.dart';
import '../widgets/start_screen/start_screen_modal.dart';
import '../state/ui_layout_state.dart';
import '../services/window_title_service.dart';
import 'daw/daw_menu_bar.dart';
import 'daw/mixins/daw_mixins.dart';
import '../utils/csv_field.dart';
import '../utils/logger.dart';

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

  // Palette editor (debug only)
  bool _showPaletteEditor = false;

  void _togglePaletteEditor() {
    assert(() {
      setState(() => _showPaletteEditor = !_showPaletteEditor);
      return true;
    }());
  }

  // Cmd+Shift+T cycles Dark ↔ Light (the selectable themes only), persisted
  // exactly like the Settings picker so a relaunch keeps the choice.
  void _cycleAppTheme() {
    final themeProvider = context.themeProvider;
    themeProvider.cycleTheme();
    UserSettings().theme = themeProvider.themeKey;
  }

  // UI Labs top-bar switcher (debug only) + the live A/B selections it drives.
  bool _showUiLabsSwitcher = false;
  TopBarVariant _topBarVariant = TopBarVariant.inline;

  void _toggleUiLabsSwitcher() {
    assert(() {
      setState(() => _showUiLabsSwitcher = !_showUiLabsSwitcher);
      return true;
    }());
  }

  // Playhead Lab (debug only) — A/B the grabber's border + vertical position.
  bool _showPlayheadLab = false;

  void _togglePlayheadLab() {
    assert(() {
      setState(() => _showPlayheadLab = !_showPlayheadLab);
      return true;
    }());
  }

  // UI Labs editor-button switcher (debug only) + the live A/B/C it drives.
  bool _showEditorButtonSwitcher = false;
  EditorButtonVariant _editorButtonVariant = EditorButtonVariant.outline;

  void _toggleEditorButtonSwitcher() {
    assert(() {
      setState(() => _showEditorButtonSwitcher = !_showEditorButtonSwitcher);
      return true;
    }());
  }

  // Arrangement-canvas background lift. Chosen default = noticeableGrey
  // (#1C1D21) — Tyr picked it in the v0.5 polish pass; may revisit later, so
  // the dev Cmd+Shift+B cycle is left in place to A/B the options live.
  CanvasBgVariant _canvasBgVariant = CanvasBgVariant.noticeableGrey;

  void _cycleCanvasBg() {
    assert(() {
      setState(() => _canvasBgVariant = _canvasBgVariant.next);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Canvas background: ${_canvasBgVariant.labLabel}'),
            duration: const Duration(milliseconds: 1100),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return true;
    }());
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
          // Restore the persisted top-bar variant (dev A/B choice).
          _topBarVariant = topBarVariantFromName(userSettings.topBarVariant);
          // Restore the persisted editor-button variant (dev A/B/C choice).
          _editorButtonVariant = editorButtonVariantFromName(
            userSettings.editorButtonVariant,
          );
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalTransportKey);

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
    _stopPlayback();

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
        final bufferPreset = _bufferSizeToPreset(userSettings.bufferSize);
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

      if (mounted) {
        setState(() {
          isAudioGraphInitialized = true;
          masterTimelineVisible = audioEngine!.getMasterTimelineVisible();
        });
        playbackController.setStatusMessage(
          'Ready to record or load audio files',
        );
      }

      // Surface output-stream death (device unplugged mid-playback — C99).
      // The controller has already stopped the transport.
      playbackController.onStreamError = (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Audio device lost — playback stopped. '
              'Pick an output device in Settings.',
            ),
          ),
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
      recordingController.getFirstArmedMidiTrackId = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        for (final t in tracks) {
          if (t.type == 'midi' && t.armed) return t.id;
        }
        return selectedTrackId ?? 0;
      };
      recordingController.getRecordingClipName = (trackId) =>
          generateClipName(trackId);
      recordingController.hasArmedAudioTracks = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        return tracks.any((t) => t.type == 'audio' && t.armed);
      };

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
        _scanVst3Plugins();
      }

      // Load MIDI devices
      _loadMidiDevices();

      // Initialize auto-save service
      autoSaveService.initialize(
        projectManager: projectManager!,
        getUILayout: getCurrentUILayout,
      );
      autoSaveService.start();

      // Check for crash recovery
      _checkForCrashRecovery();
    } catch (e, _) {
      Log.e('Audio engine initialization failed: $e');
      if (mounted) {
        setState(() => engineInitFailed = true);
        statusMessage = 'Failed to initialize: $e';
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

  void _play() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewNotifier.value.isNotEmpty) {
      automationPreviewNotifier.value = {};
    }
    playbackController.play(loadedClipId: loadedClipId);
  }

  /// Play with loop check - used by transport bar play button
  void _playWithLoopCheck() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewNotifier.value.isNotEmpty) {
      automationPreviewNotifier.value = {};
    }
    if (uiLayout.loopPlaybackEnabled) {
      _playLoopRegion();
    } else {
      _play();
    }
  }

  void _pause() {
    playbackController.pause();
  }

  void _stopPlayback() {
    Log.d('🛑 [DAW] _stopPlayback() called');
    Log.d('🛑 [DAW]   isPlaying=${playbackController.isPlaying}');
    Log.d('🛑 [DAW]   isRecording=${recordingController.isRecording}');
    Log.d(
      '🛑 [DAW]   playheadPosition=${playbackController.playheadPosition.toStringAsFixed(3)}s',
    );
    // TODO: remove after diagnosing unexpected _stopPlayback() calls
    Log.d('🛑 [DAW]   caller:\n${StackTrace.current}');
    stopPlayback(); // Use mixin method which handles idle vs playing state
    // Reset mixer meters when playback stops
    mixerKey.currentState?.resetMeters();
  }

  /// Check if a text input field currently has focus.
  /// Used to suppress single-key shortcuts when typing in text fields.
  bool _isTextFieldFocused() {
    final focusedWidget = FocusManager.instance.primaryFocus;
    if (focusedWidget == null) return false;
    final context = focusedWidget.context;
    if (context == null) return false;
    // Check if any ancestor is an EditableText (text input widget)
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// App-level handler for transport/loop single-key shortcuts (Space, L, M,
  /// I, O). Registered on [HardwareKeyboard] in initState so it runs *before*
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
    if (_isTextFieldFocused()) return false;

    // A held command modifier means this belongs to a combo shortcut
    // (e.g. Cmd+Shift+L) — leave it for CallbackShortcuts.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _togglePlayPause();
        return true;
      case LogicalKeyboardKey.keyL:
        uiLayout.toggleLoopPlayback();
        return true;
      case LogicalKeyboardKey.keyM:
        _toggleMetronome();
        return true;
      case LogicalKeyboardKey.keyI:
        uiLayout.togglePunchIn();
        return true;
      case LogicalKeyboardKey.keyO:
        uiLayout.togglePunchOut();
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
    if (_isTextFieldFocused()) return KeyEventResult.ignored;

    // These are bare single-key shortcuts (L = loop, M = metronome, …). When a
    // command modifier is held the keystroke belongs to a combo shortcut
    // (e.g. Cmd+Shift+L opens UI Labs) — bail so it reaches CallbackShortcuts
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
        _quantizeSelectedClip();
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

  /// Context-aware play/pause toggle (Space bar)
  /// - When loop is enabled: plays the loop region (cycling)
  /// - Otherwise: plays full arrangement
  void _togglePlayPause() {
    if (isPlaying) {
      _pause();
    } else {
      _playWithLoopCheck();
    }
  }

  /// Play the loop region, cycling forever until stopped
  void _playLoopRegion() {
    // Get loop bounds from UI layout state
    final loopStart = uiLayout.loopStartBeats;
    final loopEnd = uiLayout.loopEndBeats;

    // Play with loop cycling enabled
    playbackController.playLoop(
      loadedClipId: loadedClipId,
      loopStartBeats: loopStart,
      loopEndBeats: loopEnd,
      tempo: tempo,
    );
  }

  // M2: Recording methods - handled by DAWRecordingMixin
  // (toggleRecording, startRecording, stopRecording, handleRecordingComplete)

  void _toggleMetronome() {
    recordingController.toggleMetronome();
    final newState = recordingController.isMetronomeEnabled;
    playbackController.setStatusMessage(
      newState ? 'Metronome enabled' : 'Metronome disabled',
    );
  }

  void _setCountInBars(int bars) {
    userSettings.countInBars = bars;
    audioEngine?.setCountInBars(bars);

    final message = bars == 0
        ? 'Count-in disabled'
        : bars == 1
        ? 'Count-in: 1 bar'
        : 'Count-in: 2 bars';
    playbackController.setStatusMessage(message);
  }

  /// Convert buffer size in samples to preset index
  /// 64=0 (Lowest), 128=1 (Low), 256=2 (Balanced), 512=3 (Safe), 1024=4 (HighStability)
  int _bufferSizeToPreset(int bufferSize) {
    switch (bufferSize) {
      case 64:
        return 0;
      case 128:
        return 1;
      case 256:
        return 2;
      case 512:
        return 3;
      case 1024:
        return 4;
      default:
        return 2; // Default to Balanced (256)
    }
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
    }
    syncAllVolumeAutomationToEngine();

    // Keep the metadata BPM in step (the project settings dialog seeds
    // its BPM field from projectMetadata) — including on undo/redo.
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

  /// Apply a track icon override (null key clears it → auto icon).
  void _applyTrackIcon(int trackId, String? iconKey) {
    // TrackController notifies its listeners; no setState needed (mirrors
    // _applyTrackColor — wrapping in setState rebuilt the whole DAW screen).
    if (iconKey == null) {
      trackController.clearTrackIcon(trackId);
    } else {
      trackController.setTrackIcon(trackId, iconKey);
    }
  }

  Future<void> _onTrackIconChanged(int trackId, String iconKey) async {
    final oldIcon = trackController.getTrackIcon(trackId);
    if (oldIcon == iconKey) return;
    await undoRedoManager.execute(
      SetTrackIconCommand(
        trackId: trackId,
        newIconKey: iconKey,
        oldIconKey: oldIcon,
        onIconChanged: _applyTrackIcon,
      ),
    );
  }

  // M3: Virtual piano methods
  void _toggleVirtualPiano() {
    final success = recordingController.toggleVirtualPiano();
    if (success) {
      uiLayout.setVirtualPianoEnabled(
        enabled: recordingController.isVirtualPianoEnabled,
      );
      playbackController.setStatusMessage(
        recordingController.isVirtualPianoEnabled
            ? 'Virtual piano enabled - Press keys to play!'
            : 'Virtual piano disabled',
      );
    } else {
      playbackController.setStatusMessage('Virtual piano error');
    }
  }

  // MIDI Device methods - delegate to RecordingController
  void _loadMidiDevices() {
    recordingController.loadMidiDevices();
  }

  // M4: Mixer methods
  void _toggleMixer() {
    final windowWidth = MediaQuery.of(context).size.width;

    // If trying to show mixer, check if there's room
    if (!uiLayout.isMixerVisible) {
      if (!uiLayout.canShowMixer(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      uiLayout.isMixerVisible = !uiLayout.isMixerVisible;
      userSettings.mixerVisible = uiLayout.isMixerVisible;
    });
  }

  // Unified track selection method - handles both timeline and mixer clicks
  // Forwards to DAWTrackMixin.onTrackSelected — the single, correct impl. The
  // mixin version also hides/shows floating plugin windows for the selected
  // track (fixes M-3); the previous divergent private body skipped that, so
  // windows stayed visible across track switches depending on entry point.
  void _onTrackSelected(
    int? trackId, {
    bool isShiftHeld = false,
    bool autoSelectClip = false,
  }) => onTrackSelected(
    trackId,
    isShiftHeld: isShiftHeld,
    autoSelectClip: autoSelectClip,
  );

  /// Get the type of the currently selected track ("MIDI", "Audio", or "Master")
  String? _getSelectedTrackType() {
    if (selectedTrackId == null || audioEngine == null) return null;
    final info = audioEngine!.getTrackInfo(selectedTrackId!);
    if (info.isEmpty) return null;
    final parts = info.split(',');
    if (parts.length >= 3) {
      // Track type is at index 2: "track_id,name,type,..."
      final type = parts[2].toLowerCase();
      if (type == 'midi') return 'MIDI';
      if (type == 'audio') return 'Audio';
      if (type == 'master') return 'Master';
      return type;
    }
    return null;
  }

  /// Get the name of the currently selected track
  String? _getSelectedTrackName() {
    if (selectedTrackId == null || audioEngine == null) return null;
    final info = audioEngine!.getTrackInfo(selectedTrackId!);
    if (info.isEmpty) return null;
    final parts = info.split(',');
    if (parts.length >= 2) {
      // Track name is at index 1: "track_id,name,type,..." —
      // percent-encoded by the engine (C34).
      return decodeCsvField(parts[1]);
    }
    return null;
  }

  /// Handle audio clip selection from timeline
  void _onAudioClipSelected(int? clipId, ClipData? clip) {
    setState(() {
      selectedAudioClip = clip;
      if (clip != null) {
        // Also select the track that contains this clip
        selectedTrackId = clip.trackId;
        uiLayout.isEditorPanelVisible = true;
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

    // Auto-update arrangement loop region to follow content
    _updateArrangementLoopToContent();
  }

  // M9: Instrument selection/swap lives in DAWTrackMixin.onInstrumentSelected
  // (with the sampler-swap and drum-kit branches). A private duplicate here
  // diverged from a stale mixin copy that lacked both branches (the daw_screen
  // mixin trap — see .claude/rules/flutter-ui.md).

  // Forwards to DAWTrackMixin.onTrackDeleted — the single, correct impl. The
  // mixin version also closes this track's floating plugin windows (fixes H-9);
  // the previous divergent private body leaked them (native-window resource leak
  // + dangling editor id).
  void _onTrackDeleted(int trackId) => onTrackDeleted(trackId);

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
        _onTrackSelected(newTrackId);
      },
      onNotice: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );

    await undoRedoManager.execute(command);
  }

  void _onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy track state via controller
    trackController.onTrackDuplicated(sourceTrackId, newTrackId);
  }

  // Instrument drop on an existing track lives in
  // DAWTrackMixin.onInstrumentDropped (forwards to onInstrumentSelected).

  // Default-clip creation lives in DAWTrackMixin.createDefaultMidiClip. A
  // private duplicate here predated the mixin and missed the engine
  // rescheduleClip call, so tracks created via the toolbar/mixer/quick-record
  // paths played silence until their first piano-roll edit (the daw_screen
  // mixin trap — see .claude/rules/flutter-ui.md).

  /// Called when a track is created from the mixer panel - refresh timeline immediately
  void _onTrackCreatedFromMixer(int trackId, String trackType) {
    _onTrackSelected(trackId);
    refreshTrackWidgets();
    // New tracks arm themselves — keep arming exclusive (audio included).
    disarmOtherTracks(trackId);
  }

  /// Called when tracks are reordered via drag-and-drop in the mixer panel
  void _onTrackReordered(int oldIndex, int newIndex) {
    // Update shared track order in TrackController
    trackController.reorderTrack(oldIndex, newIndex);
    // Refresh timeline to match new track order
    refreshTrackWidgets();
  }

  // Instrument drop on the empty area lives in
  // DAWTrackMixin.onInstrumentDroppedOnEmpty (sampler / drum-kit / synth
  // branches, all with autoSelectClip). A private duplicate here had drifted
  // ahead of a stale mixin copy that was missing the drum-kit branch.

  // VST3 Instrument drop handlers
  Future<void> _onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
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

      // Auto-populate track name with plugin name if not user-edited
      if (!trackController.isTrackNameUserEdited(trackId)) {
        audioEngine?.setTrackName(trackId, plugin.name);
      }

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

  Future<void> _onVst3InstrumentDroppedOnEmpty(Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
      // Create a new MIDI track using UndoRedoManager
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'MIDI 1',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

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

      // Auto-populate track name with plugin name (new track, so not user-edited)
      audioEngine?.setTrackName(trackId, plugin.name);

      // Create default 1-bar clip AFTER instrument so clip name = plugin name
      createDefaultMidiClip(trackId);

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

      // Select track and highlight the clip (editor stays on Instrument tab)
      _onTrackSelected(trackId, autoSelectClip: true);

      // Immediately refresh track widgets so the new track appears instantly
      refreshTrackWidgets();

      // Disarm other MIDI tracks (exclusive arm for new track)
      disarmOtherTracks(trackId);
    } catch (e) {
      Log.e('Failed to create VST3 instrument track: $e');
    }
  }

  // Audio file drop handler - creates new audio track with clip
  Future<void> _onAudioFileDroppedOnEmpty(
    String filePath, [
    double startTimeBeats = 0.0,
  ]) async {
    if (audioEngine == null) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

      // 2. Create new audio track
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Audio',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // 3. Load audio file to the newly created track
      final clipId = audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      // 4. Get clip info
      final duration = audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = audioEngine!.getWaveformPeaks(clipId, peakResolution);

      // 5. Convert start position from beats to seconds for audio clips
      final beatsPerSecond = tempo / 60.0;
      final startTimeSeconds = startTimeBeats / beatsPerSecond;

      // Set clip start time in engine if not at position 0
      if (startTimeSeconds > 0) {
        audioEngine!.setClipStartTime(trackId, clipId, startTimeSeconds);
      }

      // 6. Add to timeline view's clip list
      timelineKey.currentState?.addClip(
        ClipData(
          clipId: clipId,
          trackId: trackId,
          filePath: finalPath, // Use the copied path
          startTime: startTimeSeconds,
          duration: duration,
          waveformPeaks: peaks,
        ),
      );

      // 7. Select the newly created clip (opens Audio Editor)
      timelineKey.currentState?.selectAudioClip(clipId);

      // 8. Refresh track widgets
      refreshTrackWidgets();

      // New tracks arm themselves — keep arming exclusive (audio included).
      disarmOtherTracks(trackId);
    } catch (e) {
      Log.e('Failed to add audio file to new track: $e');
    }
  }

  /// Import a MIDI file onto a new track (dropped on empty space)
  Future<void> _onMidiFileDroppedOnEmpty(
    String filePath,
    double startTimeBeats,
  ) async {
    if (audioEngine == null) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      // Create new MIDI track
      final command = CreateTrackCommand(trackType: 'midi', trackName: 'MIDI');
      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) return;

      // Find the max note end to determine clip duration
      double maxEnd = 0;
      for (final note in result.notes) {
        final end = note.startTime + note.duration;
        if (end > maxEnd) maxEnd = end;
      }
      final durationBeats = maxEnd > 0 ? maxEnd : 4.0;

      final clipId = DateTime.now().microsecondsSinceEpoch;
      final clipName =
          result.trackName ?? filePath.split('/').last.split('.').first;

      final clipData = MidiClipData(
        clipId: clipId,
        trackId: trackId,
        startTime: startTimeBeats,
        duration: durationBeats,
        notes: result.notes,
        name: clipName,
      );

      midiPlaybackManager?.addRecordedClip(clipData);
      midiPlaybackManager?.rescheduleClip(clipData, tempo);

      refreshTrackWidgets();
    } catch (e) {
      Log.e('Failed to import MIDI file to new track: $e');
    }
  }

  // Drag-to-create handlers — forward to the mixin impls (DAWLibraryMixin /
  // DAWClipMixin), the single, correct copies. The previous divergent private
  // bodies selected the track *before* the clip-create command ran, so the
  // selectClip(null) inside the track selection raced the command callback
  // that selects the new clip — the dropped clip's selection flickered off
  // then on (bug-hunt #21). The mixin versions await the clip command first.
  Future<void> _onCreateTrackWithClip(
    String trackType,
    double startBeats,
    double durationBeats,
  ) => onCreateTrackWithClip(trackType, startBeats, durationBeats);

  Future<void> _onCreateClipOnTrack(
    int trackId,
    double startBeats,
    double durationBeats,
  ) => onCreateClipOnTrack(trackId, startBeats, durationBeats);

  // Library double-click handlers
  void _handleLibraryItemDoubleClick(LibraryItem item) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && _isMidiTrack(selectedTrack);
    final isEmptyAudio =
        selectedTrack != null && _isEmptyAudioTrack(selectedTrack);

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
            _onAudioFileDroppedOnEmpty(item.filePath);
          }
        } else {
          _showSnackBar('Sample not available [WIP]');
        }
        break;

      case LibraryItemType.audioFile:
        if (item is AudioFileItem) {
          if (isEmptyAudio) {
            // Add clip to selected empty audio track
            _addAudioClipToTrack(selectedTrack, item.filePath);
          } else {
            // Create new audio track with clip
            _onAudioFileDroppedOnEmpty(item.filePath);
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
          _showSnackBar('Select a track first to add effects');
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
            _onMidiFileDroppedOnEmpty(item.filePath, 0.0);
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
    final isMidi = selectedTrack != null && _isMidiTrack(selectedTrack);

    if (plugin.isInstrument) {
      if (isMidi) {
        // Swap/add VST3 instrument on selected MIDI track
        _onVst3InstrumentDropped(selectedTrack, plugin);
      } else {
        // Create new MIDI track with VST3 instrument
        _onVst3InstrumentDroppedOnEmpty(plugin);
      }
    } else {
      // VST3 effect
      if (selectedTrack != null) {
        _onVst3PluginDropped(selectedTrack, plugin);
      } else {
        _showSnackBar('Select a track first to add effects');
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
      _showSnackBar('Cannot open in sampler: no file path');
      return;
    }

    // Create a new Sampler track
    createSamplerTrackWithSample(filePath, item.name);
  }

  // Sampler-track creation, drum-kit creation, and audio→sampler conversion
  // live in the mixins (DAWLibraryMixin.createSamplerTrackWithSample /
  // DAWTrackMixin.createDrumKitTrack / DAWLibraryMixin
  // .convertAudioTrackToSampler). Private duplicates here had drifted ahead
  // of stale mixin copies — the mixin convert path still had the direct-FFI
  // loop whose clips were engine-only/invisible (bug-hunt #20) and a
  // selectTrack without autoSelectClip; the consolidated copies keep the
  // corrected behaviour (the daw_screen mixin trap — see
  // .claude/rules/flutter-ui.md).

  // Helper: Check if track is a MIDI track
  bool _isMidiTrack(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    // Engine returns 'MIDI' (uppercase)
    return parts[2].toLowerCase() == 'midi';
  }

  // Helper: Check if track is an empty Audio track (no clips)
  bool _isEmptyAudioTrack(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    // Engine returns 'Audio' (capitalized)
    final trackType = parts[2].toLowerCase();
    if (trackType != 'audio') return false;

    // Check if any clips are on this track
    final hasClips =
        timelineKey.currentState?.hasClipsOnTrack(trackId) ?? false;
    return !hasClips;
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

  /// Copy audio file to project's Samples folder if setting is enabled
  ///
  /// Returns the path to use (either copied path or original path)
  Future<String> _prepareSamplePath(String originalPath) async {
    // If setting is disabled or no project is open, use original path
    if (!userSettings.copySamplesToProject ||
        projectManager?.currentPath == null) {
      return originalPath;
    }

    try {
      final projectPath = projectManager!.currentPath!;
      final samplesDir = Directory('$projectPath/Samples');

      // Create Samples folder if it doesn't exist
      if (!await samplesDir.exists()) {
        await samplesDir.create(recursive: true);
      }

      // Get the file name from the original path
      final fileName = originalPath.split(Platform.pathSeparator).last;
      final destinationPath = '$projectPath/Samples/$fileName';

      // Check if file already exists in Samples folder
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        // File already exists, use it
        return destinationPath;
      }

      // Copy the file to Samples folder
      final sourceFile = File(originalPath);
      await sourceFile.copy(destinationPath);

      return destinationPath;
    } catch (e) {
      // Fall back to original path if copy fails
      return originalPath;
    }
  }

  // Helper: Add audio clip to existing track
  Future<void> _addAudioClipToTrack(int trackId, String filePath) async {
    if (audioEngine == null) return;

    try {
      // Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

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
      if (effectId >= 0) {
        statusMessage = 'Added $effectType to track';
      }
    } catch (e) {
      Log.e('Failed to add effect to track: $e');
    }
  }

  // Helper: Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _toggleMasterTimelineRow() {
    if (audioEngine == null) return;
    final next = !masterTimelineVisible;
    audioEngine!.setMasterTimelineVisible(visible: next);
    setState(() => masterTimelineVisible = next);
  }

  void _onInstrumentParameterChanged(InstrumentData instrumentData) {
    trackController.setTrackInstrument(instrumentData.trackId, instrumentData);
  }

  // M10: VST3 Plugin methods - delegating to Vst3PluginManager

  Future<void> _scanVst3Plugins({bool forceRescan = false}) async {
    if (vst3PluginManager == null) return;

    statusMessage = forceRescan
        ? 'Rescanning VST3 plugins...'
        : 'Scanning VST3 plugins...';

    final result = await vst3PluginManager!.scanPlugins(
      forceRescan: forceRescan,
    );

    if (mounted) {
      statusMessage = result;
    }
  }

  void _removeVst3Plugin(int effectId) {
    if (vst3PluginManager == null) return;

    final result = vst3PluginManager!.removeFromTrack(effectId);

    statusMessage = result.message;
  }

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
      }
      _deferSetState(() {
        statusMessage = cmd.returnTrackId != null
            ? 'Added ${result.effectName} send to ${track.name}'
            : 'Failed to add ${result.effectName} send';
      });
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
    setState(() {
      statusMessage = 'Added ${result.effectName} to ${track.name}';
    });
  }

  void _onVst3PluginDropped(int trackId, Vst3Plugin plugin) {
    if (vst3PluginManager == null) return;
    vst3PluginManager!.addPluginToTrack(trackId, plugin);
  }

  Map<int, int> _getTrackVst3PluginCounts() {
    return vst3PluginManager?.getTrackPluginCounts() ?? {};
  }

  List<Vst3PluginInstance> _getTrackVst3Plugins(int trackId) {
    return vst3PluginManager?.getTrackPlugins(trackId) ?? [];
  }

  void _onVst3ParameterChanged(int effectId, int paramIndex, double value) {
    vst3PluginManager?.updateParameter(effectId, paramIndex, value);
  }

  void _showVst3PluginEditor(int trackId) {
    if (vst3PluginManager == null) return;

    final effectIds = vst3PluginManager!.getTrackEffectIds(trackId);
    if (effectIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Plugins - Track $trackId'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            itemCount: effectIds.length,
            itemBuilder: (context, index) {
              final effectId = effectIds[index];
              final pluginInfo = vst3PluginManager!.getPluginInfo(effectId);
              final pluginName = pluginInfo?['name'] ?? 'Unknown Plugin';

              return ListTile(
                title: Text(pluginName),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showPluginParameterEditor(effectId, pluginName);
                  },
                  child: const Text('Edit'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPluginParameterEditor(int effectId, String pluginName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$pluginName - Parameters'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Parameter editing',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Drag the sliders to adjust plugin parameters.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '🎛️  Native editor support coming soon! For now, use the parameter sliders.',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            icon: Icon(BI.openInNew, size: 16),
                            label: const Text('Open GUI'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Show a few example parameters
                      ..._buildParameterSliders(effectId),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildParameterSliders(int effectId) {
    final List<Widget> sliders = [];

    for (int i = 0; i < 8; i++) {
      sliders.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Parameter ${i + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: BT.weightMedium,
                    ),
                  ),
                  Text(
                    '0.50',
                    style: TextStyle(
                      fontSize: BT.fontLabel,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: 0.5,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (value) {
                  _onVst3ParameterChanged(effectId, i, value);
                },
              ),
            ],
          ),
        ),
      );
    }

    return sliders;
  }

  // M6: Panel toggle methods
  void _toggleLibraryPanel() {
    final windowWidth = MediaQuery.of(context).size.width;

    // If trying to expand library, check if there's room
    if (uiLayout.isLibraryPanelCollapsed) {
      if (!uiLayout.canShowLibrary(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      uiLayout.isLibraryPanelCollapsed = !uiLayout.isLibraryPanelCollapsed;
      userSettings.libraryCollapsed = uiLayout.isLibraryPanelCollapsed;
    });
  }

  void _toggleEditor() {
    setState(() {
      uiLayout.isEditorPanelVisible = !uiLayout.isEditorPanelVisible;
      userSettings.editorVisible = uiLayout.isEditorPanelVisible;
    });
  }

  void _resetPanelLayout() {
    setState(() {
      // Reset to default panel sizes and visibility
      uiLayout.resetLayout();

      // Save reset states
      userSettings.libraryCollapsed = false;
      userSettings.mixerVisible = true;
      userSettings.editorVisible = true;

      statusMessage = 'Panel layout reset';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Panel layout reset to defaults')),
    );
  }

  void _showKeyboardShortcuts() {
    KeyboardShortcutsOverlay.show(context);
  }

  // M8: MIDI clip methods - delegating to MidiClipController
  void _onMidiClipSelected(int? clipId, MidiClipData? clipData) {
    final trackId = midiClipController.selectClip(clipId, clipData);
    if (clipId != null && clipData != null) {
      // Don't auto-open editor panel - let user control visibility via View menu or double-click
      selectedTrackId = trackId ?? clipData.trackId;
    }
  }

  void _onMidiClipUpdated(MidiClipData updatedClip) {
    midiClipController.updateClip(updatedClip, playheadPosition);

    // Propagate changes to all linked clips (same patternId)
    midiPlaybackManager?.updateLinkedClips(updatedClip, tempo);

    // Auto-update arrangement loop region to follow content
    _updateArrangementLoopToContent();
  }

  /// Auto-update arrangement loop region to follow the longest clip.
  /// Only active when loopAutoFollow is true (disabled when user manually drags loop).
  void _updateArrangementLoopToContent() {
    if (!uiLayout.loopAutoFollow) return;

    double longestEnd = 4.0; // Minimum 1 bar (4 beats)

    // Check all MIDI clips
    final midiClips = midiPlaybackManager?.midiClips ?? [];
    for (final clip in midiClips) {
      final clipEnd = clip.startTime + clip.duration;
      if (clipEnd > longestEnd) longestEnd = clipEnd;
    }

    // Check all audio clips (stored in timeline state)
    final audioClips = timelineKey.currentState?.clips ?? [];
    for (final clip in audioClips) {
      // Audio clips use seconds, convert to beats
      final beatsPerSecond = tempo / 60.0;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;
      if (clipEndBeats > longestEnd) longestEnd = clipEndBeats;
    }

    // Round to next bar (4 beats)
    final newLoopEnd = (longestEnd / 4).ceil() * 4.0;

    // Only update if changed (avoids unnecessary rebuilds)
    if (newLoopEnd != uiLayout.loopEndBeats) {
      uiLayout.setLoopRegion(uiLayout.loopStartBeats, newLoopEnd);
      // Keep playback's cached loop bounds in sync. Without this, extending a
      // clip while loop-cycling grew the *displayed* loop region but playback
      // kept wrapping at the old end. updateLoopBounds self-guards on
      // is-playing/is-cycling, so it's a no-op when stopped.
      playbackController.updateLoopBounds(
        loopStartBeats: uiLayout.loopStartBeats,
        loopEndBeats: newLoopEnd,
      );
    }
  }

  void _duplicateSelectedClip() {
    final clip = midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    onMidiClipCopied(clip, newStartTime);
  }

  void _quantizeSelectedClip() {
    // Default grid size: 1 beat (quarter note)
    const gridSizeBeats = 1.0;
    final beatsPerSecond = tempo / 60.0;
    final gridSizeSeconds = gridSizeBeats / beatsPerSecond;

    // Try MIDI clip first
    if (midiPlaybackManager?.selectedClipId != null) {
      final success = midiClipController.quantizeSelectedClip(gridSizeBeats);
      if (success && mounted) {
        statusMessage = 'Quantized MIDI clip to grid';
        return;
      }
    }

    // Try audio clip
    final audioQuantized =
        timelineKey.currentState?.quantizeSelectedAudioClip(gridSizeSeconds) ??
        false;
    if (audioQuantized && mounted) {
      statusMessage = 'Quantized audio clip to grid';
      return;
    }

    // Neither worked
    if (mounted) {
      statusMessage = 'Cannot quantize: select a clip first';
    }
  }

  /// Select all clips in the timeline view
  void _selectAllClips() {
    timelineKey.currentState?.selectAllClips();
    if (mounted) {
      statusMessage = 'Selected all clips';
    }
  }

  /// Bounce MIDI to Audio - renders MIDI through instrument to audio file
  /// NOTE: This is a placeholder that shows planned feature message.
  /// Full implementation requires Rust-side single-track offline rendering.
  void _bounceMidiToAudio() {
    final selectedClipId = midiPlaybackManager?.selectedClipId;
    final selectedClip = midiPlaybackManager?.currentEditingClip;

    if (selectedClipId == null || selectedClip == null) {
      statusMessage = 'Select a MIDI clip to bounce to audio';
      return;
    }

    // Show dialog explaining this is a planned feature
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bounce MIDI to Audio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected clip: ${selectedClip.name}'),
            const SizedBox(height: 12),
            Text(
              'This feature will render the MIDI clip through its instrument '
              'to create an audio file.\n\n'
              'Coming soon in a future update.',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteMidiClip(int clipId, int trackId) {
    // Find the clip data for undo
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

    final command = DeleteMidiClipFromArrangementCommand(
      clipData: clip!,
      onClipRemoved: (cId, tId) {
        midiClipController.deleteClip(cId, tId);
        if (mounted) setState(() {});
      },
      onClipRestored: (restoredClip) {
        midiPlaybackManager?.addRecordedClip(restoredClip);
        midiClipController.updateClip(restoredClip, playheadPosition);
        midiPlaybackManager?.selectClip(restoredClip.clipId, restoredClip);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
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

  /// Batch delete multiple audio clips (eraser tool - single undo action)
  void _deleteAudioClipsBatch(List<ClipData> clipsToDelete) {
    if (clipsToDelete.isEmpty) return;

    // Build individual delete commands for each clip
    final commands = <Command>[];
    for (final clip in clipsToDelete) {
      commands.add(
        DeleteAudioClipCommand(
          clipData: clip,
          onClipRemoved: (clipId) {
            // Remove from timeline view's clip list
            // (Engine removal is handled by the command's execute method)
            timelineKey.currentState?.removeClip(clipId);
          },
          onClipRestored: (restoredClip) {
            // Restore to timeline view's clip list
            // (Engine restoration is handled by the command's undo method)
            timelineKey.currentState?.addClip(restoredClip);
          },
        ),
      );
    }

    if (commands.isEmpty) return;

    // Wrap in CompositeCommand for single undo action
    final compositeCommand = CompositeCommand(
      commands,
      'Delete ${clipsToDelete.length} audio clip${clipsToDelete.length > 1 ? 's' : ''}',
    );
    undoRedoManager.execute(compositeCommand);
    if (mounted) setState(() {});
  }

  // ========================================================================
  // Undo/Redo methods
  // ========================================================================

  Future<void> _performUndo() async {
    final success = await undoRedoManager.undo();
    if (success && mounted) {
      statusMessage = 'Undo - ${undoRedoManager.redoDescription ?? "Action"}';
      refreshTrackWidgets();
    }
  }

  Future<void> _performRedo() async {
    final success = await undoRedoManager.redo();
    if (success && mounted) {
      statusMessage = 'Redo - ${undoRedoManager.undoDescription ?? "Action"}';
      refreshTrackWidgets();
    }
  }

  // M5: Project file methods

  void _newProject() => newProject();

  Future<void> _openProject() => openProject();

  /// Open a project from a specific path (used by Open Recent)
  Future<void> _openRecentProject(String path) => openRecentProject(path);

  /// Build the Open Recent submenu items
  List<PlatformMenuItem> _buildRecentProjectsMenu() {
    final recent = userSettings.recentProjects;

    if (recent.isEmpty) {
      return [
        const PlatformMenuItem(label: 'No Recent Projects', onSelected: null),
      ];
    }

    return [
      ...recent.map(
        (project) => PlatformMenuItem(
          label: project.name,
          onSelected: () => _openRecentProject(project.path),
        ),
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: 'Clear Recent Projects',
            onSelected: () {
              userSettings.clearRecentProjects();
              setState(() {});
            },
          ),
        ],
      ),
    ];
  }

  /// Apply UI layout from loaded project
  void _applyUILayout(UILayoutData layout) => applyUILayout(layout);

  /// Check for crash recovery backup on startup
  Future<void> _checkForCrashRecovery() async {
    try {
      final backupPath = await autoSaveService.checkForRecovery();
      if (backupPath == null || !mounted) return;

      // Get backup modification time
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) return;

      final stat = await backupDir.stat();
      final backupDate = stat.modified;

      if (!mounted) return;

      // Show recovery dialog
      final shouldRecover = await RecoveryDialog.show(
        context,
        backupPath: backupPath,
        backupDate: backupDate,
      );

      if (shouldRecover == true && mounted) {
        // Load the backup project
        final result = await projectManager?.loadProject(backupPath);
        if (result?.result.success == true) {
          // Clear and restore MIDI clips from engine for UI display. Sync the
          // engine tempo first so beat→time conversion uses the recovered
          // project's BPM, not the stale default (notes would shift off-grid).
          midiPlaybackManager?.clearClipIdMappings();
          recordingController.setTempo(audioEngine!.getTempo());
          midiPlaybackManager?.restoreClipsFromEngine(
            tempo,
            savedMetadata: result?.uiLayout?.midiClips,
          );

          statusMessage = 'Recovered from backup';
          refreshTrackWidgets();

          // Apply UI layout if available
          if (result?.uiLayout != null) {
            _applyUILayout(result!.uiLayout!);
          }
        }
      }

      // Clear the recovery marker regardless of choice
      await autoSaveService.clearRecoveryMarker();
    } catch (e) {
      Log.e('Failed to check for crash recovery: $e');
    }
  }

  void _exportAudio() {
    if (audioEngine == null) return;

    ExportDialog.show(
      context,
      audioEngine: audioEngine!,
      defaultName: projectManager?.currentName ?? 'Untitled',
    );
  }

  Future<void> _saveNewVersion() async {
    if (projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save project first before creating a new version'),
          ),
        );
      }
      return;
    }

    try {
      final currentPath = projectManager!.currentPath!;
      final currentName = projectManager!.currentName;
      final parentDir = Directory(currentPath).parent.path;

      // Find the next version number by scanning for existing versions
      int nextVersion = 2;
      final baseName = currentName.replaceAll(
        RegExp(r'_v\d+$'),
        '',
      ); // Remove existing _vN suffix

      while (true) {
        final versionPath = '$parentDir/${baseName}_v$nextVersion.audio';
        if (!await Directory(versionPath).exists()) {
          break;
        }
        nextVersion++;
      }

      final newVersionName = '${baseName}_v$nextVersion';
      final newVersionPath = '$parentDir/$newVersionName.audio';

      setState(() => isLoading = true);

      // Create new version folder
      final newVersionDir = Directory(newVersionPath);
      await newVersionDir.create(recursive: true);

      // Copy project.json
      final sourceProjectFile = File('$currentPath/project.json');
      if (await sourceProjectFile.exists()) {
        await sourceProjectFile.copy('$newVersionPath/project.json');
      }

      // Copy ui_layout.json
      final sourceLayoutFile = File('$currentPath/ui_layout.json');
      if (await sourceLayoutFile.exists()) {
        await sourceLayoutFile.copy('$newVersionPath/ui_layout.json');
      }

      // Create symlink for Samples folder (shares samples to save space)
      final sourceSamplesDir = Directory('$currentPath/Samples');
      if (await sourceSamplesDir.exists()) {
        // Use Process.run to create symlink since dart:io Link may have issues
        await Process.run('ln', [
          '-s',
          '$currentPath/Samples',
          '$newVersionPath/Samples',
        ]);
      }

      // Update project manager to point to new version
      projectManager!.setProjectName(newVersionName);
      await projectManager!.saveProjectToPath(
        newVersionPath,
        getCurrentUILayout(),
      );

      // Update UI
      setState(() {
        projectMetadata = projectMetadata.copyWith(name: newVersionName);
        isLoading = false;
      });

      // Update window title
      WindowTitleService.setProjectName(newVersionName);

      // Add to recent projects
      await userSettings.addRecentProject(newVersionPath, newVersionName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created new version: $newVersionName')),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create new version: $e')),
        );
      }
    }
  }

  Future<void> _renameProject() async {
    if (projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save project first before renaming')),
        );
      }
      return;
    }

    final currentName = projectManager!.currentName;
    final nameController = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Project'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            hintText: 'Enter new project name',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;

    try {
      final currentPath = projectManager!.currentPath!;

      // Rename the .audio folder on disk
      final currentDir = Directory(currentPath);
      if (await currentDir.exists()) {
        final parentDir = currentDir.parent.path;
        final newPath = '$parentDir/$newName.audio';

        // Check if target already exists
        if (await Directory(newPath).exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'A project named "$newName" already exists in this location',
                ),
              ),
            );
          }
          return;
        }

        // Rename the directory
        await currentDir.rename(newPath);

        // Update project manager state
        projectManager!.setProjectName(newName);

        // Save project to update internal metadata with new name
        await projectManager!.saveProjectToPath(newPath, getCurrentUILayout());

        // Update UI
        setState(() {
          projectMetadata = projectMetadata.copyWith(name: newName);
        });

        // Update window title
        WindowTitleService.setProjectName(newName);

        // Update recent projects: remove old path, add new path
        await userSettings.removeRecentProject(currentPath);
        await userSettings.addRecentProject(newPath, newName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Project renamed to "$newName"')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to rename project: $e')));
      }
    }
  }

  Future<void> _appSettings() async {
    // Open app-wide settings dialog (accessed via logo "O" click)

    // Wait for audio engine if not yet initialized (up to 2 seconds)
    if (audioEngine == null) {
      for (int i = 0; i < 20 && audioEngine == null && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!mounted) return;

    await AppSettingsDialog.show(
      context,
      userSettings,
      audioEngine: audioEngine,
    );
  }

  Future<void> _openProjectSettings() async {
    // Initialize version manager if needed
    final projectPath = projectManager?.currentPath;
    if (projectPath != null) {
      final projectFolder = File(projectPath).parent.path;
      versionManager ??= VersionManager(projectFolder);
      await versionManager!.refresh();
    }

    if (!mounted) return;

    // Open project-specific settings dialog (accessed via clicking song name)
    final updated = await ProjectSettingsDialog.show(
      context,
      metadata: projectMetadata,
    );

    if (updated == null || !mounted) return;

    final nameChanged = updated.name != projectMetadata.name;

    setState(() {
      projectMetadata = updated;
    });

    if (nameChanged) {
      projectManager?.setProjectName(updated.name);
      WindowTitleService.setProjectName(updated.name);
    }
  }

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
        await _appSettings();
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
                _stopPlayback();
              }

              // Clear all tracks from the audio engine
              audioEngine?.clearAllTracks();

              // Clear project state via manager
              projectManager?.closeProject();
              midiPlaybackManager?.clear();
              undoRedoManager.clear();

              // Refresh track widgets to show empty state (clear clips too)
              refreshTrackWidgets(clearClips: true);

              setState(() {
                loadedClipId = null;
                waveformPeaks = [];
                statusMessage = 'No project loaded';
              });

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Project closed')));

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
            onNewProject: _newProject,
            onOpenProject: _openProject,
            onSaveProject: saveProject,
            onSaveProjectAs: saveProjectAs,
            onSaveNewVersion: _saveNewVersion,
            onRenameProject: _renameProject,
            onExportAudio: _exportAudio,
            onAppSettings: _appSettings,
            onProjectSettings: _openProjectSettings,
            onCloseProject: _closeProject,
            onStartScreen: _showStartScreen,
          ),
          transport: TransportCallbacks(
            onPlay: _playWithLoopCheck,
            onPause: _pause,
            onStop: _stopPlayback,
            onRecord: toggleRecording,
            onRecordNewMidiTrack: () => _recordIntoNewTrack('midi'),
            onRecordNewAudioTrack: () => _recordIntoNewTrack('audio'),
            onPauseRecording: pauseRecording,
            onStopRecording: stopRecordingAndReturn,
            onUndo: undoRedoManager.canUndo ? _performUndo : null,
            onRedo: undoRedoManager.canRedo ? _performRedo : null,
            onMetronomeToggle: _toggleMetronome,
            onPianoToggle: _toggleVirtualPiano,
            onLoopPlaybackToggle: uiLayout.toggleLoopPlayback,
            onPunchInToggle: uiLayout.togglePunchIn,
            onPunchOutToggle: uiLayout.togglePunchOut,
            onPositionChanged: (seconds) {
              playbackController.seek(seconds);
            },
          ),
          panels: PanelCallbacks(
            onToggleLibrary: _toggleLibraryPanel,
            onToggleMixer: _toggleMixer,
            onToggleEditor: _toggleEditor,
            onTogglePiano: _toggleVirtualPiano,
            onResetPanelLayout: _resetPanelLayout,
            onHelpPressed: _showKeyboardShortcuts,
            onAddMidiTrack: _addMidiTrackWithClip,
            onAddAudioTrack: _addAudioTrack,
          ),
          dividers: DividerState(
            sidebarWidth: uiLayout.libraryPanelWidth,
            onSidebarDividerDrag: (delta) {
              setState(() {
                uiLayout.resizeRightColumn(delta);
                userSettings.libraryRightColumnWidth =
                    uiLayout.libraryRightColumnWidth;
                userSettings.libraryCollapsed =
                    uiLayout.isLibraryPanelCollapsed;
              });
            },
            onSidebarDividerDoubleClick: () {
              setState(() {
                uiLayout.toggleLibraryPanel();
                userSettings.libraryCollapsed =
                    uiLayout.isLibraryPanelCollapsed;
              });
            },
            onSidebarDividerDragStart: () =>
                setState(() => _isDraggingLibrary = true),
            onSidebarDividerDragEnd: () =>
                setState(() => _isDraggingLibrary = false),
            mixerWidth: uiLayout.mixerPanelWidth,
            onMixerDividerDrag: (delta) {
              final windowWidth = MediaQuery.of(context).size.width;
              final maxWidth = UILayoutState.getMixerMaxWidth(windowWidth);
              setState(() {
                final newWidth = uiLayout.mixerPanelWidth - delta;
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
            onMixerDividerDoubleClick: () {
              setState(() {
                uiLayout.toggleMixer();
                userSettings.mixerVisible = uiLayout.isMixerVisible;
              });
            },
            onMixerDividerDragStart: () =>
                setState(() => _isDraggingMixer = true),
            onMixerDividerDragEnd: () =>
                setState(() => _isDraggingMixer = false),
            leftDividerNotifier: _leftDividerActive,
            rightDividerNotifier: _rightDividerActive,
          ),
          // Remaining individual parameters
          playheadPosition: playheadPos,
          isPlaying: isPlaying,
          canPlay: true, // Always allow transport controls
          isRecording: isRecording,
          isCountingIn: isCountingIn,
          countInBeat: recordingController.countInBeat,
          countInProgress: recordingController.countInProgress,
          hasArmedTracks:
              mixerKey.currentState?.tracks.any((t) => t.armed) ?? false,
          metronomeEnabled: isMetronomeEnabled,
          virtualPianoEnabled: uiLayout.isVirtualPianoEnabled,
          tempo: tempo,
          onTempoChanged: _onTempoChanged,
          onTempoDragStart: _onTempoDragStart,
          onTempoDragEnd: _onTempoDragEnd,
          onCountInChanged: _setCountInBars,
          countInBars: userSettings.countInBars,
          projectName: projectMetadata.name,
          hasTitleStrip: hasMacTitleStrip,
          hasProject: projectManager?.hasProject ?? false,
          libraryVisible: !uiLayout.isLibraryPanelCollapsed,
          mixerVisible: uiLayout.isMixerVisible,
          editorVisible: uiLayout.isEditorPanelVisible,
          pianoVisible: uiLayout.isVirtualPianoEnabled,
          canUndo: undoRedoManager.canUndo,
          canRedo: undoRedoManager.canRedo,
          undoDescription: undoRedoManager.undoDescription,
          redoDescription: undoRedoManager.redoDescription,
          arrangementSnap: uiLayout.arrangementSnap,
          onSnapChanged: (value) => uiLayout.setArrangementSnap(value),
          loopPlaybackEnabled: uiLayout.loopPlaybackEnabled,
          punchInEnabled: uiLayout.punchInEnabled,
          punchOutEnabled: uiLayout.punchOutEnabled,
          beatsPerBar: projectMetadata.timeSignatureNumerator,
          onTimeSignatureChanged: _onTimeSignatureChanged,
          onTimeSignatureDragStart: _onTimeSignatureDragStart,
          onTimeSignatureDragEnd: _onTimeSignatureDragEnd,
          isLoading: isLoading,
          engineFailed: engineInitFailed,
          topBarVariant: _topBarVariant,
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
    _onTrackSelected(trackId, autoSelectClip: true);
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

    _onTrackSelected(trackId);
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
    _onTrackSelected(trackId, autoSelectClip: trackType == 'midi');
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
                        onToggle: _toggleLibraryPanel,
                        availableVst3Plugins:
                            vst3PluginManager?.availablePlugins ?? [],
                        libraryService: libraryService,
                        onItemDoubleClick: _handleLibraryItemDoubleClick,
                        onVst3DoubleClick: _handleVst3DoubleClick,
                        onOpenInSampler: _handleOpenInSampler,
                        leftColumnWidth: uiLayout.libraryLeftColumnWidth,
                        onLeftColumnResize: (delta) {
                          setState(() {
                            uiLayout.resizeLeftColumn(delta);
                            userSettings.libraryLeftColumnWidth =
                                uiLayout.libraryLeftColumnWidth;
                          });
                        },
                        onLeftColumnDragStart: () =>
                            setState(() => _isDraggingLibrary = true),
                        onLeftColumnDragEnd: () =>
                            setState(() => _isDraggingLibrary = false),
                      ),
                    )
                  : LibraryPanel(
                      isCollapsed: false,
                      onToggle: _toggleLibraryPanel,
                      availableVst3Plugins:
                          vst3PluginManager?.availablePlugins ?? [],
                      libraryService: libraryService,
                      onItemDoubleClick: _handleLibraryItemDoubleClick,
                      onVst3DoubleClick: _handleVst3DoubleClick,
                      onOpenInSampler: _handleOpenInSampler,
                      leftColumnWidth: uiLayout.libraryLeftColumnWidth,
                      onLeftColumnResize: (delta) {
                        setState(() {
                          uiLayout.resizeLeftColumn(delta);
                          userSettings.libraryLeftColumnWidth =
                              uiLayout.libraryLeftColumnWidth;
                        });
                      },
                      onLeftColumnDragStart: () =>
                          setState(() => _isDraggingLibrary = true),
                      onLeftColumnDragEnd: () =>
                          setState(() => _isDraggingLibrary = false),
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
          showPinnedReadout: _topBarVariant.pinsReadoutToArrangement,
          canvasBgVariant: _canvasBgVariant,
          selectedMidiTrackId: selectedTrackId,
          selectedMidiClipId: midiPlaybackManager?.selectedClipId,
          currentEditingClip: midiPlaybackManager?.currentEditingClip,
          midiClips: midiPlaybackManager?.midiClips ?? [],
          onMidiTrackSelected: _onTrackSelected,
          getRustClipId: (dartClipId) =>
              midiPlaybackManager?.dartToRustClipIds[dartClipId] ?? dartClipId,
          midiClipCallbacks: MidiClipCallbacks(
            onSelected: _onMidiClipSelected,
            onUpdated: _onMidiClipUpdated,
            onCopied: onMidiClipCopied,
            onDeleted: _deleteMidiClip,
            onBatchDeleted: _deleteMidiClipsBatch,
            onExported: _exportMidiClip,
            onSplit: onMidiClipSplit,
            onJoinSelected: joinSelectedClips,
            buildMidiOverlapCommand: (result) => ResolveMidiOverlapCommand(
              result: result,
              tempo: tempo,
              deleteClip: (cId, tId) => midiClipController.deleteClip(cId, tId),
              updateClipInPlace: (clip) =>
                  midiPlaybackManager?.updateClipInPlace(clip),
              rescheduleClip: (clip, t) =>
                  midiPlaybackManager?.rescheduleClip(clip, t),
              addClip: (clip) => midiPlaybackManager?.addRecordedClip(clip),
            ),
          ),
          audioClipCallbacks: AudioClipCallbacks(
            onSelected: _onAudioClipSelected,
            onCopied: onAudioClipCopied,
            onBatchDeleted: _deleteAudioClipsBatch,
            onJoinSelected: joinSelectedClips,
          ),
          dragDropCallbacks: DragDropCallbacks(
            onInstrumentDropped: onInstrumentDropped,
            onInstrumentDroppedOnEmpty: onInstrumentDroppedOnEmpty,
            onVst3InstrumentDropped: _onVst3InstrumentDropped,
            onVst3InstrumentDroppedOnEmpty: _onVst3InstrumentDroppedOnEmpty,
            onMidiFileDroppedOnEmpty: _onMidiFileDroppedOnEmpty,
            onMidiFileDroppedOnTrack: onMidiFileDroppedOnTrack,
            onAudioFileDroppedOnEmpty: _onAudioFileDroppedOnEmpty,
            onAudioFileDroppedOnTrack: onAudioFileDroppedOnTrack,
            onCreateTrackWithClip: _onCreateTrackWithClip,
            onCreateClipOnTrack: _onCreateClipOnTrack,
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
          punchInEnabled: uiLayout.punchInEnabled,
          punchOutEnabled: uiLayout.punchOutEnabled,
          onLoopRegionChanged: (start, end) {
            // Mark as manual adjustment - disables auto-follow
            uiLayout.setLoopRegion(start, end, manual: true);
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
          masterTimelineVisible: masterTimelineVisible,
          // Automation state
          automationVisible: automationController.visible,
          automationScrollController:
              timelineKey.currentState?.scrollController,
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
                trackVst3PluginCounts: _getTrackVst3PluginCounts(), // M10
                onAudioFileDropped: (path) => _onAudioFileDroppedOnEmpty(path),
                getTrackColor: getTrackColor,
                getTrackIcon: (trackId) =>
                    trackController.getTrackIcon(trackId),
                config: MixerPanelConfig(
                  isEngineReady: isAudioGraphInitialized,
                  panelWidth: uiLayout.mixerPanelWidth,
                  onTogglePanel: _toggleMixer,
                  isRecording:
                      recordingController.isRecording ||
                      recordingController.isCountingIn,
                  trackOrder: trackController.trackOrder,
                  onTrackArmed: rescanMidiForHotPlug,
                ),
                selectionState: TrackSelectionState(
                  selectedTrackId: selectedTrackId,
                  selectedTrackIds: selectedTrackIds,
                  onTrackSelected: _onTrackSelected,
                ),
                trackCallbacks: TrackManagementCallbacks(
                  onDuplicated: _onTrackDuplicated,
                  onDeleted: _onTrackDeleted,
                  onDeleteRequested: _onDeleteTrackRequested,
                  onMidiTrackCreated: createDefaultMidiClip,
                  onTrackCreated: _onTrackCreatedFromMixer,
                  onReordered: _onTrackReordered,
                  onOrderSync: trackController.syncTrackOrder,
                  onDoubleClick: (trackId) {
                    // Select track and open editor
                    _onTrackSelected(trackId);
                    if (!uiLayout.isEditorPanelVisible) {
                      _toggleEditor();
                    }
                  },
                  onNameChanged: (trackId, newName) {
                    // Mark track name as user-edited
                    trackController.markTrackNameUserEdited(
                      trackId,
                      edited: true,
                    );
                  },
                  onColorChanged: _onTrackColorChanged,
                  onIconChanged: _onTrackIconChanged,
                  onConvertToSampler: convertAudioTrackToSampler,
                ),
                instrumentCallbacks: MixerInstrumentCallbacks(
                  onInstrumentSelected: onInstrumentSelected,
                  onInstrumentDropped:
                      onInstrumentDropped, // Swap built-in instrument
                  onVst3InstrumentDropped:
                      _onVst3InstrumentDropped, // Swap VST3 instrument
                  onVst3PluginDropped: _onVst3PluginDropped, // M10
                  onBuiltInEffectDropped: (trackId, effect) =>
                      _addBuiltInEffectToTrack(trackId, effect.effectType),
                  onFxButtonPressed: _showVst3PluginBrowser, // M10
                  onEditPluginsPressed: _showVst3PluginEditor, // M10
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
                  visible: automationController.visible,
                  onToggle: () {
                    setState(() {
                      automationController.toggleVisible();
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

    return PlatformMenuBar(
      menus: buildDawMenus(
        context,
        DawMenuConfig(
          // File menu callbacks
          onNewProject: _newProject,
          onOpenProject: _openProject,
          onSaveProject: saveProject,
          onSaveProjectAs: saveProjectAs,
          onSaveNewVersion: _saveNewVersion,
          onRenameProject: _renameProject,
          onExportAudio: _exportAudio,
          onProjectSettings: _openProjectSettings,
          onCloseProject: _closeProject,
          onStartScreen: _showStartScreen,
          recentProjectsMenu: _buildRecentProjectsMenu(),
          // Edit menu state and callbacks
          undoRedoManager: undoRedoManager,
          onDelete: midiPlaybackManager?.selectedClipId != null
              ? () {
                  final clipId = midiPlaybackManager!.selectedClipId!;
                  final clip = midiPlaybackManager!.currentEditingClip;
                  if (clip != null) {
                    _deleteMidiClip(clipId, clip.trackId);
                  }
                }
              : null,
          onDuplicate: _duplicateSelectedClip,
          onSplitAtMarker:
              (midiPlaybackManager?.selectedClipId != null ||
                  timelineKey.currentState?.selectedAudioClipId != null)
              ? splitSelectedClipAtPlayhead
              : null,
          onQuantizeClip:
              (midiPlaybackManager?.selectedClipId != null ||
                  timelineKey.currentState?.selectedAudioClipId != null)
              ? _quantizeSelectedClip
              : null,
          onJoinClips:
              (timelineKey.currentState?.selectedMidiClipIds.length ?? 0) >= 2
              ? joinSelectedClips
              : null,
          onBounceMidiToAudio: midiPlaybackManager?.selectedClipId != null
              ? _bounceMidiToAudio
              : null,
          hasSelectedMidiClip: midiPlaybackManager?.selectedClipId != null,
          hasSelectedAudioClip:
              timelineKey.currentState?.selectedAudioClipId != null,
          selectedMidiClipCount:
              timelineKey.currentState?.selectedMidiClipIds.length ?? 0,
          // View menu state and callbacks
          uiLayout: uiLayout,
          masterTimelineVisible: masterTimelineVisible,
          onToggleLibrary: _toggleLibraryPanel,
          onToggleMixer: _toggleMixer,
          onToggleEditor: _toggleEditor,
          onTogglePiano: _toggleVirtualPiano,
          onToggleMasterRow: _toggleMasterTimelineRow,
          onResetPanelLayout: _resetPanelLayout,
          onAppSettings: _appSettings,
          // Undo/redo callbacks
          onUndo: _performUndo,
          onRedo: _performRedo,
          onStartTour: _startTour,
        ),
      ),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // ? key (Shift + /) to show keyboard shortcuts
          const SingleActivator(LogicalKeyboardKey.slash, shift: true):
              _showKeyboardShortcuts,
          // Cmd+E to split clip at insert marker (or playhead if no marker)
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
              splitSelectedClipAtPlayhead,
          // Cmd+D to duplicate clip
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
              _duplicateSelectedClip,
          // Cmd+A to select all clips (in timeline view)
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
              _selectAllClips,
          // Cmd+J to join selected clips into one
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true):
              joinSelectedClips,
          // Cmd+B to bounce MIDI to audio
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
              _bounceMidiToAudio,
          // Cmd+Shift+P to toggle palette editor (debug only)
          const SingleActivator(
            LogicalKeyboardKey.keyP,
            meta: true,
            shift: true,
          ): _togglePaletteEditor,
          // Cmd+Shift+L to toggle the UI Labs top-bar switcher (debug only)
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            meta: true,
            shift: true,
          ): _toggleUiLabsSwitcher,
          // Cmd+Shift+E to toggle the editor-button A/B/C switcher (debug only)
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          ): _toggleEditorButtonSwitcher,
          // Cmd+Shift+B cycles the arrangement-canvas background (debug only)
          const SingleActivator(
            LogicalKeyboardKey.keyB,
            meta: true,
            shift: true,
          ): _cycleCanvasBg,
          // Cmd+Shift+H toggles the Playhead Lab (debug only)
          const SingleActivator(
            LogicalKeyboardKey.keyH,
            meta: true,
            shift: true,
          ): _togglePlayheadLab,
          // Cmd+Shift+T cycles the app theme (Dark ↔ Light)
          const SingleActivator(
            LogicalKeyboardKey.keyT,
            meta: true,
            shift: true,
          ): _cycleAppTheme,
        },
        // Transport keys (Space, L, M, I, O) are handled globally via
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
                    // Reserve space for the title strip + transport bar (both
                    // rendered in the Stack above). Height tracks the active
                    // top-bar variant plus the macOS title strip (0 elsewhere).
                    SizedBox(
                      height:
                          (hasMacTitleStrip ? kMacTitleStripHeight : 0.0) +
                          _topBarVariant.barHeight,
                    ),

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
                                selectedTrackName: _getSelectedTrackName(),
                                selectedTrackType: _getSelectedTrackType(),
                                currentInstrumentData: selectedTrackId != null
                                    ? trackInstruments[selectedTrackId]
                                    : null,
                                floatedPluginEffectIds: floatedPluginEffectIds,
                              ),
                              callbacks: EditorPanelCallbacks(
                                onVirtualPianoClose: _toggleVirtualPiano,
                                onVirtualPianoToggle: _toggleVirtualPiano,
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
                                    _onVst3ParameterChanged, // M10
                                onVst3PluginRemoved: _removeVst3Plugin, // M10
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
                                  _onInstrumentParameterChanged,
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
                                  _onVst3PluginDropped(
                                    selectedTrackId!,
                                    plugin,
                                  );
                                }
                              },
                              isCollapsed: !uiLayout.isEditorPanelVisible,
                              toolMode: currentToolMode,
                              editorButtonVariant: _editorButtonVariant,
                              beatsPerBar:
                                  projectMetadata.timeSignatureNumerator,
                              beatUnit:
                                  projectMetadata.timeSignatureDenominator,
                              onTimeSignatureChanged: _onTimeSignatureChanged,
                              onTimeSignatureDragStart:
                                  _onTimeSignatureDragStart,
                              onTimeSignatureDragEnd: _onTimeSignatureDragEnd,
                              projectTempo: projectMetadata.bpm,
                              onProjectTempoChanged: _onTempoChanged,
                              isRecording: isRecording,
                              trackColor: selectedTrackId != null
                                  ? getTrackColor(
                                      selectedTrackId!,
                                      _getSelectedTrackName() ?? '',
                                      _getSelectedTrackType() ?? '',
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
                              onClose: _toggleVirtualPiano,
                              selectedTrackId: selectedTrackId,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Transport bar: rendered in Stack (after Column) so its shadow
                // paints on top. Offset below the title strip on macOS.
                Positioned(
                  top: hasMacTitleStrip ? kMacTitleStripHeight : 0,
                  left: 0,
                  right: 0,
                  child: _buildTransportBar(),
                ),
                // macOS title strip: full-width band above the transport bar,
                // hosting the traffic lights + window-centred project title.
                // Painted AFTER the bar so its solid fill masks the bar's upward
                // shadow bleed — strip + bar read as one seamless chrome.
                if (hasMacTitleStrip)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: MacTitleStrip(projectName: projectMetadata.name),
                  ),
                if (_showPaletteEditor)
                  PaletteEditor(onClose: _togglePaletteEditor),
                if (_showUiLabsSwitcher)
                  UiLabsSwitcher(
                    activeVariant: _topBarVariant,
                    onVariantSelected: (v) {
                      setState(() => _topBarVariant = v);
                      userSettings.topBarVariant = v.token;
                    },
                    onClose: _toggleUiLabsSwitcher,
                  ),
                if (_showPlayheadLab)
                  PlayheadLabSwitcher(onClose: _togglePlayheadLab),
                if (_showEditorButtonSwitcher)
                  EditorButtonSwitcher(
                    activeVariant: _editorButtonVariant,
                    onVariantSelected: (v) {
                      setState(() => _editorButtonVariant = v);
                      userSettings.editorButtonVariant = v.token;
                    },
                    onClose: _toggleEditorButtonSwitcher,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
