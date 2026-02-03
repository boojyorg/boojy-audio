import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
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
import '../services/undo_redo_manager.dart';
import '../services/commands/command.dart';
import '../services/commands/track_commands.dart';
import '../services/commands/project_commands.dart';
import '../services/commands/clip_commands.dart';
import '../services/library_service.dart';
import '../services/library_preview_service.dart';
import '../services/vst3_plugin_manager.dart';
import '../services/project_manager.dart';
import '../services/midi_playback_manager.dart';
import '../services/user_settings.dart';
import '../services/auto_save_service.dart';
import '../services/vst3_editor_service.dart';
import '../services/plugin_preferences_service.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/app_settings_dialog.dart';
import '../widgets/project_settings_dialog.dart';
import '../widgets/export_dialog.dart';
import '../models/project_metadata.dart';
import '../models/project_version.dart';
import '../models/version_type.dart';
import '../models/project_view_state.dart';
import '../models/midi_event.dart';
import '../models/tool_mode.dart';
import '../models/track_automation_data.dart';
import '../services/version_manager.dart';
import '../services/midi_capture_buffer.dart';
import '../services/clip_naming_service.dart';
import '../widgets/capture_midi_dialog.dart';
import '../widgets/dialogs/latency_settings_dialog.dart';
import '../widgets/dialogs/crash_reporting_dialog.dart';
import '../controllers/controllers.dart';
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
  // ============================================
  // PRIVATE ALIASES FOR BACKWARD COMPATIBILITY
  // These map private names to mixin's public properties
  // ============================================

  // Audio engine
  AudioEngine? get _audioEngine => audioEngine;
  set _audioEngine(AudioEngine? value) => audioEngine = value;

  // Controllers
  PlaybackController get _playbackController => playbackController;
  RecordingController get _recordingController => recordingController;
  TrackController get _trackController => trackController;
  MidiClipController get _midiClipController => midiClipController;
  AutomationController get _automationController => automationController;
  UILayoutState get _uiLayout => uiLayout;

  // Undo/Redo
  UndoRedoManager get _undoRedoManager => undoRedoManager;

  // Services
  LibraryService get _libraryService => libraryService;
  LibraryPreviewService? get _libraryPreviewService => libraryPreviewService;
  set _libraryPreviewService(LibraryPreviewService? value) => libraryPreviewService = value;
  Vst3PluginManager? get _vst3PluginManager => vst3PluginManager;
  set _vst3PluginManager(Vst3PluginManager? value) => vst3PluginManager = value;
  ProjectManager? get _projectManager => projectManager;
  set _projectManager(ProjectManager? value) => projectManager = value;
  VersionManager? get _versionManager => versionManager;
  set _versionManager(VersionManager? value) => versionManager = value;
  MidiPlaybackManager? get _midiPlaybackManager => midiPlaybackManager;
  set _midiPlaybackManager(MidiPlaybackManager? value) => midiPlaybackManager = value;
  UserSettings get _userSettings => userSettings;
  AutoSaveService get _autoSaveService => autoSaveService;
  MidiCaptureBuffer get _midiCaptureBuffer => midiCaptureBuffer;

  // Local state
  int? get _loadedClipId => loadedClipId;
  set _loadedClipId(int? value) => loadedClipId = value;
  double? get _clipDuration => clipDuration;
  set _clipDuration(double? value) => clipDuration = value;
  List<double> get _waveformPeaks => waveformPeaks;
  set _waveformPeaks(List<double> value) => waveformPeaks = value;
  bool get _isAudioGraphInitialized => isAudioGraphInitialized;
  set _isAudioGraphInitialized(bool value) => isAudioGraphInitialized = value;
  bool get _isLoading => isLoading;
  set _isLoading(bool value) => isLoading = value;
  bool get _hasInitializedPanelSizes => hasInitializedPanelSizes;
  set _hasInitializedPanelSizes(bool value) => hasInitializedPanelSizes = value;
  ClipData? get _selectedAudioClip => selectedAudioClip;
  set _selectedAudioClip(ClipData? value) => selectedAudioClip = value;
  ToolMode get _currentToolMode => currentToolMode;
  set _currentToolMode(ToolMode value) => currentToolMode = value;
  ProjectMetadata get _projectMetadata => projectMetadata;
  set _projectMetadata(ProjectMetadata value) => projectMetadata = value;
  Map<int, double?> get _automationPreviewValues => automationPreviewValues;

  // Playback convenience
  double get _playheadPosition => playheadPosition;
  set _playheadPosition(double value) => playheadPosition = value;
  bool get _isPlaying => isPlaying;
  set _statusMessage(String value) => statusMessage = value;

  // Recording convenience
  bool get _isRecording => isRecording;
  bool get _isCountingIn => isCountingIn;
  bool get _isMetronomeEnabled => isMetronomeEnabled;
  double get _tempo => tempo;
  List<Map<String, dynamic>> get _midiDevices => midiDevices;
  int get _selectedMidiDeviceIndex => selectedMidiDeviceIndex;

  // Track convenience
  int? get _selectedTrackId => selectedTrackId;
  set _selectedTrackId(int? value) => selectedTrackId = value;
  Set<int> get _selectedTrackIds => selectedTrackIds;
  void _selectTrack(int? trackId, {bool isShiftHeld = false}) =>
      selectTrack(trackId, isShiftHeld: isShiftHeld);
  Map<int, InstrumentData> get _trackInstruments => trackInstruments;
  Map<int, double> get _clipHeights => clipHeights;
  Map<int, double> get _automationHeights => automationHeights;
  double get _masterTrackHeight => masterTrackHeight;

  // Helper method aliases
  void _setClipHeight(int trackId, double height) => setClipHeight(trackId, height);
  void _setAutomationHeight(int trackId, double height) => setAutomationHeight(trackId, height);
  void _onAutomationPreviewValue(int trackId, double? value) => onAutomationPreviewValue(trackId, value);
  void _syncVolumeAutomationToEngine(int trackId) => syncVolumeAutomationToEngine(trackId);
  void _setMasterTrackHeight(double height) => setMasterTrackHeight(height);
  Color _getTrackColor(int trackId, String trackName, String trackType) => getTrackColor(trackId, trackName, trackType);
  void _setTrackColor(int trackId, Color color) => setTrackColor(trackId, color);

  // GlobalKeys
  GlobalKey<TimelineViewState> get _timelineKey => timelineKey;
  GlobalKey<TrackMixerPanelState> get _mixerKey => mixerKey;

  // Scroll controllers
  ScrollController get _timelineVerticalScrollController => timelineVerticalScrollController;
  ScrollController get _mixerVerticalScrollController => mixerVerticalScrollController;
  bool get _isScrollSyncing => isScrollSyncing;
  set _isScrollSyncing(bool value) => isScrollSyncing = value;

  // Scroll sync methods
  void _onTimelineVerticalScroll() => onTimelineVerticalScroll();
  void _onMixerVerticalScroll() => onMixerVerticalScroll();

  // Track widget methods
  void _disarmOtherMidiTracks(int exceptTrackId) => disarmOtherMidiTracks(exceptTrackId);
  void _refreshTrackWidgets({bool clearClips = false}) => refreshTrackWidgets(clearClips: clearClips);

  // ============================================
  // END OF ALIASES
  // The mixins (DAWPlaybackMixin, DAWRecordingMixin, etc.) provide
  // public methods that can be used directly. The private methods
  // below are kept for backward compatibility during migration.
  // ============================================

  @override
  void initState() {
    super.initState();

    // Listen for undo/redo state changes to update menu
    _undoRedoManager.addListener(_onUndoRedoChanged);

    // Listen for controller state changes
    _playbackController.addListener(_onControllerChanged);
    _recordingController.addListener(_onControllerChanged);
    _trackController.addListener(_onControllerChanged);
    _midiClipController.addListener(_onControllerChanged);
    _uiLayout.addListener(_onControllerChanged);

    // Set up vertical scroll sync between timeline and mixer
    _timelineVerticalScrollController.addListener(_onTimelineVerticalScroll);
    _mixerVerticalScrollController.addListener(_onMixerVerticalScroll);

    // Load user settings and apply saved panel states
    _userSettings.load().then((_) async {
      if (mounted) {
        setState(() {
          // Load visibility states
          _uiLayout.isLibraryPanelCollapsed = _userSettings.libraryCollapsed;
          _uiLayout.isMixerVisible = _userSettings.mixerVisible;
          _uiLayout.isEditorPanelVisible = _userSettings.editorVisible;
          // Load panel sizes (library uses left/right columns, total is computed)
          _uiLayout.libraryLeftColumnWidth = _userSettings.libraryLeftColumnWidth;
          _uiLayout.libraryRightColumnWidth = _userSettings.libraryRightColumnWidth;
          _uiLayout.mixerPanelWidth = _userSettings.mixerWidth;
          _uiLayout.editorPanelHeight = _userSettings.editorHeight;
        });

        // Show crash reporting opt-in dialog on first launch
        if (!_userSettings.crashReportingAsked && mounted) {
          final optIn = await CrashReportingDialog.show(context);
          _userSettings.crashReportingEnabled = optIn;
          _userSettings.crashReportingAsked = true;
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
    _undoRedoManager.removeListener(_onUndoRedoChanged);

    // Remove controller listeners
    _playbackController.removeListener(_onControllerChanged);
    _recordingController.removeListener(_onControllerChanged);
    _trackController.removeListener(_onControllerChanged);
    _midiClipController.removeListener(_onControllerChanged); // Was missing!
    _uiLayout.removeListener(_onControllerChanged);

    // Clear callbacks to prevent memory leaks
    _recordingController.onRecordingComplete = null;
    _playbackController.onAutoStop = null;

    // Dispose controllers (ChangeNotifiers must be disposed)
    _playbackController.dispose();
    _recordingController.dispose();
    _trackController.dispose();
    _midiClipController.dispose();
    _automationController.dispose();
    _libraryPreviewService?.dispose();
    _uiLayout.dispose();

    // Dispose scroll controllers
    _timelineVerticalScrollController.removeListener(_onTimelineVerticalScroll);
    _mixerVerticalScrollController.removeListener(_onMixerVerticalScroll);
    _timelineVerticalScrollController.dispose();
    _mixerVerticalScrollController.dispose();

    // Remove VST3 manager listener
    _vst3PluginManager?.removeListener(_onVst3ManagerChanged);

    // Remove project manager listener
    _projectManager?.removeListener(_onProjectManagerChanged);

    // Remove MIDI playback manager listener
    _midiPlaybackManager?.removeListener(_onMidiPlaybackManagerChanged);

    // Stop auto-save and record clean exit
    _autoSaveService.stop();
    _autoSaveService.cleanupBackups();
    _userSettings.recordCleanExit();

    // Stop playback
    _stopPlayback();

    super.dispose();
  }

  Future<void> _initAudioEngine() async {
    try {
      // Load plugin preferences early (before any plugin operations)
      await PluginPreferencesService.load();

      // Called after 800ms delay from initState, so UI has rendered
      _audioEngine = AudioEngine();
      _audioEngine!.initAudioEngine();

      // Initialize audio graph
      final graphResult = _audioEngine!.initAudioGraph();
      if (graphResult.startsWith('Error')) {
        throw Exception(graphResult);
      }

      // Initialize recording settings
      try {
        _audioEngine!.setCountInBars(_userSettings.countInBars); // Use saved setting
        _audioEngine!.setTempo(120.0);   // Default: 120 BPM
        _audioEngine!.setMetronomeEnabled(enabled: true); // Default: enabled
      } catch (e) {
        debugPrint('Recording settings initialization failed: $e');
      }

      // Initialize buffer size from user settings
      try {
        final bufferPreset = _bufferSizeToPreset(_userSettings.bufferSize);
        _audioEngine!.setBufferSize(bufferPreset);
      } catch (e) {
        debugPrint('Buffer size setting failed: $e');
      }

      // Initialize output device from user settings
      if (_userSettings.preferredOutputDevice != null) {
        try {
          _audioEngine!.setAudioOutputDevice(_userSettings.preferredOutputDevice!);
        } catch (e) {
          debugPrint('Output device setting failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isAudioGraphInitialized = true;
        });
        _playbackController.setStatusMessage('Ready to record or load audio files');
      }

      // Initialize undo/redo manager with engine
      _undoRedoManager.initialize(_audioEngine!);

      // Initialize controllers with audio engine
      _playbackController.initialize(_audioEngine!);
      _recordingController.initialize(_audioEngine!);
      _recordingController.setLiveRecordingNotifier(liveRecordingNotifier);
      _recordingController.getFirstArmedMidiTrackId = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        for (final t in tracks) {
          if ((t.type == 'midi' || t.type == 'sampler') && t.armed) return t.id;
        }
        return selectedTrackId ?? 0;
      };
      _recordingController.getRecordingClipName = (trackId) => generateClipName(trackId);
      _recordingController.hasArmedAudioTracks = () {
        final tracks = mixerKey.currentState?.tracks ?? [];
        return tracks.any((t) => t.type == 'audio' && t.armed);
      };

      // Initialize VST3 editor service (for platform channel communication)
      VST3EditorService.initialize(_audioEngine!);

      // Initialize VST3 plugin manager
      _vst3PluginManager = Vst3PluginManager(_audioEngine!);
      _vst3PluginManager!.addListener(_onVst3ManagerChanged);

      // Initialize project manager
      _projectManager = ProjectManager(_audioEngine!);
      _projectManager!.addListener(_onProjectManagerChanged);

      // Initialize MIDI playback manager
      _midiPlaybackManager = MidiPlaybackManager(_audioEngine!);
      _midiPlaybackManager!.addListener(_onMidiPlaybackManagerChanged);

      // Initialize library preview service
      _libraryPreviewService = LibraryPreviewService(_audioEngine!);

      // Initialize MIDI clip controller with engine and manager
      _midiClipController.initialize(_audioEngine!, _midiPlaybackManager!);
      _midiClipController.setTempo(_recordingController.tempo);

      // Scan VST3 plugins after audio graph is ready
      if (!_vst3PluginManager!.isScanned && mounted) {
        _scanVst3Plugins();
      }

      // Load MIDI devices
      _loadMidiDevices();

      // Initialize auto-save service
      _autoSaveService.initialize(
        projectManager: _projectManager!,
        getUILayout: _getCurrentUILayout,
      );
      _autoSaveService.start();

      // Check for crash recovery
      _checkForCrashRecovery();
    } catch (e, _) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to initialize: $e';
        });
      }
    }
  }

  void _play() {
    // Clear automation preview values so display shows actual playback values
    if (_automationPreviewValues.isNotEmpty) {
      setState(() {
        _automationPreviewValues.clear();
      });
    }
    _playbackController.play(loadedClipId: _loadedClipId);
  }

  /// Play with loop check - used by transport bar play button
  void _playWithLoopCheck() {
    // Clear automation preview values so display shows actual playback values
    if (_automationPreviewValues.isNotEmpty) {
      setState(() {
        _automationPreviewValues.clear();
      });
    }
    if (_uiLayout.loopPlaybackEnabled) {
      _playLoopRegion();
    } else {
      _play();
    }
  }

  void _pause() {
    _playbackController.pause();
  }

  void _stopPlayback() {
    debugPrint('🛑 [DAW] _stopPlayback() called');
    debugPrint('🛑 [DAW]   isPlaying=${_playbackController.isPlaying}');
    debugPrint('🛑 [DAW]   isRecording=${_recordingController.isRecording}');
    debugPrint('🛑 [DAW]   playheadPosition=${_playbackController.playheadPosition.toStringAsFixed(3)}s');
    stopPlayback(); // Use mixin method which handles idle vs playing state
    // Reset mixer meters when playback stops
    _mixerKey.currentState?.resetMeters();
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
        _uiLayout.toggleLoopPlayback();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMetronome();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// Context-aware play/pause toggle (Space bar)
  /// - When loop is enabled: plays the loop region (cycling)
  /// - Otherwise: plays full arrangement
  void _togglePlayPause() {
    if (_isPlaying) {
      _pause();
    } else {
      _playWithLoopCheck();
    }
  }

  /// Play the loop region, cycling forever until stopped
  void _playLoopRegion() {
    // Get loop bounds from UI layout state
    final loopStart = _uiLayout.loopStartBeats;
    final loopEnd = _uiLayout.loopEndBeats;

    // Play with loop cycling enabled
    _playbackController.playLoop(
      loadedClipId: _loadedClipId,
      loopStartBeats: loopStart,
      loopEndBeats: loopEnd,
      tempo: _tempo,
    );
  }

  // M2: Recording methods - handled by DAWRecordingMixin
  // (toggleRecording, startRecording, stopRecording, handleRecordingComplete)

  void _toggleMetronome() {
    _recordingController.toggleMetronome();
    final newState = _recordingController.isMetronomeEnabled;
    _playbackController.setStatusMessage(newState ? 'Metronome enabled' : 'Metronome disabled');
  }

  void _setCountInBars(int bars) {
    _userSettings.countInBars = bars;
    _audioEngine?.setCountInBars(bars);

    final message = bars == 0
        ? 'Count-in disabled'
        : bars == 1
            ? 'Count-in: 1 bar'
            : 'Count-in: 2 bars';
    _playbackController.setStatusMessage(message);
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
    final oldBpm = _recordingController.tempo;
    if (oldBpm == bpm) return;

    final command = SetTempoCommand(
      newBpm: bpm,
      oldBpm: oldBpm,
      onTempoChanged: (newBpm) {
        // Get the current (old) tempo before we change it
        final currentTempo = _recordingController.tempo;

        _recordingController.setTempo(newBpm);
        _midiClipController.setTempo(newBpm);
        _midiCaptureBuffer.updateBpm(newBpm);
        _midiPlaybackManager?.rescheduleAllClips(newBpm);

        // Adjust audio clip positions to maintain their beat position
        // This prevents audio clips from visually shifting when tempo changes
        _timelineKey.currentState?.adjustAudioClipPositionsForTempoChange(currentTempo, newBpm);
      },
    );
    await _undoRedoManager.execute(command);
  }

  void _onTimeSignatureChanged(int beatsPerBar, int beatUnit) {
    setState(() {
      _projectMetadata = _projectMetadata.copyWith(
        timeSignatureNumerator: beatsPerBar,
        timeSignatureDenominator: beatUnit,
      );
    });
    // Update engine time signature
    _audioEngine?.setTimeSignature(beatsPerBar);
  }

  // M3: Virtual piano methods
  void _toggleVirtualPiano() {
    final success = _recordingController.toggleVirtualPiano();
    if (success) {
      _uiLayout.setVirtualPianoEnabled(enabled: _recordingController.isVirtualPianoEnabled);
      _playbackController.setStatusMessage(
        _recordingController.isVirtualPianoEnabled
            ? 'Virtual piano enabled - Press keys to play!'
            : 'Virtual piano disabled',
      );
    } else {
      _playbackController.setStatusMessage('Virtual piano error');
    }
  }

  // MIDI Device methods - delegate to RecordingController
  void _loadMidiDevices() {
    _recordingController.loadMidiDevices();
  }

  void _onMidiDeviceSelected(int deviceIndex) {
    _recordingController.selectMidiDevice(deviceIndex);

    // Show feedback
    if (_midiDevices.isNotEmpty && deviceIndex >= 0 && deviceIndex < _midiDevices.length) {
      final deviceName = _midiDevices[deviceIndex]['name'] as String? ?? 'Unknown';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎹 Selected: $deviceName'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _refreshMidiDevices() {
    _recordingController.refreshMidiDevices();
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
    if (!_uiLayout.isMixerVisible) {
      if (!_uiLayout.canShowMixer(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      _uiLayout.isMixerVisible = !_uiLayout.isMixerVisible;
      _userSettings.mixerVisible = _uiLayout.isMixerVisible;
    });
  }

  // Unified track selection method - handles both timeline and mixer clicks
  void _onTrackSelected(int? trackId, {bool isShiftHeld = false, bool autoSelectClip = false}) {
    if (trackId == null) {
      setState(() {
        _selectTrack(null);
        _uiLayout.isEditorPanelVisible = false;
      });
      return;
    }

    setState(() {
      _selectTrack(trackId, isShiftHeld: isShiftHeld);
      _uiLayout.isEditorPanelVisible = true;
    });

    // Try to find an existing clip for this track and select it
    // instead of clearing the clip selection (only for single selection)
    // When autoSelectClip is false (e.g., after instrument drop), don't auto-select clip
    if (!isShiftHeld && autoSelectClip) {
      final clipsForTrack = _midiPlaybackManager?.midiClips
          .where((c) => c.trackId == trackId)
          .toList();

      if (clipsForTrack != null && clipsForTrack.isNotEmpty) {
        // Select the first clip for this track
        final clip = clipsForTrack.first;
        _midiPlaybackManager?.selectClip(clip.clipId, clip);
      } else {
        // No clips for this track - clear selection
        _midiPlaybackManager?.selectClip(null, null);
      }
    } else if (!isShiftHeld && !autoSelectClip) {
      // Clear clip selection when autoSelectClip is false
      _midiPlaybackManager?.selectClip(null, null);
    }
  }

  /// Get the type of the currently selected track ("MIDI", "Audio", or "Master")
  String? _getSelectedTrackType() {
    if (_selectedTrackId == null || _audioEngine == null) return null;
    final info = _audioEngine!.getTrackInfo(_selectedTrackId!);
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
    if (_selectedTrackId == null || _audioEngine == null) return null;
    final info = _audioEngine!.getTrackInfo(_selectedTrackId!);
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
      _selectedAudioClip = clip;
      if (clip != null) {
        // Also select the track that contains this clip
        _selectedTrackId = clip.trackId;
        _uiLayout.isEditorPanelVisible = true;
        // Clear MIDI clip selection
        _midiPlaybackManager?.selectClip(null, null);
      }
    });
  }

  /// Handle audio clip updates from Audio Editor
  void _onAudioClipUpdated(ClipData clip) {
    setState(() {
      _selectedAudioClip = clip;
    });

    // Update the clip in the timeline view so waveform reflects gain changes
    _timelineKey.currentState?.updateClip(clip);

    // Auto-update arrangement loop region to follow content
    _updateArrangementLoopToContent();
  }

  // M9: Instrument methods
  void _onInstrumentSelected(int trackId, String instrumentId) {
    // Create default instrument data for the track
    final instrumentData = InstrumentData.defaultSynthesizer(trackId);
    _trackController.setTrackInstrument(trackId, instrumentData);
    _trackController.selectTrack(trackId);
    _uiLayout.isEditorPanelVisible = true;

    // Auto-populate track name if not user-edited
    if (!_trackController.isTrackNameUserEdited(trackId)) {
      _audioEngine?.setTrackName(trackId, 'Synthesizer');
    }

    // Call audio engine to set instrument
    if (_audioEngine != null) {
      _audioEngine!.setTrackInstrument(trackId, instrumentId);
    }
  }

  void _onTrackDeleted(int trackId) {
    // Remove all MIDI clips for this track via manager
    _midiPlaybackManager?.removeClipsForTrack(trackId);

    // Remove track state from controller
    _trackController.onTrackDeleted(trackId);

    // Refresh timeline immediately
    _refreshTrackWidgets();
  }

  void _onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy track state via controller
    _trackController.onTrackDuplicated(sourceTrackId, newTrackId);
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

    _midiPlaybackManager?.addRecordedClip(defaultClip);
  }

  /// Called when a track is created from the mixer panel - refresh timeline immediately
  void _onTrackCreatedFromMixer(int trackId, String trackType) {
    _onTrackSelected(trackId);
    _refreshTrackWidgets();
  }

  /// Called when tracks are reordered via drag-and-drop in the mixer panel
  void _onTrackReordered(int oldIndex, int newIndex) {
    // Update shared track order in TrackController
    _trackController.reorderTrack(oldIndex, newIndex);
    // Refresh timeline to match new track order
    _refreshTrackWidgets();
  }

  Future<void> _onInstrumentDroppedOnEmpty(Instrument instrument) async {
    if (_audioEngine == null) return;

    // Handle Sampler instrument separately
    if (instrument.id == 'sampler') {
      // Create empty sampler track (no sample loaded yet)
      final trackId = _audioEngine!.createTrack('sampler', 'Sampler');
      if (trackId < 0) return;

      // Initialize sampler for the track
      _audioEngine!.createSamplerForTrack(trackId);

      _refreshTrackWidgets();
      _selectTrack(trackId);
      return;
    }

    // Create a new MIDI track for Synthesizer (and other instruments)
    final command = CreateTrackCommand(
      trackType: 'midi',
      trackName: 'MIDI',
    );

    await _undoRedoManager.execute(command);

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
    _refreshTrackWidgets();

    // Disarm other MIDI tracks (exclusive arm for new track)
    _disarmOtherMidiTracks(trackId);
  }

  // VST3 Instrument drop handlers
  Future<void> _onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (_audioEngine == null) return;

    try {
      // Load the VST3 plugin as a track instrument
      final effectId = _audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      _trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name if not user-edited
      if (!_trackController.isTrackNameUserEdited(trackId)) {
        _audioEngine?.setTrackName(trackId, plugin.name);
      }

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = _audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || _audioEngine == null) return;
        _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });
    } catch (e) {
      debugPrint('Failed to preview VST3 instrument: $e');
    }
  }

  Future<void> _onVst3InstrumentDroppedOnEmpty(Vst3Plugin plugin) async {
    if (_audioEngine == null) return;

    try {
      // Create a new MIDI track using UndoRedoManager
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'MIDI',
      );

      await _undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // Create default 4-bar empty clip for the new track
      _createDefaultMidiClip(trackId);

      // Load the VST3 plugin as a track instrument
      final effectId = _audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      _trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name (new track, so not user-edited)
      _audioEngine?.setTrackName(trackId, plugin.name);

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = _audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || _audioEngine == null) return;
        _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });

      // Select the newly created track but NOT the clip (so Instrument tab shows)
      _onTrackSelected(trackId, autoSelectClip: false);

      // Immediately refresh track widgets so the new track appears instantly
      _refreshTrackWidgets();

      // Disarm other MIDI tracks (exclusive arm for new track)
      _disarmOtherMidiTracks(trackId);
    } catch (e) {
      debugPrint('Failed to create VST3 instrument track: $e');
    }
  }

  // Audio file drop handler - creates new audio track with clip
  Future<void> _onAudioFileDroppedOnEmpty(String filePath) async {
    if (_audioEngine == null) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

      // 2. Create new audio track
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Audio',
      );

      await _undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // 3. Load audio file to the newly created track
      final clipId = _audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      // 4. Get clip info
      final duration = _audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = _audioEngine!.getWaveformPeaks(clipId, peakResolution);

      // 5. Add to timeline view's clip list
      _timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: finalPath, // Use the copied path
        startTime: 0.0,
        duration: duration,
        waveformPeaks: peaks,
      ));

      // 6. Select the newly created clip (opens Audio Editor)
      _timelineKey.currentState?.selectAudioClip(clipId);

      // 7. Refresh track widgets
      _refreshTrackWidgets();
    } catch (e) {
      debugPrint('Failed to add audio file to new track: $e');
    }
  }

  // Audio file drop handler - adds clip to existing audio track (with undo support)
  Future<void> _onAudioFileDroppedOnTrack(int trackId, String filePath, double startTimeBeats) async {
    if (_audioEngine == null) return;

    // Defensive check: only allow audio file drops on audio tracks (not MIDI tracks)
    if (_isMidiTrack(trackId)) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

      // 2. Convert beats to seconds (audio clips use seconds)
      final startTimeSeconds = startTimeBeats * 60.0 / _tempo;

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
          _timelineKey.currentState?.addClip(ClipData(
            clipId: clipId,
            trackId: trackId,
            filePath: finalPath,
            startTime: startTimeSeconds,
            duration: duration,
            waveformPeaks: peaks,
          ));
          // Select the newly created clip (opens Audio Editor)
          _timelineKey.currentState?.selectAudioClip(clipId);
        },
        onClipRemoved: (clipId) {
          // Remove from timeline view (undo)
          _timelineKey.currentState?.removeClip(clipId);
        },
      );

      await _undoRedoManager.execute(command);

      // 5. Refresh track widgets
      _refreshTrackWidgets();
    } catch (e) {
      debugPrint('Failed to add audio file to track: $e');
    }
  }

  // Drag-to-create handlers
  Future<void> _onCreateTrackWithClip(String trackType, double startBeats, double durationBeats) async {
    if (_audioEngine == null) return;

    try {
      // Create new track
      final command = CreateTrackCommand(
        trackType: trackType,
        trackName: trackType == 'midi' ? 'MIDI' : 'Audio',
      );

      await _undoRedoManager.execute(command);

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
      _refreshTrackWidgets();

      // Disarm other MIDI tracks when creating new MIDI track (exclusive arm)
      if (trackType == 'midi') {
        _disarmOtherMidiTracks(trackId);
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
        _midiPlaybackManager?.addRecordedClip(newClip);
        _midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId, tId) {
        _midiClipController.deleteClip(clipId, tId);
        if (mounted) setState(() {});
      },
    );
    _undoRedoManager.execute(command);
  }

  /// Capture MIDI from the buffer and create a clip
  Future<void> _captureMidi() async {
    if (_audioEngine == null) return;

    // Check if we have a selected track
    if (_selectedTrackId == null) {
      _playbackController.setStatusMessage('Please select a MIDI track first');
      return;
    }

    // Show capture dialog
    final capturedEvents = await CaptureMidiDialog.show(context, _midiCaptureBuffer);

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
      _playbackController.setStatusMessage('No complete MIDI notes captured');
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
      trackId: _selectedTrackId!,
      startTime: _playheadPosition / 60.0 * _tempo, // Current playhead position in beats
      duration: clipDuration,
      loopLength: clipDuration,
      name: _generateClipName(_selectedTrackId!),
      notes: notes,
    );

    _midiPlaybackManager?.addRecordedClip(clip);
    _playbackController.setStatusMessage('Captured ${notes.length} MIDI notes');
  }

  // Library double-click handlers
  void _handleLibraryItemDoubleClick(LibraryItem item) {
    if (_audioEngine == null) return;

    final selectedTrack = _selectedTrackId;
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

      case LibraryItemType.folder:
        // Folders are not double-clickable for adding
        break;
    }
  }

  void _handleVst3DoubleClick(Vst3Plugin plugin) {
    if (_audioEngine == null) return;

    final selectedTrack = _selectedTrackId;
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
    if (_audioEngine == null) return;

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
    if (_audioEngine == null) return;

    // Generate track name based on sample name
    final trackName = 'Sampler: ${_truncateName(sampleName, 20)}';

    // Create Sampler track type
    final trackId = _audioEngine!.createTrack('sampler', trackName);
    if (trackId < 0) {
      _showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = _audioEngine!.createSamplerForTrack(trackId);
    if (samplerId < 0) {
      _showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = _audioEngine!.loadSampleForTrack(trackId, filePath, 60);
    if (!success) {
      _showSnackBar('Failed to load sample');
      return;
    }

    // Refresh track list and select the new track
    _refreshTrackWidgets();
    _selectTrack(trackId);

    _showSnackBar('Created sampler with "${_truncateName(sampleName, 30)}"');
  }

  /// Convert an Audio track to a Sampler track
  /// Takes the first audio clip on the track and uses it as the sample
  /// Creates MIDI notes at the position/duration of each audio clip
  void _convertAudioTrackToSampler(int trackId) {
    if (_audioEngine == null) return;

    // Get audio clips on this track
    final audioClips = _timelineKey.currentState?.getAudioClipsOnTrack(trackId);
    if (audioClips == null || audioClips.isEmpty) {
      _showSnackBar('No audio clips on track to convert');
      return;
    }

    // Get the first clip's file path (we'll use this as the sample)
    final firstClip = audioClips.first;
    final samplePath = firstClip.filePath;
    if (samplePath == null || samplePath.isEmpty) {
      _showSnackBar('Audio clip has no file path');
      return;
    }

    // Get track name for the new sampler track
    final trackName = _getTrackName(trackId) ?? 'Sampler';
    final samplerTrackName = trackName.startsWith('Sampler:')
        ? trackName
        : 'Sampler: $trackName';

    // Create Sampler track
    final samplerTrackId = _audioEngine!.createTrack('sampler', samplerTrackName);
    if (samplerTrackId < 0) {
      _showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = _audioEngine!.createSamplerForTrack(samplerTrackId);
    if (samplerId < 0) {
      _showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = _audioEngine!.loadSampleForTrack(samplerTrackId, samplePath, 60);
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
      final clipId = _audioEngine!.createMidiClip();
      if (clipId < 0) continue;

      // Add the MIDI note to the clip
      // Note: note starts at 0.0 relative to the clip, duration = clip duration
      _audioEngine!.addMidiNoteToClip(
        clipId,
        midiNote,
        100, // velocity
        0.0, // note starts at beginning of clip
        duration, // note duration = clip duration
      );

      // Add the clip to the sampler track at the correct position
      _audioEngine!.addMidiClipToTrack(samplerTrackId, clipId, startTime);
    }

    // Refresh tracks and select the new sampler track
    _refreshTrackWidgets();
    _selectTrack(samplerTrackId);

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
    final info = _audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    // Engine returns 'MIDI' (uppercase)
    return parts[2].toLowerCase() == 'midi';
  }

  // Helper: Check if track is an empty Audio track (no clips)
  bool _isEmptyAudioTrack(int trackId) {
    final info = _audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    // Engine returns 'Audio' (capitalized)
    final trackType = parts[2].toLowerCase();
    if (trackType != 'audio') return false;

    // Check if any clips are on this track
    final hasClips = _timelineKey.currentState?.hasClipsOnTrack(trackId) ?? false;
    return !hasClips;
  }

  // Helper: Get track name by ID
  String? _getTrackName(int trackId) {
    final info = _audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return null;

    final parts = info.split(',');
    if (parts.length < 2) return null;

    return parts[1];
  }

  // Helper: Generate clip name for a track using instrument or track name
  String _generateClipName(int trackId) {
    final instrument = _trackInstruments[trackId];
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
    if (!_userSettings.copySamplesToProject || _projectManager?.currentPath == null) {
      return originalPath;
    }

    try {
      final projectPath = _projectManager!.currentPath!;
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
    if (_audioEngine == null) return;

    try {
      // Copy sample to project folder if setting is enabled
      final finalPath = await _prepareSamplePath(filePath);

      final clipId = _audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      final duration = _audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec) - LOD downsampling happens at render time
      final peakResolution = (duration * 8000).clamp(8000, 240000).toInt();
      final peaks = _audioEngine!.getWaveformPeaks(clipId, peakResolution);

      _timelineKey.currentState?.addClip(ClipData(
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
    if (_audioEngine == null) return;

    try {
      final effectId = _audioEngine!.addEffectToTrack(trackId, effectType);
      if (effectId >= 0) {
        setState(() {
          _statusMessage = 'Added $effectType to track';
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
    _trackController.setTrackInstrument(instrumentData.trackId, instrumentData);
  }

  // M10: VST3 Plugin methods - delegating to Vst3PluginManager

  Future<void> _scanVst3Plugins({bool forceRescan = false}) async {
    if (_vst3PluginManager == null) return;

    setState(() {
      _statusMessage = forceRescan ? 'Rescanning VST3 plugins...' : 'Scanning VST3 plugins...';
    });

    final result = await _vst3PluginManager!.scanPlugins(forceRescan: forceRescan);

    if (mounted) {
      setState(() {
        _statusMessage = result;
      });
    }
  }

  void _addVst3PluginToTrack(int trackId, Map<String, String> plugin) {
    if (_vst3PluginManager == null) return;

    final result = _vst3PluginManager!.addToTrack(trackId, plugin);

    setState(() {
      _statusMessage = result.message;
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
    if (_vst3PluginManager == null) return;

    final result = _vst3PluginManager!.removeFromTrack(effectId);

    setState(() {
      _statusMessage = result.message;
    });
  }

  Future<void> _showVst3PluginBrowser(int trackId) async {
    if (_vst3PluginManager == null) return;

    final vst3Browser = await showVst3PluginBrowser(
      context,
      availablePlugins: _vst3PluginManager!.availablePlugins,
      isScanning: _vst3PluginManager!.isScanning,
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
    if (_vst3PluginManager == null) return;
    _vst3PluginManager!.addPluginToTrack(trackId, plugin);
  }

  Map<int, int> _getTrackVst3PluginCounts() {
    return _vst3PluginManager?.getTrackPluginCounts() ?? {};
  }

  List<Vst3PluginInstance> _getTrackVst3Plugins(int trackId) {
    return _vst3PluginManager?.getTrackPlugins(trackId) ?? [];
  }

  void _onVst3ParameterChanged(int effectId, int paramIndex, double value) {
    _vst3PluginManager?.updateParameter(effectId, paramIndex, value);
  }

  void _showVst3PluginEditor(int trackId) {
    if (_vst3PluginManager == null) return;

    final effectIds = _vst3PluginManager!.getTrackEffectIds(trackId);
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
              final pluginInfo = _vst3PluginManager!.getPluginInfo(effectId);
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
    if (_uiLayout.isLibraryPanelCollapsed) {
      if (!_uiLayout.canShowLibrary(windowWidth)) {
        return; // Not enough room - do nothing
      }
    }

    setState(() {
      _uiLayout.isLibraryPanelCollapsed = !_uiLayout.isLibraryPanelCollapsed;
      _userSettings.libraryCollapsed = _uiLayout.isLibraryPanelCollapsed;
    });
  }

  void _toggleEditor() {
    setState(() {
      _uiLayout.isEditorPanelVisible = !_uiLayout.isEditorPanelVisible;
      _userSettings.editorVisible = _uiLayout.isEditorPanelVisible;
    });
  }

  void _resetPanelLayout() {
    setState(() {
      // Reset to default panel sizes and visibility
      _uiLayout.resetLayout();

      // Save reset states
      _userSettings.libraryCollapsed = false;
      _userSettings.mixerVisible = true;
      _userSettings.editorVisible = true;

      _statusMessage = 'Panel layout reset';
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
    final trackId = _midiClipController.selectClip(clipId, clipData);
    if (clipId != null && clipData != null) {
      // Don't auto-open editor panel - let user control visibility via View menu or double-click
      _selectedTrackId = trackId ?? clipData.trackId;
    }
  }

  void _onMidiClipUpdated(MidiClipData updatedClip) {
    _midiClipController.updateClip(updatedClip, _playheadPosition);

    // Propagate changes to all linked clips (same patternId)
    _midiPlaybackManager?.updateLinkedClips(updatedClip, _tempo);

    // Auto-update arrangement loop region to follow content
    _updateArrangementLoopToContent();
  }

  /// Auto-update arrangement loop region to follow the longest clip.
  /// Only active when loopAutoFollow is true (disabled when user manually drags loop).
  void _updateArrangementLoopToContent() {
    if (!_uiLayout.loopAutoFollow) return;

    double longestEnd = 4.0; // Minimum 1 bar (4 beats)

    // Check all MIDI clips
    final midiClips = _midiPlaybackManager?.midiClips ?? [];
    for (final clip in midiClips) {
      final clipEnd = clip.startTime + clip.duration;
      if (clipEnd > longestEnd) longestEnd = clipEnd;
    }

    // Check all audio clips (stored in timeline state)
    final audioClips = _timelineKey.currentState?.clips ?? [];
    for (final clip in audioClips) {
      // Audio clips use seconds, convert to beats
      final beatsPerSecond = _tempo / 60.0;
      final clipEndBeats = (clip.startTime + clip.duration) * beatsPerSecond;
      if (clipEndBeats > longestEnd) longestEnd = clipEndBeats;
    }

    // Round to next bar (4 beats)
    final newLoopEnd = (longestEnd / 4).ceil() * 4.0;

    // Only update if changed (avoids unnecessary rebuilds)
    if (newLoopEnd != _uiLayout.loopEndBeats) {
      _uiLayout.setLoopRegion(_uiLayout.loopStartBeats, newLoopEnd);
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
          _midiPlaybackManager?.updateClipInPlace(updatedOriginal);
        }

        // Add new clip to manager and schedule for playback
        _midiPlaybackManager?.addRecordedClip(newClip);
        _midiClipController.updateClip(newClip, _playheadPosition);
        // Select the new clip
        _midiPlaybackManager?.selectClip(newClip.clipId, newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Find the clip to get track ID
        final clip = _midiPlaybackManager?.midiClips.firstWhere(
          (c) => c.clipId == clipId,
          orElse: () => sourceClip,
        );
        _midiClipController.deleteClip(clipId, clip?.trackId ?? sourceClip.trackId);
        if (mounted) setState(() {});
      },
    );
    _undoRedoManager.execute(command);
  }

  void _onAudioClipCopied(ClipData sourceClip, double newStartTime) {
    final command = DuplicateAudioClipCommand(
      originalClip: sourceClip,
      newStartTime: newStartTime,
      onClipDuplicated: (newClip) {
        // Add to timeline view's clip list
        _timelineKey.currentState?.addClip(newClip);
        if (mounted) setState(() {});
      },
      onClipRemoved: (clipId) {
        // Remove from timeline view's clip list
        _timelineKey.currentState?.removeClip(clipId);
        if (mounted) setState(() {});
      },
    );
    _undoRedoManager.execute(command);
  }

  void _duplicateSelectedClip() {
    final clip = _midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    _onMidiClipCopied(clip, newStartTime);
  }

  void _splitSelectedClipAtPlayhead() {
    // Split at playhead position
    final splitPosition = _playheadPosition;

    // Try MIDI clip first
    if (_midiPlaybackManager?.selectedClipId != null) {
      final success = _midiClipController.splitSelectedClipAtPlayhead(splitPosition);
      if (success && mounted) {
        setState(() {
          _statusMessage = 'Split MIDI clip at playhead';
        });
        return;
      }
    }

    // Try audio clip if no MIDI clip or MIDI split failed
    final audioSplit = _timelineKey.currentState?.splitSelectedAudioClipAtPlayhead(splitPosition) ?? false;
    if (audioSplit && mounted) {
      setState(() {
        _statusMessage = 'Split audio clip at playhead';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        _statusMessage = 'Cannot split: select a clip and place playhead within it';
      });
    }
  }

  void _quantizeSelectedClip() {
    // Default grid size: 1 beat (quarter note)
    const gridSizeBeats = 1.0;
    final beatsPerSecond = _tempo / 60.0;
    final gridSizeSeconds = gridSizeBeats / beatsPerSecond;

    // Try MIDI clip first
    if (_midiPlaybackManager?.selectedClipId != null) {
      final success = _midiClipController.quantizeSelectedClip(gridSizeBeats);
      if (success && mounted) {
        setState(() {
          _statusMessage = 'Quantized MIDI clip to grid';
        });
        return;
      }
    }

    // Try audio clip
    final audioQuantized = _timelineKey.currentState?.quantizeSelectedAudioClip(gridSizeSeconds) ?? false;
    if (audioQuantized && mounted) {
      setState(() {
        _statusMessage = 'Quantized audio clip to grid';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        _statusMessage = 'Cannot quantize: select a clip first';
      });
    }
  }

  /// Select all clips in the timeline view
  void _selectAllClips() {
    _timelineKey.currentState?.selectAllClips();
    if (mounted) {
      setState(() {
        _statusMessage = 'Selected all clips';
      });
    }
  }

  /// Bounce MIDI to Audio - renders MIDI through instrument to audio file
  /// NOTE: This is a placeholder that shows planned feature message.
  /// Full implementation requires Rust-side single-track offline rendering.
  void _bounceMidiToAudio() {
    final selectedClipId = _midiPlaybackManager?.selectedClipId;
    final selectedClip = _midiPlaybackManager?.currentEditingClip;

    if (selectedClipId == null || selectedClip == null) {
      setState(() {
        _statusMessage = 'Select a MIDI clip to bounce to audio';
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
    final timelineState = _timelineKey.currentState;
    if (timelineState == null) return;

    // Get selected MIDI clips
    final selectedMidiClips = timelineState.selectedMidiClips;

    if (selectedMidiClips.length < 2) {
      setState(() {
        _statusMessage = 'Select 2 or more MIDI clips to consolidate';
      });
      return;
    }

    // Ensure all clips are on the same track
    final trackIds = selectedMidiClips.map((c) => c.trackId).toSet();
    if (trackIds.length > 1) {
      setState(() {
        _statusMessage = 'Cannot consolidate clips from different tracks';
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
      _midiClipController.deleteClip(clip.clipId, clip.trackId);
    }

    // Add consolidated clip
    _midiClipController.addClip(consolidatedClip);
    _midiClipController.updateClip(consolidatedClip, _playheadPosition);

    // Select the new consolidated clip
    _midiPlaybackManager?.selectClip(consolidatedClip.clipId, consolidatedClip);
    timelineState.clearClipSelection();

    setState(() {
      _statusMessage = 'Consolidated ${sortedClips.length} clips into one';
    });
  }

  void _deleteMidiClip(int clipId, int trackId) {
    // Find the clip data for undo
    final clip = _midiPlaybackManager?.midiClips.firstWhere(
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
        _midiClipController.deleteClip(cId, tId);
        if (mounted) setState(() {});
      },
      onClipRestored: (restoredClip) {
        _midiPlaybackManager?.addRecordedClip(restoredClip);
        _midiClipController.updateClip(restoredClip, _playheadPosition);
        _midiPlaybackManager?.selectClip(restoredClip.clipId, restoredClip);
        if (mounted) setState(() {});
      },
    );
    _undoRedoManager.execute(command);
  }

  /// Batch delete multiple MIDI clips (eraser tool - single undo action)
  void _deleteMidiClipsBatch(List<(int clipId, int trackId)> clipsToDelete) {
    if (clipsToDelete.isEmpty) return;

    // Build individual delete commands for each clip
    final commands = <Command>[];
    for (final (clipId, trackId) in clipsToDelete) {
      final clip = _midiPlaybackManager?.midiClips.firstWhere(
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
            _midiClipController.deleteClip(cId, tId);
          },
          onClipRestored: (restoredClip) {
            _midiPlaybackManager?.addRecordedClip(restoredClip);
            _midiClipController.updateClip(restoredClip, _playheadPosition);
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
    _undoRedoManager.execute(compositeCommand);
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
          _timelineKey.currentState?.removeClip(clipId);
        },
        onClipRestored: (restoredClip) {
          // Restore to timeline view's clip list
          // (Engine restoration is handled by the command's undo method)
          _timelineKey.currentState?.addClip(restoredClip);
        },
      ));
    }

    if (commands.isEmpty) return;

    // Wrap in CompositeCommand for single undo action
    final compositeCommand = CompositeCommand(
      commands,
      'Delete ${clipsToDelete.length} audio clip${clipsToDelete.length > 1 ? 's' : ''}',
    );
    _undoRedoManager.execute(compositeCommand);
    if (mounted) setState(() {});
  }

  // ========================================================================
  // Undo/Redo methods
  // ========================================================================

  Future<void> _performUndo() async {
    final success = await _undoRedoManager.undo();
    if (success && mounted) {
      setState(() {
        _statusMessage = 'Undo - ${_undoRedoManager.redoDescription ?? "Action"}';
      });
      _refreshTrackWidgets();
    }
  }

  Future<void> _performRedo() async {
    final success = await _undoRedoManager.redo();
    if (success && mounted) {
      setState(() {
        _statusMessage = 'Redo - ${_undoRedoManager.undoDescription ?? "Action"}';
      });
      _refreshTrackWidgets();
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
              if (_isPlaying) {
                _stopPlayback();
              }

              // Clear all tracks from the audio engine
              _audioEngine?.clearAllTracks();

              // Reset project manager state
              _projectManager?.newProject();
              _midiPlaybackManager?.clear();
              _undoRedoManager.clear();

              // Reset loop auto-follow for new project
              _uiLayout.resetLoopAutoFollow();

              // Clear automation data
              _automationController.clear();

              // Clear window title (back to just "Boojy Audio")
              WindowTitleService.clearProjectName();

              // Refresh track widgets to show empty state (clear clips too)
              _refreshTrackWidgets(clearClips: true);

              setState(() {
                _loadedClipId = null;
                _waveformPeaks = [];
                _statusMessage = 'New project created';
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

        setState(() => _isLoading = true);

        // Load via project manager
        final loadResult = await _projectManager!.loadProject(path);

        // Clear MIDI clip ID mappings since Rust side has reset
        _midiPlaybackManager?.clearClipIdMappings();
        _undoRedoManager.clear();

        // Restore MIDI clips from engine for UI display
        _midiPlaybackManager?.restoreClipsFromEngine(_tempo);

        // Apply UI layout if available
        if (loadResult.uiLayout != null) {
          _applyUILayout(loadResult.uiLayout!);
        }

        // Refresh track widgets to show loaded tracks
        _refreshTrackWidgets();

        // Add to recent projects
        _userSettings.addRecentProject(path, _projectManager!.currentName);

        // Update window title and metadata with project name
        WindowTitleService.setProjectName(_projectManager!.currentName);

        setState(() {
          _projectMetadata = _projectMetadata.copyWith(name: _projectManager!.currentName);
          _statusMessage = 'Project loaded: ${_projectManager!.currentName}';
          _isLoading = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadResult.result.message)),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
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
      _userSettings.removeRecentProject(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project no longer exists')),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      // Load via project manager
      final loadResult = await _projectManager!.loadProject(path);

      // Clear MIDI clip ID mappings since Rust side has reset
      _midiPlaybackManager?.clearClipIdMappings();
      _undoRedoManager.clear();

      // Restore MIDI clips from engine for UI display
      _midiPlaybackManager?.restoreClipsFromEngine(_tempo);

      // Apply UI layout if available
      if (loadResult.uiLayout != null) {
        _applyUILayout(loadResult.uiLayout!);
      }

      // Refresh track widgets to show loaded tracks
      _refreshTrackWidgets();

      // Update recent projects (moves to top)
      _userSettings.addRecentProject(path, _projectManager!.currentName);

      // Update window title and metadata with project name
      WindowTitleService.setProjectName(_projectManager!.currentName);

      setState(() {
        _projectMetadata = _projectMetadata.copyWith(name: _projectManager!.currentName);
        _statusMessage = 'Project loaded: ${_projectManager!.currentName}';
        _isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loadResult.result.message)),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  /// Build the Open Recent submenu items
  List<PlatformMenuItem> _buildRecentProjectsMenu() {
    final recent = _userSettings.recentProjects;

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
              _userSettings.clearRecentProjects();
              setState(() {});
            },
          ),
        ],
      ),
    ];
  }

  Future<void> _saveProject() async {
    if (_projectManager?.currentPath != null) {
      _saveProjectToPath(_projectManager!.currentPath!);
    } else {
      _saveProjectAs();
    }
  }

  Future<void> _saveProjectAs() async {
    // Show dialog to enter project name
    final nameController = TextEditingController(text: _projectManager?.currentName ?? 'Untitled');

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
    _projectManager?.setProjectName(projectName);
    WindowTitleService.setProjectName(projectName);
    setState(() {
      _projectMetadata = _projectMetadata.copyWith(name: projectName);
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
    setState(() => _isLoading = true);

    final result = await _projectManager!.saveProjectToPath(path, _getCurrentUILayout());

    // Add to recent projects on successful save
    if (result.success) {
      _userSettings.addRecentProject(path, _projectManager!.currentName);
    }

    setState(() {
      _statusMessage = result.success ? 'Project saved' : result.message;
      _isLoading = false;
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
      _uiLayout.applyLayout(layout);
    });

    // Restore view state if "continue where I left off" is enabled
    if (_userSettings.continueWhereLeftOff && layout.viewState != null) {
      _restoreViewState(layout.viewState!);
    }

    // Restore audio clips if available
    if (layout.audioClips != null && layout.audioClips!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final timelineState = _timelineKey.currentState;
        if (timelineState != null) {
          timelineState.restoreAudioClips(layout.audioClips!);
        }
      });
    }

    // Restore automation data if available
    _automationController.loadFromJson(layout.automationData);

    // Sync all volume automation lanes to engine
    _syncAllVolumeAutomationToEngine();
  }

  /// Sync all volume automation lanes to engine (called on project load)
  void _syncAllVolumeAutomationToEngine() {
    if (_audioEngine == null) return;
    for (final trackId in _automationController.allTrackIds) {
      _syncVolumeAutomationToEngine(trackId);
    }
  }

  /// Restore view state (zoom, scroll, panels, playhead)
  void _restoreViewState(ProjectViewState viewState) {
    // Need to wait for next frame so timeline widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timelineState = _timelineKey.currentState;

      if (timelineState != null) {
        // Restore zoom and scroll
        timelineState.setPixelsPerBeat(viewState.zoom);
        timelineState.setScrollOffset(viewState.horizontalScroll);
      }

      // Restore panel visibility
      setState(() {
        _uiLayout.isLibraryPanelCollapsed = !viewState.libraryVisible;
        _uiLayout.isMixerVisible = viewState.mixerVisible;
        _uiLayout.isEditorPanelVisible = viewState.editorVisible;
        _uiLayout.isVirtualPianoEnabled = viewState.virtualPianoVisible;
      });

      // Restore selected track
      if (viewState.selectedTrackId != null) {
        _selectedTrackId = viewState.selectedTrackId;
      }

      // Restore playhead position
      _playheadPosition = viewState.playheadPosition;
    });
  }

  /// Get current UI layout for saving
  UILayoutData _getCurrentUILayout() {
    // Only save view state if "continue where I left off" is enabled
    ProjectViewState? viewState;
    if (_userSettings.continueWhereLeftOff) {
      // Access timeline view state through GlobalKey
      final timelineState = _timelineKey.currentState;

      viewState = ProjectViewState(
        horizontalScroll: timelineState?.scrollOffset ?? 0.0,
        verticalScroll: 0.0, // Not tracked in timeline view
        zoom: timelineState?.pixelsPerBeat ?? 25.0,
        libraryVisible: !_uiLayout.isLibraryPanelCollapsed,
        mixerVisible: _uiLayout.isMixerVisible,
        editorVisible: _uiLayout.isEditorPanelVisible,
        virtualPianoVisible: _uiLayout.isVirtualPianoEnabled,
        selectedTrackId: _selectedTrackId,
        playheadPosition: _playheadPosition,
      );
    }

    // Get audio clips from timeline for persistence
    final timelineState = _timelineKey.currentState;
    final audioClips = timelineState?.clips.toList();

    return UILayoutData(
      libraryWidth: _uiLayout.libraryPanelWidth,
      mixerWidth: _uiLayout.mixerPanelWidth,
      bottomHeight: _uiLayout.editorPanelHeight,
      libraryCollapsed: _uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !_uiLayout.isMixerVisible,
      bottomCollapsed: !(_uiLayout.isEditorPanelVisible || _uiLayout.isVirtualPianoEnabled),
      viewState: viewState,
      audioClips: audioClips,
      automationData: _automationController.toJson(),
    );
  }

  /// Check for crash recovery backup on startup
  Future<void> _checkForCrashRecovery() async {
    try {
      final backupPath = await _autoSaveService.checkForRecovery();
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
        final result = await _projectManager?.loadProject(backupPath);
        if (result?.result.success == true) {
          // Clear and restore MIDI clips from engine for UI display
          _midiPlaybackManager?.clearClipIdMappings();
          _midiPlaybackManager?.restoreClipsFromEngine(_tempo);

          setState(() {
            _statusMessage = 'Recovered from backup';
          });
          _refreshTrackWidgets();

          // Apply UI layout if available
          if (result?.uiLayout != null) {
            _applyUILayout(result!.uiLayout!);
          }
        }
      }

      // Clear the recovery marker regardless of choice
      await _autoSaveService.clearRecoveryMarker();
    } catch (e) {
      debugPrint('Failed to check for crash recovery: $e');
    }
  }

  void _exportAudio() {
    if (_audioEngine == null) return;

    ExportDialog.show(
      context,
      audioEngine: _audioEngine!,
      defaultName: _projectManager?.currentName ?? 'Untitled',
    );
  }

  /// Quick export MP3 using last saved settings
  Future<void> _quickExportMp3() async {
    if (_audioEngine == null) return;

    try {
      final baseName = _projectManager?.currentName ?? 'Untitled';

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
      final bitrate = _userSettings.exportMp3Bitrate;
      final sampleRate = _userSettings.exportSampleRate;
      final normalize = _userSettings.exportNormalize;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting MP3...')),
        );
      }

      final resultJson = _audioEngine!.exportMp3WithOptions(
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
    if (_audioEngine == null) return;

    try {
      final baseName = _projectManager?.currentName ?? 'Untitled';

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
      final bitDepth = _userSettings.exportWavBitDepth;
      final sampleRate = _userSettings.exportSampleRate;
      final normalize = _userSettings.exportNormalize;
      final dither = _userSettings.exportDither;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Exporting WAV...')),
        );
      }

      final resultJson = _audioEngine!.exportWavWithOptions(
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
    if (_projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save project first before creating a new version')),
        );
      }
      return;
    }

    try {
      final currentPath = _projectManager!.currentPath!;
      final currentName = _projectManager!.currentName;
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

      setState(() => _isLoading = true);

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
      _projectManager!.setProjectName(newVersionName);
      await _projectManager!.saveProjectToPath(newVersionPath, _getCurrentUILayout());

      // Update UI
      setState(() {
        _projectMetadata = _projectMetadata.copyWith(name: newVersionName);
        _isLoading = false;
      });

      // Update window title
      WindowTitleService.setProjectName(newVersionName);

      // Add to recent projects
      await _userSettings?.addRecentProject(newVersionPath, newVersionName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created new version: $newVersionName')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create new version: $e')),
        );
      }
    }
  }

  Future<void> _renameProject() async {
    if (_projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save project first before renaming')),
        );
      }
      return;
    }

    final currentName = _projectManager!.currentName;
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
      final currentPath = _projectManager!.currentPath!;

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
        _projectManager!.setProjectName(newName);

        // Save project to update internal metadata with new name
        await _projectManager!.saveProjectToPath(newPath, _getCurrentUILayout());

        // Update UI
        setState(() {
          _projectMetadata = _projectMetadata.copyWith(name: newName);
        });

        // Update window title
        WindowTitleService.setProjectName(newName);

        // Update recent projects: remove old path, add new path
        await _userSettings.removeRecentProject(currentPath);
        await _userSettings.addRecentProject(newPath, newName);

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
    if (_audioEngine == null) {
      for (int i = 0; i < 20 && _audioEngine == null && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!mounted) return;

    await AppSettingsDialog.show(context, _userSettings, audioEngine: _audioEngine);
  }

  Future<void> _openProjectSettings() async {
    // Initialize version manager if needed
    final projectPath = _projectManager?.currentPath;
    if (projectPath != null) {
      final projectFolder = File(projectPath).parent.path;
      _versionManager ??= VersionManager(projectFolder);
      await _versionManager!.refresh();
    }

    // Open project-specific settings dialog (accessed via clicking song name)
    final result = await ProjectSettingsDialog.show(
      context,
      metadata: _projectMetadata,
      versions: _versionManager?.versions ?? [],
      currentVersionNumber: _versionManager?.currentVersionNumber,
      nextVersionNumber: _versionManager?.nextVersionNumber ?? 1,
    );

    if (result == null || !mounted) return;

    // Handle metadata changes
    final updatedMetadata = result.metadata;
    final bpmChanged = updatedMetadata.bpm != _projectMetadata.bpm;
    final nameChanged = updatedMetadata.name != _projectMetadata.name;

    setState(() {
      _projectMetadata = updatedMetadata;
    });

    // Update audio engine with new BPM
    if (bpmChanged) {
      _audioEngine?.setTempo(updatedMetadata.bpm);
      _recordingController.setTempo(updatedMetadata.bpm);
    }

    // Update project name if changed
    if (nameChanged) {
      _projectManager?.setProjectName(updatedMetadata.name);
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
    if (_projectManager?.currentPath == null || _versionManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save the project first')),
      );
      return;
    }

    final projectPath = _projectManager!.currentPath!;

    // Create the version
    final version = await _versionManager!.createVersion(
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
    if (_projectManager?.currentPath == null || _versionManager == null) return;

    final projectPath = _projectManager!.currentPath!;

    // Switch to the version
    final success = await _versionManager!.switchToVersion(
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
              if (_isPlaying) {
                _stopPlayback();
              }

              // Clear all tracks from the audio engine
              _audioEngine?.clearAllTracks();

              // Clear project state via manager
              _projectManager?.closeProject();
              _midiPlaybackManager?.clear();
              _undoRedoManager.clear();

              // Refresh track widgets to show empty state (clear clips too)
              _refreshTrackWidgets(clearClips: true);

              setState(() {
                _loadedClipId = null;
                _waveformPeaks = [];
                _statusMessage = 'No project loaded';
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
    if (!_hasInitializedPanelSizes && _userSettings.isLoaded) {
      _hasInitializedPanelSizes = true;
      if (!_userSettings.hasSavedPanelSettings) {
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
              _uiLayout.libraryLeftColumnWidth = UILayoutState.libraryLeftColumnDefault;
              _uiLayout.libraryRightColumnWidth = (targetLibraryTotal -
                  UILayoutState.libraryLeftColumnDefault -
                  UILayoutState.libraryDividerWidth).clamp(
                UILayoutState.libraryRightColumnMin,
                UILayoutState.libraryRightColumnMax,
              );
              _uiLayout.mixerPanelWidth = (windowSize.width * 0.28).clamp(
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
    final arrangementWidth = _uiLayout.getArrangementWidth(windowSize.width);
    if (arrangementWidth < UILayoutState.minArrangementWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_uiLayout.isMixerVisible) {
          _uiLayout.collapseMixer();
        } else if (!_uiLayout.isLibraryPanelCollapsed) {
          _uiLayout.collapseLibrary();
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
        undoRedoManager: _undoRedoManager,
        onDelete: _midiPlaybackManager?.selectedClipId != null
            ? () {
                final clipId = _midiPlaybackManager!.selectedClipId!;
                final clip = _midiPlaybackManager!.currentEditingClip;
                if (clip != null) {
                  _deleteMidiClip(clipId, clip.trackId);
                }
              }
            : null,
        onDuplicate: _duplicateSelectedClip,
        onSplitAtMarker: (_midiPlaybackManager?.selectedClipId != null ||
                _timelineKey.currentState?.selectedAudioClipId != null)
            ? _splitSelectedClipAtPlayhead
            : null,
        onQuantizeClip: (_midiPlaybackManager?.selectedClipId != null ||
                _timelineKey.currentState?.selectedAudioClipId != null)
            ? _quantizeSelectedClip
            : null,
        onConsolidateClips: (_timelineKey.currentState?.selectedMidiClipIds.length ?? 0) >= 2
            ? _consolidateSelectedClips
            : null,
        onBounceMidiToAudio: _midiPlaybackManager?.selectedClipId != null
            ? _bounceMidiToAudio
            : null,
        hasSelectedMidiClip: _midiPlaybackManager?.selectedClipId != null,
        hasSelectedAudioClip: _timelineKey.currentState?.selectedAudioClipId != null,
        selectedMidiClipCount: _timelineKey.currentState?.selectedMidiClipIds.length ?? 0,
        // View menu state and callbacks
        uiLayout: _uiLayout,
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
            valueListenable: _playbackController.playheadNotifier,
            builder: (context, playheadPos, _) => TransportBar(
            onPlay: _playWithLoopCheck,
            onPause: _pause,
            onStop: _stopPlayback,
            onRecord: toggleRecording,
            onPauseRecording: pauseRecording,
            onStopRecording: stopRecordingAndReturn,
            onCaptureMidi: _captureMidi,
            onCountInChanged: _setCountInBars,
            countInBars: _userSettings.countInBars,
            onMetronomeToggle: _toggleMetronome,
            onPianoToggle: _toggleVirtualPiano,
            playheadPosition: playheadPos,
            isPlaying: _isPlaying,
            canPlay: true, // Always allow transport controls
            isRecording: _isRecording,
            isCountingIn: _isCountingIn,
            countInBeat: _recordingController.countInBeat,
            countInProgress: _recordingController.countInProgress,
            hasArmedTracks: mixerKey.currentState?.tracks.any((t) => t.armed) ?? false,
            metronomeEnabled: _isMetronomeEnabled,
            virtualPianoEnabled: _uiLayout.isVirtualPianoEnabled,
            tempo: _tempo,
            onTempoChanged: _onTempoChanged,
            // MIDI device selection
            midiDevices: _midiDevices,
            selectedMidiDeviceIndex: _selectedMidiDeviceIndex,
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
            projectName: _projectMetadata.name,
            hasProject: _projectManager?.hasProject ?? false,
            // View menu parameters
            onToggleLibrary: _toggleLibraryPanel,
            onToggleMixer: _toggleMixer,
            onToggleEditor: _toggleEditor,
            onTogglePiano: _toggleVirtualPiano,
            onResetPanelLayout: _resetPanelLayout,
            libraryVisible: !_uiLayout.isLibraryPanelCollapsed,
            mixerVisible: _uiLayout.isMixerVisible,
            editorVisible: _uiLayout.isEditorPanelVisible,
            pianoVisible: _uiLayout.isVirtualPianoEnabled,
            onHelpPressed: _showKeyboardShortcuts,
            // Edit menu (Undo/Redo) callbacks
            onUndo: _undoRedoManager.canUndo ? _performUndo : null,
            onRedo: _undoRedoManager.canRedo ? _performRedo : null,
            canUndo: _undoRedoManager.canUndo,
            canRedo: _undoRedoManager.canRedo,
            undoDescription: _undoRedoManager.undoDescription,
            redoDescription: _undoRedoManager.redoDescription,
            // Snap control
            arrangementSnap: _uiLayout.arrangementSnap,
            onSnapChanged: (value) => _uiLayout.setArrangementSnap(value),
            // Loop playback control
            loopPlaybackEnabled: _uiLayout.loopPlaybackEnabled,
            onLoopPlaybackToggle: _uiLayout.toggleLoopPlayback,
            // Time signature
            beatsPerBar: _projectMetadata.timeSignatureNumerator,
            beatUnit: _projectMetadata.timeSignatureDenominator,
            onTimeSignatureChanged: _onTimeSignatureChanged,
            isLoading: _isLoading,
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
                        width: _uiLayout.isLibraryPanelCollapsed ? 40 : _uiLayout.libraryPanelWidth,
                        child: _libraryPreviewService != null
                          ? ChangeNotifierProvider<LibraryPreviewService>.value(
                              value: _libraryPreviewService!,
                              child: LibraryPanel(
                                isCollapsed: _uiLayout.isLibraryPanelCollapsed,
                                onToggle: _toggleLibraryPanel,
                                availableVst3Plugins: _vst3PluginManager?.availablePlugins ?? [],
                                libraryService: _libraryService,
                                onItemDoubleClick: _handleLibraryItemDoubleClick,
                                onVst3DoubleClick: _handleVst3DoubleClick,
                                onOpenInSampler: _handleOpenInSampler,
                                leftColumnWidth: _uiLayout.libraryLeftColumnWidth,
                                onLeftColumnResize: (delta) {
                                  setState(() {
                                    _uiLayout.resizeLeftColumn(delta);
                                    _userSettings.libraryLeftColumnWidth = _uiLayout.libraryLeftColumnWidth;
                                  });
                                },
                              ),
                            )
                          : LibraryPanel(
                              isCollapsed: _uiLayout.isLibraryPanelCollapsed,
                              onToggle: _toggleLibraryPanel,
                              availableVst3Plugins: _vst3PluginManager?.availablePlugins ?? [],
                              libraryService: _libraryService,
                              onItemDoubleClick: _handleLibraryItemDoubleClick,
                              onVst3DoubleClick: _handleVst3DoubleClick,
                              onOpenInSampler: _handleOpenInSampler,
                              leftColumnWidth: _uiLayout.libraryLeftColumnWidth,
                              onLeftColumnResize: (delta) {
                                setState(() {
                                  _uiLayout.resizeLeftColumn(delta);
                                  _userSettings.libraryLeftColumnWidth = _uiLayout.libraryLeftColumnWidth;
                                });
                              },
                            ),
                      ),

                      // Divider: Library/Timeline
                      // Outer divider only affects right column (left stays fixed)
                      ResizableDivider(
                        orientation: DividerOrientation.vertical,
                        isCollapsed: _uiLayout.isLibraryPanelCollapsed,
                        onDrag: (delta) {
                          setState(() {
                            _uiLayout.resizeRightColumn(delta);
                            _userSettings.libraryRightColumnWidth = _uiLayout.libraryRightColumnWidth;
                            _userSettings.libraryCollapsed = _uiLayout.isLibraryPanelCollapsed;
                          });
                        },
                        onDoubleClick: () {
                          setState(() {
                            _uiLayout.toggleLibraryPanel();
                            _userSettings.libraryCollapsed = _uiLayout.isLibraryPanelCollapsed;
                          });
                        },
                      ),

                      // Center: Timeline area
                      // PERFORMANCE: Use ValueListenableBuilder to only rebuild TimelineView
                      // when playhead changes, not on every controller notification
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _playbackController.playheadNotifier,
                          builder: (context, playheadPos, _) => TimelineView(
                          key: _timelineKey,
                          playheadPosition: playheadPos,
                          clipDuration: _clipDuration,
                          waveformPeaks: _waveformPeaks,
                          audioEngine: _audioEngine,
                          tempo: _tempo,
                          selectedMidiTrackId: _selectedTrackId,
                          selectedMidiClipId: _midiPlaybackManager?.selectedClipId,
                          currentEditingClip: _midiPlaybackManager?.currentEditingClip,
                          midiClips: _midiPlaybackManager?.midiClips ?? [], // Pass all MIDI clips for visualization
                          onMidiTrackSelected: _onTrackSelected,
                          onMidiClipSelected: _onMidiClipSelected,
                          onAudioClipSelected: _onAudioClipSelected,
                          onMidiClipUpdated: _onMidiClipUpdated,
                          onMidiClipCopied: _onMidiClipCopied,
                          onAudioClipCopied: _onAudioClipCopied,
                          getRustClipId: (dartClipId) => _midiPlaybackManager?.dartToRustClipIds[dartClipId] ?? dartClipId,
                          onMidiClipDeleted: _deleteMidiClip,
                          onMidiClipsBatchDeleted: _deleteMidiClipsBatch,
                          onAudioClipsBatchDeleted: _deleteAudioClipsBatch,
                          onInstrumentDropped: _onInstrumentDropped,
                          onInstrumentDroppedOnEmpty: _onInstrumentDroppedOnEmpty,
                          onVst3InstrumentDropped: _onVst3InstrumentDropped,
                          onVst3InstrumentDroppedOnEmpty: _onVst3InstrumentDroppedOnEmpty,
                          onAudioFileDroppedOnEmpty: _onAudioFileDroppedOnEmpty,
                          onAudioFileDroppedOnTrack: _onAudioFileDroppedOnTrack,
                          onCreateTrackWithClip: _onCreateTrackWithClip,
                          onCreateClipOnTrack: _onCreateClipOnTrack,
                          clipHeights: _clipHeights,
                          automationHeights: _automationHeights,
                          masterTrackHeight: _masterTrackHeight,
                          trackOrder: _trackController.trackOrder,
                          getTrackColor: _getTrackColor,
                          onClipHeightChanged: _setClipHeight,
                          onAutomationHeightChanged: _setAutomationHeight,
                          onSeek: (position) {
                            _audioEngine?.transportSeek(position);
                            _playheadPosition = position;
                            // Update the notifier so ValueListenableBuilder rebuilds immediately
                            _playbackController.playheadNotifier.value = position;
                          },
                          // Loop playback state
                          loopPlaybackEnabled: _uiLayout.loopPlaybackEnabled,
                          loopStartBeats: _uiLayout.loopStartBeats,
                          loopEndBeats: _uiLayout.loopEndBeats,
                          onLoopRegionChanged: (start, end) {
                            // Mark as manual adjustment - disables auto-follow
                            _uiLayout.setLoopRegion(start, end, manual: true);
                            // Update playback controller in real-time during playback
                            _playbackController.updateLoopBounds(
                              loopStartBeats: start,
                              loopEndBeats: end,
                            );
                          },
                          // Vertical scroll sync with mixer panel
                          verticalScrollController: _timelineVerticalScrollController,
                          // Tool mode (shared with piano roll)
                          toolMode: _currentToolMode,
                          onToolModeChanged: (mode) => setState(() => _currentToolMode = mode),
                          // Recording state (for auto-scroll)
                          isRecording: _isRecording,
                          // Automation state
                          automationVisibleTrackId: _automationController.visibleTrackId,
                          getAutomationLane: (trackId) => _automationController.getLane(trackId, _automationController.visibleParameter),
                          onAutomationPointAdded: (trackId, point) {
                            _automationController.addPoint(trackId, _automationController.visibleParameter, point);
                            if (_automationController.visibleParameter == AutomationParameter.volume) {
                              _syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPointUpdated: (trackId, pointId, point) {
                            _automationController.updatePoint(trackId, _automationController.visibleParameter, pointId, point);
                            if (_automationController.visibleParameter == AutomationParameter.volume) {
                              _syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPointDeleted: (trackId, pointId) {
                            _automationController.removePoint(trackId, _automationController.visibleParameter, pointId);
                            if (_automationController.visibleParameter == AutomationParameter.volume) {
                              _syncVolumeAutomationToEngine(trackId);
                            }
                          },
                          onAutomationPreviewValue: _onAutomationPreviewValue,
                          automationScrollController: _timelineKey.currentState?.scrollController,
                        ),
                        ),
                      ),

                      // Right: Track mixer panel (expanded or collapsed bar)
                      if (_uiLayout.isMixerVisible) ...[
                        // Divider: Timeline/Mixer
                        ResizableDivider(
                          orientation: DividerOrientation.vertical,
                          isCollapsed: false,
                          onDrag: (delta) {
                            final windowWidth = MediaQuery.of(context).size.width;
                            final maxWidth = UILayoutState.getMixerMaxWidth(windowWidth);
                            setState(() {
                              final newWidth = _uiLayout.mixerPanelWidth - delta;
                              // Snap collapse if dragged below threshold
                              if (newWidth < UILayoutState.mixerCollapseThreshold) {
                                _uiLayout.collapseMixer();
                                _userSettings.mixerVisible = false;
                              } else {
                                _uiLayout.mixerPanelWidth = newWidth.clamp(
                                  UILayoutState.mixerMinWidth,
                                  maxWidth,
                                );
                                _userSettings.mixerWidth = _uiLayout.mixerPanelWidth;
                              }
                            });
                          },
                          onDoubleClick: () {
                            setState(() {
                              _uiLayout.toggleMixer();
                              _userSettings.mixerVisible = _uiLayout.isMixerVisible;
                            });
                          },
                        ),

                        SizedBox(
                          width: _uiLayout.mixerPanelWidth,
                          child: TrackMixerPanel(
                            key: _mixerKey,
                            audioEngine: _audioEngine,
                            isEngineReady: _isAudioGraphInitialized,
                            scrollController: _mixerVerticalScrollController,
                            selectedTrackId: _selectedTrackId,
                            selectedTrackIds: _selectedTrackIds,
                            onTrackSelected: _onTrackSelected,
                            onInstrumentSelected: _onInstrumentSelected,
                            onTrackDuplicated: _onTrackDuplicated,
                            onTrackDeleted: _onTrackDeleted,
                            onConvertToSampler: _convertAudioTrackToSampler,
                            trackInstruments: _trackInstruments,
                            trackVst3PluginCounts: _getTrackVst3PluginCounts(), // M10
                            onFxButtonPressed: _showVst3PluginBrowser, // M10
                            onVst3PluginDropped: _onVst3PluginDropped, // M10
                            onVst3InstrumentDropped: _onVst3InstrumentDropped, // Swap VST3 instrument
                            onInstrumentDropped: _onInstrumentDropped, // Swap built-in instrument
                            onEditPluginsPressed: _showVst3PluginEditor, // M10
                            onAudioFileDropped: _onAudioFileDroppedOnEmpty,
                            onMidiTrackCreated: _createDefaultMidiClip,
                            onTrackCreated: _onTrackCreatedFromMixer,
                            onTrackReordered: _onTrackReordered,
                            trackOrder: _trackController.trackOrder,
                            onTrackOrderSync: _trackController.syncTrackOrder,
                            clipHeights: _clipHeights,
                            automationHeights: _automationHeights,
                            masterTrackHeight: _masterTrackHeight,
                            onClipHeightChanged: _setClipHeight,
                            onAutomationHeightChanged: _setAutomationHeight,
                            onMasterTrackHeightChanged: _setMasterTrackHeight,
                            panelWidth: _uiLayout.mixerPanelWidth,
                            onTogglePanel: _toggleMixer,
                            getTrackColor: _getTrackColor,
                            onTrackColorChanged: _setTrackColor,
                            getTrackIcon: (trackId) => _trackController.getTrackIcon(trackId),
                            onTrackIconChanged: (trackId, icon) {
                              setState(() {
                                _trackController.setTrackIcon(trackId, icon);
                              });
                            },
                            onTrackNameChanged: (trackId, newName) {
                              // Mark track name as user-edited
                              _trackController.markTrackNameUserEdited(trackId, edited: true);
                            },
                            onTrackDoubleClick: (trackId) {
                              // Select track and open editor
                              _onTrackSelected(trackId);
                              if (!_uiLayout.isEditorPanelVisible) {
                                _toggleEditor();
                              }
                            },
                            automationVisibleTrackId: _automationController.visibleTrackId,
                            onAutomationToggle: (trackId) {
                              setState(() {
                                _automationController.toggleAutomationForTrack(trackId);
                              });
                            },
                            getAutomationLane: (trackId) => _automationController.getLane(trackId, _automationController.visibleParameter),
                            pixelsPerBeat: _timelineKey.currentState?.pixelsPerBeat ?? 20.0,
                            totalBeats: 256.0,
                            onAutomationPointAdded: (trackId, point) {
                              _automationController.addPoint(trackId, _automationController.visibleParameter, point);
                              if (_automationController.visibleParameter == AutomationParameter.volume) {
                                _syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            onAutomationPointUpdated: (trackId, pointId, point) {
                              _automationController.updatePoint(trackId, _automationController.visibleParameter, pointId, point);
                              if (_automationController.visibleParameter == AutomationParameter.volume) {
                                _syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            onAutomationPointDeleted: (trackId, pointId) {
                              _automationController.removePoint(trackId, _automationController.visibleParameter, pointId);
                              if (_automationController.visibleParameter == AutomationParameter.volume) {
                                _syncVolumeAutomationToEngine(trackId);
                              }
                            },
                            automationPreviewValues: _automationPreviewValues,
                            onAutomationPreviewValue: _onAutomationPreviewValue,
                            isRecording: _recordingController.isRecording || _recordingController.isCountingIn,
                            getSelectedParameter: (trackId) => _automationController.visibleParameter,
                            onParameterChanged: (trackId, param) {
                              setState(() {
                                _automationController.setVisibleParameter(param);
                              });
                            },
                            onResetParameter: (trackId) {
                              // Reset the parameter to its default value
                              final param = _automationController.visibleParameter;
                              if (param == AutomationParameter.volume) {
                                _audioEngine?.setTrackVolume(trackId, 0.0); // 0 dB
                                setState(() {}); // Trigger UI update
                              } else if (param == AutomationParameter.pan) {
                                _audioEngine?.setTrackPan(trackId, 0.0); // Center
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
                if (_uiLayout.isEditorPanelVisible) ...[
                  // Resizable divider above editor (only when expanded)
                  ResizableDivider(
                    orientation: DividerOrientation.horizontal,
                    isCollapsed: false,
                    onDrag: (delta) {
                      final windowHeight = MediaQuery.of(context).size.height;
                      final maxHeight = UILayoutState.getEditorMaxHeight(windowHeight);
                      setState(() {
                        final newHeight = _uiLayout.editorPanelHeight - delta;
                        // Snap collapse if dragged below threshold
                        if (newHeight < UILayoutState.editorCollapseThreshold) {
                          _uiLayout.collapseEditor();
                          _userSettings.editorVisible = false;
                        } else {
                          _uiLayout.editorPanelHeight = newHeight.clamp(
                            UILayoutState.editorMinHeight,
                            maxHeight,
                          );
                          _userSettings.editorHeight = _uiLayout.editorPanelHeight;
                        }
                      });
                    },
                    onDoubleClick: () {
                      setState(() {
                        _uiLayout.collapseEditor();
                        _userSettings.editorVisible = false;
                      });
                    },
                  ),
                ],

                // Editor panel content (full when visible, collapsed bar when hidden)
                SizedBox(
                  height: _uiLayout.isEditorPanelVisible ? _uiLayout.editorPanelHeight : 40,
                  child: EditorPanel(
                    audioEngine: _audioEngine,
                    virtualPianoEnabled: _uiLayout.isVirtualPianoEnabled,
                    selectedTrackId: _selectedTrackId,
                    selectedTrackName: _getSelectedTrackName(),
                    selectedTrackType: _getSelectedTrackType(),
                    currentInstrumentData: _selectedTrackId != null
                        ? _trackInstruments[_selectedTrackId]
                        : null,
                    onVirtualPianoClose: _toggleVirtualPiano,
                    onVirtualPianoToggle: _toggleVirtualPiano,
                    onClosePanel: () {
                      setState(() {
                        _uiLayout.isEditorPanelVisible = false;
                      });
                    },
                    onExpandPanel: () {
                      setState(() {
                        _uiLayout.isEditorPanelVisible = true;
                      });
                    },
                    currentEditingClip: _midiPlaybackManager?.currentEditingClip,
                    onMidiClipUpdated: _onMidiClipUpdated,
                    onInstrumentParameterChanged: _onInstrumentParameterChanged,
                    currentEditingAudioClip: _selectedAudioClip,
                    onAudioClipUpdated: _onAudioClipUpdated,
                    currentTrackPlugins: _selectedTrackId != null // M10
                        ? _getTrackVst3Plugins(_selectedTrackId!)
                        : null,
                    onVst3ParameterChanged: _onVst3ParameterChanged, // M10
                    onVst3PluginRemoved: _removeVst3Plugin, // M10
                    onVst3InstrumentDropped: (plugin) {
                      if (_selectedTrackId != null) {
                        _onVst3InstrumentDropped(_selectedTrackId!, plugin);
                      }
                    },
                    onInstrumentDropped: (instrument) {
                      if (_selectedTrackId != null) {
                        _onInstrumentDropped(_selectedTrackId!, instrument);
                      }
                    },
                    isCollapsed: !_uiLayout.isEditorPanelVisible,
                    toolMode: _currentToolMode,
                    onToolModeChanged: (mode) => setState(() => _currentToolMode = mode),
                    beatsPerBar: _projectMetadata.timeSignatureNumerator,
                    beatUnit: _projectMetadata.timeSignatureDenominator,
                    projectTempo: _projectMetadata.bpm,
                    onProjectTempoChanged: _onTempoChanged,
                    isRecording: _isRecording,
                  ),
                ),

                // Virtual Piano - independent panel, always below editor
                if (_uiLayout.isVirtualPianoEnabled)
                  VirtualPiano(
                    audioEngine: _audioEngine,
                    isEnabled: _uiLayout.isVirtualPianoEnabled,
                    onClose: _toggleVirtualPiano,
                    selectedTrackId: _selectedTrackId,
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
    if (_audioEngine == null || !_isAudioGraphInitialized) {
      return Text(
        '--ms',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      );
    }

    final latencyInfo = _audioEngine!.getLatencyInfo();
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
    if (_audioEngine == null) return;

    showLatencySettingsDialog(
      context: context,
      currentPreset: _audioEngine!.getBufferSizePreset(),
      presets: AudioEngine.bufferSizePresets,
      onPresetSelected: (preset) {
        _audioEngine!.setBufferSize(preset);
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
              color: _isAudioGraphInitialized
                  ? colors.accent.withValues(alpha: 0.15)
                  : colors.textMuted.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAudioGraphInitialized ? Icons.check_circle : Icons.hourglass_empty,
                  size: 12,
                  color: _isAudioGraphInitialized
                      ? colors.accent
                      : colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _isAudioGraphInitialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: _isAudioGraphInitialized
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
          if (_clipDuration != null) ...[
            Icon(Icons.timelapse, size: 11, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              '${_clipDuration!.toStringAsFixed(2)}s',
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

