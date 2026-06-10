// Regression test for the v0.6 M/S/R tap lag: an onDoubleTap recognizer on
// the track header / mixer strip root held the gesture arena for
// kDoubleTapTimeout (~300ms) after every tap, delaying the M/S/R/I buttons
// inside by that long. Double-click is now detected manually from single
// taps, so button taps must land immediately while double-click-to-open
// keeps working.
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/track_header.dart';
import 'package:boojy_audio/widgets/track_mixer_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 260, height: 700, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('TrackHeader (arrangement)', () {
    testWidgets('M tap fires immediately with double-click wired', (
      tester,
    ) async {
      var muteCount = 0;
      await tester.pumpWidget(
        _wrap(
          TrackHeader(
            trackId: 1,
            trackName: 'Reg',
            trackType: 'midi',
            isMuted: false,
            isSoloed: false,
            onMuteToggle: () => muteCount++,
            onDoubleClick: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('M'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        muteCount,
        1,
        reason:
            'M must toggle within 50ms of the tap. A failure here means a '
            'gesture recognizer on an ancestor is holding the arena again '
            '(the v0.6 M/S/R lag).',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('double-click on header background still opens the editor', (
      tester,
    ) async {
      var doubleClicks = 0;
      await tester.pumpWidget(
        _wrap(
          TrackHeader(
            trackId: 1,
            trackName: 'Reg',
            trackType: 'midi',
            isMuted: false,
            isSoloed: false,
            onDoubleClick: () => doubleClicks++,
          ),
        ),
      );
      await tester.pump();
      final spot =
          tester.getTopLeft(find.byType(TrackHeader)) + const Offset(5, 5);
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 50));
      expect(doubleClicks, 1);
      // A third lone tap much later must NOT count as a double-click.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 400));
      expect(doubleClicks, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('TrackMixerStrip (mixer)', () {
    Widget strip({
      VoidCallback? onMuteToggle,
      ValueChanged<bool>? onTap,
      VoidCallback? onDoubleTap,
    }) {
      return _wrap(
        TrackMixerStrip(
          trackId: 1,
          displayIndex: 1,
          trackName: 'Reg',
          trackType: 'midi',
          volumeDb: 0.0,
          pan: 0.0,
          isMuted: false,
          isSoloed: false,
          onMuteToggle: onMuteToggle,
          onTap: onTap ?? (_) {},
          onDoubleTap: onDoubleTap ?? () {},
        ),
      );
    }

    testWidgets('M tap fires immediately with strip double-tap wired', (
      tester,
    ) async {
      var muteCount = 0;
      await tester.pumpWidget(strip(onMuteToggle: () => muteCount++));
      await tester.pump();
      await tester.tap(find.text('M').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        muteCount,
        1,
        reason:
            'M must toggle within 50ms of the tap. A failure here means a '
            'gesture recognizer on an ancestor is holding the arena again '
            '(the v0.6 M/S/R lag).',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'double-click on strip background opens editor; each click selects',
      (tester) async {
        var doubleTaps = 0;
        var selects = 0;
        await tester.pumpWidget(
          strip(onTap: (_) => selects++, onDoubleTap: () => doubleTaps++),
        );
        await tester.pump();
        final spot =
            tester.getTopLeft(find.byType(TrackMixerStrip)) +
            const Offset(5, 5);
        await tester.tapAt(spot);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(spot);
        await tester.pump(const Duration(milliseconds: 50));
        expect(doubleTaps, 1);
        expect(
          selects,
          2,
          reason:
              'Manual double-click detection means the first click selects '
              'immediately instead of being swallowed by the recognizer.',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
