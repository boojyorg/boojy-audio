import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/project_metadata.dart';

void main() {
  group('ProjectMetadata', () {
    group('constructor', () {
      test('creates metadata with required parameters', () {
        const metadata = ProjectMetadata(name: 'Test Project');

        expect(metadata.name, 'Test Project');
        expect(metadata.bpm, 120.0);
        expect(metadata.timeSignatureNumerator, 4);
        expect(metadata.timeSignatureDenominator, 4);
      });

      test('creates metadata with all parameters', () {
        const metadata = ProjectMetadata(
          name: 'Custom Project',
          bpm: 140.0,
          timeSignatureNumerator: 3,
          timeSignatureDenominator: 4,
        );

        expect(metadata.name, 'Custom Project');
        expect(metadata.bpm, 140.0);
        expect(metadata.timeSignatureNumerator, 3);
        expect(metadata.timeSignatureDenominator, 4);
      });
    });

    group('timeSignature', () {
      test('returns formatted time signature string', () {
        const metadata = ProjectMetadata(name: 'Test');
        expect(metadata.timeSignature, '4/4');

        const metadata2 = ProjectMetadata(
          name: 'Test',
          timeSignatureNumerator: 6,
          timeSignatureDenominator: 8,
        );
        expect(metadata2.timeSignature, '6/8');
      });
    });

    group('fromJson', () {
      test('creates metadata from complete JSON', () {
        final json = {
          'name': 'JSON Project',
          'bpm': 160.0,
          'timeSignatureNumerator': 5,
          'timeSignatureDenominator': 4,
        };

        final metadata = ProjectMetadata.fromJson(json);

        expect(metadata.name, 'JSON Project');
        expect(metadata.bpm, 160.0);
        expect(metadata.timeSignatureNumerator, 5);
        expect(metadata.timeSignatureDenominator, 4);
      });

      test('uses defaults for missing fields', () {
        final json = <String, dynamic>{};

        final metadata = ProjectMetadata.fromJson(json);

        expect(metadata.name, 'Untitled');
        expect(metadata.bpm, 120.0);
        expect(metadata.timeSignatureNumerator, 4);
        expect(metadata.timeSignatureDenominator, 4);
      });

      test('ignores keys from older project files', () {
        final json = {
          'name': 'Old Project',
          'bpm': 100.0,
          'style': 'Type Beat',
          'key': 'Bb',
          'scale': 'Minor',
          'sampleRate': 44100,
        };

        final metadata = ProjectMetadata.fromJson(json);

        expect(metadata.name, 'Old Project');
        expect(metadata.bpm, 100.0);
        expect(metadata.toJson().containsKey('key'), isFalse);
      });

      test('handles numeric types correctly', () {
        final json = {
          'name': 'Test',
          'bpm': 120, // int instead of double
          'timeSignatureNumerator': 4,
          'timeSignatureDenominator': 4,
        };

        final metadata = ProjectMetadata.fromJson(json);

        expect(metadata.bpm, 120.0);
      });
    });

    group('toJson', () {
      test('converts metadata to JSON', () {
        const metadata = ProjectMetadata(
          name: 'Test Project',
          bpm: 128.0,
          timeSignatureNumerator: 3,
          timeSignatureDenominator: 4,
        );

        final json = metadata.toJson();

        expect(json['name'], 'Test Project');
        expect(json['bpm'], 128.0);
        expect(json['timeSignatureNumerator'], 3);
        expect(json['timeSignatureDenominator'], 4);
      });

      test('roundtrips through JSON', () {
        const original = ProjectMetadata(
          name: 'Roundtrip',
          bpm: 145.5,
          timeSignatureNumerator: 7,
          timeSignatureDenominator: 8,
        );

        final json = original.toJson();
        final restored = ProjectMetadata.fromJson(json);

        expect(restored, original);
      });
    });

    group('copyWith', () {
      test('copies with no changes', () {
        const original = ProjectMetadata(name: 'Original');
        final copy = original.copyWith();

        expect(copy.name, 'Original');
        expect(copy.bpm, 120.0);
      });

      test('copies with specific changes', () {
        const original = ProjectMetadata(name: 'Original');
        final copy = original.copyWith(name: 'Updated', bpm: 90.0);

        expect(copy.name, 'Updated');
        expect(copy.bpm, 90.0);
        expect(copy.timeSignatureNumerator, 4); // Unchanged
      });
    });

    group('equality', () {
      test('equal metadata are equal', () {
        const m1 = ProjectMetadata(name: 'Test', bpm: 120.0);
        const m2 = ProjectMetadata(name: 'Test', bpm: 120.0);

        expect(m1 == m2, true);
        expect(m1.hashCode, m2.hashCode);
      });

      test('different metadata are not equal', () {
        const m1 = ProjectMetadata(name: 'Test1');
        const m2 = ProjectMetadata(name: 'Test2');

        expect(m1 == m2, false);
      });

      test('metadata with different bpm are not equal', () {
        const m1 = ProjectMetadata(name: 'Test', bpm: 120.0);
        const m2 = ProjectMetadata(name: 'Test', bpm: 140.0);

        expect(m1 == m2, false);
      });
    });

    group('toString', () {
      test('returns readable string', () {
        const metadata = ProjectMetadata(name: 'Test Project', bpm: 120.0);

        final str = metadata.toString();

        expect(str, contains('Test Project'));
        expect(str, contains('120.0'));
        expect(str, contains('4/4'));
      });
    });
  });
}
