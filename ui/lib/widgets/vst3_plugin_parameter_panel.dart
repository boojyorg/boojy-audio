import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../audio_engine.dart';
import '../models/vst3_plugin_data.dart';
import '../services/plugin_preferences_service.dart';
import '../services/vst3_editor_service.dart';
import 'vst3_editor_widget.dart';

/// VST3 Plugin Parameter Panel - shows parameters for loaded plugins on a track
class Vst3PluginParameterPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final int trackId;
  final List<Vst3PluginInstance> plugins;
  final Function(int effectId, int paramIndex, double value)? onParameterChanged;
  final Function(int effectId)? onRemovePlugin;

  const Vst3PluginParameterPanel({
    super.key,
    this.audioEngine,
    required this.trackId,
    required this.plugins,
    this.onParameterChanged,
    this.onRemovePlugin,
  });

  @override
  State<Vst3PluginParameterPanel> createState() => _Vst3PluginParameterPanelState();
}

class _Vst3PluginParameterPanelState extends State<Vst3PluginParameterPanel> {
  int? _expandedPluginId;
  String _searchQuery = '';
  final Map<String, bool> _expandedSections = {}; // Section name -> expanded state
  int? _showEmbeddedGUIForEffect; // Effect ID showing embedded native GUI

  // Track which plugins we've already auto-opened to avoid repeated opens
  final Set<int> _autoOpenedPlugins = {};

  @override
  void didUpdateWidget(covariant Vst3PluginParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if track changed or new plugins were added
    if (widget.trackId != oldWidget.trackId) {
      // Track changed - reset auto-opened set and check all plugins
      _autoOpenedPlugins.clear();
      _checkAutoOpenPlugins();
    } else {
      // Same track - check for newly added plugins
      final oldEffectIds = oldWidget.plugins.map((p) => p.effectId).toSet();
      final newPlugins = widget.plugins.where((p) => !oldEffectIds.contains(p.effectId));
      for (final plugin in newPlugins) {
        _checkAutoOpenPlugin(plugin);
      }
    }
  }

  /// Check all plugins for auto-open preference
  void _checkAutoOpenPlugins() {
    for (final plugin in widget.plugins) {
      _checkAutoOpenPlugin(plugin);
    }
  }

