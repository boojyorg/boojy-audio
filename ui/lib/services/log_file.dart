import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/native_dialogs.dart';

/// The local log: `boojy.log` in Boojy's app-support folder. Holds errors and
/// audio dropouts in every build, so "it crackled" or "it broke" comes with
/// data. At [maxBytes] it becomes `boojy.old.log` and a new file starts; a
/// message over [maxLineBytes] is cut short.
///
/// Writes are small synchronous appends (a line now and then), never from
/// the audio thread. Until [open] runs, lines are dropped.
class LogFile {
  LogFile._();

  static const maxBytes = 1024 * 1024;
  static const maxLineBytes = 8 * 1024;

  static File? _file;
  static int _bytes = 0;

  /// Path of the current log, or null before [open].
  static String? get path => _file?.path;

  /// Open (or create) the log in Boojy's app-support folder, or in
  /// [directory] (tests).
  static Future<void> open({Directory? directory}) async {
    try {
      final dir = directory ?? await getApplicationSupportDirectory();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/boojy.log');
      _bytes = file.existsSync() ? file.lengthSync() : 0;
      _file = file;
    } catch (_) {
      _file = null;
    }
  }

  /// Append [message] as one timestamped line.
  static void write(String message) {
    final file = _file;
    if (file == null) return;
    final bytes = utf8.encode(
      '${_timestamp(DateTime.now())}  ${_shorten(message)}\n',
    );
    try {
      if (_bytes + bytes.length > maxBytes) _rotate(file);
      file.writeAsBytesSync(bytes, mode: FileMode.append);
      _bytes += bytes.length;
    } catch (_) {
      // A log that can't be written mustn't take anything else down.
    }
  }

  /// Show the log in Finder / Explorer.
  static Future<void> reveal() async {
    final file = _file;
    if (file == null) return;
    if (!file.existsSync()) file.createSync(recursive: true);
    await revealInFinder(file.path);
  }

  /// [message] cut to [maxLineBytes] of UTF-8, ending in `…` when cut.
  static String _shorten(String message) {
    final bytes = utf8.encode(message);
    if (bytes.length <= maxLineBytes) return message;
    final cut = utf8.decode(
      bytes.sublist(0, maxLineBytes),
      allowMalformed: true,
    );
    // Drop a character split by the cut.
    return '${cut.replaceAll(RegExp('\uFFFD\$'), '')}…';
  }

  static void _rotate(File file) {
    final old = File('${file.parent.path}/boojy.old.log');
    if (old.existsSync()) old.deleteSync();
    if (file.existsSync()) file.renameSync(old.path);
    _bytes = 0;
  }

  static String _timestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Forget the open file (tests).
  static void closeForTest() {
    _file = null;
    _bytes = 0;
  }
}
