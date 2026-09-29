import 'package:flutter/widgets.dart';

/// Whether a text input currently has keyboard focus.
///
/// Global single-key handlers (transport keys, the computer-keyboard piano)
/// check this so typing a name never plays notes or toggles the loop.
bool isTextFieldFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}
