// Web stub for BundledContentService — bundled samples need a real
// filesystem for the engine to load from, which web doesn't have.

/// No-op on web; always returns null.
Future<String?> installBundledDrums(
  int revision,
  String assetRoot,
  List<String> samples, {
  String? targetDirOverride,
}) async {
  return null;
}
