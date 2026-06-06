import 'package:boojy_audio/utils/csv_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeCsvField', () {
    test('passes plain names through', () {
      expect(decodeCsvField('Drums'), 'Drums');
      expect(decodeCsvField('Vocal Take 3'), 'Vocal Take 3');
    });

    test('decodes engine-escaped delimiters and percent', () {
      // Mirrors encode_csv_field in engine/src/api/helpers.rs (C34).
      expect(decodeCsvField('Drums%2C Kit'), 'Drums, Kit');
      expect(decodeCsvField('a%3Bb'), 'a;b');
      expect(decodeCsvField('100%25'), '100%');
    });

    test('round-trips a name that already looks like an escape', () {
      // "%2C" typed literally into a name arrives as "%252C" on the wire.
      expect(decodeCsvField('%252C'), '%2C');
    });
  });
}
