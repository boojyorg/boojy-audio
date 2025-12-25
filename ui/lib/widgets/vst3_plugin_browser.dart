import 'package:flutter/material.dart';
import '../models/vst3_plugin_data.dart';

/// Shows VST3 plugin browser dialog and returns selected plugin
Future<Vst3Plugin?> showVst3PluginBrowser(
  BuildContext context, {
  required List<Map<String, String>> availablePlugins,
  required bool isScanning,
  VoidCallback? onRescanRequested,
}) async {
  return await showDialog<Vst3Plugin>(
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
      backgroundColor: const Color(0xFF656565),
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
                const Icon(
                  Icons.extension,
                  color: Color(0xFFA0A0A0),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'VST3 Plugin Browser',
                  style: TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Rescan button
                if (widget.onRescanRequested != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: const Color(0xFFA0A0A0),
                    onPressed: widget.isScanning ? null : () {
                      widget.onRescanRequested?.call();
                    },
                    tooltip: 'Rescan plugins',
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: const Color(0xFFA0A0A0),
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
                hintStyle: const TextStyle(color: Color(0xFF808080)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF808080)),
                filled: true,
                fillColor: const Color(0xFF505050),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Color(0xFFA0A0A0)),
            ),

            const SizedBox(height: 16),

            // Plugins list
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF505050),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: widget.isScanning
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Color(0xFF4CAF50),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Scanning for VST3 plugins...',
                              style: TextStyle(
                                color: Color(0xFFA0A0A0),
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
                                  color: Colors.grey[600],
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  widget.availablePlugins.isEmpty
                                      ? 'No VST3 plugins found'
                                      : 'No plugins match your search',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                if (widget.availablePlugins.isEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Install VST3 plugins to /Library/Audio/Plug-Ins/VST3/',
                                    style: TextStyle(
                                      color: Colors.grey[700],
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
                      color: Colors.grey[600],
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
            color: const Color(0xFF4CAF50),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.extension,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  plugin.name,
                  style: const TextStyle(
                    color: Colors.white,
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
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF606060),
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
              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              plugin.isInstrument ? Icons.piano : Icons.graphic_eq,
              color: const Color(0xFF4CAF50),
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
                  style: const TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  plugin.vendor ?? 'Unknown Vendor',
                  style: const TextStyle(
                    color: Color(0xFF808080),
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
                  ? const Color(0xFF2196F3).withValues(alpha: 0.2)
                  : const Color(0xFFFF9800).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              plugin.isInstrument ? 'Instrument' : 'Effect',
              style: TextStyle(
                color: plugin.isInstrument
                    ? const Color(0xFF2196F3)
                    : const Color(0xFFFF9800),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Arrow icon
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF808080),
            size: 20,
          ),
        ],
      ),
    );
  }
}
