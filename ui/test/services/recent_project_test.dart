import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/user_settings.dart';

void main() {
  group('RecentProject', () {
    group('constructor', () {
      test('creates RecentProject with required fields', () {
        final openedAt = DateTime(2025, 1, 15, 10, 30);
        final project = RecentProject(
          path: '/path/to/project.boojy',
          name: 'My Project',
          openedAt: openedAt,
        );

        expect(project.path, '/path/to/project.boojy');
        expect(project.name, 'My Project');
        expect(project.openedAt, openedAt);
      });
    });

    group('JSON serialization', () {
      test('toJson includes all fields', () {
        final openedAt = DateTime(2025, 3, 20, 14, 45, 30);
        final project = RecentProject(
          path: '/Users/test/Documents/Song.boojy',
          name: 'Song',
          openedAt: openedAt,
        );

        final json = project.toJson();

        expect(json['path'], '/Users/test/Documents/Song.boojy');
        expect(json['name'], 'Song');
        expect(json['openedAt'], '2025-03-20T14:45:30.000');
      });

      test('fromJson parses all fields', () {
        final json = {
          'path': '/path/to/restored.boojy',
          'name': 'Restored Project',
          'openedAt': '2025-06-15T09:00:00.000',
        };

        final project = RecentProject.fromJson(json);

        expect(project.path, '/path/to/restored.boojy');
        expect(project.name, 'Restored Project');
        expect(project.openedAt, DateTime(2025, 6, 15, 9, 0, 0));
      });

      test('roundtrip serialization preserves data', () {
        final original = RecentProject(
          path: '/roundtrip/test.boojy',
          name: 'Roundtrip Test',
          openedAt: DateTime(2025, 7, 4, 12, 30, 45),
        );

        final json = original.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.path, original.path);
        expect(restored.name, original.name);
        expect(restored.openedAt, original.openedAt);
      });

      test('handles paths with special characters', () {
        final project = RecentProject(
          path: '/Users/test/My Music & Sounds/Project #1.boojy',
          name: 'Project #1',
          openedAt: DateTime(2025, 1, 1),
        );

        final json = project.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.path, project.path);
        expect(restored.name, project.name);
      });

      test('handles unicode in names', () {
        final project = RecentProject(
          path: '/projects/musique.boojy',
          name: 'Musique Francaise',
          openedAt: DateTime(2025, 1, 1),
        );

        final json = project.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.name, project.name);
      });

      test('handles empty name', () {
        final project = RecentProject(
          path: '/test.boojy',
          name: '',
          openedAt: DateTime(2025, 1, 1),
        );

        final json = project.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.name, '');
      });
    });

    group('edge cases', () {
      test('handles very long paths', () {
        final longPath = '/very/long${'/subdir' * 50}/file.boojy';
        final project = RecentProject(
          path: longPath,
          name: 'Long Path Project',
          openedAt: DateTime(2025, 1, 1),
        );

        final json = project.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.path, longPath);
      });

      test('handles dates at epoch boundaries', () {
        // Unix epoch
        final epochProject = RecentProject(
          path: '/test.boojy',
          name: 'Epoch',
          openedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

        final json = epochProject.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.openedAt.millisecondsSinceEpoch, 0);
      });

      test('handles future dates', () {
        final futureDate = DateTime(2030, 12, 31, 23, 59, 59);
        final project = RecentProject(
          path: '/future.boojy',
          name: 'Future Project',
          openedAt: futureDate,
        );

        final json = project.toJson();
        final restored = RecentProject.fromJson(json);

        expect(restored.openedAt, futureDate);
      });
    });
  });

  group('AutoSaveOption', () {
    test('creates AutoSaveOption with minutes and label', () {
      final option = AutoSaveOption(5, '5 minutes');

      expect(option.minutes, 5);
      expect(option.label, '5 minutes');
    });

    test('autoSaveOptions returns expected options', () {
      final options = UserSettings.autoSaveOptions;

      expect(options.length, 6);

      // Check first option (Off)
      expect(options[0].minutes, 0);
      expect(options[0].label, 'Off');

      // Check last option (15 minutes)
      expect(options.last.minutes, 15);
      expect(options.last.label, '15 minutes');
    });

    test('autoSaveOptions includes common intervals', () {
      final options = UserSettings.autoSaveOptions;
      final minutes = options.map((o) => o.minutes).toList();

      expect(minutes, contains(0));  // Off
      expect(minutes, contains(1));  // 1 minute
      expect(minutes, contains(2));  // 2 minutes
      expect(minutes, contains(5));  // 5 minutes
      expect(minutes, contains(10)); // 10 minutes
      expect(minutes, contains(15)); // 15 minutes
    });
  });
}
