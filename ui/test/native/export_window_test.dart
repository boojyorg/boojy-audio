import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boojy_audio/widgets/export_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/daw_harness.dart';
import 'support/native_engine_harness.dart';

/// What the export window sends, run against the real engine, with the
/// written files opened and checked.
///
/// Stem export once failed on every try while every export test was green:
/// the tests built their own engine calls and never ran the window's.
/// `runExport` is the window's own export step, so a wrong setting, a wrong
/// name for one, or a reply read the wrong way fails here.
void main() {
  if (!isNativeEngineAvailable) {
    const reason = 'native engine library not found — run ./build.sh first';
    if (isNativeEngineRequired) {
      test('native engine present (required under BOOJY_CI)', () {
        fail('$reason. Refusing to report a vacuous green suite (C92).');
      });
    } else {
      test('Export window (native engine)', () {}, skip: reason);
    }
    return;
  }

  /// A project with one 2 s clip, so there is something to export.
  Future<void> dropClip(DawHarness h) async {
    await h.daw.onAudioFileDroppedOnEmpty(h.writeClickWav('loop.wav'));
    await h.settle();
  }

  /// Run the window's export with [options]; the file name carries [name]
  /// and the extension the window would have given the save panel.
  Future<List<ExportResult>> export(
    DawHarness h,
    ExportOptions options,
    String name,
  ) async {
    final extension = options.exportMp3 ? 'mp3' : 'wav';
    var results = <ExportResult>[];
    await h.realTime(() async {
      results = await runExport(
        h.engine,
        options,
        baseName: name,
        filePath: '${h.tempDir.path}/$name.$extension',
      );
    });
    return results;
  }

  testWidgets('WAV: every bit depth and sample rate the window offers is the '
      'one written to the file', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h);
      for (final bitDepth in [16, 24, 32]) {
        for (final sampleRate in [44100, 48000]) {
          final name = 'wav_${bitDepth}_$sampleRate';
          final results = await export(
            h,
            ExportOptions(
              exportMp3: false,
              exportWav: true,
              wavBitDepth: bitDepth,
              sampleRate: sampleRate,
            ),
            name,
          );

          final result = results.single;
          final file = File('${h.tempDir.path}/$name.wav');
          expect(file.existsSync(), isTrue, reason: name);
          expect(result.path, file.path, reason: name);
          expect(result.fileSize, file.lengthSync(), reason: name);
          expect(result.sampleRate, sampleRate, reason: name);
          // The 2 s clip plus the one-second tail.
          expect(result.duration, closeTo(3, 0.05), reason: name);

          final wav = _WavHeader.read(file);
          expect(wav.bitsPerSample, bitDepth, reason: name);
          expect(wav.sampleRate, sampleRate, reason: name);
          expect(wav.channels, 2, reason: name);
          expect(wav.seconds, closeTo(3, 0.05), reason: name);
        }
      }
    } finally {
      await h.close();
    }
  });

  testWidgets('MP3: every bitrate and sample rate the window offers is the '
      'one written to the file', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h);
      for (final bitrate in [128, 192, 320]) {
        for (final sampleRate in [44100, 48000]) {
          final name = 'mp3_${bitrate}_$sampleRate';
          final results = await export(
            h,
            ExportOptions(mp3Bitrate: bitrate, sampleRate: sampleRate),
            name,
          );

          final result = results.single;
          final file = File('${h.tempDir.path}/$name.mp3');
          expect(file.existsSync(), isTrue, reason: name);
          expect(result.path, file.path, reason: name);
          expect(result.fileSize, file.lengthSync(), reason: name);
          expect(result.sampleRate, sampleRate, reason: name);
          expect(result.duration, closeTo(3, 0.05), reason: name);

          final mp3 = _Mp3.read(file);
          expect(mp3.sampleRate, sampleRate, reason: name);
          // Size ÷ length is the bitrate (the header frame adds a little).
          final kbps = mp3.audioBytes * 8 / result.duration / 1000;
          expect(kbps, closeTo(bitrate, bitrate * 0.1), reason: name);
          // Nothing was typed in Title or Artist, so no tags.
          expect(mp3.title, isNull, reason: name);
          expect(mp3.artist, isNull, reason: name);
        }
      }
    } finally {
      await h.close();
    }
  });

  testWidgets('MP3: the title and artist typed in the window are in the file', (
    tester,
  ) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h);

      await export(
        h,
        ExportOptions(title: 'Night Drive', artist: 'Tyr & Friends'),
        'both',
      );
      final both = _Mp3.read(File('${h.tempDir.path}/both.mp3'));
      expect(both.title, 'Night Drive');
      expect(both.artist, 'Tyr & Friends');

      // Only a title: the artist is left out, not written empty.
      await export(h, ExportOptions(title: 'Única', artist: ''), 'title');
      final titleOnly = _Mp3.read(File('${h.tempDir.path}/title.mp3'));
      expect(titleOnly.title, 'Única');
      expect(titleOnly.artist, isNull);
      // The tags go in front of the audio and must not damage it.
      expect(titleOnly.sampleRate, 44100);
    } finally {
      await h.close();
    }
  });

  testWidgets('MP3 and WAV ticked together write both files; Normalise is '
      'passed on', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h);

      // The save panel gave an .mp3 name; the WAV goes beside it.
      final results = await export(
        h,
        ExportOptions(exportWav: true, wavBitDepth: 24, sampleRate: 48000),
        'pair',
      );
      expect(results.map((r) => r.path.split('/').last), [
        'pair.mp3',
        'pair.wav',
      ]);
      expect(results.map((r) => r.format), ['MP3 320 kbps', 'WAV 24-bit']);
      expect(_WavHeader.read(File(results[1].path)).bitsPerSample, 24);

      // Normalise changes the level of what is written.
      Future<double> peak({required bool normalize}) async {
        final name = normalize ? 'loud' : 'plain';
        await export(
          h,
          ExportOptions(
            exportMp3: false,
            exportWav: true,
            normalize: normalize,
          ),
          name,
        );
        return _WavHeader.read(File('${h.tempDir.path}/$name.wav')).peak16;
      }

      final plain = await peak(normalize: false);
      final loud = await peak(normalize: true);
      expect(plain, greaterThan(0));
      expect(loud, greaterThan(plain));
      expect(loud, lessThanOrEqualTo(1.0));
    } finally {
      await h.close();
    }
  });

  testWidgets('stems: the ticked tracks are written, one file each, in the '
      'format the window is set to', (tester) async {
    final h = await DawHarness.start(tester);
    try {
      await dropClip(h);
      await h.daw.onAudioFileDroppedOnEmpty(h.writeClickWav('snare.wav'));
      await h.settle();

      // As the window does when Stems is switched on: every track, ticked.
      final tracks = stemTracksFromEngine(h.engine);
      expect(tracks, hasLength(2));
      h.engine.setTrackName(tracks[0].id, 'Kick');
      h.engine.setTrackName(tracks[1].id, 'Snare');
      // Untick the second one.
      tracks[1].selected = false;

      final folder = '${h.tempDir.path}/stems';
      var results = <ExportResult>[];
      await h.realTime(() async {
        results = await runExport(
          h.engine,
          ExportOptions(
            exportMp3: false,
            exportWav: true,
            wavBitDepth: 24,
            sampleRate: 48000,
            exportStems: true,
            stemTracks: tracks,
          ),
          baseName: 'Song',
          folderPath: folder,
        );
      });

      final files = Directory(folder).listSync().cast<File>();
      expect(files.map((f) => f.uri.pathSegments.last), ['Song - Kick.wav']);
      final wav = _WavHeader.read(files.single);
      expect(wav.bitsPerSample, 24);
      expect(wav.sampleRate, 48000);
      expect(results.single.format, '1 stems (WAV)');
      expect(results.single.path, folder);
      expect(results.single.fileSize, files.single.lengthSync());
    } finally {
      await h.close();
    }
  });
}

