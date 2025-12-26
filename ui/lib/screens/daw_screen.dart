import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import '../audio_engine.dart';
import '../widgets/transport_bar.dart';
import '../widgets/timeline_view.dart';
import '../widgets/track_mixer_panel.dart';
import '../widgets/library_panel.dart';
import '../widgets/editor_panel.dart';
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
import '../services/library_service.dart';
import '../services/vst3_plugin_manager.dart';
import '../services/project_manager.dart';
import '../services/midi_playback_manager.dart';
import '../services/user_settings.dart';
import '../services/auto_save_service.dart';
import '../services/vst3_editor_service.dart';
import '../services/plugin_preferences_service.dart';
import '../widgets/settings_dialog.dart';
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

  // M8: MIDI playback manager (lazy initialized when audio engine is ready)
  MidiPlaybackManager? _midiPlaybackManager;

  // User settings and auto-save
  final UserSettings _userSettings = UserSettings();
  final AutoSaveService _autoSaveService = AutoSaveService();

  // State (clip-specific state remains local)
  int? _loadedClipId;
  double? _clipDuration;
  List<double> _waveformPeaks = [];
  bool _isAudioGraphInitialized = false;
  bool _isLoading = false;

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

    // Load user settings
    _userSettings.load().then((_) {
      debugPrint('[DAW] User settings loaded');
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
    _uiLayout.removeListener(_onControllerChanged);

    // Dispose controllers
    _playbackController.dispose();
    _recordingController.dispose();

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
      _audioEngine!.initAudioGraph();

      // Initialize recording settings
      try {
        _audioEngine!.setCountInBars(2); // Default: 2 bars
        _audioEngine!.setTempo(120.0);   // Default: 120 BPM
        _audioEngine!.setMetronomeEnabled(true); // Default: enabled

      } catch (e) {
        debugPrint('❌ Failed to initialize recording settings: $e');
      }

      debugPrint('🔧 [DAW] About to set initialized state, mounted=$mounted');
      if (mounted) {
        setState(() {
          _isAudioGraphInitialized = true;
        });
        debugPrint('✅ [DAW] Audio graph initialized state set to true');
        _playbackController.setStatusMessage('Ready to record or load audio files');
      } else {
        debugPrint('❌ [DAW] Widget not mounted, cannot set state!');
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to initialize: $e';
        });
      }
      debugPrint('❌ Audio engine init failed: $e');
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
            final clipData = MidiClipData(
              clipId: result.midiClipId!,
              trackId: trackId >= 0 ? trackId : (_selectedTrackId ?? 0),
              startTime: startTimeBeats,
              duration: durationBeats,
              name: 'Recorded MIDI',
              notes: [], // Notes are managed by the engine
            );

            _midiPlaybackManager?.addRecordedClip(clipData);
            recordedItems.add('MIDI ($noteCount notes)');
          }
        } catch (e) {
          debugPrint('❌ Failed to parse MIDI clip info: $e');
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

  void _onTempoChanged(double bpm) {
    _recordingController.setTempo(bpm);
    _midiClipController.setTempo(bpm);
    // Reschedule all MIDI clips with new tempo
    _midiPlaybackManager?.rescheduleAllClips(bpm);
  }

  // M3: Virtual piano methods
  void _toggleVirtualPiano() {
    final success = _recordingController.toggleVirtualPiano();
    if (success) {
      _uiLayout.setVirtualPianoEnabled(_recordingController.isVirtualPianoEnabled);
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

  // M9: Instrument methods
  void _onInstrumentSelected(int trackId, String instrumentId) {
    // Create default instrument data for the track
    final instrumentData = InstrumentData.defaultSynthesizer(trackId);
    _trackController.setTrackInstrument(trackId, instrumentData);
    _trackController.selectTrack(trackId);
    _uiLayout.isEditorPanelVisible = true;

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
  }

  void _onTrackDuplicated(int sourceTrackId, int newTrackId) {
    // Copy track state via controller
    _trackController.onTrackDuplicated(sourceTrackId, newTrackId);
  }

  void _onInstrumentDropped(int trackId, Instrument instrument) {
    // Reuse the same logic as _onInstrumentSelected
    _onInstrumentSelected(trackId, instrument.id);
  }

  /// Create a default 4-bar empty MIDI clip for a new track
  void _createDefaultMidiClip(int trackId) {
    // 4 bars = 16 beats (MIDI clips store duration in beats, not seconds)
    const durationBeats = 16.0;

    final defaultClip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: 0.0, // Start at beat 0
      duration: durationBeats,
      name: 'New MIDI Clip',
      notes: [],
    );

    _midiPlaybackManager?.addRecordedClip(defaultClip);
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
      debugPrint('❌ Failed to create new MIDI track');
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
  }

  // VST3 Instrument drop handlers
  Future<void> _onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (_audioEngine == null) return;

    try {
      // Load the VST3 plugin as a track instrument
      final effectId = _audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        debugPrint('❌ Failed to load VST3 instrument: ${plugin.name}');
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      _trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      debugPrint('🎹 Sending test note to VST3 instrument $effectId');
      final noteOnResult = _audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
        debugPrint('⚠️ Note on error: $noteOnResult');
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        final noteOffResult = _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
        if (noteOffResult.isNotEmpty) {
          debugPrint('⚠️ Note off error: $noteOffResult');
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading VST3 instrument: $e');
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
        debugPrint('❌ Failed to create new MIDI track');
        return;
      }

      // Create default 4-bar empty clip for the new track
      _createDefaultMidiClip(trackId);

      // Load the VST3 plugin as a track instrument
      final effectId = _audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        debugPrint('❌ Failed to load VST3 instrument: ${plugin.name}');
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      _trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      debugPrint('🎹 Sending test note to VST3 instrument $effectId');
      final noteOnResult = _audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
        debugPrint('⚠️ Note on error: $noteOnResult');
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        final noteOffResult = _audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
        if (noteOffResult.isNotEmpty) {
          debugPrint('⚠️ Note off error: $noteOffResult');
        }
      });

      // Select the newly created track and its clip
      _onTrackSelected(trackId);

      // Immediately refresh track widgets so the new track appears instantly
      _refreshTrackWidgets();
    } catch (e) {
      debugPrint('❌ Error creating MIDI track with VST3 instrument: $e');
    }
  }

  // Audio file drop handler - creates new audio track with clip
  Future<void> _onAudioFileDroppedOnEmpty(String filePath) async {
    if (_audioEngine == null) return;

    try {
      // 1. Create new audio track
      final command = CreateTrackCommand(
        trackType: 'audio',
        trackName: 'Audio',
      );

      await _undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        debugPrint('❌ Failed to create new audio track');
        return;
      }

      // 2. Load audio file to the newly created track
      final clipId = _audioEngine!.loadAudioFileToTrack(filePath, trackId);
      if (clipId < 0) {
        debugPrint('❌ Failed to load audio file: $filePath');
        return;
      }

      // 3. Get clip info
      final duration = _audioEngine!.getClipDuration(clipId);
      final peaks = _audioEngine!.getWaveformPeaks(clipId, 2000);

      // 4. Add to timeline view's clip list
      _timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: filePath,
        startTime: 0.0,
        duration: duration,
        waveformPeaks: peaks,
      ));

      // 6. Refresh track widgets
      _refreshTrackWidgets();

      final fileName = filePath.split('/').last;
      debugPrint('✅ Created audio track $trackId with clip $clipId: $fileName');
    } catch (e) {
      debugPrint('❌ Error creating audio track with file: $e');
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
        debugPrint('❌ Failed to create new $trackType track');
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

      debugPrint('✅ Created $trackType track $trackId with ${durationBeats / 4} bar clip at beat $startBeats');
    } catch (e) {
      debugPrint('❌ Error creating track with clip: $e');
    }
  }

  void _onCreateClipOnTrack(int trackId, double startBeats, double durationBeats) {
    // Create a new MIDI clip on the specified track
    _createMidiClipWithParams(trackId, startBeats, durationBeats);

    // Select the track
    _onTrackSelected(trackId);

    debugPrint('✅ Created MIDI clip on track $trackId: ${durationBeats / 4} bars at beat $startBeats');
  }

  /// Create a MIDI clip with custom start position and duration
  void _createMidiClipWithParams(int trackId, double startBeats, double durationBeats) {
    final clip = MidiClipData(
      clipId: DateTime.now().millisecondsSinceEpoch,
      trackId: trackId,
      startTime: startBeats,
      duration: durationBeats,
      loopLength: durationBeats, // Loop length matches arrangement length initially
      name: 'New MIDI Clip',
      notes: [],
    );

    _midiPlaybackManager?.addRecordedClip(clip);
  }

  // Library double-click handlers
  void _handleLibraryItemDoubleClick(LibraryItem item) {
    if (_audioEngine == null) return;

    final selectedTrack = _selectedTrackId;
    final isEmptyMidi = selectedTrack != null && _isEmptyMidiTrack(selectedTrack);
    final isEmptyAudio = selectedTrack != null && _isEmptyAudioTrack(selectedTrack);

    switch (item.type) {
      case LibraryItemType.instrument:
        // Find the matching Instrument from availableInstruments
        final instrument = _findInstrumentByName(item.name);
        if (instrument != null) {
          if (isEmptyMidi) {
            // Load onto selected empty MIDI track
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
            if (isEmptyMidi) {
              // Load onto selected empty MIDI track
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
    final isEmptyMidi = selectedTrack != null && _isEmptyMidiTrack(selectedTrack);

    if (plugin.isInstrument) {
      if (isEmptyMidi) {
        // Load VST3 instrument onto selected empty MIDI track
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

  // Helper: Check if track is an empty MIDI track (no instrument assigned)
  bool _isEmptyMidiTrack(int trackId) {
    final info = _audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    final trackType = parts[2];
    if (trackType != 'midi') return false;

    // Empty if no instrument assigned
    return !_trackInstruments.containsKey(trackId);
  }

  // Helper: Check if track is an empty Audio track (no clips)
  bool _isEmptyAudioTrack(int trackId) {
    final info = _audioEngine?.getTrackInfo(trackId) ?? '';
    if (info.isEmpty) return false;

    final parts = info.split(',');
    if (parts.length < 3) return false;

    final trackType = parts[2];
    if (trackType != 'audio') return false;

    // Check if any clips are on this track
    final hasClips = _timelineKey.currentState?.hasClipsOnTrack(trackId) ?? false;
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
      return availableInstruments.firstWhere(
        (inst) => inst.id == id,
      );
    } catch (e) {
      return null;
    }
  }

  // Helper: Add audio clip to existing track
  void _addAudioClipToTrack(int trackId, String filePath) {
    if (_audioEngine == null) return;

    try {
      final clipId = _audioEngine!.loadAudioFileToTrack(filePath, trackId);
      if (clipId < 0) {
        debugPrint('❌ Failed to load audio file: $filePath');
        return;
      }

      final duration = _audioEngine!.getClipDuration(clipId);
      final peaks = _audioEngine!.getWaveformPeaks(clipId, 2000);

      _timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: filePath,
        startTime: 0.0,
        duration: duration,
        waveformPeaks: peaks,
      ));

      final fileName = filePath.split('/').last;
      debugPrint('✅ Added clip $clipId to track $trackId: $fileName');
    } catch (e) {
      debugPrint('❌ Error adding audio clip to track: $e');
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
        debugPrint('✅ Added effect $effectType to track $trackId');
      } else {
        debugPrint('❌ Failed to add effect $effectType');
      }
    } catch (e) {
      debugPrint('❌ Error adding effect to track: $e');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? '✅ ${result.message}' : '❌ ${result.message}'),
        duration: Duration(seconds: result.success ? 2 : 3),
        backgroundColor: result.success ? const Color(0xFF4CAF50) : const Color(0xFFFF5722),
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
                                const Text(
                                  'Drag the sliders to adjust plugin parameters.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
    List<Widget> sliders = [];

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
                  const Text(
                    '0.50',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
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
    });
  }

  void _toggleEditor() {
    setState(() {
      _uiLayout.isEditorPanelVisible = !_uiLayout.isEditorPanelVisible;
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
      _uiLayout.isEditorPanelVisible = true;
      _selectedTrackId = trackId ?? clipData.trackId;
    }
  }

  void _onMidiClipUpdated(MidiClipData updatedClip) {
    _midiClipController.updateClip(updatedClip, _playheadPosition);
  }

  void _onMidiClipCopied(MidiClipData sourceClip, double newStartTime) {
    _midiClipController.copyClipToTime(sourceClip, newStartTime);
  }

  void _duplicateSelectedClip() {
    _midiClipController.duplicateSelectedClip();
  }

  void _splitSelectedClipAtPlayhead() {
    // Use insert marker position if available, otherwise fall back to playhead
    final insertMarkerSeconds = _timelineKey.currentState?.getInsertMarkerSeconds();
    final splitPosition = insertMarkerSeconds ?? _playheadPosition;
    final usingInsertMarker = insertMarkerSeconds != null;

    // Try MIDI clip first
    if (_midiPlaybackManager?.selectedClipId != null) {
      final success = _midiClipController.splitSelectedClipAtPlayhead(splitPosition);
      if (success && mounted) {
        setState(() {
          _statusMessage = usingInsertMarker
              ? 'Split MIDI clip at insert marker'
              : 'Split MIDI clip at playhead';
        });
        return;
      }
    }

    // Try audio clip if no MIDI clip or MIDI split failed
    final audioSplit = _timelineKey.currentState?.splitSelectedAudioClipAtPlayhead(splitPosition) ?? false;
    if (audioSplit && mounted) {
      setState(() {
        _statusMessage = usingInsertMarker
            ? 'Split audio clip at insert marker'
            : 'Split audio clip at playhead';
      });
      return;
    }

    // Neither worked
    if (mounted) {
      setState(() {
        _statusMessage = usingInsertMarker
            ? 'Cannot split: select a clip and place insert marker within it'
            : 'Cannot split: select a clip and place playhead within it';
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
            const Text(
              'This feature will render the MIDI clip through its instrument '
              'to create an audio file.\n\n'
              'Coming soon in a future update.',
              style: TextStyle(color: Colors.grey),
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
    _midiClipController.deleteClip(clipId, trackId);
  }

  // ========================================================================
  // Undo/Redo methods
  // ========================================================================

  Future<void> _performUndo() async {
    final success = await _undoRedoManager.undo();
    if (success && mounted) {
      setState(() {
        _statusMessage = 'Undone: ${_undoRedoManager.redoDescription ?? "action"}';
      });
      _refreshTrackWidgets();
    }
  }

  Future<void> _performRedo() async {
    final success = await _undoRedoManager.redo();
    if (success && mounted) {
      setState(() {
        _statusMessage = 'Redone: ${_undoRedoManager.undoDescription ?? "action"}';
      });
      _refreshTrackWidgets();
    }
  }

  // M5: Project file methods
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
      // Use macOS native file picker
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Select Boojy Audio Project (.audio folder)")'
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
      debugPrint('Open project failed: $e');
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
      debugPrint('Open recent project failed: $e');
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
        PlatformMenuItem(
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
      // Use macOS native file picker for save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Choose location to save project")'
      ]);

      if (result.exitCode == 0) {
        final parentPath = result.stdout.toString().trim();
        if (parentPath.isNotEmpty) {
          final projectPath = '$parentPath/$projectName.audio';
          _saveProjectToPath(projectPath);
        }
      }
    } catch (e) {
      debugPrint('Save As failed: $e');
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
      _uiLayout.libraryPanelWidth = layout.libraryWidth.clamp(UILayoutState.libraryMinWidth, UILayoutState.libraryMaxWidth);
      _uiLayout.mixerPanelWidth = layout.mixerWidth.clamp(UILayoutState.mixerMinWidth, UILayoutState.mixerMaxWidth);
      _uiLayout.editorPanelHeight = layout.bottomHeight.clamp(UILayoutState.editorMinHeight, UILayoutState.editorMaxHeight);

      // Apply collapsed states
      _uiLayout.isLibraryPanelCollapsed = layout.libraryCollapsed;
      _uiLayout.isMixerVisible = !layout.mixerCollapsed;
      // Don't auto-open bottom panel on load
    });
  }

  /// Get current UI layout for saving
  UILayoutData _getCurrentUILayout() {
    return UILayoutData(
      libraryWidth: _uiLayout.libraryPanelWidth,
      mixerWidth: _uiLayout.mixerPanelWidth,
      bottomHeight: _uiLayout.editorPanelHeight,
      libraryCollapsed: _uiLayout.isLibraryPanelCollapsed,
      mixerCollapsed: !_uiLayout.isMixerVisible,
      bottomCollapsed: !(_uiLayout.isEditorPanelVisible || _uiLayout.isVirtualPianoVisible),
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
      debugPrint('[DAW] Crash recovery check failed: $e');
    }
  }

  void _exportAudio() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Audio'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose export format:'),
            SizedBox(height: 16),
            Text('• WAV - Lossless (Recommended)'),
            Text('• MP3 - 128 kbps (Coming Soon)'),
            Text('• Stems - Individual tracks (Coming Soon)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);

              // Get export path
              try {
                final result = await Process.run('osascript', [
                  '-e',
                  'POSIX path of (choose file name with prompt "Export as" default name "${_projectManager?.currentName ?? 'Untitled'}.wav")'
                ]);

                if (result.exitCode == 0) {
                  final path = result.stdout.toString().trim();
                  if (path.isNotEmpty) {
                    try {
                      final exportResult = _audioEngine!.exportToWav(path, true);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text(exportResult)),
                      );
                    } catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('Export not yet implemented: $e')),
                      );
                    }
                  }
                }
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Failed to export: $e')),
                );
              }
            },
            child: const Text('Export WAV'),
          ),
        ],
      ),
    );
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
      // Use macOS native file picker for save location
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Choose location for copy")'
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
      debugPrint('Make Copy failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create copy: $e')),
        );
      }
    }
  }

  void _projectSettings() {
    // Get current audio devices
    final inputDevices = _audioEngine?.getAudioInputDevices() ?? [];
    final outputDevices = _audioEngine?.getAudioOutputDevices() ?? [];
    final sampleRate = _audioEngine?.getSampleRate() ?? 48000;

    // Find default devices
    String? selectedInputDevice;
    String? selectedOutputDevice;
    for (final device in inputDevices) {
      if (device['isDefault'] == true) {
        selectedInputDevice = device['name'] as String?;
        break;
      }
    }
    for (final device in outputDevices) {
      if (device['isDefault'] == true) {
        selectedOutputDevice = device['name'] as String?;
        break;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Audio Settings'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Audio Output Device
                const Text(
                  'Audio Output Device',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: selectedOutputDevice,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select output device'),
                    items: outputDevices.map((device) {
                      final name = device['name'] as String;
                      final isDefault = device['isDefault'] as bool;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(isDefault ? '$name (Default)' : name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedOutputDevice = value;
                      });
                      // Note: Output device switching requires stream recreation
                      // which is not yet implemented
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Audio Input Device
                const Text(
                  'Audio Input Device',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: selectedInputDevice,
                    isExpanded: true,
                    underline: const SizedBox(),
                    hint: const Text('Select input device'),
                    items: inputDevices.map((device) {
                      final name = device['name'] as String;
                      final isDefault = device['isDefault'] as bool;
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(isDefault ? '$name (Default)' : name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedInputDevice = value;
                      });
                      // Find index and set device
                      final index = inputDevices.indexWhere((d) => d['name'] == value);
                      if (index >= 0) {
                        _audioEngine?.setAudioInputDevice(index);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Sample Rate (read-only)
                const Text(
                  'Sample Rate',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text('$sampleRate Hz'),
                      const Spacer(),
                      Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade500),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sample rate is fixed at 48kHz for optimal compatibility.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

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
            child: const Text('Close', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              onSelected: _projectSettings,
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
                  ? 'Undo ${_undoRedoManager.undoDescription ?? ""}'
                  : 'Undo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              onSelected: _undoRedoManager.canUndo ? _performUndo : null,
            ),
            PlatformMenuItem(
              label: _undoRedoManager.canRedo
                  ? 'Redo ${_undoRedoManager.redoDescription ?? ""}'
                  : 'Redo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
              onSelected: _undoRedoManager.canRedo ? _performRedo : null,
            ),
            PlatformMenuItem(
              label: 'Cut',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            PlatformMenuItem(
              label: 'Copy',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            PlatformMenuItem(
              label: 'Paste',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
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
            PlatformMenuItem(
              label: 'Select All',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
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
              onSelected: () => SettingsDialog.show(context),
            ),
            PlatformMenuItem(
              label: 'Zoom In',
              shortcut: const SingleActivator(LogicalKeyboardKey.equal, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            PlatformMenuItem(
              label: 'Zoom Out',
              shortcut: const SingleActivator(LogicalKeyboardKey.minus, meta: true),
              onSelected: null, // Disabled - future feature
            ),
            PlatformMenuItem(
              label: 'Zoom to Fit',
              shortcut: const SingleActivator(LogicalKeyboardKey.digit0, meta: true),
              onSelected: null, // Disabled - future feature
            ),
          ],
        ),
      ],
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
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
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
        backgroundColor: const Color(0xFF242424), // Dark grey background
        body: Column(
        children: [
          // Transport bar (with logo and file/mixer buttons)
          TransportBar(
            onPlay: _play,
            onPause: _pause,
            onStop: _stopPlayback,
            onRecord: _toggleRecording,
            onMetronomeToggle: _toggleMetronome,
            onPianoToggle: _toggleVirtualPiano,
            playheadPosition: _playheadPosition,
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
            // New parameters for file menu and mixer toggle
            onNewProject: _newProject,
            onOpenProject: _openProject,
            onSaveProject: _saveProject,
            onSaveProjectAs: _saveProjectAs,
            onMakeCopy: _makeCopy,
            onExportAudio: _exportAudio,
            onExportMidi: _exportMidi,
            onProjectSettings: _projectSettings,
            onCloseProject: _closeProject,
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
            isLoading: _isLoading,
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
                          setState(() {
                            _uiLayout.libraryPanelWidth = (_uiLayout.libraryPanelWidth + delta)
                                .clamp(UILayoutState.libraryMinWidth, UILayoutState.libraryMaxWidth);
                          });
                        },
                        onDoubleClick: () {
                          setState(() {
                            _uiLayout.isLibraryPanelCollapsed = !_uiLayout.isLibraryPanelCollapsed;
                          });
                        },
                      ),

                      // Center: Timeline area
                      Expanded(
                        child: TimelineView(
                          key: _timelineKey,
                          playheadPosition: _playheadPosition,
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
                          getTrackColor: _getTrackColor,
                          onSeek: (position) {
                            _audioEngine?.transportSeek(position);
                            setState(() {
                              _playheadPosition = position;
                            });
                          },
                        ),
                      ),

                      // Right: Track mixer panel (always visible)
                      if (_uiLayout.isMixerVisible) ...[
                        // Divider: Timeline/Mixer
                        ResizableDivider(
                          orientation: DividerOrientation.vertical,
                          isCollapsed: false,
                          onDrag: (delta) {
                            setState(() {
                              _uiLayout.mixerPanelWidth = (_uiLayout.mixerPanelWidth - delta)
                                  .clamp(UILayoutState.mixerMinWidth, UILayoutState.mixerMaxWidth);
                            });
                          },
                          onDoubleClick: () {
                            setState(() {
                              _uiLayout.isMixerVisible = false;
                            });
                          },
                        ),

                        SizedBox(
                          width: _uiLayout.mixerPanelWidth,
                          child: TrackMixerPanel(
                            key: _mixerKey,
                            audioEngine: _audioEngine,
                            isEngineReady: _isAudioGraphInitialized,
                            selectedTrackId: _selectedTrackId,
                            onTrackSelected: _onTrackSelected,
                            onInstrumentSelected: _onInstrumentSelected,
                            onTrackDuplicated: _onTrackDuplicated,
                            onTrackDeleted: _onTrackDeleted,
                            trackInstruments: _trackInstruments,
                            trackVst3PluginCounts: _getTrackVst3PluginCounts(), // M10
                            onFxButtonPressed: _showVst3PluginBrowser, // M10
                            onVst3PluginDropped: _onVst3PluginDropped, // M10
                            onEditPluginsPressed: _showVst3PluginEditor, // M10
                            onAudioFileDropped: _onAudioFileDroppedOnEmpty,
                            onMidiTrackCreated: _createDefaultMidiClip,
                            trackHeights: _trackHeights,
                            masterTrackHeight: _masterTrackHeight,
                            onTrackHeightChanged: _setTrackHeight,
                            onMasterTrackHeightChanged: _setMasterTrackHeight,
                            onTogglePanel: _toggleMixer,
                            getTrackColor: _getTrackColor,
                            onTrackColorChanged: _setTrackColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Editor panel: Piano Roll / FX Chain / Instrument / Virtual Piano
                if (_uiLayout.isEditorPanelVisible || _uiLayout.isVirtualPianoVisible) ...[
                  // Divider: Timeline/Editor Panel
                  ResizableDivider(
                    orientation: DividerOrientation.horizontal,
                    isCollapsed: false,
                    onDrag: (delta) {
                      setState(() {
                        _uiLayout.editorPanelHeight = (_uiLayout.editorPanelHeight - delta)
                            .clamp(UILayoutState.editorMinHeight, UILayoutState.editorMaxHeight);
                      });
                    },
                    onDoubleClick: () {
                      setState(() {
                        _uiLayout.isEditorPanelVisible = false;
                        _uiLayout.isVirtualPianoVisible = false;
                        _uiLayout.isVirtualPianoEnabled = false;
                      });
                    },
                  ),

                  SizedBox(
                    height: _uiLayout.editorPanelHeight,
                    child: EditorPanel(
                      audioEngine: _audioEngine,
                      virtualPianoEnabled: _uiLayout.isVirtualPianoEnabled,
                      selectedTrackId: _selectedTrackId,
                      currentInstrumentData: _selectedTrackId != null
                          ? _trackInstruments[_selectedTrackId]
                          : null,
                      onVirtualPianoClose: _toggleVirtualPiano,
                      onClosePanel: () {
                        setState(() {
                          _uiLayout.isEditorPanelVisible = false;
                          _uiLayout.isVirtualPianoVisible = false;
                          _uiLayout.isVirtualPianoEnabled = false;
                        });
                      },
                      currentEditingClip: _midiPlaybackManager?.currentEditingClip,
                      onMidiClipUpdated: _onMidiClipUpdated,
                      onInstrumentParameterChanged: _onInstrumentParameterChanged,
                      currentTrackPlugins: _selectedTrackId != null // M10
                          ? _getTrackVst3Plugins(_selectedTrackId!)
                          : null,
                      onVst3ParameterChanged: _onVst3ParameterChanged, // M10
                      onVst3PluginRemoved: _removeVst3Plugin, // M10
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Status bar
          _buildStatusBar(),
        ],
      ),
    ),
        ),  // Close Focus
      ),  // Close CallbackShortcuts
    );
  }

  // Removed _buildTimelineView - now built inline in build method

  Widget _buildLatencyDisplay() {
    if (_audioEngine == null || !_isAudioGraphInitialized) {
      return const Text(
        '--ms',
        style: TextStyle(
          color: Color(0xFF808080),
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      );
    }

    final latencyInfo = _audioEngine!.getLatencyInfo();
    final roundtripMs = latencyInfo['roundtripMs'] ?? 0.0;

    // Color based on latency quality
    Color latencyColor;
    if (roundtripMs < 10) {
      latencyColor = const Color(0xFF4CAF50); // Green - excellent
    } else if (roundtripMs < 20) {
      latencyColor = const Color(0xFF8BC34A); // Light green - good
    } else if (roundtripMs < 30) {
      latencyColor = const Color(0xFFFFC107); // Yellow - acceptable
    } else {
      latencyColor = const Color(0xFFFF9800); // Orange - high
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

    final currentPreset = _audioEngine!.getBufferSizePreset();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Audio Latency Settings',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Buffer Size',
              style: TextStyle(color: Color(0xFF909090), fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...AudioEngine.bufferSizePresets.entries.map((entry) {
              final isSelected = entry.key == currentPreset;
              return InkWell(
                onTap: () {
                  _audioEngine!.setBufferSize(entry.key);
                  Navigator.of(context).pop();
                  setState(() {}); // Refresh display
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF00BCD4).withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF00BCD4)
                          : const Color(0xFF404040),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isSelected)
                        const Icon(Icons.check, size: 16, color: Color(0xFF00BCD4))
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00BCD4) : Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            const Text(
              'Lower latency = more responsive but higher CPU usage.\n'
              'If you hear audio glitches, try a higher buffer size.',
              style: TextStyle(color: Color(0xFF707070), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF141414), // Darker background
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: Row(
        children: [
          // Engine status with icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _isAudioGraphInitialized
                  ? const Color(0xFF00BCD4).withValues(alpha: 0.15)
                  : const Color(0xFF616161).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAudioGraphInitialized ? Icons.check_circle : Icons.hourglass_empty,
                  size: 12,
                  color: _isAudioGraphInitialized
                      ? const Color(0xFF00BCD4)
                      : const Color(0xFF616161),
                ),
                const SizedBox(width: 4),
                Text(
                  _isAudioGraphInitialized ? 'Ready' : 'Initializing...',
                  style: TextStyle(
                    color: _isAudioGraphInitialized
                        ? const Color(0xFF00BCD4)
                        : const Color(0xFF616161),
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
            const Icon(Icons.timelapse, size: 11, color: Color(0xFF707070)),
            const SizedBox(width: 4),
            Text(
              '${_clipDuration!.toStringAsFixed(2)}s',
              style: const TextStyle(
                color: Color(0xFF808080),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 16),
          ],
          // Sample rate with icon
          const Icon(Icons.graphic_eq, size: 11, color: Color(0xFF707070)),
          const SizedBox(width: 4),
          const Text(
            '48kHz',
            style: TextStyle(
              color: Color(0xFF808080),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 16),
          // Latency display with icon
          const Icon(Icons.speed, size: 11, color: Color(0xFF707070)),
          const SizedBox(width: 4),
          _buildLatencyDisplay(),
          const SizedBox(width: 16),
          // CPU with icon
          const Icon(Icons.memory, size: 11, color: Color(0xFF707070)),
          const SizedBox(width: 4),
          const Text(
            '0%',
            style: TextStyle(
              color: Color(0xFF808080),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

