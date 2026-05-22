part of 'audio_engine_native.dart';

mixin _SendsMixin on _AudioEngineBase {
  // ========================================================================
  // Send/Return API
  // ========================================================================

  /// Find an existing return track for a built-in effect type.
  /// Returns -1 on error, 0 if none, or the return track ID.
  int findReturnByEffectType(String effectType) {
    try {
      final typePtr = effectType.toNativeUtf8();
      final result = _findReturnByEffectType(typePtr.cast());
      malloc.free(typePtr);
      return result;
    } catch (e) {
      return -1;
    }
  }

  /// Create a return track with a built-in effect at 100% wet.
  /// Returns return track ID or -1 on error.
  int createReturnWithEffect(String effectType, {String? name}) {
    try {
      final typePtr = effectType.toNativeUtf8();
      final namePtr = name?.toNativeUtf8();
      final result = _createReturnWithEffect(
        typePtr.cast(),
        namePtr?.cast() ?? ffi.nullptr,
      );
      malloc.free(typePtr);
      if (namePtr != null) malloc.free(namePtr);
      return result;
    } catch (e) {
      return -1;
    }
  }

  /// Create or reuse a shared return and add a send at -20 dB.
  /// Returns "return_id,amount_db" on success or "Error: ..." on failure.
  String addSharedSend(int sourceTrackId, String effectType) {
    try {
      final typePtr = effectType.toNativeUtf8();
      final resultPtr = _addSharedSend(sourceTrackId, typePtr.cast());
      malloc.free(typePtr);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  String addSend(int sourceTrackId, int returnTrackId, double amountDb) {
    try {
      final resultPtr = _addSend(sourceTrackId, returnTrackId, amountDb);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  String setSendAmount(
    int sourceTrackId,
    int returnTrackId,
    double amountDb,
  ) {
    try {
      final resultPtr = _setSendAmount(sourceTrackId, returnTrackId, amountDb);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  String removeSend(int sourceTrackId, int returnTrackId) {
    try {
      final resultPtr = _removeSend(sourceTrackId, returnTrackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  String removeReturn(int returnTrackId) {
    try {
      final resultPtr = _removeReturn(returnTrackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// CSV: "return_id,amount_db,return_name;..."
  String getTrackSends(int trackId) {
    try {
      final resultPtr = _getTrackSends(trackId);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  /// CSV: "return_id,name,effect_type;..."
  String getAllReturns() {
    try {
      final resultPtr = _getAllReturns();
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return '';
    }
  }

  int countSendsToReturn(int returnTrackId) {
    try {
      return _countSendsToReturn(returnTrackId);
    } catch (e) {
      return -1;
    }
  }

  bool getMasterTimelineVisible() {
    try {
      return _getMasterTimelineVisible() != 0;
    } catch (e) {
      return false;
    }
  }

  String setMasterTimelineVisible({required bool visible}) {
    try {
      final resultPtr = _setMasterTimelineVisible(visible ? 1 : 0);
      final result = resultPtr.toDartString();
      _freeRustString(resultPtr);
      return result;
    } catch (e) {
      return 'Error: $e';
    }
  }

  bool syncMasterTimelineVisibility() {
    try {
      return _syncMasterTimelineVisibility() != 0;
    } catch (e) {
      return false;
    }
  }
}
