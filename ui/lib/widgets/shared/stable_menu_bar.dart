import 'package:flutter/widgets.dart';

/// A [PlatformMenuBar] that only resends the menus to the OS when something
/// you can see changes: a label (including its ✓), a shortcut, or whether an
/// item is enabled.
///
/// Why: menu items have no `==`, so a plain [PlatformMenuBar] resends every
/// menu on every rebuild of the screen that owns it, and macOS closes any menu
/// that is open when that happens (a menu opened during playback, or while the
/// MIDI poll ticked, flickered shut). Here the items handed to the OS are
/// stable proxies; clicking one runs the callback from the most recent build,
/// so nothing goes stale while the proxies are reused.
class StableMenuBar extends StatefulWidget {
  final List<PlatformMenuItem> menus;
  final Widget child;

  const StableMenuBar({super.key, required this.menus, required this.child});

  @override
  State<StableMenuBar> createState() => _StableMenuBarState();
}

class _StableMenuBarState extends State<StableMenuBar> {
  String? _signature;
  List<PlatformMenuItem> _proxies = const [];

  /// Latest callback per item path ("2/5" = 6th item of the 3rd menu).
  final Map<String, VoidCallback?> _actions = {};

  @override
  Widget build(BuildContext context) {
    final signature = StringBuffer();
    _actions.clear();
    _describe(widget.menus, '', signature);
    final sig = signature.toString();
    if (sig != _signature) {
      _signature = sig;
      _proxies = _proxy(widget.menus, '');
    }
    return PlatformMenuBar(menus: _proxies, child: widget.child);
  }

  /// Records every item's visible state into [out] and its current callback
  /// into [_actions].
  void _describe(List<PlatformMenuItem> items, String path, StringBuffer out) {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final p = '$path/$i';
      switch (item) {
        case PlatformMenu():
          out.write('[M$p:${item.label}');
          _describe(item.menus, p, out);
          out.write(']');
        case PlatformMenuItemGroup():
          out.write('[G$p');
          _describe(item.members, p, out);
          out.write(']');
        case PlatformProvidedMenuItem():
          out.write('[P$p:${item.type.name}:${item.enabled}]');
        default:
          _actions[p] = item.onSelected;
          out.write(
            '[I$p:${item.label}:${item.onSelected != null}:'
            '${item.shortcut?.serializeForMenu().toChannelRepresentation()}]',
          );
      }
    }
  }

  List<PlatformMenuItem> _proxy(List<PlatformMenuItem> items, String path) {
    return [
      for (var i = 0; i < items.length; i++)
        switch (items[i]) {
          final PlatformMenu m => PlatformMenu(
            label: m.label,
            onOpen: m.onOpen,
            onClose: m.onClose,
            menus: _proxy(m.menus, '$path/$i'),
          ),
          final PlatformMenuItemGroup g => PlatformMenuItemGroup(
            members: _proxy(g.members, '$path/$i'),
          ),
          final PlatformProvidedMenuItem provided => provided,
          final item => PlatformMenuItem(
            label: item.label,
            shortcut: item.shortcut,
            onSelected: item.onSelected == null
                ? null
                : () => _actions['$path/$i']?.call(),
          ),
        },
    ];
  }
}
