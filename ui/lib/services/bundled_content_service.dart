import 'package:flutter/foundation.dart' show kIsWeb;

import 'bundled_content_io.dart'
    if (dart.library.js_interop) 'bundled_content_io_web.dart';

/// Installs bundled content (drum samples) from Flutter assets to a real
/// folder on disk, because the Rust engine loads samples by filesystem path
/// and cannot read from the asset bundle.
///
/// Idempotent: files are copied once to app-support and re-copied only when
/// [contentRevision] changes or files go missing. Web is a no-op.
class BundledContentService {
  BundledContentService._();

  /// Bump when the bundled sample set changes to force a re-copy on update.
  static const int contentRevision = 1;

  /// Asset root for the bundled drum samples (see LICENSES.md alongside them).
  static const String drumsAssetRoot = 'assets/samples/drums';

  /// Relative paths (under [drumsAssetRoot]) of every bundled drum sample.
  /// Keep in sync with the pubspec asset entries and the files on disk.
  static const List<String> drumSamples = [
    'Kicks/808 Kick.wav',
    'Kicks/House Kick.wav',
    'Kicks/Techno Kick.wav',
    'Snares/Electro Snare.wav',
    'Snares/Bright Snare.wav',
    'Snares/Fat Snare.wav',
    'Hats/Closed Hat.wav',
    'Hats/Tight Hat.wav',
    'Hats/Soft Hat.wav',
    'Hats/Open Hat.wav',
    'Hats/Metal Hat.wav',
    'Hats/Noise Hat.wav',
    'Claps/909 Clap.wav',
    'Claps/Snap.wav',
    'Claps/Snap 2.wav',
    'Toms/Low Tom.wav',
    'Toms/Low Tom Soft.wav',
    'Toms/Fuzz Tom.wav',
    'Toms/Mid Tom.wav',
    'Toms/Mid Tom Soft.wav',
    'Cymbals/Splash.wav',
    'Cymbals/Crash.wav',
    'Cymbals/Short Cymbal.wav',
  ];

  /// The starter kit: pinned GM percussion note → bundled sample, in pad
  /// order. Loaded into a fresh Drum Kit so the first beat needs no setup.
  static const List<(int, String)> starterKitPads = [
    (36, 'Kicks/808 Kick.wav'),
    (38, 'Snares/Electro Snare.wav'),
    (42, 'Hats/Closed Hat.wav'),
    (46, 'Hats/Open Hat.wav'),
    (39, 'Claps/909 Clap.wav'),
    (41, 'Toms/Low Tom.wav'),
    (47, 'Toms/Mid Tom.wav'),
    (49, 'Cymbals/Splash.wav'),
  ];

  static String? _installedDrumsRoot;
  static Future<String?>? _installFuture;

  /// Absolute path of the installed Drums folder, or null until
  /// [ensureInstalled] has completed successfully.
  static String? get installedDrumsRoot => _installedDrumsRoot;

  /// Copies the bundled drum samples out to app-support (once) and returns
  /// the absolute path of the Drums folder, or null on web / on failure.
  /// Safe to call repeatedly and concurrently.
  static Future<String?> ensureInstalled() {
    if (kIsWeb) return Future.value(null);
    if (_installedDrumsRoot != null) {
      return Future.value(_installedDrumsRoot);
    }
    // Coalesce concurrent callers onto one install pass.
    _installFuture ??=
        installBundledDrums(contentRevision, drumsAssetRoot, drumSamples).then((
          root,
        ) {
          _installedDrumsRoot = root;
          _installFuture = null;
          return root;
        });
    return _installFuture!;
  }
}
