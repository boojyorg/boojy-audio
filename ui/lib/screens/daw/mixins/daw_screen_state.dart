import 'package:flutter/material.dart';
import '../../../audio_engine.dart';
import '../../../models/clip_data.dart';
import '../../../models/instrument_data.dart';
import '../../../models/project_metadata.dart';
import '../../../models/tool_mode.dart';
import '../../../models/track_automation_data.dart';
import '../../../services/undo_redo_manager.dart';
import '../../../services/library_service.dart';
import '../../../services/library_preview_service.dart';
import '../../../services/vst3_plugin_manager.dart';
import '../../../services/project_manager.dart';
import '../../../services/version_manager.dart';
import '../../../services/midi_playback_manager.dart';
import '../../../services/user_settings.dart';
import '../../../services/auto_save_service.dart';
import '../../../services/midi_capture_buffer.dart';
import '../../../controllers/controllers.dart';
import '../../../state/ui_layout_state.dart';
import '../../../widgets/timeline_view.dart';
import '../../../widgets/track_mixer_panel.dart';
import '../../daw_screen.dart';

/// Mixin containing all state variables for DAWScreen.
/// This separates state management from UI logic.
mixin DAWScreenStateMixin on State<DAWScreen> {
  // ============================================
  // AUDIO ENGINE
  // ============================================

  AudioEngine? audioEngine;

  // ============================================
  // CONTROLLERS
  // ============================================

  final PlaybackController playbackController = PlaybackController();
  final RecordingController recordingController = RecordingController();
  final TrackController trackController = TrackController();
  final MidiClipController midiClipController = MidiClipController();
  final AutomationController automationController = AutomationController();
  final UILayoutState uiLayout = UILayoutState();

  // ============================================
  // UNDO/REDO
  // ============================================

  final UndoRedoManager undoRedoManager = UndoRedoManager();

  // ============================================
  // SERVICES
  // ============================================

  final LibraryService libraryService = LibraryService();
  LibraryPreviewService? libraryPreviewService;
  Vst3PluginManager? vst3PluginManager;
  ProjectManager? projectManager;
  VersionManager? versionManager;
  MidiPlaybackManager? midiPlaybackManager;
  final UserSettings userSettings = UserSettings();
  final AutoSaveService autoSaveService = AutoSaveService();
  final MidiCaptureBuffer midiCaptureBuffer = MidiCaptureBuffer(maxDurationSeconds: 30);

  // ============================================
  // LOCAL STATE
  // ============================================

  int? loadedClipId;
  double? clipDuration;
  List<double> waveformPeaks = [];
  bool isAudioGraphInitialized = false;
  bool isLoading = false;
  bool hasInitializedPanelSizes = false;

  /// Audio clip selection for Audio Editor
  ClipData? selectedAudioClip;

  /// Tool mode (shared between piano roll and arrangement view)
  ToolMode currentToolMode = ToolMode.draw;

  /// Project metadata
  ProjectMetadata projectMetadata = const ProjectMetadata(
    name: 'Untitled',
    bpm: 120.0,
  );

  /// Live preview values for automation drag (trackId -> normalized value)
  Map<int, double?> automationPreviewValues = {};

  // ============================================
  // PLAYBACK CONVENIENCE GETTERS/SETTERS
  // ============================================

  double get playheadPosition => playbackController.playheadPosition;
  set playheadPosition(double value) => playbackController.setPlayheadPosition(value);
  bool get isPlaying => playbackController.isPlaying;
  set statusMessage(String value) => playbackController.setStatusMessage(value);

  // ============================================
  // RECORDING CONVENIENCE GETTERS
  // ============================================

  bool get isRecording => recordingController.isRecording;
  bool get isCountingIn => recordingController.isCountingIn;
  bool get isMetronomeEnabled => recordingController.isMetronomeEnabled;
  double get tempo => recordingController.tempo;
  List<Map<String, dynamic>> get midiDevices => recordingController.midiDevices;
  int get selectedMidiDeviceIndex => recordingController.selectedMidiDeviceIndex;

  // ============================================
  // TRACK CONVENIENCE GETTERS/SETTERS
  // ============================================

  int? get selectedTrackId => trackController.selectedTrackId;
  Set<int> get selectedTrackIds => trackController.selectedTrackIds;
  set selectedTrackId(int? value) => trackController.selectTrack(value);

  void selectTrack(int? trackId, {bool isShiftHeld = false}) =>
      trackController.selectTrack(trackId, isShiftHeld: isShiftHeld);

  Map<int, InstrumentData> get trackInstruments => trackController.trackInstruments;
  Map<int, double> get clipHeights => trackController.clipHeights;
  Map<int, double> get automationHeights => trackController.automationHeights;
  double get masterTrackHeight => trackController.masterTrackHeight;

  // ============================================
  // GLOBAL KEYS
  // ============================================

  final GlobalKey<TimelineViewState> timelineKey = GlobalKey<TimelineViewState>();
  final GlobalKey<TrackMixerPanelState> mixerKey = GlobalKey<TrackMixerPanelState>();

  // ============================================
  // SCROLL CONTROLLERS
  // ============================================

  final ScrollController timelineVerticalScrollController = ScrollController();
  final ScrollController mixerVerticalScrollController = ScrollController();
  bool isScrollSyncing = false;

  // ============================================
  // HELPER METHODS (State-related)
  // ============================================

  void setClipHeight(int trackId, double height) {
    trackController.setClipHeight(trackId, height);
  }

  void setAutomationHeight(int trackId, double height) {
    trackController.setAutomationHeight(trackId, height);
  }

  void onAutomationPreviewValue(int trackId, double? value) {
    setState(() {
      if (value == null) {
        automationPreviewValues.remove(trackId);
      } else {
        automationPreviewValues[trackId] = value;
      }
    });
  }

  void syncVolumeAutomationToEngine(int trackId) {
    final lane = automationController.getLane(trackId, AutomationParameter.volume);
    if (lane != null && audioEngine != null) {
      final csv = lane.toEngineDbCsv(tempo);
      audioEngine!.setTrackVolumeAutomation(trackId, csv);
    }
  }

  void setMasterTrackHeight(double height) {
    trackController.setMasterTrackHeight(height);
  }

  Color getTrackColor(int trackId, String trackName, String trackType) {
    return trackController.getTrackColor(trackId, trackName, trackType);
  }

  void setTrackColor(int trackId, Color color) {
    trackController.setTrackColor(trackId, color);
  }

  /// Sync timeline scroll to mixer
  void onTimelineVerticalScroll() {
    if (isScrollSyncing) return;
    if (!mixerVerticalScrollController.hasClients) return;
    if (!mixerVerticalScrollController.position.hasContentDimensions) return;

    isScrollSyncing = true;
    try {
      final targetOffset = timelineVerticalScrollController.offset.clamp(
        mixerVerticalScrollController.position.minScrollExtent,
        mixerVerticalScrollController.position.maxScrollExtent,
      );
      mixerVerticalScrollController.jumpTo(targetOffset);
    } finally {
      isScrollSyncing = false;
    }
  }

  /// Sync mixer scroll to timeline
  void onMixerVerticalScroll() {
    if (isScrollSyncing) return;
    if (!timelineVerticalScrollController.hasClients) return;
    if (!timelineVerticalScrollController.position.hasContentDimensions) return;

    isScrollSyncing = true;
    try {
      final targetOffset = mixerVerticalScrollController.offset.clamp(
        timelineVerticalScrollController.position.minScrollExtent,
        timelineVerticalScrollController.position.maxScrollExtent,
      );
      timelineVerticalScrollController.jumpTo(targetOffset);
    } finally {
      isScrollSyncing = false;
    }
  }

  /// Disarm all MIDI tracks except the specified one.
  void disarmOtherMidiTracks(int exceptTrackId) {
    final tracks = mixerKey.currentState?.tracks ?? [];
    for (final track in tracks) {
      if (track.type == 'midi' && track.id != exceptTrackId && track.armed) {
        track.armed = false;
        audioEngine?.setTrackArmed(track.id, armed: false);
      }
    }
  }

  /// Trigger immediate refresh of track lists in both timeline and mixer panels
  void refreshTrackWidgets({bool clearClips = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (clearClips) {
          timelineKey.currentState?.clearClips();
        }
        timelineKey.currentState?.refreshTracks();
        mixerKey.currentState?.refreshTracks();
        setState(() {});
      }
    });
  }
}
