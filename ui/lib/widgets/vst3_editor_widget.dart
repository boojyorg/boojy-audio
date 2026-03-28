import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/tokens.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Widget that embeds a VST3 plugin editor GUI
/// Uses platform views to show the native plugin editor.
///
/// For embedded mode: pass [width]/[height] as the available panel space
/// and [nativeWidth]/[nativeHeight] as the plugin's preferred size.
/// The widget calculates a scale-to-fit factor and passes both frame
/// and bounds dimensions to the Swift platform view for Cocoa scaling.
class VST3EditorWidget extends StatefulWidget {
  final int effectId;
  final String pluginName;
  final double width;
  final double height;

  /// Plugin's native/preferred GUI size. If null, no scaling is applied.
  final double? nativeWidth;
  final double? nativeHeight;

  const VST3EditorWidget({
    super.key,
    required this.effectId,
    required this.pluginName,
    required this.width,
    required this.height,
    this.nativeWidth,
    this.nativeHeight,
  });

  @override
  State<VST3EditorWidget> createState() => _VST3EditorWidgetState();
}

class _VST3EditorWidgetState extends State<VST3EditorWidget> {
  // Unique instance counter to force new platform view on each mount
  static int _instanceCounter = 0;
  late final int _instanceId;

  @override
  void initState() {
    super.initState();
    _instanceId = ++_instanceCounter;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return _buildMacOSView();
    } else {
      return _buildUnsupportedPlatform();
    }
  }

  Widget _buildMacOSView() {
    final uniqueKey = ValueKey('vst3_editor_${widget.effectId}_$_instanceId');

    // Pass available size directly — the plugin handles its own layout
    // via IPlugView::onSize() called by PlugFrame during attachment.
    final frameW = widget.width.round();
    final frameH = widget.height.round();

    final view = AppKitView(
      key: uniqueKey,
      viewType: 'boojy_audio.vst3.editor_view',
      creationParams: {
        'effectId': widget.effectId,
        'width': frameW,
        'height': frameH,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {},
    );

    return SizedBox(
      width: frameW.toDouble(),
      height: frameH.toDouble(),
      child: view,
    );
  }

  Widget _buildUnsupportedPlatform() {
    final isWindows = Platform.isWindows;
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF202020),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWindows ? BI.monitor : BI.error,
              color: isWindows ? Colors.orange : Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              widget.pluginName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: BT.weightSemiBold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isWindows
                  ? 'Plugin UI not yet available on Windows.\nUse the parameter sliders below.'
                  : 'VST3 editors not supported on ${Platform.operatingSystem}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
