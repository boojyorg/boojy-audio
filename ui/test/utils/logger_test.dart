import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/utils/logger.dart';

void main() {
  group('Log', () {
    test('Log.d does not throw', () {
      expect(() => Log.d('debug message'), returnsNormally);
    });

    test('Log.e does not throw', () {
      expect(() => Log.e('error message'), returnsNormally);
    });

    test('Log.i does not throw', () {
      expect(() => Log.i('info message'), returnsNormally);
    });

    test('Log.d handles empty string', () {
      expect(() => Log.d(''), returnsNormally);
    });

    test('Log.e handles string interpolation', () {
      final error = Exception('test error');
      expect(() => Log.e('Failed: $error'), returnsNormally);
    });
  });
}
