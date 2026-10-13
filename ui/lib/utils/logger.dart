import 'package:flutter/foundation.dart';

import '../services/log_file.dart';

/// Simple logger: the console in debug builds; errors also go to the local
/// log file ([LogFile]) in every build.
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
    LogFile.write('Error: $message');
  }

  /// Info logging (state summaries, device info)
  static void i(String message) {
    if (kDebugMode) debugPrint('ℹ️ $message');
  }
}
