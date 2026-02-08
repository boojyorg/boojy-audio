import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
// Conditional import for platform-specific code
import 'daw_screen_io.dart' if (dart.library.js_interop) 'daw_screen_io_web.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';
import '../widgets/transport_bar.dart';
import '../widgets/timeline_view.dart';
import '../widgets/track_mixer_panel.dart';
import '../widgets/library_panel.dart';
import '../widgets/editor_panel.dart';
import '../widgets/virtual_piano.dart';
import '../widgets/resizable_divider.dart';
import '../widgets/instrument_browser.dart';
import '../widgets/vst3_plugin_browser.dart';
import '../widgets/keyboard_shortcuts_overlay.dart';
import '../models/midi_note_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';
import '../models/clip_data.dart';
import '../models/library_item.dart';
import '../services/commands/command.dart';
import '../services/commands/track_commands.dart';
import '../services/commands/project_commands.dart';
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
import '../models/project_version.dart';
import '../models/version_type.dart';
import '../models/project_view_state.dart';
import '../models/midi_event.dart';
import '../models/track_automation_data.dart';
import '../services/version_manager.dart';
import '../services/clip_naming_service.dart';
import '../services/midi_file_service.dart';
import '../widgets/capture_midi_dialog.dart';
import '../widgets/dialogs/latency_settings_dialog.dart';
import '../widgets/dialogs/crash_reporting_dialog.dart';
import '../state/ui_layout_state.dart';
import '../services/window_title_service.dart';
import 'daw/daw_menu_bar.dart';
import 'daw/mixins/daw_mixins.dart';

/// Main DAW screen with timeline, transport controls, and file import
class DAWScreen extends StatefulWidget {
  const DAWScreen({super.key});

  @override
  State<DAWScreen> createState() => _DAWScreenState();
}

