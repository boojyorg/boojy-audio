import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Widget that embeds a VST3 plugin editor GUI
/// Uses platform views to show the native plugin editor
class VST3EditorWidget extends StatefulWidget {
  final int effectId;
  final String pluginName;
  final double width;
  final double height;

  const VST3EditorWidget({
    super.key,
    required this.effectId,
    required this.pluginName,
    required this.width,
    required this.height,
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
    debugPrint('🔧 VST3EditorWidget: initState for effect ${widget.effectId}, instance $_instanceId');
  }

  @override
  void dispose() {
    debugPrint('🔧 VST3EditorWidget: dispose for effect ${widget.effectId}, instance $_instanceId');
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
    // Use a unique key that combines effectId and instanceId to force
    // Flutter to create a completely new platform view on each show/hide cycle.
    // Without this, Flutter may reuse the cached platform view which causes
    // the freeze on second toggle because viewDidMoveToWindow doesn't fire.
    final uniqueKey = ValueKey('vst3_editor_${widget.effectId}_$_instanceId');
    debugPrint('🔧 VST3EditorWidget: Building with key $uniqueKey');

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AppKitView(
        key: uniqueKey,
        viewType: 'boojy_audio.vst3.editor_view',
        creationParams: {
          'effectId': widget.effectId,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          debugPrint('✅ VST3EditorWidget: Platform view created for effect ${widget.effectId}, instance $_instanceId, platformViewId $id');
        },
      ),
    );
  }

  Widget _buildUnsupportedPlatform() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF202020),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'VST3 editors not supported on ${Platform.operatingSystem}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