/// The format a WAV file says it is, read from its `fmt ` and `data` chunks.
class _WavHeader {
  _WavHeader({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataBytes,
    required this.peak16,
  });

  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataBytes;

  /// Largest sample of a 16-bit file, 0..1 (0 for other bit depths).
  final double peak16;

  double get seconds =>
      dataBytes / (channels * (bitsPerSample ~/ 8)) / sampleRate;

  static _WavHeader read(File file) {
    final bytes = file.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');

    int? channels, sampleRate, bits, dataBytes;
    var peak = 0.0;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = ascii.decode(bytes.sublist(at, at + 4));
      final size = data.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ') {
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataBytes = size;
        if (bits == 16) {
          for (
            var i = body;
            i + 1 < body + size && i + 1 < bytes.length;
            i += 2
          ) {
            final v = data.getInt16(i, Endian.little).abs() / 32768;
            if (v > peak) peak = v;
          }
        }
        break;
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    return _WavHeader(
      channels: channels!,
      sampleRate: sampleRate!,
      bitsPerSample: bits!,
      dataBytes: dataBytes!,
      peak16: peak,
    );
  }
}

/// What an MP3 file says about itself: its ID3v2 title and artist (if it has
/// the tag) and the sample rate in its first audio frame header.
class _Mp3 {
  _Mp3({
    required this.title,
    required this.artist,
    required this.sampleRate,
    required this.audioBytes,
  });

