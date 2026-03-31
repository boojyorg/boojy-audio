import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';

/// Shows a dropdown menu for a device in the chain.
///
/// For instruments: reset, swap (built-in list + plugins), rename, delete.
/// For effects: reset, swap (built-in effects + plugins), rename, delete.
class DeviceDropdown {
  /// Show dropdown for an instrument device.
  /// Returns the selected action or null if dismissed.
  static Future<DeviceAction?> showForInstrument(
    BuildContext context,
    Offset position, {
    required String currentName,
  }) async {
    return _show(
      context,
      position,
      isInstrument: true,
      currentName: currentName,
    );
  }

  /// Show dropdown for an effect device.
  /// Returns the selected action or null if dismissed.
  static Future<DeviceAction?> showForEffect(
    BuildContext context,
    Offset position, {
    required String currentName,
  }) async {
    return _show(
      context,
      position,
      isInstrument: false,
      currentName: currentName,
    );
  }

  static Future<DeviceAction?> _show(
    BuildContext context,
    Offset position, {
    required bool isInstrument,
    required String currentName,
  }) async {
    final colors = context.themeProvider.colors;

    final items = <PopupMenuEntry<DeviceAction>>[
      // Reset to Default
      PopupMenuItem(
        value: const DeviceAction.reset(),
        child: Row(
          children: [
            Icon(BI.refresh, size: 14, color: colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              'Reset to Default',
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ],
        ),
      ),

      const PopupMenuDivider(),

      // Swap options
      if (isInstrument) ...[
        _sectionHeader(colors, 'BUILT-IN'),
        _swapItem(colors, BI.piano, 'Synthesizer', 'synthesizer'),
        _swapItem(colors, BI.piano, 'Sampler', 'sampler'),
        _sectionHeader(colors, 'PLUGINS'),
        PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            'Use library to add plugins',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ] else ...[
        _sectionHeader(colors, 'BUILT-IN'),
        _swapItem(colors, BI.lightning, 'EQ', 'eq'),
        _swapItem(colors, BI.lightning, 'Compressor', 'compressor'),
        _swapItem(colors, BI.lightning, 'Reverb', 'reverb'),
        _swapItem(colors, BI.lightning, 'Delay', 'delay'),
        _swapItem(colors, BI.lightning, 'Chorus', 'chorus'),
        _swapItem(colors, BI.lightning, 'Limiter', 'limiter'),
      ],

      const PopupMenuDivider(),

      // Delete
      PopupMenuItem(
        value: const DeviceAction.delete(),
        child: Row(
          children: [
            Icon(BI.delete, size: 14, color: colors.error),
            const SizedBox(width: 8),
            Text('Delete', style: TextStyle(color: colors.error, fontSize: 13)),
          ],
        ),
      ),
    ];

    return showMenu<DeviceAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: items,
    );
  }

  static PopupMenuItem<DeviceAction> _swapItem(
    BoojyColors colors,
    IconData icon,
    String label,
    String type,
  ) {
    return PopupMenuItem(
      value: DeviceAction.swap(type),
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<DeviceAction> _sectionHeader(
    BoojyColors colors,
    String label,
  ) {
    return PopupMenuItem(
      enabled: false,
      height: 24,
      child: Text(
        label,
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 11,
          fontWeight: BT.weightSemiBold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Actions returned by the device dropdown.
sealed class DeviceAction {
  const DeviceAction();
  const factory DeviceAction.reset() = ResetAction;
  const factory DeviceAction.swap(String type) = SwapAction;
  const factory DeviceAction.delete() = DeleteAction;
}

class ResetAction extends DeviceAction {
  const ResetAction();
}

class SwapAction extends DeviceAction {
  final String type;
  const SwapAction(this.type);
}

class DeleteAction extends DeviceAction {
  const DeleteAction();
}