class _DAWScreenState extends State<DAWScreen> with DAWScreenStateMixin, DAWPlaybackMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin, DAWClipMixin, DAWVst3Mixin, DAWLibraryMixin, DAWProjectMixin, DAWBuildMixin {
  @override
  void initState() {
    super.initState();

    // Listen for undo/redo state changes to update menu
    undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for controller state changes
    playbackController.addListener(_onControllerChanged);
    recordingController.addListener(_onControllerChanged);
    trackController.addListener(_onControllerChanged);
    midiClipController.addListener(_onControllerChanged);
    uiLayout.addListener(_onControllerChanged);

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
          uiLayout.libraryRightColumnWidth = userSettings.libraryRightColumnWidth;
          uiLayout.mixerPanelWidth = userSettings.mixerWidth;
          uiLayout.editorPanelHeight = userSettings.editorHeight;
        });

        // Show crash reporting opt-in dialog on first launch
        if (!userSettings.crashReportingAsked && mounted) {
          final optIn = await CrashReportingDialog.show(context);
          userSettings.crashReportingEnabled = optIn;
          userSettings.crashReportingAsked = true;
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

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onUndoRedoChanged() {
    if (mounted) {
      setState(() {
        // Trigger rebuild to update Edit menu state
      });
    }
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
    // Remove undo/redo listener
    undoRedoManager.removeListener(_onUndoRedoChanged);

    // Remove controller listeners
    playbackController.removeListener(_onControllerChanged);
    recordingController.removeListener(_onControllerChanged);
    trackController.removeListener(_onControllerChanged);
    midiClipController.removeListener(_onControllerChanged); // Was missing!
    uiLayout.removeListener(_onControllerChanged);

    // Clear callbacks to prevent memory leaks
    recordingController.onRecordingComplete = null;
    playbackController.onAutoStop = null;

    // Dispose controllers (ChangeNotifiers must be disposed)
    playbackController.dispose();
    recordingController.dispose();
    trackController.dispose();
    midiClipController.dispose();
    automationController.dispose();
    libraryPreviewService?.dispose();
    uiLayout.dispose();

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
        audioEngine!.setCountInBars(userSettings.countInBars); // Use saved setting
        audioEngine!.setTempo(120.0);   // Default: 120 BPM
        audioEngine!.setMetronomeEnabled(enabled: true); // Default: enabled
      } catch (e) {
        debugPrint('Recording settings initialization failed: $e');
      }

      // Initialize buffer size from user settings
      try {
        final bufferPreset = _bufferSizeToPreset(userSettings.bufferSize);
        audioEngine!.setBufferSize(bufferPreset);
      } catch (e) {
        debugPrint('Buffer size setting failed: $e');
      }

      // Initialize output device from user settings
      if (userSettings.preferredOutputDevice != null) {
        try {
          audioEngine!.setAudioOutputDevice(userSettings.preferredOutputDevice!);
        } catch (e) {
          debugPrint('Output device setting failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          isAudioGraphInitialized = true;
        });
        playbackController.setStatusMessage('Ready to record or load audio files');
      }

      // Initialize undo/redo manager with engine
      undoRedoManager.initialize(audioEngine!);

      // Initialize controllers with audio engine
      playbackController.initialize(audioEngine!);
      recordingController.initialize(audioEngine!);
      recordingController.setLiveRecordingNotifier(liveRecordingNotifier);
      recordingController.getFirstArmedMidiTrackId = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        for (final t in tracks) {
          if (t.type == 'midi' && t.armed) return t.id;
        }
        return selectedTrackId ?? 0;
      };
      recordingController.getRecordingClipName = (trackId) => generateClipName(trackId);
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
        getUILayout: _getCurrentUILayout,
      );
      autoSaveService.start();

      // Check for crash recovery
      _checkForCrashRecovery();
    } catch (e, _) {
      if (mounted) {
        setState(() {
          statusMessage = 'Failed to initialize: $e';
        });
      }
    }
  }

  void _play() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewValues.isNotEmpty) {
      setState(() {
        automationPreviewValues.clear();
      });
    }
    playbackController.play(loadedClipId: loadedClipId);
  }

  /// Play with loop check - used by transport bar play button
  void _playWithLoopCheck() {
    // Clear automation preview values so display shows actual playback values
    if (automationPreviewValues.isNotEmpty) {
      setState(() {
        automationPreviewValues.clear();
      });
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
    debugPrint('🛑 [DAW] _stopPlayback() called');
    debugPrint('🛑 [DAW]   isPlaying=${playbackController.isPlaying}');
    debugPrint('🛑 [DAW]   isRecording=${recordingController.isRecording}');
    debugPrint('🛑 [DAW]   playheadPosition=${playbackController.playheadPosition.toStringAsFixed(3)}s');
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

  /// Handle single-key shortcuts that should be suppressed when text field is focused.
  /// Returns true if the key was handled, false to let it propagate to text fields.
  KeyEventResult _handleSingleKeyShortcut(KeyEvent event) {
    // Only handle KeyDownEvent, not KeyUpEvent or KeyRepeatEvent
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // If a text field is focused, don't intercept any single-key shortcuts
    if (_isTextFieldFocused()) return KeyEventResult.ignored;

    // Handle single-key shortcuts
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _togglePlayPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyQ:
        _quantizeSelectedClip();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        uiLayout.toggleLoopPlayback();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMetronome();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyI:
        uiLayout.togglePunchIn();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyO:
        uiLayout.togglePunchOut();
        return KeyEventResult.handled;
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
    playbackController.setStatusMessage(newState ? 'Metronome enabled' : 'Metronome disabled');
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
      case 64: return 0;
      case 128: return 1;
      case 256: return 2;
      case 512: return 3;
      case 1024: return 4;
      default: return 2; // Default to Balanced (256)
    }
  }

  Future<void> _onTempoChanged(double bpm) async {
    final oldBpm = recordingController.tempo;
    if (oldBpm == bpm) return;

    final command = SetTempoCommand(
      newBpm: bpm,
      oldBpm: oldBpm,
      onTempoChanged: (newBpm) {
        // Get the current (old) tempo before we change it
        final currentTempo = recordingController.tempo;

        recordingController.setTempo(newBpm);
        midiClipController.setTempo(newBpm);
        midiCaptureBuffer.updateBpm(newBpm);
        midiPlaybackManager?.rescheduleAllClips(newBpm);

        // Adjust audio clip positions to maintain their beat position
        // This prevents audio clips from visually shifting when tempo changes
        timelineKey.currentState?.adjustAudioClipPositionsForTempoChange(currentTempo, newBpm);
      },
    );
    await undoRedoManager.execute(command);
  }

  void _onTimeSignatureChanged(int beatsPerBar, int beatUnit) {
    setState(() {
      projectMetadata = projectMetadata.copyWith(
        timeSignatureNumerator: beatsPerBar,
        timeSignatureDenominator: beatUnit,
      );
    });
    // Update engine time signature
    audioEngine?.setTimeSignature(beatsPerBar);
  }

  // M3: Virtual piano methods
  void _toggleVirtualPiano() {
    final success = recordingController.toggleVirtualPiano();
    if (success) {
      uiLayout.setVirtualPianoEnabled(enabled: recordingController.isVirtualPianoEnabled);
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

  void _onMidiDeviceSelected(int deviceIndex) {
    recordingController.selectMidiDevice(deviceIndex);

    // Show feedback
    if (midiDevices.isNotEmpty && deviceIndex >= 0 && deviceIndex < midiDevices.length) {
      final deviceName = midiDevices[deviceIndex]['name'] as String? ?? 'Unknown';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎹 Selected: $deviceName'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _refreshMidiDevices() {
    recordingController.refreshMidiDevices();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎹 MIDI devices refreshed'),
        duration: Duration(seconds: 2),
      ),
    );
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
  void _onTrackSelected(int? trackId, {bool isShiftHeld = false, bool autoSelectClip = false}) {
    if (trackId == null) {
      setState(() {
        selectTrack(null);
        uiLayout.isEditorPanelVisible = false;
      });
      return;
    }

    setState(() {
      selectTrack(trackId, isShiftHeld: isShiftHeld);
      uiLayout.isEditorPanelVisible = true;
    });

    // Try to find an existing clip for this track and select it
    // instead of clearing the clip selection (only for single selection)
    // When autoSelectClip is false (e.g., after instrument drop), don't auto-select clip
    if (!isShiftHeld && autoSelectClip) {
      final clipsForTrack = midiPlaybackManager?.midiClips
          .where((c) => c.trackId == trackId)
          .toList();

      if (clipsForTrack != null && clipsForTrack.isNotEmpty) {
        // Select the first clip for this track
        final clip = clipsForTrack.first;
        midiPlaybackManager?.selectClip(clip.clipId, clip);
      } else {
        // No clips for this track - clear selection
        midiPlaybackManager?.selectClip(null, null);
      }
    } else if (!isShiftHeld && !autoSelectClip) {
      // Clear clip selection when autoSelectClip is false
      midiPlaybackManager?.selectClip(null, null);
    }
  }

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
      // Track name is at index 1: "track_id,name,type,..."
      return parts[1];
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

  // M9: Instrument methods
  void _onInstrumentSelected(int trackId, String instrumentId) {
    // Create default instrument data for the track
    final instrumentData = InstrumentData.defaultSynthesizer(trackId);
    trackController.setTrackInstrument(trackId, instrumentData);
    trackController.selectTrack(trackId);
    uiLayout.isEditorPanelVisible = true;

    // Auto-populate track name if not user-edited
    if (!trackController.isTrackNameUserEdited(trackId)) {
      audioEngine?.setTrackName(trackId, 'Synthesizer');
    }

    // Call audio engine to set instrument
    if (audioEngine != null) {
      audioEngine!.setTrackInstrument(trackId, instrumentId);
    }
  }

  void _onTrackDeleted(int trackId) {
    // Remove all MIDI clips for this track via manager
    midiPlaybackManager?.removeClipsForTrack(trackId);

    // Remove track state from controller
    trackController.onTrackDeleted(trackId);

    // Refresh timeline immediately
    refreshTrackWidgets();
  }

  void _onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy track state via controller
    trackController.onTrackDuplicated(sourceTrackId, newTrackId);
  }

  void _onInstrumentDropped(int trackId, Instrument instrument) {
    // Reuse the same logic as _onInstrumentSelected
    _onInstrumentSelected(trackId, instrument.id);
  }

  /// Create a default 1-bar empty MIDI clip for a new track
  void _createDefaultMidiClip(int trackId) {
    // 1 bar = 4 beats (MIDI clips store duration in beats, not seconds)
    const durationBeats = 4.0;

    final defaultClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: 0.0, // Start at beat 0
      duration: durationBeats,
      name: _generateClipName(trackId),
      notes: [],
    );

    midiPlaybackManager?.addRecordedClip(defaultClip);
  }

  /// Called when a track is created from the mixer panel - refresh timeline immediately
  void _onTrackCreatedFromMixer(int trackId, String trackType) {
    _onTrackSelected(trackId);
    refreshTrackWidgets();
  }

  /// Called when tracks are reordered via drag-and-drop in the mixer panel
  void _onTrackReordered(int oldIndex, int newIndex) {
    // Update shared track order in TrackController
    trackController.reorderTrack(oldIndex, newIndex);
    // Refresh timeline to match new track order
    refreshTrackWidgets();
  }

  Future<void> _onInstrumentDroppedOnEmpty(Instrument instrument) async {
    if (audioEngine == null) return;

    // Handle Sampler instrument — creates MIDI track with sampler instrument
    if (instrument.id == 'sampler') {
      final trackId = audioEngine!.createTrack('midi', 'Sampler');
      if (trackId < 0) return;

      audioEngine!.createSamplerForTrack(trackId);
      createDefaultMidiClip(trackId);

      refreshTrackWidgets();
      selectTrack(trackId);
      return;
    }

    // Create a new MIDI track for Synthesizer (and other instruments)
    final command = CreateTrackCommand(
      trackType: 'midi',
      trackName: 'MIDI',
    );

    await undoRedoManager.execute(command);

    final trackId = command.createdTrackId;
    if (trackId == null || trackId < 0) {
      return;
    }

    // Create default 4-bar empty clip for the new track
    _createDefaultMidiClip(trackId);

    // Assign the instrument to the new track
    _onInstrumentSelected(trackId, instrument.id);

    // Select the newly created track but NOT the clip (so Instrument tab shows)
    _onTrackSelected(trackId, autoSelectClip: false);

    // Immediately refresh track widgets so the new track appears instantly
    refreshTrackWidgets();

    // Disarm other MIDI tracks (exclusive arm for new track)
    disarmOtherMidiTracks(trackId);
  }

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
      trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name if not user-edited
      if (!trackController.isTrackNameUserEdited(trackId)) {
        audioEngine?.setTrackName(trackId, plugin.name);
      }

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || audioEngine == null) return;
        audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });
    } catch (e) {
      debugPrint('Failed to preview VST3 instrument: $e');
    }
  }

  Future<void> _onVst3InstrumentDroppedOnEmpty(Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
      // Create a new MIDI track using UndoRedoManager
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'MIDI',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // Create default 4-bar empty clip for the new track
      _createDefaultMidiClip(trackId);

      // Load the VST3 plugin as a track instrument
      final effectId = audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name (new track, so not user-edited)
      audioEngine?.setTrackName(trackId, plugin.name);

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || audioEngine == null) return;
        audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });

      // Select the newly created track but NOT the clip (so Instrument tab shows)
      _onTrackSelected(trackId, autoSelectClip: false);

      // Immediately refresh track widgets so the new track appears instantly
      refreshTrackWidgets();

      // Disarm other MIDI tracks (exclusive arm for new track)
      disarmOtherMidiTracks(trackId);
    } catch (e) {
      debugPrint('Failed to create VST3 instrument track: $e');
    }
  }

  // Audio file drop handler - creates new audio track with clip
  Future<void> _onAudioFileDroppedOnEmpty(String filePath, [double startTimeBeats = 0.0]) async {
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
      timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: finalPath, // Use the copied path
        startTime: startTimeSeconds,
        duration: duration,
        waveformPeaks: peaks,
      ));

      // 7. Select the newly created clip (opens Audio Editor)
      timelineKey.currentState?.selectAudioClip(clipId);

      // 8. Refresh track widgets
      refreshTrackWidgets();
    } catch (e) {
      debugPrint('Failed to add audio file to new track: $e');
    }
  }

  // Audio file drop handler - adds clip to existing audio track (with undo support)
  Future<void> _onAudioFileDroppedOnTrack(int trackId, String filePath, double startTimeBeats) async {
    if (audioEngine == null) return;

    // Defensive check: only allow audio file drops on audio tracks (not MIDI tracks)
    if (_isMidiTrack(trackId)) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

      // 2. Convert beats to seconds (audio clips use seconds)
      final startTimeSeconds = startTimeBeats * 60.0 / tempo;

      // 3. Extract filename for display
      final fileName = finalPath.split('/').last.split('\\').last;

      // 4. Use AddAudioClipCommand for undo support
      final command = AddAudioClipCommand(
        trackId: trackId,
        filePath: finalPath,
        startTime: startTimeSeconds,
        clipName: fileName,
        onClipAdded: (clipId, duration, peaks) {
          // Add to timeline view's clip list
          timelineKey.currentState?.addClip(ClipData(
            clipId: clipId,
            trackId: trackId,
            filePath: finalPath,
            startTime: startTimeSeconds,
            duration: duration,
            waveformPeaks: peaks,
          ));
          // Select the newly created clip (opens Audio Editor)
          timelineKey.currentState?.selectAudioClip(clipId);
        },
        onClipRemoved: (clipId) {
          // Remove from timeline view (undo)
          timelineKey.currentState?.removeClip(clipId);
        },
      );

      await undoRedoManager.execute(command);

      // 5. Refresh track widgets
      refreshTrackWidgets();
    } catch (e) {
      debugPrint('Failed to add audio file to track: $e');
    }
  }

  /// Import a MIDI file onto an existing MIDI track
  Future<void> _onMidiFileDroppedOnTrack(int trackId, String filePath, double startTimeBeats) async {
    if (audioEngine == null) return;
    if (!_isMidiTrack(trackId)) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      // Find the max note end to determine clip duration
      double maxEnd = 0;
      for (final note in result.notes) {
        final end = note.startTime + note.duration;
        if (end > maxEnd) maxEnd = end;
      }
      final durationBeats = maxEnd > 0 ? maxEnd : 4.0;

      // Generate a unique clip ID
      final clipId = DateTime.now().microsecondsSinceEpoch;
      final clipName = result.trackName ?? filePath.split('/').last.split('.').first;

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

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to import MIDI file to track: $e');
    }
  }

  /// Import a MIDI file onto a new track (dropped on empty space)
  Future<void> _onMidiFileDroppedOnEmpty(String filePath, double startTimeBeats) async {
    if (audioEngine == null) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      // Create new MIDI track
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'MIDI',
      );
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
      final clipName = result.trackName ?? filePath.split('/').last.split('.').first;

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
      debugPrint('Failed to import MIDI file to new track: $e');
    }
  }

  // Drag-to-create handlers
  Future<void> _onCreateTrackWithClip(String trackType, double startBeats, double durationBeats) async {
    if (audioEngine == null) return;

    try {
      // Create new track
      final command = CreateTrackCommand(
        trackType: trackType,
        trackName: trackType == 'midi' ? 'MIDI' : 'Audio',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // For MIDI tracks, create a clip with the specified position and duration
      if (trackType == 'midi') {
        _createMidiClipWithParams(trackId, startBeats, durationBeats);
      }
      // For audio tracks, they start empty (user will drop audio files)

      // Select the newly created track
      _onTrackSelected(trackId);

      // Refresh track widgets
      refreshTrackWidgets();

      // Disarm other MIDI tracks when creating new MIDI track (exclusive arm)
      if (trackType == 'midi') {
        disarmOtherMidiTracks(trackId);
      }
    } catch (e) {
      debugPrint('Failed to create track with clip: $e');
    }
  }

  void _onCreateClipOnTrack(int trackId, double startBeats, double durationBeats) {
    // Create a new MIDI clip on the specified track
    _createMidiClipWithParams(trackId, startBeats, durationBeats);

    // Select the track
    _onTrackSelected(trackId);

  }

  /// Create a MIDI clip with custom start position and duration
  void _createMidiClipWithParams(int trackId, double startBeats, double durationBeats) {
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: startBeats,
      duration: durationBeats,
      loopLength: durationBeats, // Loop length matches arrangement length initially
      name: _generateClipName(trackId),
      notes: [],
    );

    // Use undo/redo for clip creation
    final command = CreateMidiClipCommand(
      clipData: clip,
      onClipCreated: (newClip) {
        midiPlaybackManager?.addRecordedClip(newClip);
        midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId, tId) {
        midiClipController.deleteClip(clipId, tId);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  /// Capture MIDI from the buffer and create a clip
  Future<void> _captureMidi() async {
    if (audioEngine == null) return;

    // Check if we have a selected track
    if (selectedTrackId == null) {
      playbackController.setStatusMessage('Please select a MIDI track first');
      return;
    }

    // Show capture dialog
    final capturedEvents = await CaptureMidiDialog.show(context, midiCaptureBuffer);

    if (capturedEvents == null || capturedEvents.isEmpty) {
      return;
    }

    // Convert captured events to MIDI notes
    final notes = <MidiNoteData>[];
    final Map<int, MidiEvent> activeNotes = {};

    for (final event in capturedEvents) {
      if (event.isNoteOn) {
        // Store note-on event
        activeNotes[event.note] = event;
      } else {
        // Find matching note-on and create MidiNoteData
        final noteOn = activeNotes.remove(event.note);
        if (noteOn != null) {
          final duration = event.beatsFromStart - noteOn.beatsFromStart;
          notes.add(MidiNoteData(
            note: event.note,
            velocity: noteOn.velocity,
            startTime: noteOn.beatsFromStart,
            duration: duration.clamp(0.1, double.infinity), // Min duration of 0.1 beats
          ));
        }
      }
    }

    // Handle any notes that didn't get a note-off (sustained notes)
    for (final noteOn in activeNotes.values) {
      notes.add(MidiNoteData(
        note: noteOn.note,
        velocity: noteOn.velocity,
        startTime: noteOn.beatsFromStart,
        duration: 1.0, // Default 1 beat duration for sustained notes
      ));
    }

    if (notes.isEmpty) {
      playbackController.setStatusMessage('No complete MIDI notes captured');
      return;
    }

    // Calculate clip duration based on last note
    final lastNote = notes.reduce((a, b) =>
      (a.startTime + a.duration) > (b.startTime + b.duration) ? a : b
    );
    final clipDuration = (lastNote.startTime + lastNote.duration).ceilToDouble();

    // Create the clip
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: selectedTrackId!,
      startTime: playheadPosition / 60.0 * tempo, // Current playhead position in beats
      duration: clipDuration,
      loopLength: clipDuration,
      name: _generateClipName(selectedTrackId!),
      notes: notes,
    );

    midiPlaybackManager?.addRecordedClip(clip);
    playbackController.setStatusMessage('Captured ${notes.length} MIDI notes');
  }

  // Library double-click handlers
  void _handleLibraryItemDoubleClick(LibraryItem item) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && _isMidiTrack(selectedTrack);
    final isEmptyAudio = selectedTrack != null && _isEmptyAudioTrack(selectedTrack);

    switch (item.type) {
      case LibraryItemType.instrument:
        // Find the matching Instrument from availableInstruments
        final instrument = _findInstrumentByName(item.name);
        if (instrument != null) {
          if (isMidi) {
            // Swap/add instrument on selected MIDI track
            _onInstrumentSelected(selectedTrack, instrument.id);
          } else {
            // Create new MIDI track with instrument
            _onInstrumentDroppedOnEmpty(instrument);
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
              _onInstrumentSelected(selectedTrack, instrument.id);
              // TODO: Load preset data when presets are implemented
            } else {
              // Create new MIDI track with instrument
              _onInstrumentDroppedOnEmpty(instrument);
              // TODO: Load preset data when presets are implemented
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
            _onMidiFileDroppedOnTrack(selectedTrack, item.filePath, 0.0);
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
    _createSamplerTrackWithSample(filePath, item.name);
  }

  /// Create a new Sampler track and load a sample into it
  void _createSamplerTrackWithSample(String filePath, String sampleName) {
    if (audioEngine == null) return;

    // Generate track name based on sample name
    final trackName = 'Sampler: ${_truncateName(sampleName, 20)}';

    // Create MIDI track with sampler instrument
    final trackId = audioEngine!.createTrack('midi', trackName);
    if (trackId < 0) {
      _showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(trackId);
    if (samplerId < 0) {
      _showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(trackId, filePath, 60);
    if (!success) {
      _showSnackBar('Failed to load sample');
      return;
    }

    // Create default 1-bar MIDI clip
    createDefaultMidiClip(trackId);

    // Refresh track list and select the new track
    refreshTrackWidgets();
    selectTrack(trackId);

    _showSnackBar('Created sampler with "${_truncateName(sampleName, 30)}"');
  }

  /// Convert an Audio track to a Sampler track
  /// Takes the first audio clip on the track and uses it as the sample
  /// Creates MIDI notes at the position/duration of each audio clip
  void _convertAudioTrackToSampler(int trackId) {
    if (audioEngine == null) return;

    // Get audio clips on this track
    final audioClips = timelineKey.currentState?.getAudioClipsOnTrack(trackId);
    if (audioClips == null || audioClips.isEmpty) {
      _showSnackBar('No audio clips on track to convert');
      return;
    }

    // Get the first clip's file path (we'll use this as the sample)
    final firstClip = audioClips.first;
    final samplePath = firstClip.filePath;
    if (samplePath.isEmpty) {
      _showSnackBar('Audio clip has no file path');
      return;
    }

    // Get track name for the new sampler track
    final trackName = _getTrackName(trackId) ?? 'Sampler';
    final samplerTrackName = trackName.startsWith('Sampler:')
        ? trackName
        : 'Sampler: $trackName';

    // Create MIDI track with sampler instrument
    final samplerTrackId = audioEngine!.createTrack('midi', samplerTrackName);
    if (samplerTrackId < 0) {
      _showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(samplerTrackId);
    if (samplerId < 0) {
      _showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(samplerTrackId, samplePath, 60);
    if (!success) {
      _showSnackBar('Failed to load sample');
      return;
    }

    // Create MIDI clips for each audio clip position
    // Each audio clip becomes a MIDI note at the same position
    for (final clip in audioClips) {
      final startTime = clip.startTime;
      final duration = clip.duration;

      // Calculate MIDI note based on transpose (if any)
      // Default root note is 60 (C4), transpose shifts it
      final transpose = clip.editData?.transposeSemitones ?? 0;
      final midiNote = (60 + transpose).clamp(0, 127);

      // Create an empty MIDI clip
      final clipId = audioEngine!.createMidiClip();
      if (clipId < 0) continue;

      // Add the MIDI note to the clip
      // Note: note starts at 0.0 relative to the clip, duration = clip duration
      audioEngine!.addMidiNoteToClip(
        clipId,
        midiNote,
        100, // velocity
        0.0, // note starts at beginning of clip
        duration, // note duration = clip duration
      );

      // Add the clip to the sampler track at the correct position
      audioEngine!.addMidiClipToTrack(samplerTrackId, clipId, startTime);
    }

    // Refresh tracks and select the new sampler track
    refreshTrackWidgets();
    selectTrack(samplerTrackId);

    // Optionally delete the original audio track (ask user?)
    // For now, keep both tracks so user can compare

    _showSnackBar('Converted to Sampler track');
  }

  /// Truncate a name to max length with ellipsis
  String _truncateName(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength - 3)}...';
  }

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
    final hasClips = timelineKey.currentState?.hasClipsOnTrack(trackId) ?? false;
    return !hasClips;
  }

  // Helper: Get track name by ID
  String? _getTrackName(int trackId) {
    final info = audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return null;

    final parts = info.split(',');
    if (parts.length < 2) return null;

    return parts[1];
  }

  // Helper: Generate clip name for a track using instrument or track name
  String _generateClipName(int trackId) {
    final instrument = trackInstruments[trackId];
    final trackName = _getTrackName(trackId);
    return ClipNamingService.generateClipName(
      instrument: instrument,
      trackName: trackName,
    );
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
      return availableInstruments.firstWhere(
        (inst) => inst.id == id,
      );
    } catch (e) {
      return null;
    }
  }

  /// Copy audio file to project's Samples folder if setting is enabled
  ///
  /// Returns the path to use (either copied path or original path)
  Future<String> _prepareSamplePath(String originalPath) async {
    // If setting is disabled or no project is open, use original path
    if (!userSettings.copySamplesToProject || projectManager?.currentPath == null) {
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

      timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: finalPath, // Use the copied path
        startTime: 0.0,
        duration: duration,
        waveformPeaks: peaks,
      ));
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
        setState(() {
          statusMessage = 'Added $effectType to track';
        });
      }
    } catch (e) {
      debugPrint('Failed to add effect to track: $e');
    }
  }

  // Helper: Show snackbar message
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onInstrumentParameterChanged(InstrumentData instrumentData) {
    trackController.setTrackInstrument(instrumentData.trackId, instrumentData);
  }

  // M10: VST3 Plugin methods - delegating to Vst3PluginManager

  Future<void> _scanVst3Plugins({bool forceRescan = false}) async {
    if (vst3PluginManager == null) return;

    setState(() {
      statusMessage = forceRescan ? 'Rescanning VST3 plugins...' : 'Scanning VST3 plugins...';
    });

    final result = await vst3PluginManager!.scanPlugins(forceRescan: forceRescan);

    if (mounted) {
      setState(() {
        statusMessage = result;
      });
    }
  }

  void _addVst3PluginToTrack(int trackId, Map<String, String> plugin) {
    if (vst3PluginManager == null) return;

    final result = vst3PluginManager!.addToTrack(trackId, plugin);

    setState(() {
      statusMessage = result.message;
    });

    // Show snackbar based on result
    final colors = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? '✅ ${result.message}' : '❌ ${result.message}'),
        duration: Duration(seconds: result.success ? 2 : 3),
        backgroundColor: result.success ? colors.success : colors.error,
      ),
    );
  }

  void _removeVst3Plugin(int effectId) {
    if (vst3PluginManager == null) return;

    final result = vst3PluginManager!.removeFromTrack(effectId);

    setState(() {
      statusMessage = result.message;
    });
  }

  Future<void> _showVst3PluginBrowser(int trackId) async {
    if (vst3PluginManager == null) return;

    final vst3Browser = await showVst3PluginBrowser(
      context,
      availablePlugins: vst3PluginManager!.availablePlugins,
      isScanning: vst3PluginManager!.isScanning,
      onRescanRequested: () {
        _scanVst3Plugins(forceRescan: true);
      },
    );

    if (vst3Browser != null) {
      _addVst3PluginToTrack(trackId, {
        'name': vst3Browser.name,
        'path': vst3Browser.path,
        'vendor': vst3Browser.vendor ?? '',
      });
    }
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
                                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🎛️  Native editor support coming soon! For now, use the parameter sliders.'),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open GUI'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '0.50',
                    style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
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
    }
  }

  void _onMidiClipCopied(MidiClipData sourceClip, double newStartTime) {
    // Use undo/redo manager for arrangement operations
    final command = DuplicateMidiClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip, sharedPatternId) {
        // Update original clip's patternId if it was null (first duplication)
        if (sourceClip.patternId == null) {
          final updatedOriginal = sourceClip.copyWith(patternId: sharedPatternId);
          midiPlaybackManager?.updateClipInPlace(updatedOriginal);
        }

        // Add new clip to manager and schedule for playback
        midiPlaybackManager?.addRecordedClip(newClip);
        midiClipController.updateClip(newClip, playheadPosition);
        // Select the new clip
        midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Find the clip to get track ID
        final clip = midiPlaybackManager?.midiClips.firstWhere(
          (c) => c.clipId == clipId,
          orElse: () => sourceClip,
        );
        midiClipController.deleteClip(clipId, clip?.trackId ?? sourceClip.trackId);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  void _onAudioClipCopied(ClipData sourceClip, double newStartTime) {
    final command = DuplicateAudioClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip) {
        // Add to timeline view's clip list
        timelineKey.currentState?.addClip(newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Remove from timeline view's clip list
        timelineKey.currentState?.removeClip(clipId);
        if (mounted) setState(() {});
      },
    );
    undoRedoManager.execute(command);
  }

  void _duplicateSelectedClip() {
    final clip = midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    _onMidiClipCopied(clip, newStartTime);
  }

  void _splitSelectedClipAtPlayhead() {
    // Split at playhead position
    final splitPosition = playheadPosition;

    // Try MIDI clip first
    if (midiPlaybackManager?.selectedClipId != null) {
      final success = midiClipController.splitSelectedClipAtPlayhead(splitPosition);
      if (success && mounted) {
        setState(() {
          statusMessage = 'Split MIDI clip at playhead';
        });
        return;
      }
    }

    // Try audio clip if no MIDI clip or MIDI split failed
    final audioSplit = timelineKey.currentState?.splitSelectedAudioClipAtPlayhead(splitPosition) ?? false;
    if (audioSplit && mounted) {
      setState(() {
        statusMessage = 'Split audio clip at playhead';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        statusMessage = 'Cannot split: select a clip and place playhead within it';
      });
    }
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
        setState(() {
          statusMessage = 'Quantized MIDI clip to grid';
        });
        return;
      }
    }

    // Try audio clip
    final audioQuantized = timelineKey.currentState?.quantizeSelectedAudioClip(gridSizeSeconds) ?? false;
    if (audioQuantized && mounted) {
      setState(() {
        statusMessage = 'Quantized audio clip to grid';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        statusMessage = 'Cannot quantize: select a clip first';
      });
    }
  }

  /// Select all clips in the timeline view
  void _selectAllClips() {
    timelineKey.currentState?.selectAllClips();
    if (mounted) {
      setState(() {
        statusMessage = 'Selected all clips';
      });
    }
  }

  /// Bounce MIDI to Audio - renders MIDI through instrument to audio file
  /// NOTE: This is a placeholder that shows planned feature message.
  /// Full implementation requires Rust-side single-track offline rendering.
  void _bounceMidiToAudio() {
    final selectedClipId = midiPlaybackManager?.selectedClipId;
    final selectedClip = midiPlaybackManager?.currentEditingClip;

    if (selectedClipId == null || selectedClip == null) {
      setState(() {
        statusMessage = 'Select a MIDI clip to bounce to audio';
      });
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

  /// Consolidate multiple selected MIDI clips into a single clip
  void _consolidateSelectedClips() {
    final timelineState = timelineKey.currentState;
    if (timelineState == null) return;

    // Get selected MIDI clips
    final selectedMidiClips = timelineState.selectedMidiClips;

    if (selectedMidiClips.length < 2) {
      setState(() {
        statusMessage = 'Select 2 or more MIDI clips to consolidate';
      });
      return;
    }

    // Ensure all clips are on the same track
    final trackIds = selectedMidiClips.map((c) => c.trackId).toSet();
    if (trackIds.length > 1) {
      setState(() {
        statusMessage = 'Cannot consolidate clips from different tracks';
      });
      return;
    }

    final trackId = trackIds.first;

    // Sort clips by start time
    final sortedClips = List<MidiClipData>.from(selectedMidiClips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Calculate consolidated clip bounds
    final firstClipStart = sortedClips.first.startTime;
    final lastClipEnd = sortedClips.map((c) => c.endTime).reduce((a, b) => a > b ? a : b);
    final totalDuration = lastClipEnd - firstClipStart;

    // Merge all notes with adjusted timing
    final mergedNotes = <MidiNoteData>[];
    for (final clip in sortedClips) {
      final clipOffset = clip.startTime - firstClipStart;
      for (final note in clip.notes) {
        mergedNotes.add(note.copyWith(
          startTime: note.startTime + clipOffset,
          id: '${note.note}_${note.startTime + clipOffset}_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
    }

    // Sort notes by start time
    mergedNotes.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Create consolidated clip
    final consolidatedClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: firstClipStart,
      duration: totalDuration,
      loopLength: totalDuration,
      notes: mergedNotes,
      name: 'Consolidated',
      color: sortedClips.first.color,
    );

    // Delete original clips
    for (final clip in sortedClips) {
      midiClipController.deleteClip(clip.clipId, clip.trackId);
    }

    // Add consolidated clip
    midiClipController.addClip(consolidatedClip);
    midiClipController.updateClip(consolidatedClip, playheadPosition);

    // Select the new consolidated clip
    midiPlaybackManager?.selectClip(consolidatedClip.clipId, consolidatedClip);
    timelineState.clearClipSelection();

    setState(() {
      statusMessage = 'Consolidated ${sortedClips.length} clips into one';
    });
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
        commands.add(DeleteMidiClipFromArrangementCommand(
          clipData: clip,
          onClipRemoved: (cId, tId) {
            midiClipController.deleteClip(cId, tId);
          },
          onClipRestored: (restoredClip) {
            midiPlaybackManager?.addRecordedClip(restoredClip);
            midiClipController.updateClip(restoredClip, playheadPosition);
          },
        ));
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
      commands.add(DeleteAudioClipCommand(
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
      ));
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
      setState(() {
        statusMessage = 'Undo - ${undoRedoManager.redoDescription ?? "Action"}';
      });
      refreshTrackWidgets();
    }
  }

  Future<void> _performRedo() async {
    final success = await undoRedoManager.redo();
    if (success && mounted) {
      setState(() {
        statusMessage = 'Redo - ${undoRedoManager.undoDescription ?? "Action"}';
      });
      refreshTrackWidgets();
    }
  }

  // M5: Project file methods

  /// Get the default projects folder path: ~/Documents/Boojy/Audio/Projects
  Future<String> _getDefaultProjectsFolder() async {
    final home = Platform.environment['HOME'] ?? '/Users/${Platform.environment['USER']}';
    final projectsPath = '$home/Documents/Boojy/Audio/Projects';

    // Create the folder if it doesn't exist
    final dir = Directory(projectsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return projectsPath;
  }

  void _newProject() {
    // Show confirmation dialog if current project has unsaved changes
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: const Text('Create a new project? Any unsaved changes will be lost.'),
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

              // Reset project manager state
              projectManager?.newProject();
              midiPlaybackManager?.clear();
              undoRedoManager.clear();

              // Reset loop auto-follow for new project
              uiLayout.resetLoopAutoFollow();

              // Clear automation data
              automationController.clear();

              // Clear window title (back to just "Boojy Audio")
              WindowTitleService.clearProjectName();

              // Refresh track widgets to show empty state (clear clips too)
              refreshTrackWidgets(clearClips: true);

              setState(() {
                loadedClipId = null;
                waveformPeaks = [];
                statusMessage = 'New project created';
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New project created')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProject() async {
    try {
      // Get default projects folder
      final defaultFolder = await _getDefaultProjectsFolder();

      // Use macOS native file picker with default location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Select Boojy Audio Project (.audio folder)" default location POSIX file "$defaultFolder")'
      ]);

      if (result.exitCode == 0) {
        var path = result.stdout.toString().trim();
        // Remove trailing slash if present
        if (path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }

        if (path.isEmpty) {
          return;
        }

        if (!path.endsWith('.audio')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a .audio folder')),
          );
          return;
        }

        setState(() => isLoading = true);

        // Load via project manager
        final loadResult = await projectManager!.loadProject(path);

        // Clear MIDI clip ID mappings since Rust side has reset
        midiPlaybackManager?.clearClipIdMappings();
        undoRedoManager.clear();

        // Restore MIDI clips from engine for UI display
        midiPlaybackManager?.restoreClipsFromEngine(tempo);

        // Apply UI layout if available
        if (loadResult.uiLayout != null) {
          _applyUILayout(loadResult.uiLayout!);
        }

        // Refresh track widgets to show loaded tracks
        refreshTrackWidgets();

        // Add to recent projects
        userSettings.addRecentProject(path, projectManager!.currentName);

        // Update window title and metadata with project name
        WindowTitleService.setProjectName(projectManager!.currentName);

        setState(() {
          projectMetadata = projectMetadata.copyWith(name: projectManager!.currentName);
          statusMessage = 'Project loaded: ${projectManager!.currentName}';
          isLoading = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadResult.result.message)),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  /// Open a project from a specific path (used by Open Recent)
  Future<void> _openRecentProject(String path) async {
    // Check if path still exists
    final dir = Directory(path);
    if (!await dir.exists()) {
      userSettings.removeRecentProject(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project no longer exists')),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      // Load via project manager
      final loadResult = await projectManager!.loadProject(path);

      // Clear MIDI clip ID mappings since Rust side has reset
      midiPlaybackManager?.clearClipIdMappings();
      undoRedoManager.clear();

      // Restore MIDI clips from engine for UI display
      midiPlaybackManager?.restoreClipsFromEngine(tempo);

      // Apply UI layout if available
      if (loadResult.uiLayout != null) {
        _applyUILayout(loadResult.uiLayout!);
      }

      // Refresh track widgets to show loaded tracks
      refreshTrackWidgets();

      // Update recent projects (moves to top)
      userSettings.addRecentProject(path, projectManager!.currentName);

      // Update window title and metadata with project name
      WindowTitleService.setProjectName(projectManager!.currentName);

      setState(() {
        projectMetadata = projectMetadata.copyWith(name: projectManager!.currentName);
        statusMessage = 'Project loaded: ${projectManager!.currentName}';
        isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadResult.result.message)),
      );
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  /// Build the Open Recent submenu items
  List<PlatformMenuItem> _buildRecentProjectsMenu() {
    final recent = userSettings.recentProjects;

    if (recent.isEmpty) {
      return [
        const PlatformMenuItem(
          label: 'No Recent Projects',
          onSelected: null,
        ),
      ];
    }

    return [
      ...recent.map((project) => PlatformMenuItem(
        label: project.name,
        onSelected: () => _openRecentProject(project.path),
      )),
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

  Future<void> _saveProject() async {
    if (projectManager?.currentPath != null) {
      _saveProjectToPath(projectManager!.currentPath!);
    } else {
      _saveProjectAs();
    }
  }

  Future<void> _saveProjectAs() async {
    // Show dialog to enter project name
    final nameController = TextEditingController(text: projectManager?.currentName ?? 'Untitled');

    final projectName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Project As'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            hintText: 'Enter project name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (projectName == null || projectName.isEmpty) return;

    // Update project name in manager, metadata, and window title
    projectManager?.setProjectName(projectName);
    WindowTitleService.setProjectName(projectName);
    setState(() {
      projectMetadata = projectMetadata.copyWith(name: projectName);
    });

    try {
      // Get default projects folder
      final defaultFolder = await _getDefaultProjectsFolder();

      // Use macOS native file picker for save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Choose location to save project" default location POSIX file "$defaultFolder")'
      ]);

      if (result.exitCode == 0) {
        final parentPath = result.stdout.toString().trim();
        if (parentPath.isNotEmpty) {
          final projectPath = '$parentPath/$projectName.audio';
          _saveProjectToPath(projectPath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save project: $e')),
        );
      }
    }
  }

  Future<void> _saveProjectToPath(String path) async {
    setState(() => isLoading = true);

    final result = await projectManager!.saveProjectToPath(path, _getCurrentUILayout());

    // Add to recent projects on successful save
    if (result.success) {
      userSettings.addRecentProject(path, projectManager!.currentName);
    }

    setState(() {
      statusMessage = result.success ? 'Project saved' : result.message;
      isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  /// Apply UI layout from loaded project
  void _applyUILayout(UILayoutData layout) {
    setState(() {
      // Apply panel sizes and visibility from layout
      uiLayout.applyLayout(layout);
    });

    // Restore view state if "continue where I left off" is enabled
    if (userSettings.continueWhereLeftOff && layout.viewState != null) {
      _restoreViewState(layout.viewState!);
    }

    // Restore audio clips if available
    if (layout.audioClips != null && layout.audioClips!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final timelineState = timelineKey.currentState;
        if (timelineState != null) {
          timelineState.restoreAudioClips(layout.audioClips!);
        }
      });
    }

    // Restore automation data if available
    automationController.loadFromJson(layout.automationData);

    // Sync all volume automation lanes to engine
    _syncAllVolumeAutomationToEngine();
  }

  /// Sync all volume automation lanes to engine (called on project load)
  void _syncAllVolumeAutomationToEngine() {
    if (audioEngine == null) return;
    for (final trackId in automationController.allTrackIds) {
      syncVolumeAutomationToEngine(trackId);
    }
  }

  /// Restore view state (zoom, scroll, panels, playhead)
  void _restoreViewState(ProjectViewState viewState) {
    // Need to wait for next frame so timeline widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timelineState = timelineKey.currentState;

      if (timelineState != null) {
        // Restore zoom and scroll
        timelineState.setPixelsPerBeat(viewState.zoom);
        timelineState.setScrollOffset(viewState.horizontalScroll);
      }

      // Restore panel visibility
      setState(() {
        uiLayout.isLibraryPanelCollapsed = !viewState.libraryVisible;
        uiLayout.isMixerVisible = viewState.mixerVisible;
        uiLayout.isEditorPanelVisible = viewState.editorVisible;
        uiLayout.isVirtualPianoEnabled = viewState.virtualPianoVisible;
      });

      // Restore selected track
      if (viewState.selectedTrackId != null) {
        selectedTrackId = viewState.selectedTrackId;
      }

      // Restore playhead position
      playheadPosition = viewState.playheadPosition;
    });
  }

  /// Get current UI layout for saving
  UILayoutData _getCurrentUILayout() {
    // Only save view state if "continue where I left off" is enabled
    ProjectViewState? viewState;
    if (userSettings.continueWhereLeftOff) {
      // Access timeline view state through GlobalKey
      final timelineState = timelineKey.currentState;

      viewState = ProjectViewState(
        horizontalScroll: timelineState?.scrollOffset ?? 0.0,
        verticalScroll: 0.0, // Not tracked in timeline view
        zoom: timelineState?.pixelsPerBeat ?? 25.0,
        libraryVisible: !uiLayout.isLibraryPanelCollapsed,
        mixerVisible: uiLayout.isMixerVisible,
        editorVisible: uiLayout.isEditorPanelVisible,
        virtualPianoVisible: uiLayout.isVirtualPianoEnabled,
        selectedTrackId: selectedTrackId,
        playheadPosition: playheadPosition,
      );
    }

    // Get audio clips from timeline for persistence
    final timelineState = timelineKey.currentState;
    final audioClips = timelineState?.clips.toList();

    return UILayoutData(
      libraryWidth: uiLayout.libraryPanelWidth,
      mixerWidth: uiLayout.mixerPanelWidth,
      bottomHeight: uiLayout.editorPanelHeight,
      libraryCollapsed: uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !uiLayout.isMixerVisible,
      bottomCollapsed: !(uiLayout.isEditorPanelVisible || uiLayout.isVirtualPianoEnabled),
      viewState: viewState,
      audioClips: audioClips,
      automationData: automationController.toJson(),
    );
  }

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
          // Clear and restore MIDI clips from engine for UI display
          midiPlaybackManager?.clearClipIdMappings();
          midiPlaybackManager?.restoreClipsFromEngine(tempo);

          setState(() {
            statusMessage = 'Recovered from backup';
          });
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
      debugPrint('Failed to check for crash recovery: $e');
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

  /// Quick export MP3 using last saved settings
  Future<void> _quickExportMp3() async {
    if (audioEngine == null) return;

    try {
      final baseName = projectManager?.currentName ?? 'Untitled';

      // Use file_picker to choose save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose file name with prompt "Export MP3" default name "$baseName.mp3")'
      ]);

      if (result.exitCode != 0) return; // User cancelled

      String? filePath = result.stdout.toString().trim();
      if (filePath.isEmpty) return;

      // Ensure .mp3 extension
      if (!filePath.endsWith('.mp3')) {
        filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.mp3';
      }

      // Export with saved settings
      final bitrate = userSettings.exportMp3Bitrate;
      final sampleRate = userSettings.exportSampleRate;
      final normalize = userSettings.exportNormalize;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting MP3...')),
        );
      }

      final resultJson = audioEngine!.exportMp3WithOptions(
        outputPath: filePath,
        bitrate: bitrate,
        sampleRate: sampleRate,
        normalize: normalize,
      );

      if (mounted) {
        final result = jsonDecode(resultJson) as Map<String, dynamic>;
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MP3 export complete')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: ${result['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Quick export WAV using last saved settings
  Future<void> _quickExportWav() async {
    if (audioEngine == null) return;

    try {
      final baseName = projectManager?.currentName ?? 'Untitled';

      // Use file_picker to choose save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose file name with prompt "Export WAV" default name "$baseName.wav")'
      ]);

      if (result.exitCode != 0) return; // User cancelled

      String? filePath = result.stdout.toString().trim();
      if (filePath.isEmpty) return;

      // Ensure .wav extension
      if (!filePath.endsWith('.wav')) {
        filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.wav';
      }

      // Export with saved settings
      final bitDepth = userSettings.exportWavBitDepth;
      final sampleRate = userSettings.exportSampleRate;
      final normalize = userSettings.exportNormalize;
      final dither = userSettings.exportDither;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting WAV...')),
        );
      }

      final resultJson = audioEngine!.exportWavWithOptions(
        outputPath: filePath,
        bitDepth: bitDepth,
        sampleRate: sampleRate,
        normalize: normalize,
        dither: dither,
      );

      if (mounted) {
        final result = jsonDecode(resultJson) as Map<String, dynamic>;
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('WAV export complete')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: ${result['error']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _exportMidi() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export MIDI'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export MIDI functionality coming soon.'),
            SizedBox(height: 16),
            Text('This will export:'),
            Text('• All MIDI tracks as .mid file'),
            Text('• Preserve tempo and time signatures'),
            Text('• Include all note data and velocities'),
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

  Future<void> _saveNewVersion() async {
    if (projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save project first before creating a new version')),
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
      final baseName = currentName.replaceAll(RegExp(r'_v\d+$'), ''); // Remove existing _vN suffix

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
        await Process.run('ln', ['-s', '$currentPath/Samples', '$newVersionPath/Samples']);
      }

      // Update project manager to point to new version
      projectManager!.setProjectName(newVersionName);
      await projectManager!.saveProjectToPath(newVersionPath, _getCurrentUILayout());

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
              SnackBar(content: Text('A project named "$newName" already exists in this location')),
            );
          }
          return;
        }

        // Rename the directory
        await currentDir.rename(newPath);

        // Update project manager state
        projectManager!.setProjectName(newName);

        // Save project to update internal metadata with new name
        await projectManager!.saveProjectToPath(newPath, _getCurrentUILayout());

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename project: $e')),
        );
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

    await AppSettingsDialog.show(context, userSettings, audioEngine: audioEngine);
  }

  Future<void> _openProjectSettings() async {
    // Initialize version manager if needed
    final projectPath = projectManager?.currentPath;
    if (projectPath != null) {
      final projectFolder = File(projectPath).parent.path;
      versionManager ??= VersionManager(projectFolder);
      await versionManager!.refresh();
    }

    // Open project-specific settings dialog (accessed via clicking song name)
    final result = await ProjectSettingsDialog.show(
      context,
      metadata: projectMetadata,
      versions: versionManager?.versions ?? [],
      currentVersionNumber: versionManager?.currentVersionNumber,
      nextVersionNumber: versionManager?.nextVersionNumber ?? 1,
    );

    if (result == null || !mounted) return;

    // Handle metadata changes
    final updatedMetadata = result.metadata;
    final bpmChanged = updatedMetadata.bpm != projectMetadata.bpm;
    final nameChanged = updatedMetadata.name != projectMetadata.name;

    setState(() {
      projectMetadata = updatedMetadata;
    });

    // Update audio engine with new BPM
    if (bpmChanged) {
      audioEngine?.setTempo(updatedMetadata.bpm);
      recordingController.setTempo(updatedMetadata.bpm);
    }

    // Update project name if changed
    if (nameChanged) {
      projectManager?.setProjectName(updatedMetadata.name);
      WindowTitleService.setProjectName(updatedMetadata.name);
    }

    // Handle version actions
    if (result.versionAction == 'create' && result.newVersionData != null) {
      await _createVersion(result.newVersionData!);
    } else if (result.versionAction == 'restore' && result.selectedVersion != null) {
      await _restoreVersion(result.selectedVersion!);
    }
  }

  // ========================================================================
  // Version Methods
  // ========================================================================

  Future<void> _createVersion(({String name, String? note, VersionType type}) data) async {
    if (projectManager?.currentPath == null || versionManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save the project first')),
      );
      return;
    }

    final projectPath = projectManager!.currentPath!;

    // Create the version
    final version = await versionManager!.createVersion(
      name: data.name,
      note: data.note,
      versionType: data.type,
      currentProjectFilePath: projectPath,
    );

    if (version != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Version "${version.name}" created')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create version')),
      );
    }
  }

  Future<void> _restoreVersion(ProjectVersion version) async {
    if (projectManager?.currentPath == null || versionManager == null) return;

    final projectPath = projectManager!.currentPath!;

    // Switch to the version
    final success = await versionManager!.switchToVersion(
      version: version,
      currentProjectFilePath: projectPath,
    );

    if (success && mounted) {
      // Reload the project
      await _openRecentProject(projectPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored version "${version.name}"')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to restore version')),
      );
    }
  }

  // ========================================================================
  // End Snapshot Methods
  // ========================================================================

  void _closeProject() {
    // Show confirmation dialog if current project has unsaved changes
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Project'),
        content: const Text('Are you sure you want to close the current project?\n\nAny unsaved changes will be lost.'),
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

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Project closed')),
              );
            },
            child: Text('Close', style: TextStyle(color: context.colors.error)),
          ),
        ],
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
        // First launch: use percentage-based sizing
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              // Calculate target total library width
              final targetLibraryTotal = (windowSize.width * 0.15).clamp(
                UILayoutState.libraryMinWidth,
                UILayoutState.libraryHardMax,
              );
              // Split into left (default) and right (remainder)
              uiLayout.libraryLeftColumnWidth = UILayoutState.libraryLeftColumnDefault;
              uiLayout.libraryRightColumnWidth = (targetLibraryTotal -
                  UILayoutState.libraryLeftColumnDefault -
                  UILayoutState.libraryDividerWidth).clamp(
                UILayoutState.libraryRightColumnMin,
                UILayoutState.libraryRightColumnMax,
              );
              uiLayout.mixerPanelWidth = (windowSize.width * 0.28).clamp(
                UILayoutState.mixerMinWidth,
                UILayoutState.mixerHardMax,
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
      menus: buildDawMenus(context, DawMenuConfig(
        // File menu callbacks
        onNewProject: _newProject,
        onOpenProject: _openProject,
        onSaveProject: _saveProject,
        onSaveProjectAs: _saveProjectAs,
        onSaveNewVersion: _saveNewVersion,
        onRenameProject: _renameProject,
        onExportAudio: _exportAudio,
        onExportMidi: _exportMidi,
        onProjectSettings: _openProjectSettings,
        onCloseProject: _closeProject,
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
        onSplitAtMarker: (midiPlaybackManager?.selectedClipId != null ||
                timelineKey.currentState?.selectedAudioClipId != null)
            ? _splitSelectedClipAtPlayhead
            : null,
        onQuantizeClip: (midiPlaybackManager?.selectedClipId != null ||
                timelineKey.currentState?.selectedAudioClipId != null)
            ? _quantizeSelectedClip
            : null,
        onConsolidateClips: (timelineKey.currentState?.selectedMidiClipIds.length ?? 0) >= 2
            ? _consolidateSelectedClips
            : null,
        onBounceMidiToAudio: midiPlaybackManager?.selectedClipId != null
            ? _bounceMidiToAudio
            : null,
        hasSelectedMidiClip: midiPlaybackManager?.selectedClipId != null,
        hasSelectedAudioClip: timelineKey.currentState?.selectedAudioClipId != null,
        selectedMidiClipCount: timelineKey.currentState?.selectedMidiClipIds.length ?? 0,
        // View menu state and callbacks
        uiLayout: uiLayout,
        onToggleLibrary: _toggleLibraryPanel,
        onToggleMixer: _toggleMixer,
        onToggleEditor: _toggleEditor,
        onTogglePiano: _toggleVirtualPiano,
        onResetPanelLayout: _resetPanelLayout,
        onAppSettings: _appSettings,
        // Undo/redo callbacks
        onUndo: _performUndo,
        onRedo: _performRedo,
      )),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // ? key (Shift + /) to show keyboard shortcuts
          const SingleActivator(LogicalKeyboardKey.slash, shift: true): _showKeyboardShortcuts,
          // Cmd+E to split clip at insert marker (or playhead if no marker)
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _splitSelectedClipAtPlayhead,
          // Cmd+D to duplicate clip
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): _duplicateSelectedClip,
          // Cmd+A to select all clips (in timeline view)
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAllClips,
          // Cmd+J to consolidate clips
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): _consolidateSelectedClips,
          // Cmd+B to bounce MIDI to audio
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _bounceMidiToAudio,
        },
        // Single-key shortcuts (Space, Q, L, M) are handled in Focus.onKeyEvent
        // so they don't interfere with text input fields
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleSingleKeyShortcut(event),
          child: Scaffold(
        backgroundColor: context.colors.standard,
        body: Column(
          children: [
          // Transport bar (with logo and file/mixer buttons)
          // PERFORMANCE: Use ValueListenableBuilder for playhead-only updates
          ValueListenableBuilder<double>(
            valueListenable: playbackController.playheadNotifier,
            builder: (context, playheadPos, _) => TransportBar(
            onPlay: _playWithLoopCheck,
            onPause: _pause,
            onStop: _stopPlayback,
            onRecord: toggleRecording,
            onPauseRecording: pauseRecording,
            onStopRecording: stopRecordingAndReturn,
            onCaptureMidi: _captureMidi,
            onCountInChanged: _setCountInBars,
            countInBars: userSettings.countInBars,
            onMetronomeToggle: _toggleMetronome,
            onPianoToggle: _toggleVirtualPiano,
            playheadPosition: playheadPos,
            isPlaying: isPlaying,
            canPlay: true, // Always allow transport controls
            isRecording: isRecording,
            isCountingIn: isCountingIn,
            countInBeat: recordingController.countInBeat,
            countInProgress: recordingController.countInProgress,
            hasArmedTracks: mixerKey.currentState?.tracks.any((t) => t.armed) ?? false,
            metronomeEnabled: isMetronomeEnabled,
            virtualPianoEnabled: uiLayout.isVirtualPianoEnabled,
            tempo: tempo,
            onTempoChanged: _onTempoChanged,
            // MIDI device selection
            midiDevices: midiDevices,
            selectedMidiDeviceIndex: selectedMidiDeviceIndex,
            onMidiDeviceSelected: _onMidiDeviceSelected,
            onRefreshMidiDevices: _refreshMidiDevices,
            // File menu callbacks
            onNewProject: _newProject,
            onOpenProject: _openProject,
            onSaveProject: _saveProject,
            onSaveProjectAs: _saveProjectAs,
            onSaveNewVersion: _saveNewVersion,
            onRenameProject: _renameProject,
            onExportAudio: _exportAudio,
            onExportMp3: _quickExportMp3,
            onExportWav: _quickExportWav,
            onExportMidi: _exportMidi,
            onAppSettings: _appSettings, // App-wide settings (logo click)
            onProjectSettings: _openProjectSettings, // Project-specific settings (song name click)
            onCloseProject: _closeProject,
            projectName: projectMetadata.name,
            hasProject: projectManager?.hasProject ?? false,
            // View menu parameters
            onToggleLibrary: _toggleLibraryPanel,
            onToggleMixer: _toggleMixer,
            onToggleEditor: _toggleEditor,
            onTogglePiano: _toggleVirtualPiano,
            onResetPanelLayout: _resetPanelLayout,
            libraryVisible: !uiLayout.isLibraryPanelCollapsed,
            mixerVisible: uiLayout.isMixerVisible,
            editorVisible: uiLayout.isEditorPanelVisible,
            pianoVisible: uiLayout.isVirtualPianoEnabled,
            onHelpPressed: _showKeyboardShortcuts,
            // Edit menu (Undo/Redo) callbacks
            onUndo: undoRedoManager.canUndo ? _performUndo : null,
            onRedo: undoRedoManager.canRedo ? _performRedo : null,
            canUndo: undoRedoManager.canUndo,
            canRedo: undoRedoManager.canRedo,
            undoDescription: undoRedoManager.undoDescription,
            redoDescription: undoRedoManager.redoDescription,
            // Snap control
            arrangementSnap: uiLayout.arrangementSnap,
            onSnapChanged: (value) => uiLayout.setArrangementSnap(value),
            // Loop playback control
            loopPlaybackEnabled: uiLayout.loopPlaybackEnabled,
            onLoopPlaybackToggle: uiLayout.toggleLoopPlayback,
            // Punch in/out
            punchInEnabled: uiLayout.punchInEnabled,
            punchOutEnabled: uiLayout.punchOutEnabled,
            onPunchInToggle: uiLayout.togglePunchIn,
            onPunchOutToggle: uiLayout.togglePunchOut,
            // Time signature
            beatsPerBar: projectMetadata.timeSignatureNumerator,
            beatUnit: projectMetadata.timeSignatureDenominator,
            onTimeSignatureChanged: _onTimeSignatureChanged,
            isLoading: isLoading,
          ),
          ),

          // Main content area - 3-column layout
          Expanded(
            child: Column(
              children: [
                // Top section: Library + Timeline + Mixer
                Expanded(
                  child: Row(
                    children: [
                      // Left: Library panel
                      SizedBox(
                        width: uiLayout.isLibraryPanelCollapsed ? 40 : uiLayout.libraryPanelWidth,
                        child: libraryPreviewService != null
                          ? ChangeNotifierProvider<LibraryPreviewService>.value(
                              value: libraryPreviewService!,
                              child: LibraryPanel(
                                isCollapsed: uiLayout.isLibraryPanelCollapsed,
                                onToggle: _toggleLibraryPanel,
                                availableVst3Plugins: vst3PluginManager?.availablePlugins ?? [],
                                libraryService: libraryService,
                                onItemDoubleClick: _handleLibraryItemDoubleClick,
                                onVst3DoubleClick: _handleVst3DoubleClick,
                                onOpenInSampler: _handleOpenInSampler,
                                leftColumnWidth: uiLayout.libraryLeftColumnWidth,
                                onLeftColumnResize: (delta) {
                                  setState(() {
                                    uiLayout.resizeLeftColumn(delta);
                                    userSettings.libraryLeftColumnWidth = uiLayout.libraryLeftColumnWidth;
                                  });
                                },
                              ),
                            )
                          : LibraryPanel(
                              isCollapsed: uiLayout.isLibraryPanelCollapsed,
                              onToggle: _toggleLibraryPanel,
                              availableVst3Plugins: vst3PluginManager?.availablePlugins ?? [],
                              libraryService: libraryService,
                              onItemDoubleClick: _handleLibraryItemDoubleClick,
                              onVst3DoubleClick: _handleVst3DoubleClick,
                              onOpenInSampler: _handleOpenInSampler,
                              leftColumnWidth: uiLayout.libraryLeftColumnWidth,
                              onLeftColumnResize: (delta) {
                                setState(() {
                                  uiLayout.resizeLeftColumn(delta);
                                  userSettings.libraryLeftColumnWidth = uiLayout.libraryLeftColumnWidth;
                                });
                              },
                            ),
                      ),

                      // Divider: Library/Timeline
                      // Outer divider only affects right column (left stays fixed)
                      ResizableDivider(
                        orientation: DividerOrientation.vertical,
                        isCollapsed: uiLayout.isLibraryPanelCollapsed,
                        onDrag: (delta) {
                          setState(() {
                            uiLayout.resizeRightColumn(delta);
                            userSettings.libraryRightColumnWidth = uiLayout.libraryRightColumnWidth;
                            userSettings.libraryCollapsed = uiLayout.isLibraryPanelCollapsed;
                          });
                        },
                        onDoubleClick: () {
                          setState(() {
                            uiLayout.toggleLibraryPanel();
                            userSettings.libraryCollapsed = uiLayout.isLibraryPanelCollapsed;
                          });
                        },
                      ),

                      // Center: Timeline area
                      // PERFORMANCE: Use ValueListenableBuilder to only rebuild TimelineView
                      // when playhead changes, not on every controller notification
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: playbackController.playheadNotifier,
                          builder: (context, playheadPos, _) => TimelineView(
                          key: timelineKey,
                          playheadPosition: playheadPos,
                          clipDuration: clipDuration,
                          waveformPeaks: waveformPeaks,
                          audioEngine: audioEngine,
                          tempo: tempo,
                          selectedMidiTrackId: selectedTrackId,
                          selectedMidiClipId: midiPlaybackManager?.selectedClipId,
                          currentEditingClip: midiPlaybackManager?.currentEditingClip,
                          midiClips: midiPlaybackManager?.midiClips ?? [], // Pass all MIDI clips for visualization
                          onMidiTrackSelected: _onTrackSelected,
                          onMidiClipSelected: _onMidiClipSelected,
                          onAudioClipSelected: _onAudioClipSelected,
                          onMidiClipUpdated: _onMidiClipUpdated,
                          onMidiClipCopied: _onMidiClipCopied,
                          onAudioClipCopied: _onAudioClipCopied,
                          getRustClipId: (dartClipId) => midiPlaybackManager?.dartToRustClipIds[dartClipId] ?? dartClipId,
                          onMidiClipDeleted: _deleteMidiClip,
                          onMidiClipsBatchDeleted: _deleteMidiClipsBatch,
                          onAudioClipsBatchDeleted: _deleteAudioClipsBatch,
                          onInstrumentDropped: _onInstrumentDropped,
                          onInstrumentDroppedOnEmpty: _onInstrumentDroppedOnEmpty,
                          onVst3InstrumentDropped: _onVst3InstrumentDropped,
                          onVst3InstrumentDroppedOnEmpty: _onVst3InstrumentDroppedOnEmpty,
                          onMidiClipExported: _exportMidiClip,
                          onMidiFileDroppedOnEmpty: _onMidiFileDroppedOnEmpty,
                          onMidiFileDroppedOnTrack: _onMidiFileDroppedOnTrack,
                          onAudioFileDroppedOnEmpty: _onAudioFileDroppedOnEmpty,
                          onAudioFileDroppedOnTrack: _onAudioFileDroppedOnTrack,
                          onCreateTrackWithClip: _onCreateTrackWithClip,
                          onCreateClipOnTrack: _onCreateClipOnTrack,
                          clipHeights: clipHeights,
                          automationHeights: automationHeights,
                          masterTrackHeight: masterTrackHeight,
                          trackOrder: trackController.trackOrder,
                          getTrackColor: getTrackColor,
                          onClipHeightChanged: setClipHeight,
                          onAutomationHeightChanged: setAutomationHeight,
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
                          // Recording state (for auto-scroll)
                          isRecording: isRecording,
                          // Automation state
                          automationVisibleTrackId: automationController.visibleTrackId,
                          getAutomationLane: (trackId) => automationController.getLane(trackId, automationController.visibleParameter),
                          onAutomationPointAdded: (trackId, point) {
                            automationController.addPoint(trackId, automationController.visibleParameter, point);
                            if (automationController.visibleParameter == AutomationParameter.volume) {
                              syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPointUpdated: (trackId, pointId, point) {
                            automationController.updatePoint(trackId, automationController.visibleParameter, pointId, point);
                            if (automationController.visibleParameter == AutomationParameter.volume) {
                              syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPointDeleted: (trackId, pointId) {
                            automationController.removePoint(trackId, automationController.visibleParameter, pointId);
                            if (automationController.visibleParameter == AutomationParameter.volume) {
                              syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPreviewValue: onAutomationPreviewValue,
                          automationScrollController: timelineKey.currentState?.scrollController,
                        ),
                        ),
                      ),

                      // Right: Track mixer panel (expanded or collapsed bar)
                      if (uiLayout.isMixerVisible) ...[
                        // Divider: Timeline/Mixer
                        ResizableDivider(
                          orientation: DividerOrientation.vertical,
                          isCollapsed: false,
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
                            isEngineReady: isAudioGraphInitialized,
                            scrollController: mixerVerticalScrollController,
                            selectedTrackId: selectedTrackId,
                            selectedTrackIds: selectedTrackIds,
                            onTrackSelected: _onTrackSelected,
                            onInstrumentSelected: _onInstrumentSelected,
                            onTrackDuplicated: _onTrackDuplicated,
                            onTrackDeleted: _onTrackDeleted,
                            onConvertToSampler: _convertAudioTrackToSampler,
                            trackInstruments: trackInstruments,
                            trackVst3PluginCounts: _getTrackVst3PluginCounts(), // M10
                            onFxButtonPressed: _showVst3PluginBrowser, // M10
                            onVst3PluginDropped: _onVst3PluginDropped, // M10
                            onVst3InstrumentDropped: _onVst3InstrumentDropped, // Swap VST3 instrument
                            onInstrumentDropped: _onInstrumentDropped, // Swap built-in instrument
                            onEditPluginsPressed: _showVst3PluginEditor, // M10
                            onAudioFileDropped: (path) => _onAudioFileDroppedOnEmpty(path),
                            onMidiTrackCreated: _createDefaultMidiClip,
                            onTrackCreated: _onTrackCreatedFromMixer,
                            onTrackReordered: _onTrackReordered,
                            trackOrder: trackController.trackOrder,
                            onTrackOrderSync: trackController.syncTrackOrder,
                            clipHeights: clipHeights,
                            automationHeights: automationHeights,
                            masterTrackHeight: masterTrackHeight,
                            onClipHeightChanged: setClipHeight,
                            onAutomationHeightChanged: setAutomationHeight,
                            onMasterTrackHeightChanged: setMasterTrackHeight,
                            panelWidth: uiLayout.mixerPanelWidth,
                            onTogglePanel: _toggleMixer,
                            getTrackColor: getTrackColor,
                            onTrackColorChanged: setTrackColor,
                            getTrackIcon: (trackId) => trackController.getTrackIcon(trackId),
                            onTrackIconChanged: (trackId, icon) {
                              setState(() {
                                trackController.setTrackIcon(trackId, icon);
                              });
                            },
                            onTrackNameChanged: (trackId, newName) {
                              // Mark track name as user-edited
                              trackController.markTrackNameUserEdited(trackId, edited: true);
                            },
                            onTrackDoubleClick: (trackId) {
                              // Select track and open editor
                              _onTrackSelected(trackId);
                              if (!uiLayout.isEditorPanelVisible) {
                                _toggleEditor();
                              }
                            },
                            automationVisibleTrackId: automationController.visibleTrackId,
                            onAutomationToggle: (trackId) {
                              setState(() {
                                automationController.toggleAutomationForTrack(trackId);
                              });
                            },
                            getAutomationLane: (trackId) => automationController.getLane(trackId, automationController.visibleParameter),
                            pixelsPerBeat: timelineKey.currentState?.pixelsPerBeat ?? 20.0,
                            totalBeats: 256.0,
                            onAutomationPointAdded: (trackId, point) {
                              automationController.addPoint(trackId, automationController.visibleParameter, point);
                              if (automationController.visibleParameter == AutomationParameter.volume) {
                                syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            onAutomationPointUpdated: (trackId, pointId, point) {
                              automationController.updatePoint(trackId, automationController.visibleParameter, pointId, point);
                              if (automationController.visibleParameter == AutomationParameter.volume) {
                                syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            onAutomationPointDeleted: (trackId, pointId) {
                              automationController.removePoint(trackId, automationController.visibleParameter, pointId);
                              if (automationController.visibleParameter == AutomationParameter.volume) {
                                syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            automationPreviewValues: automationPreviewValues,
                            onAutomationPreviewValue: onAutomationPreviewValue,
                            isRecording: recordingController.isRecording || recordingController.isCountingIn,
                            getSelectedParameter: (trackId) => automationController.visibleParameter,
                            onParameterChanged: (trackId, param) {
                              setState(() {
                                automationController.setVisibleParameter(param);
                              });
                            },
                            onResetParameter: (trackId) {
                              // Reset the parameter to its default value
                              final param = automationController.visibleParameter;
                              if (param == AutomationParameter.volume) {
                                audioEngine?.setTrackVolume(trackId, 0.0); // 0 dB
                                setState(() {}); // Trigger UI update
                              } else if (param == AutomationParameter.pan) {
                                audioEngine?.setTrackPan(trackId, 0.0); // Center
                                setState(() {}); // Trigger UI update
                              }
                            },
                            onAddParameter: (trackId) {
                              // TODO: Future feature - add another automation parameter lane
                            },
                          ),
                        ),
                      ] else ...[
                        // Collapsed mixer bar - thin bar with arrow to expand
                        _buildCollapsedMixerBar(),
                      ],
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
                    onDrag: (delta) {
                      final windowHeight = MediaQuery.of(context).size.height;
                      final maxHeight = UILayoutState.getEditorMaxHeight(windowHeight);
                      setState(() {
                        final newHeight = uiLayout.editorPanelHeight - delta;
                        // Snap collapse if dragged below threshold
                        if (newHeight < UILayoutState.editorCollapseThreshold) {
                          uiLayout.collapseEditor();
                          userSettings.editorVisible = false;
                        } else {
                          uiLayout.editorPanelHeight = newHeight.clamp(
                            UILayoutState.editorMinHeight,
                            maxHeight,
                          );
                          userSettings.editorHeight = uiLayout.editorPanelHeight;
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
                SizedBox(
                  height: uiLayout.isEditorPanelVisible ? uiLayout.editorPanelHeight : 40,
                  child: EditorPanel(
                    audioEngine: audioEngine,
                    virtualPianoEnabled: uiLayout.isVirtualPianoEnabled,
                    selectedTrackId: selectedTrackId,
                    selectedTrackName: _getSelectedTrackName(),
                    selectedTrackType: _getSelectedTrackType(),
                    currentInstrumentData: selectedTrackId != null
                        ? trackInstruments[selectedTrackId]
                        : null,
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
                    currentEditingClip: midiPlaybackManager?.currentEditingClip,
                    onMidiClipUpdated: _onMidiClipUpdated,
                    onInstrumentParameterChanged: _onInstrumentParameterChanged,
                    currentEditingAudioClip: selectedAudioClip,
                    onAudioClipUpdated: _onAudioClipUpdated,
                    currentTrackPlugins: selectedTrackId != null // M10
                        ? _getTrackVst3Plugins(selectedTrackId!)
                        : null,
                    onVst3ParameterChanged: _onVst3ParameterChanged, // M10
                    onVst3PluginRemoved: _removeVst3Plugin, // M10
                    onVst3InstrumentDropped: (plugin) {
                      if (selectedTrackId != null) {
                        _onVst3InstrumentDropped(selectedTrackId!, plugin);
                      }
                    },
                    onInstrumentDropped: (instrument) {
                      if (selectedTrackId != null) {
                        _onInstrumentDropped(selectedTrackId!, instrument);
                      }
                    },
                    isCollapsed: !uiLayout.isEditorPanelVisible,
                    toolMode: currentToolMode,
                    onToolModeChanged: (mode) => setState(() => currentToolMode = mode),
                    beatsPerBar: projectMetadata.timeSignatureNumerator,
                    beatUnit: projectMetadata.timeSignatureDenominator,
                    projectTempo: projectMetadata.bpm,
                    onProjectTempoChanged: _onTempoChanged,
                    isRecording: isRecording,
                    onCreateSamplerFromClip: (clipPath) {
                      // Extract filename for track name
                      final name = clipPath.split('/').last.split('.').first;
                      _createSamplerTrackWithSample(clipPath, name);
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

          // Status bar
          _buildStatusBar(),
        ],
      ),
          ),
        ),
      ),
    );
  }

  // Removed _buildTimelineView - now built inline in build method

  /// Build collapsed mixer bar when mixer is hidden
  Widget _buildCollapsedMixerBar() {
    final colors = context.colors;
    return Container(
      width: 30,
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(
          left: BorderSide(color: colors.divider),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          // Mixer icon to expand
          Tooltip(
            message: 'Show Mixer',
            child: Material(
              color: colors.standard,
              child: InkWell(
                onTap: _toggleMixer,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.tune,
                    color: colors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyDisplay() {
    final colors = context.colors;
    if (audioEngine == null || !isAudioGraphInitialized) {
      return Text(
        '--ms',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      );
    }

    final latencyInfo = audioEngine!.getLatencyInfo();
    final roundtripMs = latencyInfo['roundtripMs'] ?? 0.0;

    // Color based on latency quality (semantic colors stay consistent)
    Color latencyColor;
    if (roundtripMs < 10) {
      latencyColor = colors.success; // Green - excellent
    } else if (roundtripMs < 20) {
      latencyColor = colors.success.withValues(alpha: 0.7); // Light green - good
    } else if (roundtripMs < 30) {
      latencyColor = colors.warning; // Yellow - acceptable
    } else {
      latencyColor = colors.warning.withValues(alpha: 0.8); // Orange - high
    }

    return GestureDetector(
      onTap: _showLatencySettings,
      child: Text(
        '${roundtripMs.toStringAsFixed(1)}ms',
        style: TextStyle(
          color: latencyColor,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  void _showLatencySettings() {
    if (audioEngine == null) return;

    showLatencySettingsDialog(
      context: context,
      currentPreset: audioEngine!.getBufferSizePreset(),
      presets: AudioEngine.bufferSizePresets,
      onPresetSelected: (preset) {
        audioEngine!.setBufferSize(preset);
        setState(() {}); // Refresh display
      },
    );
  }

  Widget _buildStatusBar() {
    final colors = context.colors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.darkest,
        border: Border(
          top: BorderSide(color: colors.standard),
        ),
      ),
      child: Row(
        children: [
          // Engine status with icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isAudioGraphInitialized
                  ? colors.accent.withValues(alpha: 0.15)
                  : colors.textMuted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAudioGraphInitialized ? Icons.check_circle : Icons.hourglass_empty,
                  size: 12,
                  color: isAudioGraphInitialized
                      ? colors.accent
                      : colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  isAudioGraphInitialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: isAudioGraphInitialized
                        ? colors.accent
                        : colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Duration (if clip selected)
          if (clipDuration != null) ...[
            Icon(Icons.timelapse, size: 11, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              '${clipDuration!.toStringAsFixed(2)}s',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 16),
          ],
          // Sample rate with icon
          Icon(Icons.graphic_eq, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '48kHz',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 16),
          // Latency display with icon
          Icon(Icons.speed, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          _buildLatencyDisplay(),
          const SizedBox(width: 16),
          // CPU with icon
          Icon(Icons.memory, size: 11, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '0%',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

