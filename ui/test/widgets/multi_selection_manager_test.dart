import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/widgets/shared/editors/multi_selection_manager.dart';

void main() {
  late MultiSelectionManager<int> manager;

  setUp(() {
    manager = MultiSelectionManager<int>();
  });

  group('basic selection', () {
    test('starts empty', () {
      expect(manager.isEmpty, isTrue);
      expect(manager.count, 0);
      expect(manager.primary, isNull);
    });

    test('select single item', () {
      manager.select(1);
      expect(manager.isSelected(1), isTrue);
      expect(manager.primary, 1);
      expect(manager.count, 1);
    });

    test('select replaces previous selection by default', () {
      manager.select(1);
      manager.select(2);
      expect(manager.isSelected(1), isFalse);
      expect(manager.isSelected(2), isTrue);
      expect(manager.count, 1);
    });
  });

  group('additive selection', () {
    test('adds to existing selection', () {
      manager.select(1);
      manager.select(2, additive: true);
      expect(manager.isSelected(1), isTrue);
      expect(manager.isSelected(2), isTrue);
      expect(manager.count, 2);
      expect(manager.primary, 2);
    });
  });

  group('toggle selection', () {
    test('adds unselected item', () {
      manager.select(1, toggle: true);
      expect(manager.isSelected(1), isTrue);
    });

    test('removes already selected item', () {
      manager.select(1);
      manager.select(1, toggle: true);
      expect(manager.isSelected(1), isFalse);
      expect(manager.isEmpty, isTrue);
    });

    test('updates primary when toggled item was primary', () {
      manager.select(1);
      manager.select(2, additive: true);
      manager.select(2, toggle: true);
      expect(manager.primary, 1);
    });
  });

  group('selectAll', () {
    test('replaces selection by default', () {
      manager.select(1);
      manager.selectAll([2, 3, 4]);
      expect(manager.count, 3);
      expect(manager.isSelected(1), isFalse);
      expect(manager.isSelected(4), isTrue);
      expect(manager.primary, 4); // last item
    });

    test('additive mode preserves existing', () {
      manager.select(1);
      manager.selectAll([2, 3], additive: true);
      expect(manager.count, 3);
      expect(manager.isSelected(1), isTrue);
    });
  });

  group('clear and deselect', () {
    test('clear empties selection', () {
      manager.selectAll([1, 2, 3]);
      manager.clear();
      expect(manager.isEmpty, isTrue);
      expect(manager.primary, isNull);
    });

    test('deselect removes specific item', () {
      manager.selectAll([1, 2, 3]);
      manager.deselect(2);
      expect(manager.isSelected(2), isFalse);
      expect(manager.count, 2);
    });

    test('deselect updates primary if removed item was primary', () {
      manager.select(1);
      manager.select(2, additive: true);
      // Primary is now 2
      manager.deselect(2);
      expect(manager.primary, 1);
    });
  });

  group('replaceSelection', () {
    test('replaces entire selection', () {
      manager.selectAll([1, 2, 3]);
      manager.replaceSelection({4, 5}, primary: 5);
      expect(manager.count, 2);
      expect(manager.isSelected(1), isFalse);
      expect(manager.isSelected(5), isTrue);
      expect(manager.primary, 5);
    });

    test('picks first item as primary when not specified', () {
      manager.replaceSelection({10, 20});
      expect(manager.primary, isNotNull);
    });
  });

  group('notifications', () {
    test('notifies listeners on select', () {
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);

      manager.select(1);
      expect(notifyCount, 1);

      manager.select(2, additive: true);
      expect(notifyCount, 2);
    });

    test('clear does not notify when already empty', () {
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);

      manager.clear();
      expect(notifyCount, 0);
    });

    test('deselect does not notify for absent item', () {
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);

      manager.deselect(999);
      expect(notifyCount, 0);
    });
  });
}
