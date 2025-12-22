import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../audio_engine.dart';
import '../widgets/transport_bar.dart';
import '../widgets/timeline_view.dart';
import '../widgets/track_mixer_panel.dart';
import '../widgets/library_panel.dart';
import '../widgets/editor_panel.dart';
import '../widgets/resizable_divider.dart';
import '../widgets/instrument_browser.dart';
import '../widgets/vst3_plugin_browser.dart';
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

/// Main DAW screen with timeline, transport controls, and file import
class DAWScreen extends StatefulWidget {
  const DAWScreen({super.key});

  @override
  State<DAWScreen> createState() => _DAWScreenState();
}

class _DAWScreenState extends State<DAWScreen> {
  AudioEngine? _audioEngine;
  Timer? _playheadTimer;
  Timer? _recordingStateTimer;

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

  // State
  double _playheadPosition = 0.0;
  int? _loadedClipId;
  double? _clipDuration;
  List<double> _waveformPeaks = [];
  bool _isPlaying = false;
  bool _isAudioGraphInitialized = false;
  String _statusMessage = '';
  bool _isLoading = false;

  // M2: Recording state
  bool _isRecording = false;
  bool _isCountingIn = false;
  bool _isMetronomeEnabled = true;
  double _tempo = 120.0;

  // M3: Virtual piano state
  bool _isVirtualPianoEnabled = false;
  bool _isVirtualPianoVisible = false;

  // M4: Mixer state
  bool _isMixerVisible = true; // Always visible by default

  // M5: Project state (managed by ProjectManager)

  // M6: UI panel state
  bool _isLibraryPanelCollapsed = false;
  bool _isEditorPanelVisible = true; // Show editor panel by default

  // M7: Resizable panels state
  double _libraryPanelWidth = 200.0;
  double _mixerPanelWidth = 380.0;
  double _editorPanelHeight = 250.0;
  static const double _libraryMinWidth = 40.0;
  static const double _libraryMaxWidth = 400.0;
  static const double _mixerMinWidth = 200.0;
  static const double _mixerMaxWidth = 600.0;
  static const double _editorMinHeight = 100.0;
  static const double _editorMaxHeight = 500.0;

  // M8: MIDI editing state (managed by MidiPlaybackManager, except track selection)
  int? _selectedTrackId; // Unified track selection for piano roll, FX, and instrument panels

  // M9: Instrument state
  Map<int, InstrumentData> _trackInstruments = {}; // trackId -> InstrumentData

  // M10: VST3 Plugin state is now managed by _vst3PluginManager

  // MIDI Recording state
  List<Map<String, dynamic>> _midiDevices = [];
  int _selectedMidiDeviceIndex = -1;
  bool _isMidiRecording = false;

  // Track height state (synced between mixer and timeline)
  Map<int, double> _trackHeights = {}; // trackId -> height (default 100.0)
  double _masterTrackHeight = 60.0;
  static const double _defaultTrackHeight = 100.0;
  static const double _minTrackHeight = 50.0;
  static const double _maxTrackHeight = 300.0;

  /// Get track height, returning default if not set
  double _getTrackHeight(int trackId) {
    return _trackHeights[trackId] ?? _defaultTrackHeight;
  }

  /// Set track height
  void _setTrackHeight(int trackId, double height) {
    setState(() {
      _trackHeights[trackId] = height.clamp(_minTrackHeight, _maxTrackHeight);
    });
  }

  /// Set master track height
  void _setMasterTrackHeight(double height) {
    setState(() {
      _masterTrackHeight = height.clamp(_minTrackHeight, _maxTrackHeight);
    });
  }

  // GlobalKeys for child widgets that need immediate refresh
  final GlobalKey<TimelineViewState> _timelineKey = GlobalKey<TimelineViewState>();
  final GlobalKey<TrackMixerPanelState> _mixerKey = GlobalKey<TrackMixerPanelState>();

  /// Trigger immediate refresh of track lists in both timeline and mixer panels
  void _refreshTrackWidgets() {
    _timelineKey.currentState?.refreshTracks();
    _mixerKey.currentState?.refreshTracks();
  }

