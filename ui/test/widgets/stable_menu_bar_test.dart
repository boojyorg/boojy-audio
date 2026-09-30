import 'package:boojy_audio/widgets/shared/stable_menu_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<Object?, Object?>> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (call) async {
          if (call.method == 'Menu.setMenus') {
            sent.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, null);
  });

  Widget bar({required String label, VoidCallback? onSelected}) {
    return StableMenuBar(
      menus: [
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(label: label, onSelected: onSelected),
            PlatformMenuItemGroup(
              members: [PlatformMenuItem(label: 'Other', onSelected: () {})],
            ),
          ],
        ),
      ],
      child: const SizedBox(),
    );
  }

  /// Finds the platform id the framework gave the item called [label].
  int idFor(String label) {
    int? find(Object? node) {
      if (node is Map) {
        if (node['label'] == label) return node['id'] as int;
        for (final v in node.values) {
          final id = find(v);
          if (id != null) return id;
        }
      } else if (node is List) {
        for (final v in node) {
          final id = find(v);
          if (id != null) return id;
        }
      }
      return null;
    }

    return find(sent.last)!;
  }

  Future<void> click(WidgetTester tester, String label) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.menu.name,
      SystemChannels.menu.codec.encodeMethodCall(
        MethodCall('Menu.selectedCallback', idFor(label)),
      ),
      (_) {},
    );
  }

  testWidgets('an identical rebuild does not resend the menus', (tester) async {
    await tester.pumpWidget(bar(label: 'Split', onSelected: () {}));
    // Flutter's PlatformMenuBar always resends once on its first rebuild (its
    // comparison list starts empty), so warm up before counting.
    await tester.pumpWidget(bar(label: 'Split', onSelected: () {}));
    final first = sent.length;
    expect(first, greaterThan(0));

    // New closures and new item objects, but nothing visible changed.
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(bar(label: 'Split', onSelected: () {}));
    }
    expect(sent.length, first);
  });

  testWidgets('a visible change resends', (tester) async {
    await tester.pumpWidget(bar(label: 'Split', onSelected: () {}));
    await tester.pumpWidget(bar(label: 'Split', onSelected: () {}));
    final first = sent.length;

    await tester.pumpWidget(bar(label: '✓ Split', onSelected: () {}));
    expect(sent.length, first + 1);

    // Enabled → disabled is visible too.
    await tester.pumpWidget(bar(label: '✓ Split'));
    expect(sent.length, first + 2);
  });

  testWidgets('a click runs the callback from the latest build', (
    tester,
  ) async {
    var which = '';
    await tester.pumpWidget(bar(label: 'Split', onSelected: () => which = 'a'));
    await tester.pumpWidget(bar(label: 'Split', onSelected: () => which = 'b'));

    await click(tester, 'Split');
    expect(which, 'b');
  });
}
