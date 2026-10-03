import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Holds the mouse pointer still and hidden while a drag-to-adjust control
/// (tempo, knobs, …) is dragged, so a long drag never runs into the edge of
/// the screen and the pointer reappears where it was pressed.
///
/// While held, the drag's own updates stop moving (the pointer doesn't
/// move), and the native side reports the mouse's movement through the
/// `onMove` given to [start] instead. A control sends both to the same
/// handler: one is always still, so nothing counts twice. Where the native
/// side is missing (tests, touch, other platforms) the drag works as before.
class PointerHold {
  static const _channel = MethodChannel('boojy_audio/pointer_hold');
  static PointerHold? _active;
  static bool _listening = false;

  void Function(Offset delta)? _onMove;

  /// Hold the pointer for a drag that started with [kind]. Mouse drags only:
  /// touch has no pointer to hide.
  void start(PointerDeviceKind? kind, void Function(Offset delta) onMove) {
    if (kind != PointerDeviceKind.mouse) return;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_handleNative);
    }
    _active?.end();
    _active = this;
    _onMove = onMove;
    _invoke('hold');
  }

  /// Let the pointer go (it reappears where the drag started). Safe to call
  /// when not holding.
  void end() {
    if (_active != this) return;
    _active = null;
    _onMove = null;
    _invoke('release');
  }

  static Future<void> _handleNative(MethodCall call) async {
    if (call.method != 'move') return;
    final args = call.arguments as List<Object?>;
    _active?._onMove?.call(
      Offset((args[0]! as num).toDouble(), (args[1]! as num).toDouble()),
    );
  }

  static void _invoke(String method) {
    _channel.invokeMethod<void>(method).catchError((Object _) {
      // No native side here: the drag simply moves the pointer as before.
    });
  }
}
