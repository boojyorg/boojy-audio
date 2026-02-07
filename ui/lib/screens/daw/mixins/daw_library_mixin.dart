import 'dart:io';
import 'package:flutter/material.dart';
import '../../../models/clip_data.dart';
import '../../../models/library_item.dart';
import '../../../models/midi_note_data.dart';
import '../../../models/vst3_plugin_data.dart';
import '../../../services/commands/track_commands.dart';
import '../../../services/commands/clip_commands.dart';
import '../../../services/midi_file_service.dart';
import '../../../widgets/instrument_browser.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';
import 'daw_vst3_mixin.dart';

/// Mixin containing library-related methods for DAWScreen.
/// Handles library item interactions, audio file drops, and sampler operations.
mixin DAWLibraryMixin on State<DAWScreen>, DAWScreenStateMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin, DAWClipMixin, DAWVst3Mixin {
  // ============================================
  // LIBRARY ITEM DOUBLE-CLICK
  // ============================================

  /// Handle double-click on library item
  void handleLibraryItemDoubleClick(LibraryItem item) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && isMidiTrack(selectedTrack);
    final isEmptyAudio = selectedTrack != null && isEmptyAudioTrack(selectedTrack);

    switch (item.type) {
      case LibraryItemType.instrument:
        // Find the matching Instrument from availableInstruments
        final instrument = findInstrumentByName(item.name);
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
          final instrument = findInstrumentById(item.instrumentId);
          if (instrument != null) {
            if (isMidi) {
              // Swap/add instrument on selected MIDI track
              onInstrumentSelected(selectedTrack, instrument.id);
              // TODO: Load preset data when presets are implemented
            } else {
              // Create new MIDI track with instrument
              onInstrumentDroppedOnEmpty(instrument);
              // TODO: Load preset data when presets are implemented
            }
          }
        }
        break;

      case LibraryItemType.sample:
        if (item is SampleItem && item.filePath.isNotEmpty) {
          if (isEmptyAudio) {
            // Add clip to selected empty audio track
            addAudioClipToTrack(selectedTrack, item.filePath);
          } else {
            // Create new audio track with clip
            onAudioFileDroppedOnEmpty(item.filePath);
          }
        } else {
          showSnackBar('Sample not available [WIP]');
        }
        break;

      case LibraryItemType.audioFile:
        if (item is AudioFileItem) {
          if (isEmptyAudio) {
            // Add clip to selected empty audio track
            addAudioClipToTrack(selectedTrack, item.filePath);
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
            addBuiltInEffectToTrack(selectedTrack, item.effectType);
          }
        } else {
          showSnackBar('Select a track first to add effects');
        }
        break;

      case LibraryItemType.midiFile:
        if (item is MidiFileItem) {
          if (isMidi) {
            onMidiFileDroppedOnTrack(selectedTrack, item.filePath, 0.0);
          } else {
            onMidiFileDroppedOnEmpty(item.filePath);
          }
        }
        break;

      case LibraryItemType.vst3Instrument:
      case LibraryItemType.vst3Effect:
        // Handled by handleVst3DoubleClick
        break;

      case LibraryItemType.folder:
        // Folders are not double-clickable for adding
        break;
    }
  }

  /// Handle double-click on VST3 plugin in library
  void handleVst3DoubleClick(Vst3Plugin plugin) {
    if (audioEngine == null) return;

    final selectedTrack = selectedTrackId;
    final isMidi = selectedTrack != null && isMidiTrack(selectedTrack);

    if (plugin.isInstrument) {
      if (isMidi) {
        // Swap/add VST3 instrument on selected MIDI track
        onVst3InstrumentDropped(selectedTrack, plugin);
      } else {
        // Create new MIDI track with VST3 instrument
        onVst3InstrumentDroppedOnEmpty(plugin);
      }
    } else {
      // VST3 effect
      if (selectedTrack != null) {
        onVst3PluginDropped(selectedTrack, plugin);
      } else {
        showSnackBar('Select a track first to add effects');
      }
    }
  }

  // ============================================
  // SAMPLER OPERATIONS
  // ============================================

  /// Open an audio file in a new Sampler track
  void handleOpenInSampler(LibraryItem item) {
    if (audioEngine == null) return;

    // Get the file path
    String? filePath;
    if (item is SampleItem) {
      filePath = item.filePath;
    } else if (item is AudioFileItem) {
      filePath = item.filePath;
    }

    if (filePath == null || filePath.isEmpty) {
      showSnackBar('Cannot open in sampler: no file path');
      return;
    }

    // Create a new Sampler track
    createSamplerTrackWithSample(filePath, item.name);
  }

  /// Create a new Sampler track and load a sample into it
  void createSamplerTrackWithSample(String filePath, String sampleName) {
    if (audioEngine == null) return;

    // Generate track name based on sample name
    final trackName = 'Sampler: ${truncateName(sampleName, 20)}';

    // Create Sampler track type
    final trackId = audioEngine!.createTrack('sampler', trackName);
    if (trackId < 0) {
      showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(trackId);
    if (samplerId < 0) {
      showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(trackId, filePath, 60);
    if (!success) {
      showSnackBar('Failed to load sample');
      return;
    }

    // Refresh track list and select the new track
    refreshTrackWidgets();
    selectTrack(trackId);

    showSnackBar('Created sampler with "${truncateName(sampleName, 30)}"');
  }

  /// Convert an Audio track to a Sampler track
  void convertAudioTrackToSampler(int trackId) {
    if (audioEngine == null) return;

    // Get audio clips on this track
    final audioClips = timelineKey.currentState?.getAudioClipsOnTrack(trackId);
    if (audioClips == null || audioClips.isEmpty) {
      showSnackBar('No audio clips on track to convert');
      return;
    }

    // Get the first clip's file path (we'll use this as the sample)
    final firstClip = audioClips.first;
    final samplePath = firstClip.filePath;
    if (samplePath.isEmpty) {
      showSnackBar('Audio clip has no file path');
      return;
    }

    // Get track name for the new sampler track
    final trackName = getTrackName(trackId) ?? 'Sampler';
    final samplerTrackName = trackName.startsWith('Sampler:')
        ? trackName
        : 'Sampler: $trackName';

    // Create Sampler track
    final samplerTrackId = audioEngine!.createTrack('sampler', samplerTrackName);
    if (samplerTrackId < 0) {
      showSnackBar('Failed to create sampler track');
      return;
    }

    // Create sampler instrument for the track
    final samplerId = audioEngine!.createSamplerForTrack(samplerTrackId);
    if (samplerId < 0) {
      showSnackBar('Failed to create sampler instrument');
      return;
    }

    // Load the sample (root note C4 = 60)
    final success = audioEngine!.loadSampleForTrack(samplerTrackId, samplePath, 60);
    if (!success) {
      showSnackBar('Failed to load sample');
      return;
    }

    // Create MIDI clips for each audio clip position
    for (final clip in audioClips) {
      final startTime = clip.startTime;
      final duration = clip.duration;

      // Calculate MIDI note based on transpose (if any)
      final transpose = clip.editData?.transposeSemitones ?? 0;
      final midiNote = (60 + transpose).clamp(0, 127);

      // Create an empty MIDI clip
      final clipId = audioEngine!.createMidiClip();
      if (clipId < 0) continue;

      // Add the MIDI note to the clip
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

    showSnackBar('Converted to Sampler track');
  }

  // ============================================
  // AUDIO FILE DROP HANDLERS
  // ============================================

  /// Handle audio file dropped on empty area - creates new audio track
  Future<void> onAudioFileDroppedOnEmpty(String filePath) async {
    if (audioEngine == null) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

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

      // 5. Add to timeline view's clip list
      timelineKey.currentState?.addClip(ClipData(
        clipId: clipId,
        trackId: trackId,
        filePath: finalPath, // Use the copied path
        startTime: 0.0,
        duration: duration,
        waveformPeaks: peaks,
      ));

      // 6. Select the newly created clip (opens Audio Editor)
      timelineKey.currentState?.selectAudioClip(clipId);

      // 7. Refresh track widgets
      refreshTrackWidgets();
    } catch (e) {
      debugPrint('Failed to add audio file to new track: $e');
    }
  }

  /// Handle audio file dropped on existing track (with undo support)
  Future<void> onAudioFileDroppedOnTrack(int trackId, String filePath, double startTimeBeats) async {
    if (audioEngine == null) return;

    // Defensive check: only allow audio file drops on audio tracks (not MIDI tracks)
    if (isMidiTrack(trackId)) return;

    try {
      // 1. Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

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

  /// Create new track with clip (drag-to-create)
  Future<void> onCreateTrackWithClip(String trackType, double startBeats, double durationBeats) async {
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
        createMidiClipWithParams(trackId, startBeats, durationBeats);
      }
      // For audio tracks, they start empty (user will drop audio files)

      // Select the newly created track
      onTrackSelected(trackId);

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

  // ============================================
  // MIDI FILE DROP HANDLERS
  // ============================================

  /// Handle MIDI file dropped on empty area - creates new MIDI track
  Future<void> onMidiFileDroppedOnEmpty(String filePath) async {
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

      _importMidiNotesToTrack(trackId, filePath, 0.0, result);
    } catch (e) {
      debugPrint('Failed to import MIDI file to new track: $e');
    }
  }

  /// Handle MIDI file dropped on existing track
  Future<void> onMidiFileDroppedOnTrack(int trackId, String filePath, double startTimeBeats) async {
    if (audioEngine == null) return;
    if (!isMidiTrack(trackId)) return;

    try {
      final bytes = await File(filePath).readAsBytes();
      final result = MidiFileService.decode(bytes);
      if (result.notes.isEmpty) return;

      _importMidiNotesToTrack(trackId, filePath, startTimeBeats, result);
    } catch (e) {
      debugPrint('Failed to import MIDI file to track: $e');
    }
  }

  /// Import decoded MIDI notes as a clip on a track
  void _importMidiNotesToTrack(int trackId, String filePath, double startTimeBeats, MidiFileDecodeResult result) {
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
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  /// Copy audio file to project's Samples folder if setting is enabled
  Future<String> prepareSamplePath(String originalPath) async {
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

  /// Add audio clip to existing track
  Future<void> addAudioClipToTrack(int trackId, String filePath) async {
    if (audioEngine == null) return;

    try {
      // Copy sample to project folder if setting is enabled
      final finalPath = await prepareSamplePath(filePath);

      final clipId = audioEngine!.loadAudioFileToTrack(finalPath, trackId);
      if (clipId < 0) {
        return;
      }

      final duration = audioEngine!.getClipDuration(clipId);
      // Store high-resolution peaks (8000/sec)
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

  /// Add built-in effect to track
  void addBuiltInEffectToTrack(int trackId, String effectType) {
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

  /// Find instrument by name
  Instrument? findInstrumentByName(String name) {
    try {
      return availableInstruments.firstWhere(
        (inst) => inst.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find instrument by ID
  Instrument? findInstrumentById(String id) {
    try {
      return availableInstruments.firstWhere(
        (inst) => inst.id == id,
      );
    } catch (e) {
      return null;
    }
  }

  /// Truncate a name to max length with ellipsis
  String truncateName(String name, int maxLength) {
    if (name.length <= maxLength) return name;
    return '${name.substring(0, maxLength - 3)}...';
  }

  /// Show snackbar message
  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
