import 'dart:io';

import 'package:boojy_audio/services/plugin_folders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory vst3;

  setUp(() => vst3 = Directory.systemTemp.createTempSync('boojy_vst3_'));
  tearDown(() => vst3.deleteSync(recursive: true));

  // A moment after everything so far, so later changes count as newer.
  Future<DateTime> lastScan() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final at = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return at;
  }

  test('nothing installed since the last scan', () async {
    Directory('${vst3.path}/Old.vst3').createSync();
    final scannedAt = await lastScan();

    expect(pluginFoldersChangedSince(scannedAt, [vst3.path]), isFalse);
  });

  test('a plugin installed after the last scan', () async {
    final scannedAt = await lastScan();
    Directory('${vst3.path}/ValhallaSupermassive.vst3').createSync();

    expect(pluginFoldersChangedSince(scannedAt, [vst3.path]), isTrue);
  });

  test('a plugin installed into an existing vendor folder', () async {
    Directory('${vst3.path}/FabFilter').createSync();
    final scannedAt = await lastScan();
    Directory('${vst3.path}/FabFilter/Pro-Q 3.vst3').createSync();

    expect(pluginFoldersChangedSince(scannedAt, [vst3.path]), isTrue);
  });

  test('a plugin removed after the last scan', () async {
    final old = Directory('${vst3.path}/Old.vst3')..createSync();
    final scannedAt = await lastScan();
    old.deleteSync();

    expect(pluginFoldersChangedSince(scannedAt, [vst3.path]), isTrue);
  });

  test('a plugin folder that does not exist is skipped', () async {
    final scannedAt = await lastScan();

    expect(
      pluginFoldersChangedSince(scannedAt, ['${vst3.path}/missing']),
      isFalse,
    );
  });
}
