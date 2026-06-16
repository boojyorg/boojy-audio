import 'package:flutter/material.dart';
import '../../models/vst3_plugin_data.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../shared/boojy_dropdown.dart';
import 'builtin_devices.dart';

/// Shows a unified, searchable device picker for swapping or adding devices in
/// the chain.
///
/// **Instruments:** Reset + Built-in (Synth / Sampler / Drum Kit) + optional
/// VST3 instrument rows. No Delete — every track needs exactly one instrument;
/// the right verb is swap, not delete.
///
/// **Effects:** Reset + Built-in (EQ / Compressor / Reverb / Delay / Chorus /
/// Limiter) + optional VST3 effect rows + destructive Delete.
///
/// When the total row count exceeds [_searchThreshold], a live-filter search
/// bar appears above the list automatically.
class DeviceDropdown {
  static const int _searchThreshold = 8;

  /// Show picker for an instrument device.
  static Future<DeviceAction?> showForInstrument(
    BuildContext context,
    Offset position, {
    required String currentName,
    List<Vst3Plugin> availablePlugins = const [],
  }) => _show(
    context,
    position,
    isInstrument: true,
    currentName: currentName,
    availablePlugins: availablePlugins,
  );

  /// Show picker for an effect device (swap — called from the name-tap).
  static Future<DeviceAction?> showForEffect(
    BuildContext context,
    Offset position, {
    required String currentName,
    List<Vst3Plugin> availablePlugins = const [],
  }) => _show(
    context,
    position,
    isInstrument: false,
    currentName: currentName,
    availablePlugins: availablePlugins,
  );

  /// Show picker for adding a new effect (called from the "+" button).
  ///
  /// Same surface as [showForEffect] but anchored via [anchor] (button-aligned
  /// Rect) and without the Reset row — adding is not the same as swapping.
  static Future<DeviceAction?> showAddEffect(
    BuildContext context,
    Rect anchor, {
    List<Vst3Plugin> availablePlugins = const [],
  }) {
    final colors = context.themeProvider.colors;
    final vst3Effects = availablePlugins.where((p) => p.isEffect).toList();

    final items = <BoojyMenuEntry<DeviceAction>>[
      const BoojyMenuSection(label: 'Built-in'),
      for (final e in builtinEffects)
        BoojyMenuItem(
          value: DeviceAction.swap(e.type),
          icon: e.icon,
          label: e.name,
        ),
      if (vst3Effects.isNotEmpty) ...[
        const BoojyMenuSection(label: 'Plugins'),
        for (final p in vst3Effects)
          BoojyMenuItem(
            value: DeviceAction.swap('vst3:${p.path}'),
            icon: BI.plugin,
            label: p.name,
          ),
      ],
    ];

    final totalItems = items.whereType<BoojyMenuItem<DeviceAction>>().length;

    return showBoojyMenu<DeviceAction>(
      context: context,
      anchor: anchor,
      items: items,
      selectedValue: null,
      colors: colors,
      showSearch: totalItems > _searchThreshold,
    );
  }

  static Future<DeviceAction?> _show(
    BuildContext context,
    Offset position, {
    required bool isInstrument,
    required String currentName,
    required List<Vst3Plugin> availablePlugins,
  }) {
    final colors = context.themeProvider.colors;

    final vst3Instruments = availablePlugins
        .where((p) => p.isInstrument)
        .toList();
    final vst3Effects = availablePlugins.where((p) => p.isEffect).toList();
    final vst3List = isInstrument ? vst3Instruments : vst3Effects;

    final items = <BoojyMenuEntry<DeviceAction>>[
      BoojyMenuItem(
        value: const DeviceAction.reset(),
        icon: BI.refresh,
        label: 'Reset to Default',
      ),
      const BoojyMenuDivider(),
      const BoojyMenuSection(label: 'Built-in'),
      if (isInstrument) ...[
        BoojyMenuItem(
          value: const DeviceAction.swap('synthesizer'),
          icon: BI.piano,
          label: 'Synthesizer',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('sampler'),
          icon: BI.waveform,
          label: 'Sampler',
        ),
        BoojyMenuItem(
          value: const DeviceAction.swap('drum_kit'),
          icon: BI.gridOn,
          label: 'Drum Kit',
        ),
      ] else ...[
        for (final e in builtinEffects)
          BoojyMenuItem(
            value: DeviceAction.swap(e.type),
            icon: e.icon,
            label: e.name,
          ),
      ],
      if (vst3List.isNotEmpty) ...[
        const BoojyMenuSection(label: 'Plugins'),
        for (final p in vst3List)
          BoojyMenuItem(
            value: DeviceAction.swap('vst3:${p.path}'),
            icon: BI.plugin,
            label: p.name,
          ),
      ],
      // Delete only makes sense for effects — instruments are never removed.
      if (!isInstrument) ...[
        const BoojyMenuDivider(),
        BoojyMenuItem(
          value: const DeviceAction.delete(),
          icon: BI.delete,
          label: 'Delete',
          destructive: true,
        ),
      ],
    ];

    // Count actionable rows (not dividers/sections) to decide if search helps.
    final totalItems = items.whereType<BoojyMenuItem<DeviceAction>>().length;

    return showBoojyMenu<DeviceAction>(
      context: context,
      anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
      items: items,
      selectedValue: null,
      colors: colors,
      showSearch: totalItems > _searchThreshold,
    );
  }
}

/// Actions returned by the device picker.
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
