part of 'audio_engine_native.dart';

mixin _TracksMixin on _AudioEngineBase {
  // ========================================================================
  // M4 API - Tracks & Mixer
  // ========================================================================

  /// Create a new track
  /// trackType: "audio", "midi", "return", "group", or "master"
  /// Returns track ID or -1 on error
  int createTrack(String trackType, String name) {
    try {
      final typePtr = trackType.toNativeUtf8();
      final namePtr = name.toNativeUtf8();
      final trackId = _createTrack(typePtr.cast(), namePtr.cast());
      malloc.free(typePtr);
      malloc.free(namePtr);

      if (trackId < 0) {
        return -1;
      }

      return trackId;
    } catch (e) {
      return -1;
    }
  }

  /// Set track volume in dB (-∞ to +6 dB)
  String setTrackVolume(int trackId, double volumeDb) {
    try {
      final resultPtr = _setTrackVolume(trackId, volumeDb);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set volume automation curve for a track
  /// csvData format: "time_seconds,db;time_seconds,db;..." or empty to clear
  String setTrackVolumeAutomation(int trackId, String csvData) {
    try {
      final csvPtr = csvData.toNativeUtf8();
      final resultPtr = _setTrackVolumeAutomation(trackId, csvPtr);
      calloc.free(csvPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set track pan (-1.0 = full left, 0.0 = center, 1.0 = full right)
  String setTrackPan(int trackId, double pan) {
    try {
      final resultPtr = _setTrackPan(trackId, pan);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Mute or unmute a track
  String setTrackMute(int trackId, {required bool mute}) {
    try {
      final resultPtr = _setTrackMute(trackId, mute);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Solo or unsolo a track
  String setTrackSolo(int trackId, {required bool solo}) {
    try {
      final resultPtr = _setTrackSolo(trackId, solo);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Arm or disarm a track for recording
  String setTrackArmed(int trackId, {required bool armed}) {
    try {
      final resultPtr = _setTrackArmed(trackId, armed);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set audio input device and channel for a track
  /// deviceIndex: -1 = no input, 0+ = device index
  /// channel: 0-based channel within the device
  String setTrackInput(int trackId, int deviceIndex, int channel) {
    try {
      final resultPtr = _setTrackInput(trackId, deviceIndex, channel);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get audio input device and channel for a track
  /// Returns map with 'deviceIndex' (-1 if none) and 'channel'
  Map<String, int> getTrackInput(int trackId) {
    try {
      final resultPtr = _getTrackInput(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      if (result.startsWith('Error')) {
        return {'deviceIndex': -1, 'channel': 0};
      }
      final parts = result.split(',');
      if (parts.length >= 2) {
        return {
          'deviceIndex': int.tryParse(parts[0]) ?? -1,
          'channel': int.tryParse(parts[1]) ?? 0,
        };
      }
      return {'deviceIndex': -1, 'channel': 0};
    } catch (e) {
      return {'deviceIndex': -1, 'channel': 0};
    }
  }

  /// Set input monitoring for a track
  String setTrackInputMonitoring(int trackId, {required bool enabled}) {
    try {
      final resultPtr = _setTrackInputMonitoring(trackId, enabled);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Get input channel peak level for metering (0.0 to 1.0+)
  /// channel: 0 = left, 1 = right
  double getInputChannelLevel(int channel) {
    try {
      final resultPtr = _getInputChannelLevel(channel);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      if (result.startsWith('Error')) return 0.0;
      return double.tryParse(result) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// Get number of input channels for the current device
  int getInputChannelCount() {
    try {
      return _getInputChannelCount();
    } catch (e) {
      return 0;
    }
  }

  /// Rename a track
  String setTrackName(int trackId, String name) {
    try {
      final namePtr = name.toNativeUtf8();
      final resultPtr = _setTrackName(trackId, namePtr);
      calloc.free(namePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get total number of tracks
  int getTrackCount() {
    try {
      return _getTrackCount();
    } catch (e) {
      return 0;
    }
  }

  /// Get all track IDs as list
  List<int> getAllTrackIds() {
    try {
      final resultPtr = _getAllTrackIds();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);

      if (result.isEmpty || result.startsWith('Error:')) {
        return [];
      }

      return result.split(',').map((id) => int.parse(id)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get track info as CSV: "track_id,name,type,volume_db,pan,mute,solo"
  String getTrackInfo(int trackId) {
    try {
      final resultPtr = _getTrackInfo(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Get track peak levels (M5.5) as CSV: "peak_left_db,peak_right_db"
  String getTrackPeakLevels(int trackId) {
    try {
      final resultPtr = _getTrackPeakLevels(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      // Fail silently for peak levels (called frequently)
      return '-96.0,-96.0';
    }
  }

  /// Delete a track (cannot delete master track)
  String deleteTrack(int trackId) {
    try {
      final resultPtr = _deleteTrack(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Duplicate a track (cannot duplicate master track)
  /// Returns the new track ID, or -1 on error
  int duplicateTrack(int trackId) {
    try {
      final newTrackId = _duplicateTrack(trackId);
      if (newTrackId >= 0) {
        return newTrackId;
      } else {
        return -1;
      }
    } catch (e) {
      return -1;
    }
  }

  /// Duplicate an audio clip on the same track at a new position
  /// Returns the new clip ID, or -1 on error
  int duplicateAudioClip(int trackId, int sourceClipId, double newStartTime) {
    try {
      final newClipId = _duplicateAudioClip(trackId, sourceClipId, newStartTime);
      if (newClipId >= 0) {
        return newClipId;
      } else {
        return -1;
      }
    } catch (e) {
      return -1;
    }
  }

  /// Remove an audio clip from a track
  /// Returns true if removed, false if not found
  bool removeAudioClip(int trackId, int clipId) {
    try {
      final result = _removeAudioClip(trackId, clipId);
      return result > 0;
    } catch (e) {
      return false;
    }
  }

  /// Re-add an existing audio clip to a track from the engine's clips map.
  /// Used for redo after undoing a recording or clip deletion.
  /// Returns the new clip ID, or -1 on error.
  int addExistingClipToTrack(int clipId, int trackId, double startTime,
      {double offset = 0.0, double? duration}) {
    try {
      final result = _addExistingClipToTrack(
        clipId,
        trackId,
        startTime,
        offset,
        duration != null ? 1 : 0,
        duration ?? 0.0,
      );
      return result;
    } catch (e) {
      print('❌ addExistingClipToTrack error: $e');
      return -1;
    }
  }

  /// Clear all tracks except master - used for New Project / Close Project
  String clearAllTracks() {
    try {
      final resultPtr = _clearAllTracks();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // ========================================================================
  // M4 API - Effects
  // ========================================================================

  /// Add an effect to a track's FX chain
  /// effectType: "eq", "compressor", "reverb", "delay", "chorus", "limiter"
  /// Returns effect ID or -1 on error
  int addEffectToTrack(int trackId, String effectType) {
    try {
      final typePtr = effectType.toNativeUtf8();
      final effectId = _addEffectToTrack(trackId, typePtr.cast());
      malloc.free(typePtr);

      if (effectId < 0) {
        return -1;
      }

      return effectId;
    } catch (e) {
      return -1;
    }
  }

  /// Remove an effect from a track's FX chain
  String removeEffectFromTrack(int trackId, int effectId) {
    try {
      final resultPtr = _removeEffectFromTrack(trackId, effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all effects on a track (returns CSV of effect IDs)
  String getTrackEffects(int trackId) {
    try {
      final resultPtr = _getTrackEffects(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Get effect info (type and parameters)
  /// Returns format: "type:eq,low_freq:100,low_gain:0,..."
  String getEffectInfo(int effectId) {
    try {
      final resultPtr = _getEffectInfo(effectId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// Set an effect parameter
  String setEffectParameter(int effectId, String paramName, double value) {
    try {
      final namePtr = paramName.toNativeUtf8();
      final resultPtr = _setEffectParameter(effectId, namePtr.cast(), value);
      malloc.free(namePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Set effect bypass state
  /// Returns true on success, false on failure
  bool setEffectBypass(int effectId, {required bool bypassed}) {
    try {
      final result = _setEffectBypass(effectId, bypassed ? 1 : 0);
      return result == 1;
    } catch (e) {
      return false;
    }
  }

  /// Get effect bypass state
  /// Returns true if bypassed, false if not bypassed or on error
  bool getEffectBypass(int effectId) {
    try {
      final result = _getEffectBypass(effectId);
      return result == 1;
    } catch (e) {
      return false;
    }
  }

  /// Reorder effects in a track's FX chain
  /// Takes a list of effect IDs in the desired order
  String reorderTrackEffects(int trackId, List<int> effectIds) {
    try {
      final idsStr = effectIds.join(',');
      final idsPtr = idsStr.toNativeUtf8();
      final resultPtr = _reorderTrackEffects(trackId, idsPtr.cast());
      malloc.free(idsPtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }
}
