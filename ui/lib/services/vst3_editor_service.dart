import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../audio_engine.dart';
import 'plugin_preferences_service.dart';

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

  /// Handle method calls from Swift (view ready, view closed, window moved, etc.)
  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    debugPrint('📥 VST3EditorService: Received ${call.method} from Swift');

    switch (call.method) {
      case 'viewReady':
        return _handleViewReady(call.arguments);
      case 'viewClosed':
        return _handleViewClosed(call.arguments);
      case 'windowMoved':
        return _handleWindowMoved(call.arguments);
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'Method ${call.method} not implemented',
        );
    }
  }

  /// Handle window moved notification from Swift
  /// Save the window position to preferences
  static Future<void> _handleWindowMoved(dynamic args) async {
    final pluginName = args['pluginName'] as String?;
    final x = args['x'] as double?;
    final y = args['y'] as double?;

    if (pluginName == null || x == null || y == null) {
      debugPrint('❌ VST3EditorService: Invalid windowMoved args: $args');
      return;
    }

    debugPrint('📍 VST3EditorService: Window moved for $pluginName: ($x, $y)');
    await PluginPreferencesService.saveWindowPosition(pluginName, x, y);
  }

  /// Handle view ready notification from Swift
  /// Swift sends effectId when the platform view is in window hierarchy
  /// We then call attachEditor to complete the attachment
  ///
  /// IMPORTANT: This is called from within the platform channel handler.
  /// We must NOT await attachEditor here, as it sends a message back to Swift,
  /// which would deadlock the platform channel. Instead, we schedule it async.
  static Future<void> _handleViewReady(dynamic args) async {
    final effectId = args['effectId'] as int?;

    if (effectId == null) {
      debugPrint('❌ VST3EditorService: Invalid viewReady args: $args');
      return;
    }

    debugPrint('🔔 VST3EditorService: View ready for effect $effectId - returning immediately');

    // Schedule attachEditor asynchronously to avoid deadlocking the platform channel
    // We can't await here because attachEditor sends a message back to Swift,
    // and Swift is waiting for this handler to return first.
    Future.delayed(const Duration(milliseconds: 100), () async {
      debugPrint('🔔 VST3EditorService: Starting delayed attachEditor for effect $effectId');
      final success = await attachEditor(effectId: effectId);
      if (!success) {
        debugPrint('❌ VST3EditorService: Failed to attach editor for effect $effectId');
      }
    });

    debugPrint('🔔 VST3EditorService: _handleViewReady returning for effect $effectId');
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
      // Include saved position if available
      final savedPosition = PluginPreferencesService.getWindowPosition(pluginName);
      final Map<String, dynamic> openArgs = {
        'effectId': effectId,
        'pluginName': pluginName,
        'width': editorWidth,
        'height': editorHeight,
      };
      if (savedPosition != null) {
        openArgs['x'] = savedPosition.x;
        openArgs['y'] = savedPosition.y;
        debugPrint('📍 VST3EditorService: Using saved position (${savedPosition.x}, ${savedPosition.y})');
      }
      final result = await _channel.invokeMethod('openFloatingWindow', openArgs);

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

  /// Attach a VST3 editor to a docked (embedded) platform view
  /// This is called when the user clicks "Show Plugin GUI" in the bottom panel
  ///
  /// Flow:
  /// 1. Ask Swift to prepare the child window and return view pointer
  /// 2. Open the editor via FFI (creates IPlugView)
  /// 3. Attach the editor to the view via FFI
  /// 4. Confirm attachment to Swift
  static Future<bool> attachEditor({
    required int effectId,
  }) async {
    if (_audioEngine == null) {
      debugPrint('❌ VST3EditorService: AudioEngine not initialized');
      return false;
    }

    try {
      debugPrint('📎 VST3EditorService: Attaching editor for effect $effectId...');

      // Step 1: Ask Swift to prepare the view and return the pointer
      // Use timeout to prevent infinite blocking if something goes wrong
      final result = await _channel.invokeMethod('attachEditor', {
        'effectId': effectId,
      }).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ VST3EditorService: attachEditor timed out after 5 seconds');
          return null;
        },
      );

      if (result == null) {
        debugPrint('❌ VST3EditorService: attachEditor returned null (likely timeout)');
        return false;
      }

      if (result is! Map) {
        debugPrint('❌ VST3EditorService: Unexpected result type: ${result.runtimeType}');
        return false;
      }

      final success = result['success'] as bool? ?? false;
      final viewPointer = result['viewPointer'] as int?;

      if (!success || viewPointer == null) {
        debugPrint('❌ VST3EditorService: Swift failed to prepare view');
        return false;
      }

      debugPrint('✅ VST3EditorService: View prepared, viewPointer=$viewPointer');

      // Step 2: Open the editor via FFI (creates IPlugView)
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Open editor error: $openResult');
        await _channel.invokeMethod('detachEditor', {'effectId': effectId});
        return false;
      }
      debugPrint('✅ VST3EditorService: Editor opened for effect $effectId');

      // Step 3: Get editor size
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      int width = sizeResult?['width'] ?? 800;
      int height = sizeResult?['height'] ?? 600;
      debugPrint('📏 VST3EditorService: Editor size ${width}x$height');

      // Step 4: Attach editor to the NSView via FFI
      final viewPtr = ffi.Pointer<ffi.Void>.fromAddress(viewPointer);
      final attachResult = _audioEngine!.vst3AttachEditor(effectId, viewPtr);
      if (attachResult.isNotEmpty) {
        debugPrint('⚠️ VST3EditorService: Attach editor error: $attachResult');
        _audioEngine!.vst3CloseEditor(effectId);
        await _channel.invokeMethod('detachEditor', {'effectId': effectId});
        return false;
      }
      debugPrint('✅ VST3EditorService: Editor attached for effect $effectId');

      // Step 5: Confirm attachment back to Swift
      await _channel.invokeMethod('confirmAttachment', {
        'effectId': effectId,
        'width': width,
        'height': height,
      });

      debugPrint('✅ VST3EditorService: Embedded editor fully attached!');
      return true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to attach editor: $e');
      return false;
    }
  }

  /// Detach a VST3 editor from a docked platform view
  /// This is called when the user clicks "Hide Plugin GUI" in the bottom panel
  static Future<bool> detachEditor({
    required int effectId,
  }) async {
    try {
      debugPrint('📎 VST3EditorService: Detaching editor for effect $effectId...');

      // Step 1: Close the editor via FFI
      if (_audioEngine != null) {
        debugPrint('📎 VST3EditorService: Calling vst3CloseEditor...');
        _audioEngine!.vst3CloseEditor(effectId);
        debugPrint('✅ VST3EditorService: Editor closed for effect $effectId');
      }

      // Step 2: Tell Swift to cleanup the child window (with timeout)
      debugPrint('📎 VST3EditorService: Calling Swift detachEditor...');
      final result = await _channel.invokeMethod('detachEditor', {
        'effectId': effectId,
      }).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ VST3EditorService: detachEditor timed out after 5 seconds');
          return false;
        },
      );

      debugPrint('✅ VST3EditorService: Detach complete, result=$result');
      return result == true;
    } catch (e) {
      debugPrint('❌ VST3EditorService: Failed to detach editor: $e');
      return false;
    }
  }
}
