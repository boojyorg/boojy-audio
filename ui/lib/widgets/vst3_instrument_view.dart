import 'dart:math' show min;
import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../services/vst3_editor_service.dart';
import '../theme/animation_constants.dart';
import '../theme/boojy_icons.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import 'vst3_editor_widget.dart';

/// Simplified VST3 instrument view for the editor panel's instrument tab.
/// Shows the native plugin GUI directly — no search bar, no parameter list,
/// no plugin header. Replaces Vst3PluginParameterPanel for instrument display.
class Vst3InstrumentView extends StatefulWidget {
  final int effectId;
  final String pluginName;
  final AudioEngine? audioEngine;
  final bool isFloated;
  final VoidCallback? onRescanPlugins;
  final VoidCallback? onFloat;
  final void Function(VoidCallback resetFn)? onResetRegistered;

  const Vst3InstrumentView({
    super.key,
    required this.effectId,
    required this.pluginName,
    this.audioEngine,
    this.isFloated = false,
    this.onRescanPlugins,
    this.onFloat,
    this.onResetRegistered,
  });

  @override
  State<Vst3InstrumentView> createState() => _Vst3InstrumentViewState();
}

class _Vst3InstrumentViewState extends State<Vst3InstrumentView>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  bool _hasError = false;

  /// Default state captured on first load, used for "Reset to Default"
  String? _defaultStateBase64;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initEditor();
    _captureDefaultState();
  }

  @override
  void didUpdateWidget(covariant Vst3InstrumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.effectId != oldWidget.effectId) {
      _initEditor();
      _captureDefaultState();
    }
  }

  void _initEditor() {
    // Check if plugin has an editor GUI
    final hasEditor =
        widget.audioEngine?.vst3HasEditor(widget.effectId) ?? false;
    setState(() {
      _hasError = !hasEditor;
      // If the plugin has an editor, show loading briefly while platform view
      // initializes. The platform view lifecycle handles the actual attachment.
      _isLoading = hasEditor;
    });

    if (hasEditor) {
      // Give the platform view time to initialize
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
      // After attachment completes (~1s), rebuild to get real editor size
      // for correct width capping (vst3GetEditorSize returns 0 before open)
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() {});
      });
    }
  }

  /// Capture the plugin's state immediately after load for "Reset to Default"
  void _captureDefaultState() {
    if (widget.audioEngine == null) return;
    final state = widget.audioEngine!.getVst3State(widget.effectId);
    if (state.isNotEmpty && !state.startsWith('Error')) {
      _defaultStateBase64 = state;
    }
    // Register the reset callback with the parent
    widget.onResetRegistered?.call(resetToDefault);
  }

  /// Reset plugin to its initial loaded state
  void resetToDefault() {
    if (_defaultStateBase64 == null || widget.audioEngine == null) return;
    widget.audioEngine!.setVst3State(widget.effectId, _defaultStateBase64!);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final colors = context.colors;

    return AnimatedSwitcher(
      duration: AnimationConstants.panelDuration,
      child: widget.isFloated
          ? _buildFloatedPlaceholder(colors)
          : _hasError
          ? _buildErrorState(colors)
          : _isLoading
          ? _buildLoadingState(colors)
          : _buildEditorView(colors),
    );
  }

  /// Plugin is in a floating window — show placeholder in panel
  Widget _buildFloatedPlaceholder(BoojyColors colors) {
    return ColoredBox(
      key: const ValueKey('floated'),
      color: colors.darkest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(BI.openInNew, size: 48, color: colors.textMuted),
            const SizedBox(height: BT.lg),
            Text(
              '${widget.pluginName} is in a floating window',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: BT.fontBody,
                fontWeight: BT.weightMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Plugin GUI is loading
  Widget _buildLoadingState(BoojyColors colors) {
    return ColoredBox(
      key: const ValueKey('loading'),
      color: colors.darkest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: BT.lg),
            Text(
              'Loading ${widget.pluginName}...',
              style: TextStyle(color: colors.textMuted, fontSize: BT.fontBody),
            ),
          ],
        ),
      ),
    );
  }

  /// Plugin failed to load
  Widget _buildErrorState(BoojyColors colors) {
    return ColoredBox(
      key: const ValueKey('error'),
      color: colors.darkest,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(BI.error, size: 48, color: colors.textMuted),
            const SizedBox(height: BT.lg),
            Text(
              'Failed to load ${widget.pluginName}',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: BT.fontBody,
                fontWeight: BT.weightMedium,
              ),
            ),
            const SizedBox(height: BT.xs),
            Text(
              'The plugin may be missing or incompatible.',
              style: TextStyle(color: colors.textMuted, fontSize: BT.fontLabel),
            ),
            if (widget.onRescanPlugins != null) ...[
              const SizedBox(height: BT.xl),
              TextButton.icon(
                onPressed: widget.onRescanPlugins,
                icon: Icon(BI.refresh, size: 16, color: colors.accent),
                label: Text(
                  'Rescan Plugins',
                  style: TextStyle(
                    color: colors.accent,
                    fontSize: BT.fontLabel,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Native plugin GUI embedded in panel.
  ///
  /// Uses scale-to-fit: the plugin is uniformly scaled down to fit entirely
  /// within the available space, preserving aspect ratio. Dark letterbox bars
  /// appear if aspect ratios differ. When the panel is large enough, the
  /// plugin displays at its native 1:1 size.
  /// Minimum panel height to show the plugin. Below this, show a placeholder.
  static const double _minHeightForPlugin = 250;

  Widget _buildEditorView(BoojyColors colors) {
    return LayoutBuilder(
      key: const ValueKey('editor'),
      builder: (context, constraints) {
        // Below minimum height: show placeholder instead of plugin
        if (constraints.maxHeight < _minHeightForPlugin) {
          return _buildTooSmallPlaceholder(colors);
        }

        // Get preferred size (stored after first attachment)
        final preferred =
            VST3EditorService.preferredEditorSize[widget.effectId];
        final nativeW = preferred?.$1.toDouble() ?? 0;
        final nativeH = preferred?.$2.toDouble() ?? 0;

        double width;
        double height;

        if (nativeW > 0 && nativeH > 0) {
          // Uniform scale: both axes use the SAME scale factor
          final scale = min(
            constraints.maxWidth / nativeW,
            min(constraints.maxHeight / nativeH, 1.0),
          );
          width = nativeW * scale;
          height = nativeH * scale;
        } else {
          // Before attachment, use full available space
          width = constraints.maxWidth;
          height = constraints.maxHeight;
        }

        // Register max embedded size so PlugFrame knows we're in embedded mode
        VST3EditorService.setEmbeddedMaxSize(
          widget.effectId,
          width.round(),
          height.round(),
        );

        return ColoredBox(
          color: colors.darkest,
          child: Center(
            child: VST3EditorWidget(
              effectId: widget.effectId,
              pluginName: widget.pluginName,
              width: width,
              height: height,
            ),
          ),
        );
      },
    );
  }

  /// Shown when the editor panel is too small to display the plugin.
  Widget _buildTooSmallPlaceholder(BoojyColors colors) {
    return ColoredBox(
      color: colors.dark,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Press Float to open ${widget.pluginName}',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: BT.lg),
            if (widget.onFloat != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onFloat,
                  borderRadius: BorderRadius.circular(BT.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(BT.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          BI.openInNew,
                          size: 16,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Float',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: BT.lg),
            Text(
              'Or increase editor panel height',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
