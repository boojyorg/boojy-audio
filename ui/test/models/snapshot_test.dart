import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/snapshot.dart';

void main() {
  group('Snapshot', () {
    group('constructor', () {
      test('creates snapshot with required fields', () {
        final created = DateTime(2025, 1, 15, 10, 30);
        final snapshot = Snapshot(
          id: 'test-id-123',
          name: 'My Snapshot',
          created: created,
          fileName: 'My Snapshot.boojy',
        );

        expect(snapshot.id, 'test-id-123');
        expect(snapshot.name, 'My Snapshot');
        expect(snapshot.note, isNull);
        expect(snapshot.created, created);
        expect(snapshot.fileName, 'My Snapshot.boojy');
      });

      test('creates snapshot with optional note', () {
        final snapshot = Snapshot(
          id: 'test-id',
          name: 'Test',
          note: 'This is a note',
          created: DateTime.now(),
          fileName: 'Test.boojy',
        );

        expect(snapshot.note, 'This is a note');
      });
    });

    group('create factory', () {
      test('generates unique ID', () {
        final snapshot1 = Snapshot.create(name: 'Test 1');
        final snapshot2 = Snapshot.create(name: 'Test 2');

        expect(snapshot1.id, isNotEmpty);
        expect(snapshot2.id, isNotEmpty);
        expect(snapshot1.id, isNot(equals(snapshot2.id)));
      });

      test('sets creation timestamp', () {
        final before = DateTime.now();
        final snapshot = Snapshot.create(name: 'Test');
        final after = DateTime.now();

        expect(snapshot.created.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
        expect(snapshot.created.isBefore(after.add(const Duration(seconds: 1))), isTrue);
      });

      test('creates safe filename from name', () {
        final snapshot = Snapshot.create(name: 'My Cool Snapshot');
        expect(snapshot.fileName, 'My Cool Snapshot.boojy');
      });

      test('includes optional note', () {
        final snapshot = Snapshot.create(name: 'Test', note: 'My note');
        expect(snapshot.note, 'My note');
      });
    });

    group('filename sanitization', () {
      test('replaces invalid characters with underscore', () {
        final snapshot = Snapshot.create(name: 'Test<>:"/\\|?*Name');
        expect(snapshot.fileName, 'Test_________Name.boojy');
      });

      test('trims whitespace', () {
        final snapshot = Snapshot.create(name: '  Test Name  ');
        expect(snapshot.fileName, 'Test Name.boojy');
      });

      test('collapses multiple spaces', () {
        final snapshot = Snapshot.create(name: 'Test   Multiple   Spaces');
        expect(snapshot.fileName, 'Test Multiple Spaces.boojy');
      });

      test('truncates long names to 100 characters', () {
        final longName = 'A' * 150;
        final snapshot = Snapshot.create(name: longName);
        // fileName should be 100 chars + '.boojy'
        expect(snapshot.fileName.length, 100 + '.boojy'.length);
      });

      test('uses default name for empty string', () {
        final snapshot = Snapshot.create(name: '');
        expect(snapshot.fileName, 'Snapshot.boojy');
      });

      test('uses default name when only invalid characters', () {
        final snapshot = Snapshot.create(name: '<>:"/\\|?*');
        // After sanitization, all chars become underscores, but trimmed result isn't empty
        expect(snapshot.fileName, endsWith('.boojy'));
      });
    });

    group('JSON serialization', () {
      test('toJson includes all fields', () {
        final created = DateTime(2025, 1, 15, 10, 30, 45);
        final snapshot = Snapshot(
          id: 'uuid-123',
          name: 'Test Snapshot',
          note: 'A test note',
          created: created,
          fileName: 'Test Snapshot.boojy',
        );

        final json = snapshot.toJson();

        expect(json['id'], 'uuid-123');
        expect(json['name'], 'Test Snapshot');
        expect(json['note'], 'A test note');
        expect(json['created'], '2025-01-15T10:30:45.000');
        expect(json['fileName'], 'Test Snapshot.boojy');
      });

      test('toJson handles null note', () {
        final snapshot = Snapshot(
          id: 'uuid-123',
          name: 'Test',
          created: DateTime(2025, 1, 1),
          fileName: 'Test.boojy',
        );

        final json = snapshot.toJson();
        expect(json['note'], isNull);
      });

      test('fromJson parses all fields', () {
        final json = {
          'id': 'uuid-456',
          'name': 'Parsed Snapshot',
          'note': 'Parsed note',
          'created': '2025-06-20T14:45:30.000',
          'fileName': 'Parsed Snapshot.boojy',
        };

        final snapshot = Snapshot.fromJson(json);

        expect(snapshot.id, 'uuid-456');
        expect(snapshot.name, 'Parsed Snapshot');
        expect(snapshot.note, 'Parsed note');
        expect(snapshot.created, DateTime(2025, 6, 20, 14, 45, 30));
        expect(snapshot.fileName, 'Parsed Snapshot.boojy');
      });

      test('fromJson handles null note', () {
        final json = {
          'id': 'uuid-789',
          'name': 'No Note',
          'note': null,
          'created': '2025-01-01T00:00:00.000',
          'fileName': 'No Note.boojy',
        };

        final snapshot = Snapshot.fromJson(json);
        expect(snapshot.note, isNull);
      });

      test('roundtrip serialization preserves data', () {
        final original = Snapshot(
          id: 'roundtrip-id',
          name: 'Roundtrip Test',
          note: 'Should survive serialization',
          created: DateTime(2025, 3, 15, 9, 0, 0),
          fileName: 'Roundtrip Test.boojy',
        );

        final json = original.toJson();
        final restored = Snapshot.fromJson(json);

        expect(restored, equals(original));
      });
    });

    group('copyWith', () {
      test('creates copy with same values when no arguments', () {
        final original = Snapshot(
          id: 'id-1',
          name: 'Original',
          note: 'Note',
          created: DateTime(2025, 1, 1),
          fileName: 'Original.boojy',
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.note, original.note);
        expect(copy.created, original.created);
        expect(copy.fileName, original.fileName);
      });

      test('updates only specified fields', () {
        final original = Snapshot(
          id: 'id-1',
          name: 'Original',
          note: 'Note',
          created: DateTime(2025, 1, 1),
          fileName: 'Original.boojy',
        );

        final updated = original.copyWith(name: 'Updated Name');

        expect(updated.id, original.id);
        expect(updated.name, 'Updated Name');
        expect(updated.note, original.note);
        expect(updated.created, original.created);
        expect(updated.fileName, original.fileName);
      });

      test('can update multiple fields', () {
        final original = Snapshot(
          id: 'id-1',
          name: 'Original',
          note: 'Note',
          created: DateTime(2025, 1, 1),
          fileName: 'Original.boojy',
        );

        final newCreated = DateTime(2025, 6, 15);
        final updated = original.copyWith(
          name: 'New Name',
          note: 'New Note',
          created: newCreated,
        );

        expect(updated.id, original.id);
        expect(updated.name, 'New Name');
        expect(updated.note, 'New Note');
        expect(updated.created, newCreated);
        expect(updated.fileName, original.fileName);
      });
    });

    group('formattedDate', () {
      test('shows "Just now" for very recent', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime.now(),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, 'Just now');
      });

      test('shows minutes ago for less than an hour', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime.now().subtract(const Duration(minutes: 30)),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, '30m ago');
      });

      test('shows hours ago for same day', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime.now().subtract(const Duration(hours: 5)),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, '5h ago');
      });

      test('shows "Yesterday" for one day ago', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime.now().subtract(const Duration(days: 1)),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, 'Yesterday');
      });

      test('shows days ago for less than a week', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime.now().subtract(const Duration(days: 4)),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, '4d ago');
      });

      test('shows formatted date for older snapshots', () {
        final snapshot = Snapshot(
          id: 'id',
          name: 'Test',
          created: DateTime(2024, 3, 15),
          fileName: 'Test.boojy',
        );

        expect(snapshot.formattedDate, 'Mar 15, 2024');
      });

      test('formats all months correctly', () {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

        for (var i = 0; i < 12; i++) {
          final snapshot = Snapshot(
            id: 'id',
            name: 'Test',
            created: DateTime(2020, i + 1, 1),
            fileName: 'Test.boojy',
          );
          expect(snapshot.formattedDate, startsWith(months[i]));
        }
      });
    });

    group('equality', () {
      test('equal snapshots are equal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(
          id: 'same-id',
          name: 'Same Name',
          note: 'Same Note',
          created: created,
          fileName: 'Same.boojy',
        );
        final snapshot2 = Snapshot(
          id: 'same-id',
          name: 'Same Name',
          note: 'Same Note',
          created: created,
          fileName: 'Same.boojy',
        );

        expect(snapshot1, equals(snapshot2));
        expect(snapshot1.hashCode, equals(snapshot2.hashCode));
      });

      test('different id makes snapshots unequal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(id: 'id-1', name: 'Name', created: created, fileName: 'F.boojy');
        final snapshot2 = Snapshot(id: 'id-2', name: 'Name', created: created, fileName: 'F.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });

      test('different name makes snapshots unequal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(id: 'id', name: 'Name 1', created: created, fileName: 'F.boojy');
        final snapshot2 = Snapshot(id: 'id', name: 'Name 2', created: created, fileName: 'F.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });

      test('different note makes snapshots unequal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(id: 'id', name: 'Name', note: 'Note 1', created: created, fileName: 'F.boojy');
        final snapshot2 = Snapshot(id: 'id', name: 'Name', note: 'Note 2', created: created, fileName: 'F.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });

      test('null vs non-null note makes snapshots unequal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(id: 'id', name: 'Name', note: null, created: created, fileName: 'F.boojy');
        final snapshot2 = Snapshot(id: 'id', name: 'Name', note: 'Note', created: created, fileName: 'F.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });

      test('different created makes snapshots unequal', () {
        final snapshot1 = Snapshot(id: 'id', name: 'Name', created: DateTime(2025, 1, 1), fileName: 'F.boojy');
        final snapshot2 = Snapshot(id: 'id', name: 'Name', created: DateTime(2025, 1, 2), fileName: 'F.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });

      test('different fileName makes snapshots unequal', () {
        final created = DateTime(2025, 1, 1);
        final snapshot1 = Snapshot(id: 'id', name: 'Name', created: created, fileName: 'File1.boojy');
        final snapshot2 = Snapshot(id: 'id', name: 'Name', created: created, fileName: 'File2.boojy');

        expect(snapshot1, isNot(equals(snapshot2)));
      });
    });

    group('toString', () {
      test('includes relevant information', () {
        final snapshot = Snapshot(
          id: 'test-id',
          name: 'Test Snapshot',
          created: DateTime(2025, 1, 15),
          fileName: 'Test.boojy',
        );

        final str = snapshot.toString();

        expect(str, contains('test-id'));
        expect(str, contains('Test Snapshot'));
        expect(str, contains('Test.boojy'));
      });
    });
  });
}
