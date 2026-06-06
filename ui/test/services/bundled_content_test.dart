import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:boojy_audio/services/bundled_content_io.dart';
import 'package:boojy_audio/services/bundled_content_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bundled_content_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('BundledContentService manifest', () {
    test('every starter-kit pad references a bundled sample', () {
      for (final (note, sample) in BundledContentService.starterKitPads) {
        expect(
          BundledContentService.drumSamples,
          contains(sample),
          reason: 'pad note $note references unbundled sample $sample',
        );
      }
    });

    test('starter kit has 8 pads with unique pinned notes', () {
      final notes = BundledContentService.starterKitPads
          .map((pad) => pad.$1)
          .toSet();
      expect(BundledContentService.starterKitPads.length, 8);
      expect(notes.length, 8, reason: 'pinned notes must be unique');
    });

    test('every manifest entry exists in the asset bundle', () async {
      for (final sample in BundledContentService.drumSamples) {
        final data = await rootBundle.load(
          '${BundledContentService.drumsAssetRoot}/$sample',
        );
        expect(
          data.lengthInBytes,
          greaterThan(44), // larger than a bare WAV header
          reason: '$sample is empty or missing',
        );
      }
    });
  });

  group('installBundledDrums', () {
    test('copies all samples and stamps the revision', () async {
      final root = await installBundledDrums(
        1,
        BundledContentService.drumsAssetRoot,
        BundledContentService.drumSamples,
        targetDirOverride: tempDir.path,
      );

      expect(root, isNotNull);
      for (final sample in BundledContentService.drumSamples) {
        final path = '$root/${sample.split('/').join(Platform.pathSeparator)}';
        expect(File(path).existsSync(), isTrue, reason: 'missing $path');
      }
      expect(File('$root/.revision').readAsStringSync(), '1');
    });

    test('is idempotent and restores deleted files', () async {
      final root = (await installBundledDrums(
        1,
        BundledContentService.drumsAssetRoot,
        BundledContentService.drumSamples,
        targetDirOverride: tempDir.path,
      ))!;

      // Delete one file — a re-run must restore it.
      final victim = File(
        '$root/${BundledContentService.drumSamples.first.split('/').join(Platform.pathSeparator)}',
      );
      victim.deleteSync();

      final rootAgain = await installBundledDrums(
        1,
        BundledContentService.drumsAssetRoot,
        BundledContentService.drumSamples,
        targetDirOverride: tempDir.path,
      );

      expect(rootAgain, root);
      expect(victim.existsSync(), isTrue);
    });

    test('re-copies when the revision changes', () async {
      final root = (await installBundledDrums(
        1,
        BundledContentService.drumsAssetRoot,
        BundledContentService.drumSamples,
        targetDirOverride: tempDir.path,
      ))!;

      await installBundledDrums(
        2,
        BundledContentService.drumsAssetRoot,
        BundledContentService.drumSamples,
        targetDirOverride: tempDir.path,
      );

      expect(File('$root/.revision').readAsStringSync(), '2');
    });
  });
}
