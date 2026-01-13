import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import '../services/commands/track_commands.dart';
import '../services/commands/project_commands.dart';
import '../services/commands/clip_commands.dart';
import '../services/library_service.dart';
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
import '../services/version_manager.dart';
import '../services/midi_capture_buffer.dart';
import '../services/clip_naming_service.dart';
import '../widgets/capture_midi_dialog.dart';
import '../widgets/dialogs/latency_settings_dialog.dart';
import '../widgets/dialogs/crash_reporting_dialog.dart';
import '../controllers/controllers.dart';
import '../state/ui_layout_state.dart';

/// Main DAW screen with timeline, transport controls, and file import
class DAWScreen extends StatefulWidget {
  const DAWScreen({super.key});

  @override
  State<DAWScreen> createState() => _DAWScreenState();
}

class _DAWScreenState extends State<DAWScreen> {
  AudioEngine? _audioEngine;

  // Controllers (extracted from daw_screen for maintainability)
  final PlaybackController _playbackController = PlaybackController();
  final RecordingController _recordingController = RecordingController();
  final TrackController _trackController = TrackController();
  final MidiClipController _midiClipController = MidiClipController();
  final UILayoutState _uiLayout = UILayoutState();

  // Undo/Redo manager
  final UndoRedoManager _undoRedoManager = UndoRedoManager();

  // Library service
  final LibraryService _libraryService = LibraryService();

  // M10: VST3 Plugin manager (lazy initialized when audio engine is ready)
  Vst3PluginManager? _vst3PluginManager;

  // M5: Project manager (lazy initialized when audio engine is ready)
  ProjectManager? _projectManager;

  // Version manager (lazy initialized when project is loaded)
  VersionManager? _versionManager;

  // M8: MIDI playback manager (lazy initialized when audio engine is ready)
  MidiPlaybackManager? _midiPlaybackManager;

  // User settings and auto-save
  final UserSettings _userSettings = UserSettings();
  final AutoSaveService _autoSaveService = AutoSaveService();

  // MIDI capture buffer for retroactive recording
  final MidiCaptureBuffer _midiCaptureBuffer = MidiCaptureBuffer(maxDurationSeconds: 30);

  // State (clip-specific state remains local)
  int? _loadedClipId;
  double? _clipDuration;
  List<double> _waveformPeaks = [];
  bool _isAudioGraphInitialized = false;
  bool _isLoading = false;

  // Audio clip selection for Audio Editor
  ClipData? _selectedAudioClip;

  // Tool mode (shared between piano roll and arrangement view)
  ToolMode _currentToolMode = ToolMode.draw;

  // Project metadata
  ProjectMetadata _projectMetadata = const ProjectMetadata(
    name: 'Untitled Project',
    bpm: 120.0,
  );

  // Playback state now managed by _playbackController
  // Convenience getters/setters for backwards compatibility
  double get _playheadPosition => _playbackController.playheadPosition;
  set _playheadPosition(double value) => _playbackController.setPlayheadPosition(value);
  bool get _isPlaying => _playbackController.isPlaying;
  set _statusMessage(String value) => _playbackController.setStatusMessage(value);

  // Recording state now managed by _recordingController
  // Convenience getters for backwards compatibility
  bool get _isRecording => _recordingController.isRecording;
  bool get _isCountingIn => _recordingController.isCountingIn;
  bool get _isMetronomeEnabled => _recordingController.isMetronomeEnabled;
  double get _tempo => _recordingController.tempo;
  List<Map<String, dynamic>> get _midiDevices => _recordingController.midiDevices;
  int get _selectedMidiDeviceIndex => _recordingController.selectedMidiDeviceIndex;

  // M3-M7: UI panel state now managed by _uiLayout (UILayoutState)
  // Includes: virtual piano, mixer, library panel, editor panel, and panel sizes

  // M8-M10: Track state now managed by _trackController (TrackController)

  // Convenience getters/setters that delegate to _trackController
  int? get _selectedTrackId => _trackController.selectedTrackId;
  set _selectedTrackId(int? value) => _trackController.selectTrack(value);

