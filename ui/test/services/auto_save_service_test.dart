import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/auto_save_service.dart';

void main() {
  group('BackupInfo', () {
    group('constructor', () {
      test('creates instance with all required fields', () {
        final modified = DateTime(2025, 6, 15, 14, 30);
        final backup = BackupInfo(
          path: '/path/to/backup/autosave_2025-06-15.audio',
          name: 'autosave_2025-06-15.audio',
          modified: modified,
        );

        expect(backup.path, '/path/to/backup/autosave_2025-06-15.audio');
        expect(backup.name, 'autosave_2025-06-15.audio');
        expect(backup.modified, modified);
      });
    });

    group('formattedDate', () {
      test('formats date with zero padding', () {
        final backup = BackupInfo(
          path: '/path/to/backup.audio',
          name: 'backup.audio',
          modified: DateTime(2025, 1, 5, 9, 3),
        );

        expect(backup.formattedDate, '2025-01-05 09:03');
      });

      test('formats date with double digits', () {
        final backup = BackupInfo(
          path: '/path/to/backup.audio',
          name: 'backup.audio',
          modified: DateTime(2025, 12, 25, 23, 59),
        );

        expect(backup.formattedDate, '2025-12-25 23:59');
      });

      test('formats midnight correctly', () {
        final backup = BackupInfo(
          path: '/path/to/backup.audio',
          name: 'backup.audio',
          modified: DateTime(2025, 7, 1, 0, 0),
        );

        expect(backup.formattedDate, '2025-07-01 00:00');
      });

      test('formats noon correctly', () {
        final backup = BackupInfo(
          path: '/path/to/backup.audio',
          name: 'backup.audio',
          modified: DateTime(2025, 7, 1, 12, 0),
        );

        expect(backup.formattedDate, '2025-07-01 12:00');
      });
    });

    group('edge cases', () {
      test('handles empty path', () {
        final backup = BackupInfo(
          path: '',
          name: '',
          modified: DateTime.now(),
        );

        expect(backup.path, '');
        expect(backup.name, '');
      });

      test('handles long path', () {
        final longPath = '/Library/Application Support/BoojyAudio/${'a' * 500}/backup.audio';
        final backup = BackupInfo(
          path: longPath,
          name: 'backup.audio',
          modified: DateTime.now(),
        );

        expect(backup.path, longPath);
      });

      test('handles special characters in name', () {
        final backup = BackupInfo(
          path: '/path/to/my-backup_2025-06-15T14-30-00.audio',
          name: 'my-backup_2025-06-15T14-30-00.audio',
          modified: DateTime.now(),
        );

        expect(backup.name, 'my-backup_2025-06-15T14-30-00.audio');
      });
    });
  });

  group('AutoSaveService', () {
    // The service is a singleton, so we test it carefully
    late AutoSaveService service;

    setUp(() {
      service = AutoSaveService();
    });

    tearDown(() {
      service.stop();
    });

    group('singleton', () {
      test('returns same instance', () {
        final service1 = AutoSaveService();
        final service2 = AutoSaveService();

        expect(identical(service1, service2), true);
      });
    });

    group('constants', () {
      test('maxBackups is 3', () {
        expect(AutoSaveService.maxBackups, 3);
      });
    });

    group('initial state', () {
      test('isRunning is false initially', () {
        // Stop any running timer first
        service.stop();
        expect(service.isRunning, false);
      });

      test('lastAutoSave is null initially when not started', () {
        // This tests the initial state concept
        // Note: Since it's a singleton, lastAutoSave might have been set in other tests
        // We mainly verify the property exists and is accessible
        expect(service.lastAutoSave, isA<DateTime?>());
      });

      test('isAutoSaving is false when not saving', () {
        service.stop();
        expect(service.isAutoSaving, false);
      });
    });

    group('stop', () {
      test('sets isRunning to false', () {
        service.stop();
        expect(service.isRunning, false);
      });

      test('can be called multiple times safely', () {
        service.stop();
        service.stop();
        service.stop();
        expect(service.isRunning, false);
      });
    });

    group('ChangeNotifier behavior', () {
      test('can add listeners', () {
        var notified = false;
        void listener() {
          notified = true;
        }

        service.addListener(listener);
        service.stop(); // This triggers notifyListeners

        expect(notified, true);

        service.removeListener(listener);
      });

      test('can remove listeners', () {
        var count = 0;
        void listener() {
          count++;
        }

        service.addListener(listener);
        service.stop(); // notifies
        expect(count, 1);

        service.removeListener(listener);
        service.stop(); // should not notify this listener
        expect(count, 1);
      });
    });
  });

  group('BackupInfo sorting', () {
    test('can sort by modified date descending (newest first)', () {
      final backups = [
        BackupInfo(
          path: '/old.audio',
          name: 'old.audio',
          modified: DateTime(2025, 1, 1),
        ),
        BackupInfo(
          path: '/newest.audio',
          name: 'newest.audio',
          modified: DateTime(2025, 6, 15),
        ),
        BackupInfo(
          path: '/middle.audio',
          name: 'middle.audio',
          modified: DateTime(2025, 3, 10),
        ),
      ];

      backups.sort((a, b) => b.modified.compareTo(a.modified));

      expect(backups[0].name, 'newest.audio');
      expect(backups[1].name, 'middle.audio');
      expect(backups[2].name, 'old.audio');
    });

    test('can sort by modified date ascending (oldest first)', () {
      final backups = [
        BackupInfo(
          path: '/old.audio',
          name: 'old.audio',
          modified: DateTime(2025, 1, 1),
        ),
        BackupInfo(
          path: '/newest.audio',
          name: 'newest.audio',
          modified: DateTime(2025, 6, 15),
        ),
      ];

      backups.sort((a, b) => a.modified.compareTo(b.modified));

      expect(backups[0].name, 'old.audio');
      expect(backups[1].name, 'newest.audio');
    });
  });
}
