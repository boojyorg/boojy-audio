import 'package:flutter/foundation.dart';

/// Simple logger that is silent in release builds.
/// Usage: Log.d('message'), Log.e('error'), Log.i('info')
class Log {
  Log._();

  /// Debug tracing (operation flow, state transitions)
  static void d(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Error logging (exceptions, failures)
  static void e(String message) {
    if (kDebugMode) debugPrint('❌ $message');
  }

  /// Info logging (state summaries, device info)
  static void i(String message) {
    if (kDebugMode) debugPrint('ℹ️ $message');
  }
}