  /// Check if a plugin should auto-open in floating mode
  void _checkAutoOpenPlugin(Vst3PluginInstance plugin) {
    // Skip if already auto-opened
    if (_autoOpenedPlugins.contains(plugin.effectId)) return;

    // Mark as processed
    _autoOpenedPlugins.add(plugin.effectId);

    // Check preference
    if (PluginPreferencesService.prefersFloating(plugin.pluginName)) {
      debugPrint('🔄 Auto-opening ${plugin.pluginName} in floating mode (user preference)');
      // Delay slightly to ensure widget is fully built
      Future.microtask(() => _openPluginGUI(plugin));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.plugins.isEmpty) {
      return Container(
        color: const Color(0xFF707070),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.extension_off,
                size: 64,
                color: Color(0xFF909090),
              ),
              const SizedBox(height: 16),
              const Text(
                'No VST3 Plugins',
                style: TextStyle(
                  color: Color(0xFF202020),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Click the FX button on the track to add plugins',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check if any plugin is showing embedded GUI
    final showingEmbeddedGUI = _showEmbeddedGUIForEffect != null;

    return Container(
      color: const Color(0xFF707070),
      child: Column(
        children: [
          // Search bar - hide when embedded GUI is shown (not useful for native GUI)
          if (!showingEmbeddedGUI)
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF656565),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search parameters...',
                  hintStyle: const TextStyle(color: Color(0xFF808080)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF808080), size: 18),
                  filled: true,
                  fillColor: const Color(0xFF505050),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 12),
              ),
            ),

          // Plugin list
          Expanded(
            child: ListView.builder(
              itemCount: widget.plugins.length,
              itemBuilder: (context, index) {
                final plugin = widget.plugins[index];
                final isExpanded = _expandedPluginId == plugin.effectId;
                return _buildPluginItem(plugin, isExpanded);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginItem(Vst3PluginInstance plugin, bool isExpanded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plugin header (click to expand/collapse)
        InkWell(
          onTap: () {
            setState(() {
              _expandedPluginId = isExpanded ? null : plugin.effectId;
              _expandedSections.clear(); // Reset section expansions
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isExpanded ? const Color(0xFF505050) : const Color(0xFF606060),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF808080), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  color: const Color(0xFFA0A0A0),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.extension,
                  color: Color(0xFF4CAF50),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.pluginName,
                        style: const TextStyle(
                          color: Color(0xFFA0A0A0),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Show different subtitle based on current view mode
                      Text(
                        _showEmbeddedGUIForEffect == plugin.effectId
                            ? 'Native GUI'
                            : '${plugin.parameters.length} parameters',
                        style: const TextStyle(
                          color: Color(0xFF808080),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Embed GUI button (toggle)
                IconButton(
                  icon: Icon(
                    _showEmbeddedGUIForEffect == plugin.effectId
                        ? Icons.tune
                        : Icons.display_settings,
                  ),
                  color: _showEmbeddedGUIForEffect == plugin.effectId
                      ? const Color(0xFF2196F3)
                      : const Color(0xFF4CAF50),
                  iconSize: 18,
                  onPressed: () => _toggleEmbeddedGUI(plugin),
                  tooltip: _showEmbeddedGUIForEffect == plugin.effectId
                      ? 'Show Parameters'
                      : 'Show Plugin GUI (Embedded)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 4),
                // Open floating GUI button
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  color: const Color(0xFF4CAF50),
                  iconSize: 18,
                  onPressed: () => _openPluginGUI(plugin),
                  tooltip: 'Open Plugin GUI (Floating Window)',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 4),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFFFF5722),
                  iconSize: 18,
                  onPressed: () => widget.onRemovePlugin?.call(plugin.effectId),
                  tooltip: 'Remove Plugin',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),

        // Content (shown when expanded) - either embedded GUI or parameters
        if (isExpanded)
          _showEmbeddedGUIForEffect == plugin.effectId
              ? _buildEmbeddedGUI(plugin)
              : _buildParameterList(plugin),
      ],
    );
  }

  Widget _buildEmbeddedGUI(Vst3PluginInstance plugin) {
    return Container(
      color: const Color(0xFF303030),
      constraints: const BoxConstraints(
        minHeight: 400,
        maxHeight: 600,
      ),
      child: VST3EditorWidget(
        effectId: plugin.effectId,
        pluginName: plugin.pluginName,
        width: double.infinity,
        height: 500,
      ),
    );
  }

  Widget _buildParameterList(Vst3PluginInstance plugin) {
    final filteredParams = plugin.filterParameters(_searchQuery);

    if (filteredParams.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF505050),
        child: Center(
          child: Text(
            _searchQuery.isEmpty
                ? 'No parameters available'
                : 'No parameters match "$_searchQuery"',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // Group parameters by prefix
    final grouped = plugin.groupParameters();

    // Filter groups to only include those with matching parameters
    final filteredGroups = <String, List<Vst3ParameterInfo>>{};
    for (final entry in grouped.entries) {
      final matchingParams = entry.value
          .where((p) => filteredParams.contains(p))
          .toList();
      if (matchingParams.isNotEmpty) {
        filteredGroups[entry.key] = matchingParams;
      }
    }

    return Container(
      color: const Color(0xFF505050),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Render each group
          for (final entry in filteredGroups.entries)
            _buildParameterGroup(plugin, entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _buildParameterGroup(
    Vst3PluginInstance plugin,
    String groupName,
    List<Vst3ParameterInfo> parameters,
  ) {
    final isExpanded = _expandedSections[groupName] ?? true; // Default: expanded

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header
        InkWell(
          onTap: () {
            setState(() {
              _expandedSections[groupName] = !isExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF454545),
              border: Border(
                bottom: BorderSide(color: Color(0xFF606060), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  color: const Color(0xFF909090),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  groupName,
                  style: const TextStyle(
                    color: Color(0xFF909090),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${parameters.length}',
                  style: const TextStyle(
                    color: Color(0xFF707070),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Parameters in this group
        if (isExpanded)
          for (final param in parameters)
            _buildParameterControl(plugin, param),
      ],
    );
  }

  Widget _buildParameterControl(
    Vst3PluginInstance plugin,
    Vst3ParameterInfo param,
  ) {
    final value = plugin.getParameterValue(param.index) ?? param.defaultValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF606060), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Parameter name
          Expanded(
            flex: 2,
            child: Text(
              param.name,
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 11,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Slider
          Expanded(
            flex: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
                activeTrackColor: const Color(0xFF4CAF50),
                inactiveTrackColor: const Color(0xFF606060),
                thumbColor: const Color(0xFF4CAF50),
              ),
              child: Slider(
                value: value.clamp(param.min, param.max),
                min: param.min,
                max: param.max,
                onChanged: (newValue) {
                  setState(() {
                    plugin.setParameterValue(param.index, newValue);
                  });
                  widget.onParameterChanged?.call(
                    plugin.effectId,
                    param.index,
                    newValue,
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Value display (clickable to edit)
          GestureDetector(
            onTap: () => _showValueEditDialog(plugin, param, value),
            child: Container(
              width: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF404040),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF606060)),
              ),
              child: Text(
                '${value.toStringAsFixed(2)}${param.unit}',
                style: const TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showValueEditDialog(
    Vst3PluginInstance plugin,
    Vst3ParameterInfo param,
    double currentValue,
  ) {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF656565),
        title: Text(
          param.name,
          style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Range: ${param.min.toStringAsFixed(2)} - ${param.max.toStringAsFixed(2)} ${param.unit}',
              style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                hintText: 'Enter value',
                hintStyle: const TextStyle(color: Color(0xFF808080)),
                filled: true,
                fillColor: const Color(0xFF505050),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Color(0xFFA0A0A0)),
              onSubmitted: (text) {
                final newValue = double.tryParse(text);
                if (newValue != null) {
                  final clampedValue = newValue.clamp(param.min, param.max);
                  setState(() {
                    plugin.setParameterValue(param.index, clampedValue);
                  });
                  widget.onParameterChanged?.call(
                    plugin.effectId,
                    param.index,
                    clampedValue,
                  );
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF808080))),
          ),
          TextButton(
            onPressed: () {
              final newValue = double.tryParse(controller.text);
              if (newValue != null) {
                final clampedValue = newValue.clamp(param.min, param.max);
                setState(() {
                  plugin.setParameterValue(param.index, clampedValue);
                });
                widget.onParameterChanged?.call(
                  plugin.effectId,
                  param.index,
                  clampedValue,
                );
              }
              Navigator.of(context).pop();
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF4CAF50))),
          ),
        ],
      ),
    );
  }

  // Flag to prevent rapid toggle that can cause crashes
  bool _isTogglingGUI = false;

  // Toggle embedded GUI visibility
  void _toggleEmbeddedGUI(Vst3PluginInstance plugin) async {
    // Prevent rapid toggling which can cause race conditions
    if (_isTogglingGUI) {
      debugPrint('⚠️ _toggleEmbeddedGUI: Already toggling, ignoring request');
      return;
    }
    _isTogglingGUI = true;

    debugPrint('🔘 _toggleEmbeddedGUI called for ${plugin.pluginName}, current state: $_showEmbeddedGUIForEffect');

    try {
      if (_showEmbeddedGUIForEffect == plugin.effectId) {
        // Hide embedded GUI - detach editor first
        debugPrint('📺 Hiding embedded GUI for ${plugin.pluginName} - calling detachEditor...');
        await VST3EditorService.detachEditor(effectId: plugin.effectId);
        debugPrint('📺 detachEditor completed for ${plugin.pluginName}');
        setState(() {
          _showEmbeddedGUIForEffect = null;
        });
        debugPrint('📺 setState completed - GUI hidden');

        // Give Flutter time to fully dispose the old platform view
        // This prevents crashes when the new view is created before cleanup completes
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('📺 Cleanup delay completed');
      } else {
        // Show embedded GUI - the platform view will be created by setState
        // and Swift will notify when ready for attachment
        debugPrint('📺 Showing embedded GUI for ${plugin.pluginName}');

        // Save preference for embedded mode
        debugPrint('📺 Saving display mode preference...');
        await PluginPreferencesService.setDisplayMode(
          plugin.pluginName,
          PluginDisplayMode.embedded,
        );
        debugPrint('📺 Display mode saved, calling setState...');

        setState(() {
          _showEmbeddedGUIForEffect = plugin.effectId;
          _expandedPluginId = plugin.effectId;
        });
        debugPrint('📺 setState completed - GUI should be showing');
        // Note: Attachment happens via the platform view lifecycle:
        // 1. VST3EditorWidget creates AppKitView
        // 2. Swift's VST3EditorView.viewDidMoveToWindow() fires
        // 3. Swift sends "viewReady" notification
        // 4. Dart's _handleViewReady calls attachEditor
      }
    } finally {
      _isTogglingGUI = false;
    }
  }

  // M7 Phase 3: Open native VST3 plugin GUI
  void _openPluginGUI(Vst3PluginInstance plugin) async {
    debugPrint('📺 Opening native GUI for ${plugin.pluginName} (effect ${plugin.effectId})');

    // Save preference for floating mode
    await PluginPreferencesService.setDisplayMode(
      plugin.pluginName,
      PluginDisplayMode.floating,
    );

    // Default VST3 editor size (will be updated with actual size from plugin)
    const defaultWidth = 800.0;
    const defaultHeight = 600.0;

    final success = await VST3EditorService.openFloatingWindow(
      effectId: plugin.effectId,
      pluginName: plugin.pluginName,
      width: defaultWidth,
      height: defaultHeight,
    );

    if (success) {
      debugPrint('✅ Successfully opened GUI for ${plugin.pluginName}');
    } else {
      debugPrint('❌ Failed to open GUI for ${plugin.pluginName}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open GUI for ${plugin.pluginName}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
