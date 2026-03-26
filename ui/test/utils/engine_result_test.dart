import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/utils/engine_result.dart';

void main() {
  group('EngineResult.parse', () {
    test('parses JSON success', () {
      final result = EngineResult.parse('{"ok":"Audio graph initialized"}');
      expect(result.isOk, isTrue);
      expect(result.data, 'Audio graph initialized');
      expect(result.errorCode, isNull);
    });

    test('parses JSON error', () {
      final result = EngineResult.parse(
        '{"error":{"code":"not_found","msg":"Track 5 not found"}}',
      );
      expect(result.isError, isTrue);
      expect(result.errorCode, 'not_found');
      expect(result.errorMessage, 'Track 5 not found');
      expect(result.data, isNull);
    });

    test('parses legacy "Error: " format', () {
      final result = EngineResult.parse('Error: Audio graph already initialized');
      expect(result.isError, isTrue);
      expect(result.errorCode, 'internal');
      expect(result.errorMessage, 'Audio graph already initialized');
    });

    test('parses legacy "Error" without colon', () {
      final result = EngineResult.parse('Error');
      expect(result.isError, isTrue);
    });

    test('parses plain success string', () {
      final result = EngineResult.parse('OK');
      expect(result.isOk, isTrue);
      expect(result.data, 'OK');
    });

    test('unwrap returns data on success', () {
      final result = EngineResult.parse('{"ok":"data"}');
      expect(result.unwrap(), 'data');
    });

    test('unwrap throws EngineException on error', () {
      final result = EngineResult.parse(
        '{"error":{"code":"engine_state","msg":"Not initialized"}}',
      );
      expect(() => result.unwrap(), throwsA(isA<EngineException>()));
    });
  });

  group('EngineException', () {
    test('isNotFound', () {
      const e = EngineException('not_found', 'gone');
      expect(e.isNotFound, isTrue);
      expect(e.isInvalidArg, isFalse);
    });

    test('isEngineState', () {
      const e = EngineException('engine_state', 'not ready');
      expect(e.isEngineState, isTrue);
    });
  });
}
