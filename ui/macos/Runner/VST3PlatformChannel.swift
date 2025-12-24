import Cocoa
import FlutterMacOS

/// Platform channel for VST3 editor communication
/// Handles method calls from Flutter to manage VST3 editor windows
class VST3PlatformChannel {
    static let channelName = "boojy_audio.vst3.editor"

    private var channel: FlutterMethodChannel
    private var windowManager = VST3WindowManager.shared

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: VST3PlatformChannel.channelName,
            binaryMessenger: messenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }

        // Give window manager access to channel for sending notifications to Dart
        windowManager.setMethodChannel(channel)

        print("✅ VST3PlatformChannel: Initialized")
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let method = call.method
        let args = call.arguments as? [String: Any] ?? [:]

        switch method {
        case "openFloatingWindow":
            openFloatingWindow(args: args, result: result)

        case "closeFloatingWindow":
            closeFloatingWindow(args: args, result: result)

        case "attachEditor":
            attachEditor(args: args, result: result)

        case "detachEditor":
            detachEditor(args: args, result: result)

        case "confirmAttachment":
            confirmAttachment(args: args, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Open a floating (undocked) editor window
    /// Returns the view pointer so Dart can call FFI to attach the editor
    private func openFloatingWindow(args: [String: Any], result: @escaping FlutterResult) {
        guard let effectId = args["effectId"] as? Int,
              let pluginName = args["pluginName"] as? String,
              let width = args["width"] as? Double,
              let height = args["height"] as? Double else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required arguments: effectId, pluginName, width, height",
                details: nil
            ))
            return
        }

        let size = NSSize(width: width, height: height)

        // Optional saved position
        var position: NSPoint? = nil
        if let x = args["x"] as? Double, let y = args["y"] as? Double {
            position = NSPoint(x: x, y: y)
            print("📍 VST3PlatformChannel: Using saved position (\(x), \(y))")
        }

        if windowManager.openWindow(effectId: effectId, pluginName: pluginName, size: size, position: position) != nil {
            // Get the container view pointer for FFI attachment
            if let viewPtr = windowManager.getContainerViewPointer(effectId: effectId) {
                let viewPtrInt = Int64(Int(bitPattern: viewPtr))
                print("✅ VST3PlatformChannel: Floating window opened, viewPointer=\(viewPtrInt)")

                // Return success with the view pointer so Dart can call FFI
                result([
                    "success": true,
                    "viewPointer": viewPtrInt
                ])
            } else {
                result(FlutterError(
                    code: "VIEW_POINTER_FAILED",
                    message: "Failed to get view pointer for effect \(effectId)",
                    details: nil
                ))
            }
        } else {
            result(FlutterError(
                code: "WINDOW_CREATION_FAILED",
                message: "Failed to create window for effect \(effectId)",
                details: nil
            ))
        }
    }

    /// Close a floating editor window
    private func closeFloatingWindow(args: [String: Any], result: @escaping FlutterResult) {
        guard let effectId = args["effectId"] as? Int else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required argument: effectId",
                details: nil
            ))
            return
        }

        windowManager.closeWindow(effectId: effectId)
        result(true)
    }

    /// Attach a VST3 editor to a docked platform view
    /// Returns the view pointer so Dart can call FFI to attach the editor
    private func attachEditor(args: [String: Any], result: @escaping FlutterResult) {
        guard let effectId = args["effectId"] as? Int else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required argument: effectId",
                details: nil
            ))
            return
        }

        print("📎 VST3PlatformChannel: Attach editor for effect \(effectId)")

        // Find the VST3EditorView from the registry
        guard let editorView = VST3EditorViewRegistry.shared.getView(effectId: effectId) else {
            result(FlutterError(
                code: "VIEW_NOT_FOUND",
                message: "No VST3EditorView found for effect \(effectId)",
                details: nil
            ))
            return
        }

        // Ensure view is in a window
        guard editorView.window != nil else {
            result(FlutterError(
                code: "VIEW_NOT_IN_WINDOW",
                message: "VST3EditorView is not in a window hierarchy",
                details: nil
            ))
            return
        }

        // Create child window and get container view pointer
        guard let viewPointer = editorView.prepareForAttachment() else {
            result(FlutterError(
                code: "PREPARE_FAILED",
                message: "Failed to prepare editor view for attachment",
                details: nil
            ))
            return
        }

        print("✅ VST3PlatformChannel: Attachment prepared, viewPointer=\(viewPointer)")

        // Return success with the view pointer so Dart can call FFI
        result([
            "success": true,
            "viewPointer": viewPointer
        ])
    }

    /// Detach a VST3 editor from a platform view
    private func detachEditor(args: [String: Any], result: @escaping FlutterResult) {
        guard let effectId = args["effectId"] as? Int else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required argument: effectId",
                details: nil
            ))
            return
        }

        print("📎 VST3PlatformChannel: Detach editor for effect \(effectId)")

        // Find the VST3EditorView from the registry
        guard let editorView = VST3EditorViewRegistry.shared.getView(effectId: effectId) else {
            // View might already be gone, which is fine
            print("⚠️ VST3PlatformChannel: No view found for effect \(effectId) - may already be cleaned up")
            result(true)
            return
        }

        // Clean up the child window
        editorView.cleanupAfterDetachment()

        print("✅ VST3PlatformChannel: Editor detached for effect \(effectId)")
        result(true)
    }

    /// Confirm that Dart has attached the editor via FFI
    /// This is called by Dart after successful FFI attachment
    private func confirmAttachment(args: [String: Any], result: @escaping FlutterResult) {
        guard let effectId = args["effectId"] as? Int,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required arguments: effectId, width, height",
                details: nil
            ))
            return
        }

        print("✅ VST3PlatformChannel: Attachment confirmed for effect \(effectId), size \(width)x\(height)")

        // Notify the view that attachment is complete
        VST3PlatformChannelHandler.shared.handleAttachmentConfirmed(
            effectId: effectId,
            width: width,
            height: height
        )

        result(true)
    }
}
