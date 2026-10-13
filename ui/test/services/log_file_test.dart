import 'dart:io';

import 'package:boojy_audio/services/log_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('boojy_log_test');
  });

  tearDown(() {
    LogFile.closeForTest();
    dir.deleteSync(recursive: true);
  });

  File log() => File('${dir.path}/boojy.log');
  File oldLog() => File('${dir.path}/boojy.old.log');

  test('lines are timestamped and appended across sessions', () async {
    await LogFile.open(directory: dir);
    LogFile.write('Boojy started');
    await LogFile.open(directory: dir);
    LogFile.write('Boojy started again');

    final lines = log().readAsLinesSync();
    expect(lines, hasLength(2));
    expect(
      lines.first,
      matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d  Boojy started$')),
    );
    expect(lines.last, endsWith('Boojy started again'));
  });

  test('nothing is written before the log is opened', () {
    LogFile.write('too early');
    expect(log().existsSync(), isFalse);
  });

  test('a full log becomes the old log and a new one starts', () async {
    await LogFile.open(directory: dir);
    final line = 'x' * 999;
    for (var i = 0; i < LogFile.maxBytes ~/ 1000 + 5; i++) {
      LogFile.write(line);
    }

    expect(oldLog().existsSync(), isTrue);
    expect(oldLog().lengthSync(), lessThanOrEqualTo(LogFile.maxBytes));
    expect(log().lengthSync(), lessThan(LogFile.maxBytes));
    expect(log().readAsLinesSync(), isNotEmpty);
  });
}
