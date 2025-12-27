import 'dart:ffi' as ffi;
import 'package:flutter/services.dart';
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

  }

  /// Handle method calls from Swift (view ready, view closed, window moved, etc.)
  static Future<dynamic> _handleNativeCall(MethodCall call) async {

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
      return;
    }

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
      return;
    }


    // Schedule attachEditor asynchronously to avoid deadlocking the platform channel
    // We can't await here because attachEditor sends a message back to Swift,
    // and Swift is waiting for this handler to return first.
    Future.delayed(const Duration(milliseconds: 100), () async {
      final success = await attachEditor(effectId: effectId);
      if (!success) {
      }
    });

  }

  /// Handle view closed notification from Swift
  static Future<void> _handleViewClosed(dynamic args) async {
    final effectId = args['effectId'] as int?;

    if (effectId == null) {
      return;
    }


    if (_audioEngine == null) {
      return;
    }

    try {
      // vst3CloseEditor returns void
      _audioEngine!.vst3CloseEditor(effectId);
    } catch (e) {
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
      return false;
    }

    try {

      // Step 1: Open the editor FIRST to get the plugin's preferred size
      // This creates the IPlugView before we create the window
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        return false;
      }

      // Step 2: Get editor size - use plugin's preferred size for the window
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      double editorWidth = (sizeResult?['width'] ?? 800).toDouble();
      double editorHeight = (sizeResult?['height'] ?? 600).toDouble();

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
      }
      final result = await _channel.invokeMethod('openFloatingWindow', openArgs);

      if (result is! Map) {
        _audioEngine!.vst3CloseEditor(effectId);
        return false;
      }

      final success = result['success'] as bool? ?? false;
      final viewPointer = result['viewPointer'] as int?;

      if (!success || viewPointer == null) {
        _audioEngine!.vst3CloseEditor(effectId);
        return false;
      }


      // Step 4: Attach editor to the floating window's NSView
      final viewPtr = ffi.Pointer<ffi.Void>.fromAddress(viewPointer);

      final attachResult = _audioEngine!.vst3AttachEditor(effectId, viewPtr);
      if (attachResult.isNotEmpty) {
        // Close editor and window
        _audioEngine!.vst3CloseEditor(effectId);
        await _channel.invokeMethod('closeFloatingWindow', {'effectId': effectId});
        return false;
      }

      return true;
    } catch (e) {
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
      }

      // Then close the window via platform channel
      final result = await _channel.invokeMethod('closeFloatingWindow', {
        'effectId': effectId,
      });
      return result == true;
    } catch (e) {
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
      return false;
    }

    try {

      // Step 1: Ask Swift to prepare the view and return the pointer
      // Use timeout to prevent infinite blocking if something goes wrong
      final result = await _channel.invokeMethod('attachEditor', {
        'effectId': effectId,
      }).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return null;
        },
      );

      if (result == null) {
        return false;
      }

      if (result is! Map) {
        return false;
      }

      final success = result['success'] as bool? ?? false;
      final viewPointer = result['viewPointer'] as int?;

      if (!success || viewPointer == null) {
        return false;
      }


      // Step 2: Open the editor via FFI (creates IPlugView)
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        await _channel.invokeMethod('detachEditor', {'effectId': effectId});
        return false;
      }

      // Step 3: Get editor size
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      int width = sizeResult?['width'] ?? 800;
      int height = sizeResult?['height'] ?? 600;

      // Step 4: Attach editor to the NSView via FFI
      final viewPtr = ffi.Pointer<ffi.Void>.fromAddress(viewPointer);
      final attachResult = _audioEngine!.vst3AttachEditor(effectId, viewPtr);
      if (attachResult.isNotEmpty) {
        _audioEngine!.vst3CloseEditor(effectId);
        await _channel.invokeMethod('detachEditor', {'effectId': effectId});
        return false;
      }

      // Step 5: Confirm attachment back to Swift
      await _channel.invokeMethod('confirmAttachment', {
        'effectId': effectId,
        'width': width,
        'height': height,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Detach a VST3 editor from a docked platform view
  /// This is called when the user clicks "Hide Plugin GUI" in the bottom panel
  static Future<bool> detachEditor({
    required int effectId,
  }) async {
    try {

      // Step 1: Close the editor via FFI
      if (_audioEngine != null) {
        _audioEngine!.vst3CloseEditor(effectId);
      }

      // Step 2: Tell Swift to cleanup the child window (with timeout)
      final result = await _channel.invokeMethod('detachEditor', {
        'effectId': effectId,
      }).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return false;
        },
      );

      return result == true;
    } catch (e) {
      return false;
    }
  }
}
