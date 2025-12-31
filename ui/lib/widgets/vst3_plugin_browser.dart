import 'package:flutter/material.dart';
import '../models/vst3_plugin_data.dart';
import '../theme/theme_extension.dart';

/// Shows VST3 plugin browser dialog and returns selected plugin
Future<Vst3Plugin?> showVst3PluginBrowser(
  BuildContext context, {
  required List<Map<String, String>> availablePlugins,
  required bool isScanning,
  VoidCallback? onRescanRequested,
}) {
  return showDialog<Vst3Plugin>(
    context: context,
    builder: (context) => Vst3PluginBrowserDialog(
      availablePlugins: availablePlugins,
      isScanning: isScanning,
      onRescanRequested: onRescanRequested,
    ),
  );
}

/// VST3 plugin browser dialog widget
class Vst3PluginBrowserDialog extends StatefulWidget {
  final List<Map<String, String>> availablePlugins;
  final bool isScanning;
  final VoidCallback? onRescanRequested;

  const Vst3PluginBrowserDialog({
    super.key,
    required this.availablePlugins,
    required this.isScanning,
    this.onRescanRequested,
  });

  @override
  State<Vst3PluginBrowserDialog> createState() => _Vst3PluginBrowserDialogState();
}

class _Vst3PluginBrowserDialogState extends State<Vst3PluginBrowserDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // Filter plugins based on search query
    final filteredPlugins = widget.availablePlugins.where((plugin) {
      if (_searchQuery.isEmpty) return true;

      final name = plugin['name']?.toLowerCase() ?? '';
      final vendor = plugin['vendor']?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      return name.contains(query) || vendor.contains(query);
    }).toList();

    return Dialog(
      backgroundColor: context.colors.surface,
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.extension,
                  color: context.colors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'VST3 Plugin Browser',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Rescan button
                if (widget.onRescanRequested != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: context.colors.textSecondary,
                    onPressed: widget.isScanning ? null : () {
                      widget.onRescanRequested?.call();
                    },
                    tooltip: 'Rescan plugins',
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: context.colors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Search bar
            TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search plugins...',
                hintStyle: TextStyle(color: context.colors.textMuted),
                prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
                filled: true,
                fillColor: context.colors.hover,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: TextStyle(color: context.colors.textSecondary),
            ),

            const SizedBox(height: 16),

            // Plugins list
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.hover,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.isScanning
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: context.colors.success,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Scanning for VST3 plugins...',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : filteredPlugins.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.extension_off,
                                  color: context.colors.textMuted,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.availablePlugins.isEmpty
                                      ? 'No VST3 plugins found'
                                      : 'No plugins match your search',
                                  style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                                if (widget.availablePlugins.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Install VST3 plugins to /Library/Audio/Plug-Ins/VST3/',
                                    style: TextStyle(
                                      color: context.colors.textMuted,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredPlugins.length,
                            itemBuilder: (context, index) {
                              final pluginData = filteredPlugins[index];
                              final plugin = Vst3Plugin.fromMap(pluginData);
                              return _buildPluginTile(plugin);
                            },
                          ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer info
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Double-click a plugin to add it to the current track',
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginTile(Vst3Plugin plugin) {
    return Draggable<Vst3Plugin>(
      data: plugin,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.colors.success,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension,
                color: context.colors.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  plugin.name,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildPluginTileContent(plugin),
      ),
      child: InkWell(
        onTap: () {
          // Single click - preview or select
        },
        onDoubleTap: () {
          // Double click - choose and close
          Navigator.of(context).pop(plugin);
        },
        child: _buildPluginTileContent(plugin),
      ),
    );
  }

  Widget _buildPluginTileContent(Vst3Plugin plugin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.divider,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Plugin icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.success.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              plugin.isInstrument ? Icons.piano : Icons.graphic_eq,
              color: context.colors.success,
              size: 24,
            ),
          ),

          const SizedBox(width: 16),

          // Plugin info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.name,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  plugin.vendor ?? 'Unknown Vendor',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: plugin.isInstrument
                  ? context.colors.accent.withValues(alpha: 0.2)
                  : context.colors.warning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              plugin.isInstrument ? 'Instrument' : 'Effect',
              style: TextStyle(
                color: plugin.isInstrument
                    ? context.colors.accent
                    : context.colors.warning,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Arrow icon
          Icon(
            Icons.chevron_right,
            color: context.colors.textMuted,
            size: 20,
          ),
        ],
      ),
    );
  }
}
