import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/tool_mode_resolver.dart';
import 'package:boojy_audio/models/tool_mode.dart';

void main() {
  group('ModifierKeyState', () {
    group('getOverrideToolMode', () {
      test('alt pressed returns ToolMode.eraser', () {
        const state = ModifierKeyState(
          isShiftPressed: false,
          isAltPressed: true,
          isCtrlOrCmd: false,
        );

        expect(state.getOverrideToolMode(), ToolMode.eraser);
      });

      test('ctrl/cmd pressed returns ToolMode.duplicate', () {
        const state = ModifierKeyState(
          isShiftPressed: false,
          isAltPressed: false,
          isCtrlOrCmd: true,
        );

        expect(state.getOverrideToolMode(), ToolMode.duplicate);
      });

      test('shift pressed returns ToolMode.select', () {
        const state = ModifierKeyState(
          isShiftPressed: true,
          isAltPressed: false,
          isCtrlOrCmd: false,
        );

        expect(state.getOverrideToolMode(), ToolMode.select);
      });

      test('no modifiers returns null', () {
        const state = ModifierKeyState(
          isShiftPressed: false,
          isAltPressed: false,
          isCtrlOrCmd: false,
        );

        expect(state.getOverrideToolMode(), isNull);
      });

      test('alt takes priority over ctrl', () {
        const state = ModifierKeyState(
          isShiftPressed: false,
          isAltPressed: true,
          isCtrlOrCmd: true,
        );

        expect(state.getOverrideToolMode(), ToolMode.eraser);
      });

      test('alt takes priority over shift', () {
        const state = ModifierKeyState(
          isShiftPressed: true,
          isAltPressed: true,
          isCtrlOrCmd: false,
        );

        expect(state.getOverrideToolMode(), ToolMode.eraser);
      });

      test('ctrl takes priority over shift', () {
        const state = ModifierKeyState(
          isShiftPressed: true,
          isAltPressed: false,
          isCtrlOrCmd: true,
        );

        expect(state.getOverrideToolMode(), ToolMode.duplicate);
      });
    });
  });

  group('ToolModeResolver', () {
    group('getCursor', () {
      test('draw returns SystemMouseCursors.precise', () {
        expect(
          ToolModeResolver.getCursor(ToolMode.draw),
          SystemMouseCursors.precise,
        );
      });

      test('select returns SystemMouseCursors.basic', () {
        expect(
          ToolModeResolver.getCursor(ToolMode.select),
          SystemMouseCursors.basic,
        );
      });

      test('eraser returns SystemMouseCursors.forbidden', () {
        expect(
          ToolModeResolver.getCursor(ToolMode.eraser),
          SystemMouseCursors.forbidden,
        );
      });

      test('duplicate returns SystemMouseCursors.copy', () {
        expect(
          ToolModeResolver.getCursor(ToolMode.duplicate),
          SystemMouseCursors.copy,
        );
      });

      test('slice returns SystemMouseCursors.verticalText', () {
        expect(
          ToolModeResolver.getCursor(ToolMode.slice),
          SystemMouseCursors.verticalText,
        );
      });
    });

    group('isModifierKey', () {
      test('returns true for shift', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.shift),
          isTrue,
        );
      });

      test('returns true for alt', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.alt),
          isTrue,
        );
      });

      test('returns true for meta', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.meta),
          isTrue,
        );
      });

      test('returns true for control', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.control),
          isTrue,
        );
      });

      test('returns false for keyA', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.keyA),
          isFalse,
        );
      });

      test('returns false for space', () {
        expect(
          ToolModeResolver.isModifierKey(LogicalKeyboardKey.space),
          isFalse,
        );
      });
    });
  });
}
