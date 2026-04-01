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

  /// Pending max size constraints for embedded editor, keyed by effectId.
  static final Map<int, (int, int)> _pendingMaxSize = {};

  /// Plugin's original preferred editor size, stored after first attachment.
  /// Used by Vst3InstrumentView for uniform scale-to-fit calculation.
  static final Map<int, (int, int)> preferredEditorSize = {};

  /// Effect IDs that currently have a floating window open.
  /// Used to skip closeEditorOnDispose when the embedded widget is disposed
  /// during the float transition (the editor is still alive in the float window).
  static final Set<int> _floatingEffectIds = {};

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
    final argsMap = args as Map<dynamic, dynamic>;
    final pluginName = argsMap['pluginName'] as String?;
    final x = argsMap['x'] as double?;
    final y = argsMap['y'] as double?;

    if (pluginName == null || x == null || y == null) {
      return;
    }

    await PluginPreferencesService.saveWindowPosition(pluginName, x, y);
  }

  /// Register the max embedded size for a plugin effect.
  /// Called by Vst3InstrumentView when the platform view is about to be created.
  static void setEmbeddedMaxSize(int effectId, int maxW, int maxH) {
    _pendingMaxSize[effectId] = (maxW, maxH);
  }

  /// Handle view ready notification from Swift
  /// Swift sends effectId when the platform view is in window hierarchy
  /// We then call attachEditor to complete the attachment
  ///
  /// IMPORTANT: This is called from within the platform channel handler.
  /// We must NOT await attachEditor here, as it sends a message back to Swift,
  /// which would deadlock the platform channel. Instead, we schedule it async.
  static Future<void> _handleViewReady(dynamic args) async {
    final argsMap = args as Map<dynamic, dynamic>;
    final effectId = argsMap['effectId'] as int?;

    if (effectId == null) {
      return;
    }

    // Retrieve and consume pending max size for embedded mode
    final maxSize = _pendingMaxSize.remove(effectId);
    final maxW = maxSize?.$1 ?? 0;
    final maxH = maxSize?.$2 ?? 0;
    // Schedule attachEditor asynchronously to avoid deadlocking the platform channel
    // We can't await here because attachEditor sends a message back to Swift,
    // and Swift is waiting for this handler to return first.
    Future.delayed(const Duration(milliseconds: 100), () async {
      await attachEditor(
        effectId: effectId,
        maxWidth: maxW,
        maxHeight: maxH,
      );
    });
  }

  /// Handle view closed notification from Swift
  static Future<void> _handleViewClosed(dynamic args) async {
    final argsMap = args as Map<dynamic, dynamic>;
    final effectId = argsMap['effectId'] as int?;

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
      // FFI cleanup - ignore errors silently
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
      final double editorWidth = (sizeResult?['width'] ?? 800).toDouble();
      final double editorHeight = (sizeResult?['height'] ?? 600).toDouble();

      // Step 3: Create the floating window at the CORRECT size
      // Include saved position if available
      final savedPosition = PluginPreferencesService.getWindowPosition(
        pluginName,
      );
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
      final result = await _channel.invokeMethod(
        'openFloatingWindow',
        openArgs,
      );

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
        await _channel.invokeMethod('closeFloatingWindow', {
          'effectId': effectId,
        });
        return false;
      }

      _floatingEffectIds.add(effectId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Close a floating editor window
  static Future<bool> closeFloatingWindow({required int effectId}) async {
    _floatingEffectIds.remove(effectId);
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
  /// [maxWidth]/[maxHeight]: if > 0, constrain plugin resize requests
  /// (embedded mode). Pass 0,0 for floating windows (unconstrained).
  static Future<bool> attachEditor({
    required int effectId,
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    if (_audioEngine == null) return false;

    // Set max size constraint BEFORE attachment so PlugFrame::resizeView()
    // clamps immediately when the plugin requests resize during attached()
    if (maxWidth > 0 || maxHeight > 0) {
      _audioEngine!.setVst3EditorMaxSize(effectId, maxWidth, maxHeight);
    } else {
      _audioEngine!.setVst3EditorMaxSize(effectId, 0, 0);
    }

    try {
      // Step 1: Ask Swift to prepare the view and return the pointer
      final result = await _channel
          .invokeMethod('attachEditor', {'effectId': effectId})
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );

      if (result == null || result is! Map) return false;

      final success = result['success'] as bool? ?? false;
      final viewPointer = result['viewPointer'] as int?;

      if (!success || viewPointer == null) return false;

      // Step 2: Open the editor via FFI (creates IPlugView)
      final openResult = _audioEngine!.vst3OpenEditor(effectId);
      if (openResult.isNotEmpty) {
        await _channel.invokeMethod('detachEditor', {'effectId': effectId});
        return false;
      }

      // Step 3: Get editor size (this is the PREFERRED size before any onSize)
      final sizeResult = _audioEngine!.vst3GetEditorSize(effectId);
      final int width = sizeResult?['width'] ?? 800;
      final int height = sizeResult?['height'] ?? 600;

      // Store preferred size for uniform scale-to-fit in the widget
      preferredEditorSize[effectId] = (width, height);

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

  /// Close the C++ editor during widget dispose, BEFORE the platform view
  /// is destroyed. This prevents use-after-free when the NSView is deallocated
  /// while C++ still holds a parent_window pointer to it.
  static void closeEditorOnDispose(int effectId) {
    if (_audioEngine == null) return;
    // Don't close the editor if it's currently in a floating window —
    // the embedded widget is being disposed during the float transition
    // but the editor is still alive in the floating window.
    if (_floatingEffectIds.contains(effectId)) return;
    try {
      _audioEngine!.vst3CloseEditor(effectId);
    } catch (e) {
      // FFI cleanup during dispose - ignore errors
    }
  }

  /// Tell Swift to destroy the child window and unregister the old view.
  /// Called fire-and-forget from dispose() — the platform channel message
  /// is processed before the next frame, ensuring cleanup before any new
  /// platform view is created for the same effectId.
  static void cleanupViewOnDispose(int effectId) {
    _channel.invokeMethod('detachEditor', {'effectId': effectId});
  }

  /// Hide all plugin child windows (when a Flutter popup/dialog appears)
  static void hideAllEditors() {
    _channel.invokeMethod('hideAllEditors');
  }

  /// Show all plugin child windows (when a Flutter popup/dialog is dismissed)
  static void showAllEditors() {
    _channel.invokeMethod('showAllEditors');
  }

  /// Show a native macOS context menu that appears above plugin child windows.
  /// Returns the selected item's `id`, or null if dismissed.
  static Future<String?> showNativeContextMenu({
    required List<Map<String, dynamic>> items,
    required double x,
    required double y,
  }) async {
    return _channel.invokeMethod<String>('showContextMenu', {
      'items': items,
      'x': x,
      'y': y,
    });
  }

  /// Show a native macOS alert that appears above plugin child windows.
  /// Returns the button index (0-based), or null on failure.
  static Future<int?> showNativeAlert({
    required String title,
    required String message,
    required List<Map<String, dynamic>> buttons,
  }) async {
    return _channel.invokeMethod<int>('showNativeAlert', {
      'title': title,
      'message': message,
      'buttons': buttons,
    });
  }

  /// Hide a floating window (when switching away from its track)
  static void hideFloatingWindow(int effectId) {
    _channel.invokeMethod('hideFloatingWindow', {'effectId': effectId});
  }

  /// Show a floating window (when switching back to its track)
  static void showFloatingWindow(int effectId) {
    _channel.invokeMethod('showFloatingWindow', {'effectId': effectId});
  }

  /// Detach a VST3 editor from a docked platform view
  /// This is called when the user clicks "Hide Plugin GUI" in the bottom panel
  static Future<bool> detachEditor({required int effectId}) async {
    try {
      // Step 1: Close the editor via FFI
      if (_audioEngine != null) {
        _audioEngine!.vst3CloseEditor(effectId);
      }

      // Step 2: Tell Swift to cleanup the child window (with timeout)
      final result = await _channel
          .invokeMethod('detachEditor', {'effectId': effectId})
          .timeout(
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
