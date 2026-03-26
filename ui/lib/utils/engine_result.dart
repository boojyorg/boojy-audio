import 'dart:convert';

/// Structured result from the Rust audio engine FFI layer.
///
/// Handles both legacy format ("Error: ...") and new JSON format:
///   {"ok": "<data>"}
///   {"error": {"code": "<code>", "msg": "..."}}
class EngineResult {
  /// The data payload on success, or null on error.
  final String? data;

  /// The error code on failure (e.g. "not_found", "invalid_arg").
  final String? errorCode;

  /// The error message on failure.
  final String? errorMessage;

  const EngineResult._({this.data, this.errorCode, this.errorMessage});

  bool get isOk => data != null;
  bool get isError => !isOk;

  /// Parse an FFI result string into a structured [EngineResult].
  ///
  /// Supports:
  /// - New JSON format: `{"ok": "data"}` or `{"error": {"code": "...", "msg": "..."}}`
  /// - Legacy format: `"Error: message"` or plain success string
  factory EngineResult.parse(String raw) {
    // Try new JSON format first
    if (raw.startsWith('{')) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json.containsKey('ok')) {
          return EngineResult._(data: json['ok'] as String);
        }
        if (json.containsKey('error')) {
          final err = json['error'] as Map<String, dynamic>;
          return EngineResult._(
            errorCode: err['code'] as String?,
            errorMessage: err['msg'] as String?,
          );
        }
      } catch (_) {
        // Fall through to legacy parsing
      }
    }

    // Legacy format
    if (raw.startsWith('Error')) {
      final msg = raw.startsWith('Error: ') ? raw.substring(7) : raw;
      return EngineResult._(errorCode: 'internal', errorMessage: msg);
    }

    // Plain success string
    return EngineResult._(data: raw);
  }

  /// Unwrap the data or throw an [EngineException].
  String unwrap() {
    if (data != null) return data!;
    throw EngineException(errorCode ?? 'unknown', errorMessage ?? 'Unknown error');
  }

  @override
  String toString() =>
      isOk ? 'EngineResult.ok($data)' : 'EngineResult.error($errorCode: $errorMessage)';
}

/// Exception thrown when an engine FFI call fails.
class EngineException implements Exception {
  final String code;
  final String message;

  const EngineException(this.code, this.message);

  /// Whether this is a "not found" error.
  bool get isNotFound => code == 'not_found';

  /// Whether this is an invalid argument error.
  bool get isInvalidArg => code == 'invalid_arg';

  /// Whether the engine is in the wrong state.
  bool get isEngineState => code == 'engine_state';

  @override
  String toString() => 'EngineException($code): $message';
}
