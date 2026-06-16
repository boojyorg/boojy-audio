import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../shared/boojy_dropdown.dart';

/// Shows a swap/reset/delete dropdown for a device in the chain.
///
/// For instruments: reset, swap (built-in list + plugins hint), delete.
/// For effects: reset, swap (built-in effects), delete.
class DeviceDropdown {
  /// Show dropdown for an instrument device.
  static Future<DeviceAction?> showForInstrument(
    BuildContext context,
    Offset position, {
    required String currentName,
  }) => _show(context, position, isInstrument: true, currentName: currentName);

  /// Show dropdown for an effect device.
  static Future<DeviceAction?> showForEffect(
    BuildContext context,
    Offset position, {
    required String currentName,
  }) => _show(context, position, isInstrument: false, currentName: currentName);

  static Future<DeviceAction?> _show(
    BuildContext context,
    Offset position, {
    required bool isInstrument,
    required String currentName,
  }) {
    final colors = context.themeProvider.colors;

    final items = <BoojyMenuEntry<DeviceAction>>[
      BoojyMenuItem(
        value: const DeviceAction.reset(),
        icon: BI.refresh,
        label: 'Reset to Default',
      ),
      const BoojyMenuDivider(),
      if (isInstrument) ...[
        const BoojyMenuSection(label: 'Built-in'),
        BoojyMenuItem(
          value: const DeviceAction.swap('synthesizer'),
          icon: BI.piano,
          label: 'Synthesizer',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('sampler'),
          icon: BI.piano,
          label: 'Sampler',
        ),
        const BoojyMenuSection(label: 'Plugins'),
        BoojyMenuItem(
          value: const DeviceAction.swap(''),
          icon: BI.info,
          label: 'Use library to add plugins',
          enabled: false,
        ),
      ] else ...[
        const BoojyMenuSection(label: 'Built-in'),
        BoojyMenuItem(
          value: const DeviceAction.swap('eq'),
          icon: BI.lightning,
          label: 'EQ',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('compressor'),
          icon: BI.lightning,
          label: 'Compressor',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('reverb'),
          icon: BI.lightning,
          label: 'Reverb',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('delay'),
          icon: BI.lightning,
          label: 'Delay',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('chorus'),
          icon: BI.lightning,
          label: 'Chorus',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('limiter'),
          icon: BI.lightning,
          label: 'Limiter',
        ),
      ],
      const BoojyMenuDivider(),
      BoojyMenuItem(
        value: const DeviceAction.delete(),
        icon: BI.delete,
        label: 'Delete',
        destructive: true,
      ),
    ];

    return showBoojyMenu<DeviceAction>(
      context: context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      items: items,
      selectedValue: null,
      colors: colors,
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
