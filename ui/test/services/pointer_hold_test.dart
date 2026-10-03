import 'package:boojy_audio/services/pointer_hold.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('boojy_audio/pointer_hold');

/// Calls the app made to the native side, in order.
List<String> _recordNativeCalls() {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call.method);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

/// The native side reporting mouse movement while the pointer is held.
Future<void> nativeMove(double dx, double dy) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('move', [dx, dy]),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a mouse drag holds the pointer and gets its movement', () async {
    final calls = _recordNativeCalls();
    final moves = <Offset>[];
    final hold = PointerHold()..start(PointerDeviceKind.mouse, moves.add);

    await nativeMove(0, -4);
    hold.end();
    await nativeMove(0, -4); // after release: ignored

    expect(calls, ['hold', 'release']);
    expect(moves, [const Offset(0, -4)]);
  });

  test('a touch drag leaves the pointer alone', () {
    final calls = _recordNativeCalls();
    PointerHold()
      ..start(PointerDeviceKind.touch, (_) {})
      ..end();
    expect(calls, isEmpty);
  });

  test('a new hold takes over from one never ended', () async {
    final calls = _recordNativeCalls();
    final first = <Offset>[];
    final second = <Offset>[];
    PointerHold().start(PointerDeviceKind.mouse, first.add);
    PointerHold().start(PointerDeviceKind.mouse, second.add);

    await nativeMove(1, 0);

    expect(calls, ['hold', 'release', 'hold']);
    expect(first, isEmpty);
    expect(second, [const Offset(1, 0)]);
  });

  test('without a native side, holding is a quiet no-op', () async {
    final hold = PointerHold()..start(PointerDeviceKind.mouse, (_) {});
    hold.end();
    await Future<void>.delayed(Duration.zero); // let the failed calls settle
  });
}
