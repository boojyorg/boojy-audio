import 'package:boojy_audio/models/midi_note_data.dart';
import 'package:boojy_audio/theme/theme_provider.dart';
import 'package:boojy_audio/widgets/piano_roll.dart';
import 'package:boojy_audio/widgets/piano_roll/piano_roll_state.dart';
import 'package:boojy_audio/widgets/piano_roll/velocity_lane_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Velocity lane drags, through the handlers the lane's GestureDetector calls.
void main() {
  late MidiClipData latest;

  Future<VelocityLaneMixin> pumpRoll(
    WidgetTester tester,
    List<MidiNoteData> notes,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clip = MidiClipData(
      clipId: 1,
      trackId: 1,
      startTime: 0,
      duration: 4,
      notes: notes,
    );
    latest = clip;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: PianoRoll(clipData: clip, onClipUpdated: (c) => latest = c),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state(find.byType(PianoRoll)) as VelocityLaneMixin;
  }

  /// Pointer position in the lane for [velocity]; past 127 or below 1 is
  /// above or below the lane, where a drag keeps reporting.
  Offset at(VelocityLaneMixin roll, double beat, int velocity) {
    final state = roll as PianoRollStateMixin;
    return Offset(
      beat * state.pixelsPerBeat,
      (1 - velocity / 127) * state.velocityLaneHeight,
    );
  }

  /// Press on the note at [beat], move through [path] (velocities the
  /// pointer's height stands for) and let go, as the lane does.
  Future<void> drag(
    WidgetTester tester,
    VelocityLaneMixin roll,
    double beat,
    List<int> path, {
    void Function(int velocity)? afterEach,
  }) async {
    roll.onVelocityPanStart(
      DragStartDetails(localPosition: at(roll, beat, path.first)),
    );
    for (final v in path) {
      roll.onVelocityPanUpdate(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          localPosition: at(roll, beat, v),
        ),
      );
      await tester.pump();
      afterEach?.call(v);
    }
    roll.onVelocityPanEnd(DragEndDetails());
    await tester.pump();
  }

  /// Drag in the lane from the note at [beat] to [velocity].
  Future<void> dragVelocity(
    WidgetTester tester,
    VelocityLaneMixin roll,
    double beat,
    int velocity,
  ) => drag(tester, roll, beat, [velocity]);

  Map<String, int> velocities() => {
    for (final n in latest.notes) n.id: n.velocity,
  };

  MidiNoteData note(String id, double beat, int velocity, {bool sel = false}) =>
      MidiNoteData(
        id: id,
        note: 60,
        velocity: velocity,
        startTime: beat,
        duration: 0.5,
        isSelected: sel,
      );

  testWidgets('dragging a selected note moves every selected note by the '
      'same amount', (tester) async {
    final roll = await pumpRoll(tester, [
      note('a', 0, 100, sel: true),
      note('b', 1, 60, sel: true),
      note('c', 2, 80),
    ]);

    await dragVelocity(tester, roll, 0, 110);

    expect(velocities(), {'a': 110, 'b': 70, 'c': 80});
  });

  testWidgets('pushing past the top gathers selected notes at 127, and the '
      'gap comes back on the way down in the same drag', (tester) async {
    final roll = await pumpRoll(tester, [
      note('loud', 0, 100, sel: true),
      note('soft', 1, 90, sel: true),
    ]);

    final seen = <int, Map<String, int>>{};
    await drag(tester, roll, 0, [
      100,
      127,
      132,
      137,
      147,
      110,
    ], afterEach: (v) => seen[v] = velocities());

    expect(seen[127], {'loud': 127, 'soft': 117}, reason: 'loud hits the top');
    expect(seen[132], {'loud': 127, 'soft': 122}, reason: 'soft keeps rising');
    expect(seen[137], {'loud': 127, 'soft': 127}, reason: 'both at the top');
    expect(seen[147], {'loud': 127, 'soft': 127}, reason: 'neither goes past');
    expect(seen[110], {'loud': 110, 'soft': 100}, reason: 'gap back');
    expect(velocities(), {'loud': 110, 'soft': 100});
  });

  testWidgets('letting go at the limit keeps the notes together', (
    tester,
  ) async {
    final roll = await pumpRoll(tester, [
      note('loud', 0, 100, sel: true),
      note('soft', 1, 90, sel: true),
    ]);

    await drag(tester, roll, 1, [90, -20]);
    expect(velocities(), {'loud': 1, 'soft': 1}, reason: 'pushed to the floor');

    await drag(tester, roll, 0, [1, 64]);
    expect(velocities(), {'loud': 64, 'soft': 64}, reason: 'now move as one');
  });

  testWidgets('dragging an unselected note changes only that note', (
    tester,
  ) async {
    final roll = await pumpRoll(tester, [
      note('a', 0, 100, sel: true),
      note('b', 1, 60, sel: true),
      note('c', 2, 80),
    ]);

    await dragVelocity(tester, roll, 2, 40);

    expect(velocities(), {'a': 100, 'b': 60, 'c': 40});
  });

  testWidgets('dragging sideways still paints across notes', (tester) async {
    final roll = await pumpRoll(tester, [note('a', 0, 100), note('b', 2, 60)]);

    roll.onVelocityPanStart(DragStartDetails(localPosition: at(roll, 0, 30)));
    roll.onVelocityPanUpdate(
      DragUpdateDetails(
        globalPosition: Offset.zero,
        localPosition: at(roll, 2, 30),
      ),
    );
    roll.onVelocityPanEnd(DragEndDetails());
    await tester.pump();

    expect(velocities(), {'a': 30, 'b': 30});
  });

  group('notes that start together (a chord)', () {
    // The quieter note comes first in the clip, so a tie on position alone
    // would always pick it.
    List<MidiNoteData> chord() => [note('soft', 0, 60), note('loud', 0, 100)];

    for (final (where, click, expected) in [
      ('above both', 120, {'soft': 60, 'loud': 120}),
      ('nearer the loud one', 90, {'soft': 60, 'loud': 90}),
      ('nearer the soft one', 70, {'soft': 70, 'loud': 100}),
      ('below both', 20, {'soft': 20, 'loud': 100}),
    ]) {
      testWidgets('a click $where moves the nearest circle', (tester) async {
        final roll = await pumpRoll(tester, chord());
        await dragVelocity(tester, roll, 0, click);
        expect(velocities(), expected);
      });
    }

    testWidgets('a chord played slightly loose still picks by height', (
      tester,
    ) async {
      // 0.02 beats apart: under 2 px at the default zoom.
      final roll = await pumpRoll(tester, [
        note('soft', 0.02, 60),
        note('loud', 0, 100),
      ]);
      await dragVelocity(tester, roll, 0.02, 110);
      expect(velocities(), {'soft': 60, 'loud': 110});
    });

    testWidgets('dragging one past the other keeps hold of the same note', (
      tester,
    ) async {
      final roll = await pumpRoll(tester, chord());
      await drag(tester, roll, 0, [100, 80, 60, 40, 30]);
      expect(velocities(), {'soft': 60, 'loud': 30});
    });
  });
}