  @override
  void initState() {
    super.initState();

    // Listen for undo/redo state changes to update menu
    _undoRedoManager.addListener(_onUndoRedoChanged);

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

    // Remove VST3 manager listener
    _vst3PluginManager?.removeListener(_onVst3ManagerChanged);

    // Remove project manager listener
    _projectManager?.removeListener(_onProjectManagerChanged);

    // Remove MIDI playback manager listener
    _midiPlaybackManager?.removeListener(_onMidiPlaybackManagerChanged);

    // Clean up timers
    _playheadTimer?.cancel();
    _recordingStateTimer?.cancel();

    // Stop playback
    _stopPlayback();

    super.dispose();
  }

  void _initAudioEngine() async {
    try {
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

      if (mounted) {
        setState(() {
          _isAudioGraphInitialized = true;
          _statusMessage = 'Ready to record or load audio files';
          _tempo = 120.0;
          _isMetronomeEnabled = true;
        });
      }

      // Initialize undo/redo manager with engine
      _undoRedoManager.initialize(_audioEngine!);

      // Initialize VST3 plugin manager
      _vst3PluginManager = Vst3PluginManager(_audioEngine!);
      _vst3PluginManager!.addListener(_onVst3ManagerChanged);

      // Initialize project manager
      _projectManager = ProjectManager(_audioEngine!);
      _projectManager!.addListener(_onProjectManagerChanged);

      // Initialize MIDI playback manager
      _midiPlaybackManager = MidiPlaybackManager(_audioEngine!);
      _midiPlaybackManager!.addListener(_onMidiPlaybackManagerChanged);

      // Scan VST3 plugins after audio graph is ready
      if (!_vst3PluginManager!.isScanned && mounted) {
        _scanVst3Plugins();
      }

      // Load MIDI devices
      _loadMidiDevices();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to initialize: $e';
        });
      }
      debugPrint('❌ Audio engine init failed: $e');
    }
  }

  void _loadAudioFile(String path) async {
    if (_audioEngine == null || !_isAudioGraphInitialized) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading file...';
    });

    try {
      // Load the file
      final clipId = _audioEngine!.loadAudioFile(path);
      
      if (clipId < 0) {
        setState(() {
          _statusMessage = 'Failed to load file';
          _isLoading = false;
        });
        return;
      }

      // Get duration
      final duration = _audioEngine!.getClipDuration(clipId);
      
      // Get waveform peaks for visualization
      final peaks = _audioEngine!.getWaveformPeaks(clipId, 2000);
      
      setState(() {
        _loadedClipId = clipId;
        _clipDuration = duration;
        _waveformPeaks = peaks;
        _statusMessage = 'Loaded: ${path.split('/').last} (${duration.toStringAsFixed(2)}s)';
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading file: $e';
        _isLoading = false;
      });
      debugPrint('❌ Load error: $e');
    }
  }

  void _startPlayheadTimer() {
    _playheadTimer?.cancel();
    // 16ms = ~60fps for smooth visual playhead updates
    // Previous 50ms caused noticeable visual lag
    _playheadTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_audioEngine != null && mounted) {
        final pos = _audioEngine!.getPlayheadPosition();
        if (mounted) {
          setState(() {
            _playheadPosition = pos;
          });
        }

        // Auto-stop at end of clip
        if (_clipDuration != null && pos >= _clipDuration!) {
          _stopPlayback();
        }
      }
    });
  }

  void _stopPlayheadTimer() {
    _playheadTimer?.cancel();
  }

  void _play() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.transportPlay();
      setState(() {
        _isPlaying = true;
        _statusMessage = _loadedClipId != null ? 'Playing...' : 'Playing (empty)';
      });
      _startPlayheadTimer();
      print('✅ [Flutter] _play() completed');
    } catch (e) {
      setState(() {
        _statusMessage = 'Play error: $e';
      });
    }
  }

  void _pause() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.transportPause();
      setState(() {
        _isPlaying = false;
        _statusMessage = 'Paused';
      });
      _stopPlayheadTimer();

      // NOTE: No longer need to call transportPlay() for virtual piano.
      // Synths now process audio even when transport is paused.
    } catch (e) {
      setState(() {
        _statusMessage = 'Pause error: $e';
      });
    }
  }

  void _stopPlayback() {
    print('🛑 [Flutter] _stopPlayback() called');
    if (_audioEngine == null) {
      print('⚠️  [Flutter] _audioEngine is null, returning');
      return;
    }

    try {
      print('📞 [Flutter] Calling _audioEngine.transportStop()...');
      final result = _audioEngine!.transportStop();
      print('✅ [Flutter] transportStop() returned: $result');

      setState(() {
        _isPlaying = false;
        _playheadPosition = 0.0;
        _statusMessage = 'Stopped';
      });
      _stopPlayheadTimer();

      // NOTE: No longer need to call transportPlay() for virtual piano.
      // Synths now process audio even when transport is stopped, allowing
      // real-time MIDI input (virtual piano) without triggering timeline MIDI clips.
      print('🏁 [Flutter] _stopPlayback() completed');
    } catch (e) {
      print('❌ [Flutter] Stop error: $e');
      setState(() {
        _statusMessage = 'Stop error: $e';
      });
    }
  }

  // File picking method
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'flac', 'aif', 'aiff'],
      dialogTitle: 'Select Audio File',
    );

    if (result != null && result.files.single.path != null) {
      _loadAudioFile(result.files.single.path!);
    }
  }

  // M2: Recording methods
  void _toggleRecording() {
    if (_audioEngine == null) return;

    if (_isRecording || _isCountingIn) {
      // Stop recording
      _stopRecording();
    } else {
      // Start recording
      _startRecording();
    }
  }

  void _startRecording() {
    if (_audioEngine == null) return;

    try {
      // Check current settings for status message
      final countInBars = _audioEngine!.getCountInBars();
      final tempo = _audioEngine!.getTempo();

      // Start audio recording
      _audioEngine!.startRecording();

      // Also start MIDI recording (for armed MIDI tracks)
      _audioEngine!.startMidiRecording();

      setState(() {
        _isCountingIn = true;
        _isMidiRecording = true;
        _statusMessage = 'Count-in... ($countInBars bars at $tempo BPM)';
        _tempo = tempo;
      });

      // Start timer to poll recording state
      _startRecordingStateTimer();
    } catch (e) {
      debugPrint('❌ Recording error: $e');
      setState(() {
        _statusMessage = 'Recording error: $e';
      });
    }
  }

  void _stopRecording() {
    if (_audioEngine == null) return;

    try {
      // Stop audio recording
      final audioClipId = _audioEngine!.stopRecording();

      // Stop MIDI recording
      final midiClipId = _audioEngine!.stopMidiRecording();

      setState(() {
        _isRecording = false;
        _isCountingIn = false;
        _isMidiRecording = false;
      });

      // Build status message based on what was recorded
      final List<String> recordedItems = [];

      if (audioClipId >= 0) {
        // Audio recording successful - get clip info
        final duration = _audioEngine!.getClipDuration(audioClipId);
        final peaks = _audioEngine!.getWaveformPeaks(audioClipId, 2000);

        setState(() {
          _loadedClipId = audioClipId;
          _clipDuration = duration;
          _waveformPeaks = peaks;
        });
        recordedItems.add('Audio ${duration.toStringAsFixed(2)}s');
      }

      if (midiClipId > 0) {
        // Get clip info from engine: "clip_id,track_id,start_time,duration,note_count"
        final clipInfo = _audioEngine!.getMidiClipInfo(midiClipId);

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
                clipId: midiClipId,
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

      setState(() {
        if (recordedItems.isNotEmpty) {
          _statusMessage = 'Recorded: ${recordedItems.join(', ')}';
        } else {
          _statusMessage = 'No recording captured';
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Stop recording error: $e';
        _isRecording = false;
        _isCountingIn = false;
        _isMidiRecording = false;
      });
    }
  }

  void _startRecordingStateTimer() {
    // Cancel any existing timer to prevent leaks
    _recordingStateTimer?.cancel();

    _recordingStateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_audioEngine == null || (!_isRecording && !_isCountingIn)) {
        timer.cancel();
        _recordingStateTimer = null;
        return;
      }

      final state = _audioEngine!.getRecordingState();
      final duration = _audioEngine!.getRecordedDuration();

      if (state == 1 && !_isCountingIn) {
        // Transitioned to count-in
        setState(() {
          _isCountingIn = true;
          _statusMessage = 'Count-in...';
        });
      } else if (state == 2 && !_isRecording) {
        // Transitioned to recording
        setState(() {
          _isCountingIn = false;
          _isRecording = true;
          _statusMessage = 'Recording... ${duration.toStringAsFixed(1)}s';
        });
      } else if (state == 2 && _isRecording) {
        // Update recording duration display
        setState(() {
          _statusMessage = 'Recording... ${duration.toStringAsFixed(1)}s';
        });
      } else if (state == 0 && (_isRecording || _isCountingIn)) {
        // Recording stopped
        timer.cancel();
        _recordingStateTimer = null;
        setState(() {
          _isRecording = false;
          _isCountingIn = false;
        });
      }
    });
  }

  void _toggleMetronome() {
    if (_audioEngine == null) return;

    try {
      final newState = !_isMetronomeEnabled;
      _audioEngine!.setMetronomeEnabled(newState);
      setState(() {
        _isMetronomeEnabled = newState;
        _statusMessage = newState ? 'Metronome enabled' : 'Metronome disabled';
      });
    } catch (e) {
      debugPrint('❌ Metronome toggle error: $e');
      setState(() {
        _statusMessage = 'Metronome toggle error: $e';
      });
    }
  }

  void _onTempoChanged(double bpm) {
    if (_audioEngine == null) return;

    // Clamp tempo to valid range (20-300 BPM)
    final clampedBpm = bpm.clamp(20.0, 300.0);

    try {
      _audioEngine!.setTempo(clampedBpm);
      setState(() {
        _tempo = clampedBpm;
      });
    } catch (e) {
      debugPrint('❌ Tempo change error: $e');
      setState(() {
        _statusMessage = 'Tempo change error: $e';
      });
    }
  }

  // M3: Virtual piano methods
  void _toggleVirtualPiano() {
    if (_audioEngine == null) return;

    setState(() {
      _isVirtualPianoEnabled = !_isVirtualPianoEnabled;

      if (_isVirtualPianoEnabled) {
        // Enable: Initialize MIDI, start audio stream, and show panel
        try {
          _audioEngine!.startMidiInput();

          // CRITICAL: Start audio output stream so synthesizer can be heard
          // The synthesizer generates audio but needs the stream running to output it
          _audioEngine!.transportPlay();

          _isVirtualPianoVisible = true;
          _statusMessage = 'Virtual piano enabled - Press keys to play!';
        } catch (e) {
          debugPrint('❌ Virtual piano enable error: $e');
          _statusMessage = 'Virtual piano error: $e';
          _isVirtualPianoEnabled = false;
          _isVirtualPianoVisible = false;
        }
      } else {
        // Disable: Hide panel
        _isVirtualPianoVisible = false;
        _isEditorPanelVisible = false; // Hide editor panel when piano disabled
        _statusMessage = 'Virtual piano disabled';
      }
    });
  }

  // MIDI Device methods
  void _loadMidiDevices() {
    if (_audioEngine == null) return;

    try {
      final devices = _audioEngine!.getMidiInputDevices();

      setState(() {
        _midiDevices = devices;

        // Auto-select default device if available
        if (_selectedMidiDeviceIndex < 0 && devices.isNotEmpty) {
          final defaultIndex = devices.indexWhere((d) => d['isDefault'] == true);
          if (defaultIndex >= 0) {
            _selectedMidiDeviceIndex = defaultIndex;
            _onMidiDeviceSelected(defaultIndex);
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Failed to load MIDI devices: $e');
    }
  }

  void _onMidiDeviceSelected(int deviceIndex) {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.selectMidiInputDevice(deviceIndex);

      setState(() {
        _selectedMidiDeviceIndex = deviceIndex;
      });

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
    } catch (e) {
      debugPrint('❌ Failed to select MIDI device: $e');
    }
  }

  void _refreshMidiDevices() {
    if (_audioEngine == null) return;

    try {
      _audioEngine!.refreshMidiDevices();
      _loadMidiDevices();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎹 MIDI devices refreshed'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to refresh MIDI devices: $e');
    }
  }

  // M4: Mixer methods
  void _toggleMixer() {
    setState(() {
      _isMixerVisible = !_isMixerVisible;
    });
  }

  // Unified track selection method - handles both timeline and mixer clicks
  void _onTrackSelected(int? trackId) {
    if (trackId == null) {
      setState(() {
        _selectedTrackId = null;
        _isEditorPanelVisible = false;
      });
      return;
    }

    setState(() {
      _selectedTrackId = trackId;
      _isEditorPanelVisible = true;
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
    setState(() {
      // Create default instrument data for the track
      final instrumentData = InstrumentData.defaultSynthesizer(trackId);
      _trackInstruments[trackId] = instrumentData;
      _selectedTrackId = trackId; // Select the track when instrument is assigned
      _isEditorPanelVisible = true; // Show editor panel when instrument selected

      // Call audio engine to set instrument
      if (_audioEngine != null) {
        _audioEngine!.setTrackInstrument(trackId, instrumentId);
      }
    });
  }

  void _onTrackDeleted(int trackId) {
    // Remove all MIDI clips for this track via manager
    _midiPlaybackManager?.removeClipsForTrack(trackId);

    setState(() {
      // Remove instrument mapping
      _trackInstruments.remove(trackId);
    });
  }

  void _onTrackDuplicated(int sourceTrackId, int newTrackId) {
    setState(() {
      // Copy instrument mapping from source track to new track if it exists
      if (_trackInstruments.containsKey(sourceTrackId)) {
        final sourceInstrument = _trackInstruments[sourceTrackId]!;
        // Create a copy with the new track ID
        _trackInstruments[newTrackId] = InstrumentData(
          trackId: newTrackId,
          type: sourceInstrument.type,
          parameters: Map.from(sourceInstrument.parameters),
        );
      }
    });
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

  void _onInstrumentDroppedOnEmpty(Instrument instrument) async {
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
  void _onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (_audioEngine == null) return;

    try {
      // Load the VST3 plugin as a track instrument
      final effectId = _audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        debugPrint('❌ Failed to load VST3 instrument: ${plugin.name}');
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      setState(() {
        _trackInstruments[trackId] = InstrumentData.vst3Instrument(
          trackId: trackId,
          pluginPath: plugin.path,
          pluginName: plugin.name,
          effectId: effectId,
        );
      });
    } catch (e) {
      debugPrint('❌ Error loading VST3 instrument: $e');
    }
  }

  void _onVst3InstrumentDroppedOnEmpty(Vst3Plugin plugin) async {
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
      setState(() {
        _trackInstruments[trackId] = InstrumentData.vst3Instrument(
          trackId: trackId,
          pluginPath: plugin.path,
          pluginName: plugin.name,
          effectId: effectId,
        );
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
  void _onAudioFileDroppedOnEmpty(String filePath) async {
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
    setState(() {
      _trackInstruments[instrumentData.trackId] = instrumentData;
    });
  }

  // M10: VST3 Plugin methods - delegating to Vst3PluginManager

  void _scanVst3Plugins({bool forceRescan = false}) async {
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

  void _showVst3PluginBrowser(int trackId) async {
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
      _isLibraryPanelCollapsed = !_isLibraryPanelCollapsed;
    });
  }

  void _toggleEditor() {
    setState(() {
      _isEditorPanelVisible = !_isEditorPanelVisible;
    });
  }

  void _resetPanelLayout() {
    setState(() {
      // Reset to default panel sizes
      _libraryPanelWidth = 200.0;
      _mixerPanelWidth = 380.0;
      _editorPanelHeight = 250.0;

      // Reset visibility states
      _isLibraryPanelCollapsed = false;
      _isMixerVisible = true;
      _isEditorPanelVisible = true;

      _statusMessage = 'Panel layout reset';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Panel layout reset to defaults')),
    );
  }

  // M8: MIDI clip selection methods - delegating to MidiPlaybackManager
  void _onMidiClipSelected(int? clipId, MidiClipData? clipData) {
    final trackId = _midiPlaybackManager?.selectClip(clipId, clipData);
    if (clipId != null && clipData != null) {
      setState(() {
        // Open piano roll and set the selected track
        _isEditorPanelVisible = true;
        _selectedTrackId = trackId ?? clipData.trackId;
      });
    }
  }

  void _onMidiClipUpdated(MidiClipData updatedClip) {
    // Convert playhead position from seconds to beats for MIDI clip placement
    final beatsPerSecond = _tempo / 60.0;
    final playheadPositionBeats = _playheadPosition * beatsPerSecond;
    _midiPlaybackManager?.updateClip(updatedClip, _tempo, playheadPositionBeats);
  }

  void _onMidiClipCopied(MidiClipData sourceClip, double newStartTime) {
    _midiPlaybackManager?.copyClip(sourceClip, newStartTime, _tempo);
    setState(() {});
  }

  /// Duplicate the currently selected clip in place (Cmd+D)
  /// Places the duplicate immediately after the original clip
  void _duplicateSelectedClip() {
    final clip = _midiPlaybackManager?.currentEditingClip;
    if (clip == null) return;

    // Place duplicate immediately after original
    final newStartTime = clip.startTime + clip.duration;
    _midiPlaybackManager?.copyClip(clip, newStartTime, _tempo);
    setState(() {});
  }

  /// Delete a MIDI clip by ID
  void _deleteMidiClip(int clipId, int trackId) {
    // Get Rust clip ID before removing from Dart side
    final rustClipId = _midiPlaybackManager?.dartToRustClipIds[clipId];

    // Remove from Dart side (MidiPlaybackManager)
    _midiPlaybackManager?.removeClip(clipId);

    // Remove from Rust engine
    if (rustClipId != null) {
      _audioEngine?.removeMidiClip(trackId, rustClipId);
    }

    setState(() {});
  }

  // ========================================================================
  // Undo/Redo methods
  // ========================================================================

  void _performUndo() async {
    final success = await _undoRedoManager.undo();
    if (success && mounted) {
      setState(() {
        _statusMessage = 'Undone: ${_undoRedoManager.redoDescription ?? "action"}';
      });
      _refreshTrackWidgets();
    }
  }

  void _performRedo() async {
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
              _projectManager?.newProject();
              _midiPlaybackManager?.clear();
              setState(() {
                _loadedClipId = null;
                _waveformPeaks = [];
                _statusMessage = 'New project created';
              });
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _openProject() async {
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

        // Apply UI layout if available
        if (loadResult.uiLayout != null) {
          _applyUILayout(loadResult.uiLayout!);
        }

        setState(() {
          _statusMessage = 'Project loaded: ${_projectManager!.currentName}';
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loadResult.result.message)),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Open project failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project: $e')),
      );
    }
  }

  void _saveProject() async {
    if (_projectManager?.currentPath != null) {
      _saveProjectToPath(_projectManager!.currentPath!);
    } else {
      _saveProjectAs();
    }
  }

  void _saveProjectAs() async {
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

  void _saveProjectToPath(String path) async {
    setState(() => _isLoading = true);

    final result = await _projectManager!.saveProjectToPath(path, _getCurrentUILayout());

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
      _libraryPanelWidth = layout.libraryWidth.clamp(_libraryMinWidth, _libraryMaxWidth);
      _mixerPanelWidth = layout.mixerWidth.clamp(_mixerMinWidth, _mixerMaxWidth);
      _editorPanelHeight = layout.bottomHeight.clamp(_editorMinHeight, _editorMaxHeight);

      // Apply collapsed states
      _isLibraryPanelCollapsed = layout.libraryCollapsed;
      _isMixerVisible = !layout.mixerCollapsed;
      // Don't auto-open bottom panel on load
    });
  }

  /// Get current UI layout for saving
  UILayoutData _getCurrentUILayout() {
    return UILayoutData(
      libraryWidth: _libraryPanelWidth,
      mixerWidth: _mixerPanelWidth,
      bottomHeight: _editorPanelHeight,
      libraryCollapsed: _isLibraryPanelCollapsed,
      mixerCollapsed: !_isMixerVisible,
      bottomCollapsed: !(_isEditorPanelVisible || _isVirtualPianoVisible),
    );
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(exportResult)),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export not yet implemented: $e')),
                      );
                    }
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
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

  void _makeCopy() async {
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

              // Clear project state via manager
              _projectManager?.closeProject();
              setState(() {
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
              label: !_isLibraryPanelCollapsed ? '✓ Show Library Panel' : 'Show Library Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
              onSelected: _toggleLibraryPanel,
            ),
            PlatformMenuItem(
              label: _isMixerVisible ? '✓ Show Mixer Panel' : 'Show Mixer Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
              onSelected: _toggleMixer,
            ),
            PlatformMenuItem(
              label: _isEditorPanelVisible ? '✓ Show Editor Panel' : 'Show Editor Panel',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
              onSelected: _toggleEditor,
            ),
            PlatformMenuItem(
              label: _isVirtualPianoEnabled ? '✓ Show Virtual Piano' : 'Show Virtual Piano',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true),
              onSelected: _toggleVirtualPiano,
            ),
            PlatformMenuItem(
              label: 'Reset Panel Layout',
              onSelected: _resetPanelLayout,
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
            virtualPianoEnabled: _isVirtualPianoEnabled,
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
            libraryVisible: !_isLibraryPanelCollapsed,
            mixerVisible: _isMixerVisible,
            editorVisible: _isEditorPanelVisible,
            pianoVisible: _isVirtualPianoEnabled,
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
                        width: _isLibraryPanelCollapsed ? 40 : _libraryPanelWidth,
                        child: LibraryPanel(
                          isCollapsed: _isLibraryPanelCollapsed,
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
                        isCollapsed: _isLibraryPanelCollapsed,
                        onDrag: (delta) {
                          setState(() {
                            _libraryPanelWidth = (_libraryPanelWidth + delta)
                                .clamp(_libraryMinWidth, _libraryMaxWidth);
                          });
                        },
                        onDoubleClick: () {
                          setState(() {
                            _isLibraryPanelCollapsed = !_isLibraryPanelCollapsed;
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
                          trackHeights: _trackHeights,
                          masterTrackHeight: _masterTrackHeight,
                          onSeek: (position) {
                            _audioEngine?.transportSeek(position);
                            setState(() {
                              _playheadPosition = position;
                            });
                          },
                        ),
                      ),

                      // Right: Track mixer panel (always visible)
                      if (_isMixerVisible) ...[
                        // Divider: Timeline/Mixer
                        ResizableDivider(
                          orientation: DividerOrientation.vertical,
                          isCollapsed: false,
                          onDrag: (delta) {
                            setState(() {
                              _mixerPanelWidth = (_mixerPanelWidth - delta)
                                  .clamp(_mixerMinWidth, _mixerMaxWidth);
                            });
                          },
                          onDoubleClick: () {
                            setState(() {
                              _isMixerVisible = false;
                            });
                          },
                        ),

                        SizedBox(
                          width: _mixerPanelWidth,
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
                            trackHeights: _trackHeights,
                            masterTrackHeight: _masterTrackHeight,
                            onTrackHeightChanged: _setTrackHeight,
                            onMasterTrackHeightChanged: _setMasterTrackHeight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Editor panel: Piano Roll / FX Chain / Instrument / Virtual Piano
                if (_isEditorPanelVisible || _isVirtualPianoVisible) ...[
                  // Divider: Timeline/Editor Panel
                  ResizableDivider(
                    orientation: DividerOrientation.horizontal,
                    isCollapsed: false,
                    onDrag: (delta) {
                      setState(() {
                        _editorPanelHeight = (_editorPanelHeight - delta)
                            .clamp(_editorMinHeight, _editorMaxHeight);
                      });
                    },
                    onDoubleClick: () {
                      setState(() {
                        _isEditorPanelVisible = false;
                        _isVirtualPianoVisible = false;
                        _isVirtualPianoEnabled = false;
                      });
                    },
                  ),

                  SizedBox(
                    height: _editorPanelHeight,
                    child: EditorPanel(
                      audioEngine: _audioEngine,
                      virtualPianoEnabled: _isVirtualPianoEnabled,
                      selectedTrackId: _selectedTrackId,
                      currentInstrumentData: _selectedTrackId != null
                          ? _trackInstruments[_selectedTrackId]
                          : null,
                      onVirtualPianoClose: _toggleVirtualPiano,
                      onClosePanel: () {
                        setState(() {
                          _isEditorPanelVisible = false;
                          _isVirtualPianoVisible = false;
                          _isVirtualPianoEnabled = false;
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