  Map<int, InstrumentData> get _trackInstruments => _trackController.trackInstruments;
  Map<int, double> get _trackHeights => _trackController.trackHeights;
  double get _masterTrackHeight => _trackController.masterTrackHeight;

  void _setTrackHeight(int trackId, double height) {
    _trackController.setTrackHeight(trackId, height);
  }

  void _setMasterTrackHeight(double height) {
    _trackController.setMasterTrackHeight(height);
  }

  Color _getTrackColor(int trackId, String trackName, String trackType) {
    return _trackController.getTrackColor(trackId, trackName, trackType);
  }

  void _setTrackColor(int trackId, Color color) {
    _trackController.setTrackColor(trackId, color);
  }

  // GlobalKeys for child widgets that need immediate refresh
  final GlobalKey<TimelineViewState> _timelineKey = GlobalKey<TimelineViewState>();
  final GlobalKey<TrackMixerPanelState> _mixerKey = GlobalKey<TrackMixerPanelState>();

  // Linked vertical scroll controllers for timeline and mixer panel sync
  final ScrollController _timelineVerticalScrollController = ScrollController();
  final ScrollController _mixerVerticalScrollController = ScrollController();
  bool _isScrollSyncing = false; // Prevent infinite loop during sync

  /// Sync timeline scroll to mixer
  void _onTimelineVerticalScroll() {
    if (_isScrollSyncing) return;
    if (!_mixerVerticalScrollController.hasClients) return;
    if (!_mixerVerticalScrollController.position.hasContentDimensions) return;

    _isScrollSyncing = true;
    try {
      final targetOffset = _timelineVerticalScrollController.offset.clamp(
        _mixerVerticalScrollController.position.minScrollExtent,
        _mixerVerticalScrollController.position.maxScrollExtent,
      );
      _mixerVerticalScrollController.jumpTo(targetOffset);
    } finally {
      _isScrollSyncing = false;
    }
  }

  /// Sync mixer scroll to timeline
  void _onMixerVerticalScroll() {
    if (_isScrollSyncing) return;
    if (!_timelineVerticalScrollController.hasClients) return;
    if (!_timelineVerticalScrollController.position.hasContentDimensions) return;

    _isScrollSyncing = true;
    try {
      final targetOffset = _mixerVerticalScrollController.offset.clamp(
        _timelineVerticalScrollController.position.minScrollExtent,
        _timelineVerticalScrollController.position.maxScrollExtent,
      );
      _timelineVerticalScrollController.jumpTo(targetOffset);
    } finally {
      _isScrollSyncing = false;
    }
  }

  /// Disarm all MIDI tracks except the specified one.
  /// Called when a new MIDI track is created to implement exclusive arm.
  void _disarmOtherMidiTracks(int exceptTrackId) {
    final tracks = _mixerKey.currentState?.tracks ?? [];
    for (final track in tracks) {
      if (track.type == 'midi' && track.id != exceptTrackId && track.armed) {
        track.armed = false;
        _audioEngine?.setTrackArmed(track.id, armed: false);
      }
    }
  }

