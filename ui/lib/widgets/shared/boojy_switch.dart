import 'package:flutter/material.dart';

import '../../theme/theme_extension.dart';

/// A compact pill toggle (Notion / iOS style) for an independent on/off setting
/// — track fills with the accent colour when on, a white knob slides across.
///
/// Use this for a *single* boolean setting where changes apply immediately. For
/// "pick N items from a list" use a [Checkbox] instead — that's the one case a
/// tick box still reads correctly.
class BoojySwitch extends StatelessWidget {
  const BoojySwitch({super.key, required this.value, required this.onChanged});

  final bool value;

  /// Null disables the toggle (greyed, non-interactive).
  final ValueChanged<bool>? onChanged;

  static const double _width = 38;
  static const double _height = 22;
  static const double _knob = 16;
  static const Duration _anim = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onChanged != null;

    return GestureDetector(
      onTap: enabled ? () => onChanged!(!value) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: _anim,
            curve: Curves.easeOut,
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? colors.accent : colors.divider,
              borderRadius: BorderRadius.circular(_height / 2),
            ),
            child: AnimatedAlign(
              duration: _anim,
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: _knob,
                height: _knob,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
