import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';

/// Service for managing VST3 plugin editor windows
/// Communicates with native platform code to show/hide editor GUIs
class VST3EditorService {
  static const _channel = MethodChannel('boojy_audio.vst3.editor');
  static const _nativeChannel = MethodChannel('boojy_audio.vst3.editor.native');

  static AudioEngine? _audioEngine;
  static bool _initialized = false;

  /// Initialize the service with an AudioEngine instance
  /// This must be called before the service can handle view attachments
  static void initialize(AudioEngine engine) {
    if (_initialized) return;
    _audioEngine = engine;
    _initialized = true;

    // Listen for Swift -> Dart notifications
    _nativeChannel.setMethodCallHandler(_handleNativeCall);

    debugPrint('✅ VST3EditorService: Initialized with AudioEngine');
  }

  /// Handle method calls from Swift (view ready, view closed, etc.)
  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    debugPrint('📥 VST3EditorService: Received ${call.method} from Swift');

    switch (call.method) {
      case 'viewReady':
        return _handleViewReady(call.arguments);
      case 'viewClosed':
        return _handleViewClosed(call.arguments);
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Handle view ready notification from Swift
  /// Swift sends effectId and viewPointer, we call FFI to attach
  static Future<void> _handleViewReady(dynamic args) async {
    final effectId = args['effectId'] as int?;
    final viewPointer = args['viewPointer'] as int?;

    if (effectId == null || viewPointer == null) {
      debugPrint('❌ VST3EditorService: Invalid viewReady args: $args');
      return;
    }

    debugPrint('🔔 VST3EditorService: View ready for effect $effectId, ptr=$viewPointer');

    if (_audioEngine == null) {
      debugPrint('❌ VST3EditorService: AudioEngine not initialized');
      return;
    }

    try {
      // First, open the editor (creates IPlugView)
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Open editor error: $openResult');
        return;
      }
      debugPrint('✅ VST3EditorService: Editor opened for effect $effectId');

      // Get editor size (returns Map<String, int>? with 'width' and 'height')
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      int width = sizeResult?['width'] ?? 800;
      int height = sizeResult?['height'] ?? 600;
      debugPrint('📏 VST3EditorService: Editor size ${width}x$height');

      // Attach editor to the NSView
      final viewPtr = ffi.Pointer<ffi.Void>.fromAddress(viewPointer);
      final attachResult = _audioEngine!.vst3AttachEditor(effectId, viewPtr);
      if (attachResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Attach editor error: $attachResult');
        return;
      }
      debugPrint('✅ VST3EditorService: Editor attached for effect $effectId');

      // Confirm attachment back to Swift
      await _channel.invokeMethod('confirmAttachment', {
        'effectId': effectId,
        'width': width,
        'height': height,
      });
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to handle viewReady: $e');
    }
  }

  /// Handle view closed notification from Swift
  static Future<void> _handleViewClosed(dynamic args) async {
    final effectId = args['effectId'] as int?;

    if (effectId == null) {
      debugPrint('❌ VST3EditorService: Invalid viewClosed args: $args');
      return;
    }

    debugPrint('📤 VST3EditorService: View closed for effect $effectId');

    if (_audioEngine == null) {
      debugPrint('❌ VST3EditorService: AudioEngine not initialized');
      return;
    }

    try {
      // vst3CloseEditor returns void
      _audioEngine!.vst3CloseEditor(effectId);
      debugPrint('✅ VST3EditorService: Editor closed for effect $effectId');
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to handle viewClosed: $e');
    }
  }

  /// Open a floating (undocked) editor window for a VST3 plugin
  /// This creates a standalone floating window and attaches the VST3 editor via FFI
  ///
  /// Parameters:
  /// - effectId: The effect ID from the audio engine
  /// - pluginName: Display name for the window title
  /// - width: Default window width (will be overridden by plugin's preferred size)
  /// - height: Default window height (will be overridden by plugin's preferred size)
  static Future<bool> openFloatingWindow({
    required int effectId,
    required String pluginName,
    required double width,
    required double height,
  }) async {
    if (_audioEngine == null) {
      debugPrint('❌ VST3EditorService: AudioEngine not initialized');
      return false;
    }

    try {
      debugPrint('🪟 VST3EditorService: Opening floating window for effect $effectId...');

      // Step 1: Open the editor FIRST to get the plugin's preferred size
      // This creates the IPlugView before we create the window
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Open editor error: $openResult');
        return false;
      }
      debugPrint('✅ VST3EditorService: Editor opened for effect $effectId');

      // Step 2: Get editor size - use plugin's preferred size for the window
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      double editorWidth = (sizeResult?['width'] ?? 800).toDouble();
      double editorHeight = (sizeResult?['height'] ?? 600).toDouble();
      debugPrint('📏 VST3EditorService: Editor size ${editorWidth.toInt()}x${editorHeight.toInt()}');

      // Step 3: Create the floating window at the CORRECT size
      final result = await _channel.invokeMethod('openFloatingWindow', {
        'effectId': effectId,
        'pluginName': pluginName,
        'width': editorWidth,
        'height': editorHeight,
      });

      if (result is! Map) {
        debugPrint('❌ VST3EditorService: Unexpected result type: ${result.runtimeType}');
        _audioEngine!.vst3CloseEditor(effectId);
        return false;
      }

      final success = result['success'] as bool? ?? false;
      final viewPointer = result['viewPointer'] as int?;

      if (!success || viewPointer == null) {
        debugPrint('❌ VST3EditorService: Failed to create floating window');
        _audioEngine!.vst3CloseEditor(effectId);
        return false;
      }

      debugPrint('✅ VST3EditorService: Floating window created at ${editorWidth.toInt()}x${editorHeight.toInt()}, viewPointer=$viewPointer');

      // Step 4: Attach editor to the floating window's NSView
      final viewPtr = ffi.Pointer<ffi.Void>.fromAddress(viewPointer);
      debugPrint('🔗 VST3EditorService: Attaching editor to view pointer $viewPtr...');

      final attachResult = _audioEngine!.vst3AttachEditor(effectId, viewPtr);
      if (attachResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Attach editor error: $attachResult');
        // Close editor and window
        _audioEngine!.vst3CloseEditor(effectId);
        await _channel.invokeMethod('closeFloatingWindow', {'effectId': effectId});
        return false;
      }

      debugPrint('✅ VST3EditorService: Editor attached successfully to floating window!');
      return true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to open floating window: $e');
      return false;
    }
  }

  /// Close a floating editor window
  static Future<bool> closeFloatingWindow({
    required int effectId,
  }) async {
    try {
      // First close the editor via FFI
      if (_audioEngine != null) {
        _audioEngine!.vst3CloseEditor(effectId);
        debugPrint('✅ VST3EditorService: Editor closed for effect $effectId');
      }

      // Then close the window via platform channel
      final result = await _channel.invokeMethod('closeFloatingWindow', {
        'effectId': effectId,
      });
      return result == true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to close floating window: $e');
      return false;
    }
  }

  /// Attach a VST3 editor to a docked platform view
  static Future<bool> attachEditor({
    required int effectId,
  }) async {
    try {
      final result = await _channel.invokeMethod('attachEditor', {
        'effectId': effectId,
      });
      return result == true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to attach editor: $e');
      return false;
    }
  }

  /// Detach a VST3 editor from a platform view
  static Future<bool> detachEditor({
    required int effectId,
  }) async {
    try {
      final result = await _channel.invokeMethod('detachEditor', {
        'effectId': effectId,
      });
      return result == true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to detach editor: $e');
      return false;
    }
  }
}