  /// Trigger immediate refresh of track lists in both timeline and mixer panels
  void _refreshTrackWidgets({bool clearClips = false}) {
    // Use post-frame callback to ensure the engine state has settled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (clearClips) {
          _timelineKey.currentState?.clearClips();
        }
        _timelineKey.currentState?.refreshTracks();
        _mixerKey.currentState?.refreshTracks();
        // Force a rebuild of the parent widget as well
        setState(() {});
      }
    });
  }

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
          // Load panel sizes
          _uiLayout.libraryPanelWidth = _userSettings.libraryWidth;
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
    debugPrint('DawScreen: Starting audio engine initialization...');
    try {
      // Load plugin preferences early (before any plugin operations)
      await PluginPreferencesService.load();

      // Called after 800ms delay from initState, so UI has rendered
      debugPrint('DawScreen: Creating AudioEngine...');
      _audioEngine = AudioEngine();
      debugPrint('DawScreen: AudioEngine created, calling initAudioEngine...');
      _audioEngine!.initAudioEngine();
      debugPrint('DawScreen: initAudioEngine done');

      // Initialize audio graph
      _audioEngine!.initAudioGraph();

      // Initialize recording settings
      try {
        _audioEngine!.setCountInBars(_userSettings.countInBars); // Use saved setting
        _audioEngine!.setTempo(120.0);   // Default: 120 BPM
        _audioEngine!.setMetronomeEnabled(enabled: true); // Default: enabled
      } catch (e) {
        debugPrint('DawScreen: Failed to initialize recording settings: $e');
      }

      // Initialize buffer size from user settings
      try {
        final bufferPreset = _bufferSizeToPreset(_userSettings.bufferSize);
        _audioEngine!.setBufferSize(bufferPreset);
        debugPrint('DawScreen: Buffer size set to ${_userSettings.bufferSize} samples (preset $bufferPreset)');
      } catch (e) {
        debugPrint('DawScreen: Failed to set buffer size: $e');
      }

      // Initialize output device from user settings
      if (_userSettings.preferredOutputDevice != null) {
        try {
          _audioEngine!.setAudioOutputDevice(_userSettings.preferredOutputDevice!);
          debugPrint('DawScreen: Output device set to ${_userSettings.preferredOutputDevice}');
        } catch (e) {
          debugPrint('DawScreen: Failed to set output device: $e');
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
    } catch (e, stackTrace) {
      debugPrint('DawScreen: FAILED to initialize audio engine: $e');
      debugPrint('DawScreen: Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to initialize: $e';
        });
      }
    }
  }

  void _play() {
    _playbackController.play(loadedClipId: _loadedClipId);
  }

  void _pause() {
    _playbackController.pause();
  }

  void _stopPlayback() {
    _playbackController.stop();
    // Reset mixer meters when playback stops
    _mixerKey.currentState?.resetMeters();
  }

  /// Context-aware play/pause toggle (Space bar)
  /// - When Piano Roll is visible: plays just the loop region (cycling)
  /// - When Timeline only: plays full arrangement
  void _togglePlayPause() {
    if (_isPlaying) {
      _pause();
    } else {
      // Context-aware: check if Piano Roll is the focus
      if (_uiLayout.isEditorPanelVisible && _loadedClipId != null) {
        // Piano Roll context: play loop region (cycling)
        _playLoopRegion();
      } else {
        // Timeline context: normal arrangement playback
        _play();
      }
    }
  }

  /// Play just the loop region in the Piano Roll, cycling forever
  void _playLoopRegion() {
    // Get loop bounds from UI layout state
    final loopStart = _uiLayout.loopStartBeats;
    final loopEnd = _uiLayout.loopEndBeats;

    // Play with loop cycling enabled
    _playbackController.playLoop(
      loadedClipId: _loadedClipId,
      loopStartBeats: loopStart,
      loopEndBeats: loopEnd,
    );
  }

  // M2: Recording methods - delegate to RecordingController
  void _toggleRecording() {
    if (_isRecording || _isCountingIn) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    // Set up callback to handle recording completion with MIDI clip processing
    _recordingController.onRecordingComplete = _handleRecordingComplete;
    _recordingController.startRecording();
  }

  void _stopRecording() {
    final result = _recordingController.stopRecording();
    _handleRecordingComplete(result);
  }

  /// Handle recording completion - process audio and MIDI clips
  void _handleRecordingComplete(RecordingResult result) {
    final List<String> recordedItems = [];

    // Handle audio clip
    if (result.audioClipId != null) {
      setState(() {
        _loadedClipId = result.audioClipId;
        _clipDuration = result.duration;
        _waveformPeaks = result.waveformPeaks ?? [];
      });
      recordedItems.add('Audio ${result.duration?.toStringAsFixed(2) ?? ""}s');
    }

    // Handle MIDI clip
    if (result.midiClipId != null && result.midiClipInfo != null) {
      final clipInfo = result.midiClipInfo!;
      if (!clipInfo.startsWith('Error')) {
        try {
          final parts = clipInfo.split(',');
          if (parts.length >= 5) {
            final trackId = int.parse(parts[1]);
            final startTimeSeconds = double.parse(parts[2]);
            final durationSeconds = double.parse(parts[3]);
            final noteCount = int.parse(parts[4]);

            // Convert from seconds to beats for MIDI clip storage
            final beatsPerSecond = _tempo / 60.0;
            final startTimeBeats = startTimeSeconds * beatsPerSecond;
            final durationBeats = durationSeconds > 0
                ? durationSeconds * beatsPerSecond
                : 16.0; // Default 4 bars (16 beats) if no duration

            // Create MidiClipData and add to timeline
            final actualTrackId = trackId >= 0 ? trackId : (_selectedTrackId ?? 0);
            final clipData = MidiClipData(
              clipId: result.midiClipId!,
              trackId: actualTrackId,
              startTime: startTimeBeats,
              duration: durationBeats,
              name: _generateClipName(actualTrackId),
              notes: [], // Notes are managed by the engine
            );

            _midiPlaybackManager?.addRecordedClip(clipData);
            recordedItems.add('MIDI ($noteCount notes)');
          }
        } catch (e) {
          recordedItems.add('MIDI clip');
        }
      } else {
        recordedItems.add('MIDI clip');
      }
    }

    // Update status message
    if (recordedItems.isNotEmpty) {
      _playbackController.setStatusMessage('Recorded: ${recordedItems.join(', ')}');
    } else if (result.audioClipId == null && result.midiClipId == null) {
      _playbackController.setStatusMessage('No recording captured');
    }
  }

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
        _recordingController.setTempo(newBpm);
        _midiClipController.setTempo(newBpm);
        _midiCaptureBuffer.updateBpm(newBpm);
        _midiPlaybackManager?.rescheduleAllClips(newBpm);
      },
    );
    await _undoRedoManager.execute(command);
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
    setState(() {
      _uiLayout.isMixerVisible = !_uiLayout.isMixerVisible;
      _userSettings.mixerVisible = _uiLayout.isMixerVisible;
    });
  }

  // Unified track selection method - handles both timeline and mixer clicks
  void _onTrackSelected(int? trackId) {
    if (trackId == null) {
      setState(() {
        _selectedTrackId = null;
        _uiLayout.isEditorPanelVisible = false;
      });
      return;
    }

    setState(() {
      _selectedTrackId = trackId;
      _uiLayout.isEditorPanelVisible = true;
    });

    // Try to find an existing clip for this track and select it
    // instead of clearing the clip selection
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
    // TODO: Persist changes to audio engine when audio clip editing is implemented
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

    // Assign the instrument to the new track
    _onInstrumentSelected(trackId, instrument.id);

    // Select the newly created track and its clip
    _onTrackSelected(trackId);

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
        final noteOffResult = _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
        if (noteOffResult.isNotEmpty) {
          debugPrint('DawScreen: Note off result: $noteOffResult');
        }
      });
    } catch (e) {
      debugPrint('DawScreen: Failed to preview VST3 instrument: $e');
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
        final noteOffResult = _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
        if (noteOffResult.isNotEmpty) {
        }
      });

      // Select the newly created track and its clip
      _onTrackSelected(trackId);

      // Immediately refresh track widgets so the new track appears instantly
      _refreshTrackWidgets();

      // Disarm other MIDI tracks (exclusive arm for new track)
      _disarmOtherMidiTracks(trackId);
    } catch (e) {
      debugPrint('DawScreen: Failed to create VST3 instrument track: $e');
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

      // 6. Refresh track widgets
      _refreshTrackWidgets();
    } catch (e) {
      // Silently fail
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
      debugPrint('DawScreen: Failed to create audio track: $e');
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
      } else {
        debugPrint('DawScreen: Failed to add effect (returned $effectId)');
      }
    } catch (e) {
      debugPrint('DawScreen: Exception adding effect to track: $e');
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
      // Reset to default panel sizes
      _uiLayout.libraryPanelWidth = 200.0;
      _uiLayout.mixerPanelWidth = 380.0;
      _uiLayout.editorPanelHeight = 250.0;

      // Reset visibility states
      _uiLayout.isLibraryPanelCollapsed = false;
      _uiLayout.isMixerVisible = true;
      _uiLayout.isEditorPanelVisible = true;

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

        setState(() {
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

      setState(() {
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
    final nameController = TextEditingController(text: _projectManager?.currentName ?? 'Untitled Project');

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

    // Update project name in manager
    _projectManager?.setProjectName(projectName);

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
      // Apply panel sizes with clamping
      _uiLayout.libraryPanelWidth = layout.libraryWidth.clamp(UILayoutState.libraryMinWidth, UILayoutState.libraryHardMax);
      _uiLayout.mixerPanelWidth = layout.mixerWidth.clamp(UILayoutState.mixerMinWidth, UILayoutState.mixerHardMax);
      _uiLayout.editorPanelHeight = layout.bottomHeight.clamp(UILayoutState.editorMinHeight, UILayoutState.editorHardMax);

      // Apply collapsed states
      _uiLayout.isLibraryPanelCollapsed = layout.libraryCollapsed;
      _uiLayout.isMixerVisible = !layout.mixerCollapsed;
      // Don't auto-open bottom panel on load
    });

    // Restore view state if "continue where I left off" is enabled
    if (_userSettings.continueWhereLeftOff && layout.viewState != null) {
      _restoreViewState(layout.viewState!);
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

    return UILayoutData(
      libraryWidth: _uiLayout.libraryPanelWidth,
      mixerWidth: _uiLayout.mixerPanelWidth,
      bottomHeight: _uiLayout.editorPanelHeight,
      libraryCollapsed: _uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !_uiLayout.isMixerVisible,
      bottomCollapsed: !(_uiLayout.isEditorPanelVisible || _uiLayout.isVirtualPianoEnabled),
      viewState: viewState,
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
      debugPrint('DawScreen: Failed to check for crash recovery: $e');
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

  Future<void> _makeCopy() async {
    if (_projectManager?.currentPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No project to copy')),
        );
      }
      return;
    }

    // Show dialog to enter copy name
    final nameController = TextEditingController(text: '${_projectManager!.currentName} Copy');

    final copyName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make a Copy'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Copy Name',
            hintText: 'Enter name for the copy',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Create Copy'),
          ),
        ],
      ),
    );

    if (copyName == null || copyName.isEmpty) return;

    try {
      // Get default projects folder
      final defaultFolder = await _getDefaultProjectsFolder();

      // Use macOS native file picker for save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Choose location for copy" default location POSIX file "$defaultFolder")'
      ]);

      if (result.exitCode == 0) {
        final parentPath = result.stdout.toString().trim();
        if (parentPath.isNotEmpty) {
          setState(() => _isLoading = true);

          final copyResult = await _projectManager!.makeCopy(
            copyName,
            parentPath,
            _getCurrentUILayout(),
          );

          setState(() => _isLoading = false);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(copyResult.message)),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create copy: $e')),
        );
      }
    }
  }

  Future<void> _appSettings() async {
    // Open app-wide settings dialog (accessed via logo "O" click)

    // Wait for audio engine if not yet initialized (up to 2 seconds)
    if (_audioEngine == null) {
      debugPrint('DawScreen._appSettings: Waiting for audio engine...');
      for (int i = 0; i < 20 && _audioEngine == null && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!mounted) return;

    final engineStatus = _audioEngine != null ? 'available' : 'NULL';
    debugPrint('DawScreen._appSettings: audioEngine is $engineStatus');

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
    // Auto-collapse panels on small windows
    final windowSize = MediaQuery.of(context).size;

    // Auto-collapse library if window < 900px wide and library is expanded
    if (windowSize.width < UILayoutState.autoCollapseLibraryWidth &&
        !_uiLayout.isLibraryPanelCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _uiLayout.collapseLibrary();
          _userSettings.libraryCollapsed = true;
        }
      });
    }

    // Auto-collapse mixer if window < 1000px wide and mixer is visible
    if (windowSize.width < UILayoutState.autoCollapseMixerWidth &&
        _uiLayout.isMixerVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _uiLayout.collapseMixer();
          _userSettings.mixerVisible = false;
        }
      });
    }

    return PlatformMenuBar(
      menus: [
        // Standard macOS app menu (Audio)
        PlatformMenu(
          label: 'Audio',
          menus: [
            PlatformMenuItem(
              label: 'About Audio',
              onSelected: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('About Audio'),
                    content: const Text('Audio\nVersion M6.2\n\nA modern, cross-platform DAW'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (Platform.isMacOS)
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu),
            if (Platform.isMacOS)
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            if (Platform.isMacOS)
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
            if (Platform.isMacOS)
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
            PlatformMenuItem(
              label: 'Quit Audio',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
              onSelected: () {
                // Close the app
                exit(0);
              },
            ),
          ],
        ),

        // File Menu
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Project',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
              onSelected: _newProject,
            ),
            PlatformMenuItem(
              label: 'Open Project...',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: _openProject,
            ),
            PlatformMenu(
              label: 'Open Recent',
              menus: _buildRecentProjectsMenu(),
            ),
            PlatformMenuItem(
              label: 'Save',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
              onSelected: _saveProject,
            ),
            PlatformMenuItem(
              label: 'Save As...',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
              onSelected: _saveProjectAs,
            ),
            PlatformMenuItem(
              label: 'Make a Copy...',
              onSelected: _makeCopy,
            ),
            PlatformMenuItem(
              label: 'Export Audio...',
              onSelected: _exportAudio,
            ),
            PlatformMenuItem(
              label: 'Export MIDI...',
              onSelected: _exportMidi,
            ),
            PlatformMenuItem(
              label: 'Project Settings...',
              shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
              onSelected: _openProjectSettings,
            ),
            PlatformMenuItem(
              label: 'Close Project',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
              onSelected: _closeProject,
            ),
          ],
        ),

        // Edit Menu
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(
              label: _undoRedoManager.canUndo
                  ? 'Undo - ${_undoRedoManager.undoDescription ?? "Action"}'
                  : 'Undo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              onSelected: _undoRedoManager.canUndo ? _performUndo : null,
            ),
            PlatformMenuItem(
              label: _undoRedoManager.canRedo
                  ? 'Redo - ${_undoRedoManager.redoDescription ?? "Action"}'
                  : 'Redo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
              onSelected: _undoRedoManager.canRedo ? _performRedo : null,
            ),
            const PlatformMenuItem(
              label: 'Cut',
              shortcut: SingleActivator(LogicalKeyboardKey.keyX, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            const PlatformMenuItem(
              label: 'Copy',
              shortcut: SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            const PlatformMenuItem(
              label: 'Paste',
              shortcut: SingleActivator(LogicalKeyboardKey.keyV, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            PlatformMenuItem(
              label: 'Delete',
              shortcut: const SingleActivator(LogicalKeyboardKey.delete),
              onSelected: _midiPlaybackManager?.selectedClipId != null
                  ? () {
                      final clipId = _midiPlaybackManager!.selectedClipId!;
                      final clip = _midiPlaybackManager!.currentEditingClip;
                      if (clip != null) {
                        _deleteMidiClip(clipId, clip.trackId);
                      }
                    }
                  : null,
            ),
            PlatformMenuItem(
              label: 'Duplicate',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
              onSelected: _duplicateSelectedClip,
            ),
            PlatformMenuItem(
              label: 'Split at Marker',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
              onSelected: (_midiPlaybackManager?.selectedClipId != null ||
                      _timelineKey.currentState?.selectedAudioClipId != null)
                  ? _splitSelectedClipAtPlayhead
                  : null,
            ),
            PlatformMenuItem(
              label: 'Quantize Clip',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyQ),
              onSelected: (_midiPlaybackManager?.selectedClipId != null ||
                      _timelineKey.currentState?.selectedAudioClipId != null)
                  ? _quantizeSelectedClip
                  : null,
            ),
            PlatformMenuItem(
              label: 'Consolidate Clips',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyJ, meta: true),
              onSelected: (_timelineKey.currentState?.selectedMidiClipIds.length ?? 0) >= 2
                  ? _consolidateSelectedClips
                  : null,
            ),
            PlatformMenuItem(
              label: 'Bounce MIDI to Audio',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyB, meta: true),
              onSelected: _midiPlaybackManager?.selectedClipId != null
                  ? _bounceMidiToAudio
                  : null,
            ),
            const PlatformMenuItem(
              label: 'Select All',
              shortcut: SingleActivator(LogicalKeyboardKey.keyA, meta: true),
              onSelected: null, // Disabled - future feature
            ),
          ],
        ),

        // View Menu
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: !_uiLayout.isLibraryPanelCollapsed ? '✓ Show Library Panel' : 'Show Library Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
              onSelected: _toggleLibraryPanel,
            ),
            PlatformMenuItem(
              label: _uiLayout.isMixerVisible ? '✓ Show Mixer Panel' : 'Show Mixer Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
              onSelected: _toggleMixer,
            ),
            PlatformMenuItem(
              label: _uiLayout.isEditorPanelVisible ? '✓ Show Editor Panel' : 'Show Editor Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
              onSelected: _toggleEditor,
            ),
            PlatformMenuItem(
              label: _uiLayout.isVirtualPianoEnabled ? '✓ Show Virtual Piano' : 'Show Virtual Piano',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
              onSelected: _toggleVirtualPiano,
            ),
            PlatformMenuItem(
              label: 'Reset Panel Layout',
              onSelected: _resetPanelLayout,
            ),
            PlatformMenuItem(
              label: 'Settings...',
              onSelected: _appSettings,
            ),
            const PlatformMenuItem(
              label: 'Zoom In',
              shortcut: SingleActivator(LogicalKeyboardKey.equal, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            const PlatformMenuItem(
              label: 'Zoom Out',
              shortcut: SingleActivator(LogicalKeyboardKey.minus, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            const PlatformMenuItem(
              label: 'Zoom to Fit',
              shortcut: SingleActivator(LogicalKeyboardKey.digit0, meta: true),
              onSelected: null, // Disabled - future feature
            ),
          ],
        ),
      ],
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // Space bar to play/pause (context-aware: Piano Roll = loop, Timeline = arrangement)
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
          // ? key (Shift + /) to show keyboard shortcuts
          const SingleActivator(LogicalKeyboardKey.slash, shift: true): _showKeyboardShortcuts,
          // Cmd+E to split clip at insert marker (or playhead if no marker)
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _splitSelectedClipAtPlayhead,
          // Q to quantize clip (context-aware: works for clips in arrangement)
          const SingleActivator(LogicalKeyboardKey.keyQ): _quantizeSelectedClip,
          // Cmd+D to duplicate clip
          const SingleActivator(LogicalKeyboardKey.keyD, meta: true): _duplicateSelectedClip,
          // Cmd+A to select all clips (in timeline view)
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAllClips,
          // Cmd+J to consolidate clips
          const SingleActivator(LogicalKeyboardKey.keyJ, meta: true): _consolidateSelectedClips,
          // Cmd+B to bounce MIDI to audio
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): _bounceMidiToAudio,
          // L to toggle loop playback
          const SingleActivator(LogicalKeyboardKey.keyL): _uiLayout.toggleLoopPlayback,
          // M to toggle metronome
          const SingleActivator(LogicalKeyboardKey.keyM): _toggleMetronome,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
        backgroundColor: context.colors.standard,
        body: Column(
          children: [
          // Transport bar (with logo and file/mixer buttons)
          // PERFORMANCE: Use ValueListenableBuilder for playhead-only updates
          ValueListenableBuilder<double>(
            valueListenable: _playbackController.playheadNotifier,
            builder: (context, playheadPos, _) => TransportBar(
            onPlay: _play,
            onPause: _pause,
            onStop: _stopPlayback,
            onRecord: _toggleRecording,
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
            onMakeCopy: _makeCopy,
            onExportAudio: _exportAudio,
            onExportMp3: _quickExportMp3,
            onExportWav: _quickExportWav,
            onExportMidi: _exportMidi,
            onAppSettings: _appSettings, // App-wide settings (logo click)
            onProjectSettings: _openProjectSettings, // Project-specific settings (song name click)
            onCloseProject: _closeProject,
            projectName: _projectMetadata.name,
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
                        child: LibraryPanel(
                          isCollapsed: _uiLayout.isLibraryPanelCollapsed,
                          onToggle: _toggleLibraryPanel,
                          availableVst3Plugins: _vst3PluginManager?.availablePlugins ?? [],
                          libraryService: _libraryService,
                          onItemDoubleClick: _handleLibraryItemDoubleClick,
                          onVst3DoubleClick: _handleVst3DoubleClick,
                        ),
                      ),

                      // Divider: Library/Timeline
                      ResizableDivider(
                        orientation: DividerOrientation.vertical,
                        isCollapsed: _uiLayout.isLibraryPanelCollapsed,
                        onDrag: (delta) {
                          final windowWidth = MediaQuery.of(context).size.width;
                          final maxWidth = UILayoutState.getLibraryMaxWidth(windowWidth);
                          setState(() {
                            final newWidth = _uiLayout.libraryPanelWidth + delta;
                            // Snap collapse if dragged below threshold
                            if (newWidth < UILayoutState.libraryCollapseThreshold) {
                              _uiLayout.collapseLibrary();
                              _userSettings.libraryCollapsed = true;
                            } else {
                              _uiLayout.libraryPanelWidth = newWidth.clamp(
                                UILayoutState.libraryMinWidth,
                                maxWidth,
                              );
                              _userSettings.libraryWidth = _uiLayout.libraryPanelWidth;
                            }
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
                          getRustClipId: (dartClipId) => _midiPlaybackManager?.dartToRustClipIds[dartClipId] ?? dartClipId,
                          onMidiClipDeleted: _deleteMidiClip,
                          onInstrumentDropped: _onInstrumentDropped,
                          onInstrumentDroppedOnEmpty: _onInstrumentDroppedOnEmpty,
                          onVst3InstrumentDropped: _onVst3InstrumentDropped,
                          onVst3InstrumentDroppedOnEmpty: _onVst3InstrumentDroppedOnEmpty,
                          onAudioFileDroppedOnEmpty: _onAudioFileDroppedOnEmpty,
                          onCreateTrackWithClip: _onCreateTrackWithClip,
                          onCreateClipOnTrack: _onCreateClipOnTrack,
                          trackHeights: _trackHeights,
                          masterTrackHeight: _masterTrackHeight,
                          trackOrder: _trackController.trackOrder,
                          getTrackColor: _getTrackColor,
                          onSeek: (position) {
                            _audioEngine?.transportSeek(position);
                            setState(() {
                              _playheadPosition = position;
                            });
                          },
                          // Loop playback state
                          loopPlaybackEnabled: _uiLayout.loopPlaybackEnabled,
                          loopStartBeats: _uiLayout.loopStartBeats,
                          loopEndBeats: _uiLayout.loopEndBeats,
                          onLoopRegionChanged: (start, end) {
                            _uiLayout.setLoopRegion(start, end);
                          },
                          // Vertical scroll sync with mixer panel
                          verticalScrollController: _timelineVerticalScrollController,
                          // Tool mode (shared with piano roll)
                          toolMode: _currentToolMode,
                          onToolModeChanged: (mode) => setState(() => _currentToolMode = mode),
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
                            onTrackSelected: _onTrackSelected,
                            onInstrumentSelected: _onInstrumentSelected,
                            onTrackDuplicated: _onTrackDuplicated,
                            onTrackDeleted: _onTrackDeleted,
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
                            trackHeights: _trackHeights,
                            masterTrackHeight: _masterTrackHeight,
                            onTrackHeightChanged: _setTrackHeight,
                            onMasterTrackHeightChanged: _setMasterTrackHeight,
                            onTogglePanel: _toggleMixer,
                            getTrackColor: _getTrackColor,
                            onTrackColorChanged: _setTrackColor,
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
                // Only show when editor is enabled in View menu
                if (_uiLayout.isEditorPanelVisible) ...[
                  // Resizable divider above editor
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

                  SizedBox(
                    height: _uiLayout.editorPanelHeight,
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
                      isCollapsed: false,
                      toolMode: _currentToolMode,
                      onToolModeChanged: (mode) => setState(() => _currentToolMode = mode),
                    ),
                  ),
                ],

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

