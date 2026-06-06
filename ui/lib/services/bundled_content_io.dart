// Native platform IO for BundledContentService — copies bundled sample
// assets out to the app-support directory so the engine can load them by
// filesystem path.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Copies the bundled drum samples into `<app-support>/Samples/Drums/…`,
/// skipping the copy when the stamped revision matches and all files are
/// present. Returns the absolute Drums folder path, or null on failure.
///
/// [targetDirOverride] replaces the app-support location (tests only).
Future<String?> installBundledDrums(
  int revision,
  String assetRoot,
  List<String> samples, {
  String? targetDirOverride,
}) async {
  try {
    final root =
        targetDirOverride ?? (await getApplicationSupportDirectory()).path;
    final drumsDir = Directory(p.join(root, 'Samples', 'Drums'));
    final stamp = File(p.join(drumsDir.path, '.revision'));

    if (await _isCurrent(stamp, revision, drumsDir, samples)) {
      return drumsDir.path;
    }

    for (final rel in samples) {
      final data = await rootBundle.load('$assetRoot/$rel');
      final out = File(p.join(drumsDir.path, p.joinAll(rel.split('/'))));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await stamp.writeAsString('$revision');
    Log.i('BundledContent: installed ${samples.length} drum samples');
    return drumsDir.path;
  } catch (e) {
    Log.e('BundledContent: install failed: $e');
    return null;
  }
}

Future<bool> _isCurrent(
  File stamp,
  int revision,
  Directory drumsDir,
  List<String> samples,
) async {
  if (!await stamp.exists()) return false;
  if ((await stamp.readAsString()).trim() != '$revision') return false;
  for (final rel in samples) {
    if (!await File(
      p.join(drumsDir.path, p.joinAll(rel.split('/'))),
    ).exists()) {
      return false;
    }
  }
  return true;
}
