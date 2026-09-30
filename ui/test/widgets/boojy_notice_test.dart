import 'package:boojy_audio/theme/boojy_icons.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/shared/boojy_notice.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final notices = Notices.instance;

  setUp(notices.reset);
  tearDown(notices.reset);

  Future<void> pumpHost(WidgetTester tester, {bool anchored = false}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          builder: (context, child) => NoticeHost(child: child!),
          home: Scaffold(
            body: anchored
                ? const Column(
                    children: [
                      Expanded(child: NoticeAnchor(child: SizedBox.expand())),
                      SizedBox(height: 200),
                    ],
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  testWidgets('info fades after infoDuration', (tester) async {
    await pumpHost(tester);
    Notices.info('Select a clip first');
    await tester.pump();
    expect(find.text('Select a clip first'), findsOneWidget);

    await tester.pump(Notices.infoDuration - const Duration(milliseconds: 100));
    expect(notices.currentInfo, isNotNull);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(notices.currentInfo, isNull);
    expect(find.text('Select a clip first'), findsNothing);
  });

  testWidgets('a new info replaces the old one', (tester) async {
    await pumpHost(tester);
    Notices.info('First');
    Notices.info('Second');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(Notices.infoDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('hovering info pauses the fade', (tester) async {
    await pumpHost(tester);
    Notices.info('Hover me');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Hover me')));
    await tester.pump(Notices.infoDuration * 2);
    expect(notices.currentInfo, isNotNull, reason: 'held while hovered');

    await mouse.moveTo(Offset.zero);
    await tester.pump(Notices.infoDuration);
    await tester.pumpAndSettle();
    expect(notices.currentInfo, isNull, reason: 'fades after leaving');
  });

  testWidgets('problems stay until closed', (tester) async {
    await pumpHost(tester);
    Notices.problem("Couldn't save the project");
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1));
    expect(find.text("Couldn't save the project"), findsOneWidget);
    expect(find.byIcon(BI.warning), findsOneWidget);

    await tester.tap(find.byIcon(BI.close));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save the project"), findsNothing);
  });

  testWidgets('the action runs and closes the problem', (tester) async {
    await pumpHost(tester);
    var ran = false;
    Notices.problem(
      'Audio device lost',
      action: NoticeAction('Open Settings', () => ran = true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(ran, isTrue);
    expect(notices.problems, isEmpty);
  });

  testWidgets('clear(id) removes only that problem', (tester) async {
    await pumpHost(tester);
    Notices.problem("Boojy can't hear your input", id: 'audio-input');
    Notices.problem("Couldn't load that audio file");
    await tester.pumpAndSettle();

    Notices.clear('audio-input');
    await tester.pumpAndSettle();
    expect(find.text("Boojy can't hear your input"), findsNothing);
    expect(find.text("Couldn't load that audio file"), findsOneWidget);
  });

  test('the same problem twice does not stack', () {
    Notices.problem('Same text');
    Notices.problem('Same text');
    Notices.problem('Old wording', id: 'x');
    Notices.problem('New wording', id: 'x');
    expect(notices.problems.map((p) => p.text), ['Same text', 'New wording']);
  });

  test('a problem beyond maxProblems drops the oldest', () {
    for (var i = 1; i <= Notices.maxProblems + 1; i++) {
      Notices.problem('Problem $i');
    }
    expect(notices.problems.length, Notices.maxProblems);
    expect(notices.problems.first.text, 'Problem 2');
  });

  testWidgets('pills are one height per line and grow with a second line', (
    tester,
  ) async {
    await pumpHost(tester);
    Notices.problem('Short problem');
    Notices.problem(
      'A much longer problem that cannot possibly fit on one line of the '
      'pill, so it has to wrap onto a second line',
    );
    Notices.info('Short hint');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    double pillHeight(String startsWith) => tester
        .getSize(
          find
              .ancestor(
                of: find.textContaining(startsWith),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .height;

    final oneLine = pillHeight('Short problem');
    expect(pillHeight('Short hint'), closeTo(oneLine, 0.5));
    expect(pillHeight('A much longer'), greaterThan(oneLine + 8));
    expect(oneLine, greaterThanOrEqualTo(32), reason: 'touch-ready ✕');
    await tester.pump(Notices.infoDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('centres on the anchor, above its bottom edge', (tester) async {
    await pumpHost(tester, anchored: true);
    Notices.info('Anchored');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    final screen = tester.getSize(find.byType(Scaffold));
    final pill = tester.getRect(find.text('Anchored'));
    expect(pill.center.dx, closeTo(screen.width / 2, 1));
    // The anchor ends 200px above the bottom of the window.
    expect(pill.bottom, lessThan(screen.height - 200));
    expect(pill.bottom, greaterThan(screen.height - 200 - 60));
    await tester.pump(Notices.infoDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('clicks pass through around the notice', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          builder: (context, child) => NoticeHost(child: child!),
          home: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped = true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    Notices.problem('Something');
    await tester.pumpAndSettle();
    final pill = tester.getRect(find.text('Something'));
    await tester.tapAt(Offset(10, pill.center.dy));
    expect(tapped, isTrue);
  });
}