  final String? title;
  final String? artist;
  final int sampleRate;

  /// File size without the ID3 tag.
  final int audioBytes;

  static _Mp3 read(File file) {
    final bytes = file.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    var audioStart = 0;
    final frames = <String, String>{};

    // "ID3" (compared as bytes: an untagged MP3 starts with 0xFF, not text).
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      final major = bytes[3];
      int synchsafe(int at) =>
          (bytes[at] << 21) |
          (bytes[at + 1] << 14) |
          (bytes[at + 2] << 7) |
          bytes[at + 3];
      final tagSize = synchsafe(6);
      audioStart = 10 + tagSize;
      var at = 10;
      while (at + 10 <= audioStart && bytes[at] != 0) {
        final id = latin1.decode(bytes.sublist(at, at + 4));
        // v2.4 frame sizes are synchsafe; v2.3 sizes are plain.
        final size = major >= 4 ? synchsafe(at + 4) : data.getUint32(at + 4);
        final body = bytes.sublist(at + 10, at + 10 + size);
        if (id.startsWith('T') && body.isNotEmpty) {
          frames[id] = _decodeText(body);
        }
        at += 10 + size;
      }
    }

    // First audio frame: 11 sync bits, then version/layer, then the byte
    // holding the sample-rate index.
    var at = audioStart;
    while (at + 3 < bytes.length &&
        !(bytes[at] == 0xFF && (bytes[at + 1] & 0xE0) == 0xE0)) {
      at++;
    }
    expect(at + 3 < bytes.length, isTrue, reason: 'no MP3 frame found');
    final rateIndex = (bytes[at + 2] >> 2) & 0x3;
    final sampleRate = const [44100, 48000, 32000, 0][rateIndex];

    return _Mp3(
      title: frames['TIT2'],
      artist: frames['TPE1'],
      sampleRate: sampleRate,
      audioBytes: bytes.length - audioStart,
    );
  }

  /// An ID3 text frame: one encoding byte, then the text.
  static String _decodeText(List<int> body) {
    final text = body.sublist(1);
    String strip(String s) => s.replaceAll('\u0000', '');
    switch (body[0]) {
      case 0: // ISO-8859-1
        return strip(latin1.decode(text));
      case 1: // UTF-16 with a byte-order mark
        final bigEndian = text.length >= 2 && text[0] == 0xFE;
        final units = <int>[];
        for (var i = 2; i + 1 < text.length; i += 2) {
          units.add(
            bigEndian
                ? (text[i] << 8) | text[i + 1]
                : (text[i + 1] << 8) | text[i],
          );
        }
        return strip(String.fromCharCodes(units));
      case 2: // UTF-16BE, no mark
        final units = <int>[];
        for (var i = 0; i + 1 < text.length; i += 2) {
          units.add((text[i] << 8) | text[i + 1]);
        }
        return strip(String.fromCharCodes(units));
      default: // UTF-8
        return strip(utf8.decode(text));
    }
  }
}
