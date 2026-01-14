import 'package:flutter/services.dart';

import '../models/tool_mode.dart';

/// Captures the current state of modifier keys.
class ModifierKeyState {
  final bool isShiftPressed;
  final bool isAltPressed;
  final bool isCtrlOrCmd;

  const ModifierKeyState({
    required this.isShiftPressed,
    required this.isAltPressed,
    required this.isCtrlOrCmd,
  });

  /// Create from current hardware keyboard state.
  factory ModifierKeyState.current() {
    return ModifierKeyState(
      isShiftPressed: HardwareKeyboard.instance.isShiftPressed,
      isAltPressed: HardwareKeyboard.instance.isAltPressed,
      isCtrlOrCmd: HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed,
    );
  }

  /// Get the tool mode override based on modifier keys.
  /// Returns null if no override applies.
  ///
  /// Priority order:
  /// 1. Alt → Eraser (delete mode)
  /// 2. Cmd/Ctrl → Duplicate (copy mode)
  /// 3. Shift → Select (selection mode)
  ToolMode? getOverrideToolMode() {
    if (isAltPressed) return ToolMode.eraser;
    if (isCtrlOrCmd) return ToolMode.duplicate;
    if (isShiftPressed) return ToolMode.select;
    return null;
  }
}

/// Centralized tool mode resolution based on base tool and modifier keys.
///
/// This eliminates duplication of modifier key → tool mode logic across
/// Piano Roll, Timeline, and Editor Panel.
class ToolModeResolver {
  ToolModeResolver._();

  /// Resolve the effective tool mode given a base tool mode.
  /// Modifier keys can override the base tool mode.
  static ToolMode resolve(ToolMode baseToolMode) {
    final modifiers = ModifierKeyState.current();
    return modifiers.getOverrideToolMode() ?? baseToolMode;
  }

  /// Get the cursor for a given tool mode.
  static MouseCursor getCursor(ToolMode toolMode) {
    return switch (toolMode) {
      ToolMode.draw => SystemMouseCursors.precise,
      ToolMode.select => SystemMouseCursors.basic,
      ToolMode.eraser => SystemMouseCursors.forbidden,
      ToolMode.duplicate => SystemMouseCursors.copy,
      ToolMode.slice => SystemMouseCursors.verticalText,
    };
  }

  /// Get the cursor for the effective tool mode (resolving modifier keys).
  static MouseCursor getEffectiveCursor(ToolMode baseToolMode) {
    return getCursor(resolve(baseToolMode));
  }

  /// All modifier keys that can affect tool mode.
  static const List<LogicalKeyboardKey> modifierKeys = [
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  ];

  /// Check if a key is a modifier key that affects tool mode.
  static bool isModifierKey(LogicalKeyboardKey key) {
    return modifierKeys.contains(key);
  }

  /// Check if any modifier key is currently pressed.
  static bool get isAnyModifierPressed {
    final modifiers = ModifierKeyState.current();
    return modifiers.isShiftPressed ||
        modifiers.isAltPressed ||
        modifiers.isCtrlOrCmd;
  }
}
