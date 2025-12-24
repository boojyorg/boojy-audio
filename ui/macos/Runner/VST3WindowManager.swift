import Cocoa
import FlutterMacOS

/// Manager for undocked VST3 editor windows
/// Handles creation, lifecycle, and tracking of floating editor windows
///
/// This is a STANDALONE floating window approach that bypasses Flutter platform views.
/// Used for testing VST3 plugin UIs without Flutter embedding complexity.
class VST3WindowManager: NSObject, NSWindowDelegate {
    static let shared = VST3WindowManager()

    private var windows: [Int: NSWindow] = [:]
    /// Plain NSView containers for each window (not VST3EditorView - for direct FFI testing)
    private var containerViews: [Int: NSView] = [:]
    /// Plugin names for each window (for preferences)
    private var pluginNames: [Int: String] = [:]
    /// Reverse lookup: window -> effectId
    private var windowToEffectId: [NSWindow: Int] = [:]
    /// Platform channel for notifying Dart
    private var methodChannel: FlutterMethodChannel?

    private override init() {
        super.init()
    }

    /// Set the method channel for notifying Dart about window events
    func setMethodChannel(_ channel: FlutterMethodChannel) {
        methodChannel = channel
    }

    /// Open a floating window for a VST3 plugin editor
    /// This version creates a REAL NSWindow and plain NSView, bypassing Flutter entirely
    /// - Parameters:
    ///   - effectId: The effect ID from the audio engine
    ///   - pluginName: Display name for the window title
    ///   - size: Initial window size
    ///   - position: Optional saved window position (x, y)
    /// - Returns: The created window, or nil if creation failed
    func openWindow(effectId: Int, pluginName: String, size: NSSize, position: NSPoint? = nil) -> NSWindow? {
        // Close existing window if open
        closeWindow(effectId: effectId)

        print("🪟 VST3WindowManager: Creating standalone floating window for effect \(effectId)...")

        // Create window EXACTLY like Steinberg's editorhost sample:
        // - defer: true (deferred window creation)
        // - Use the window's default contentView (don't replace it)
        // - Resizable style
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true  // Match SDK: defer window server connection
        )

        window.title = pluginName
        window.isReleasedWhenClosed = false
        window.delegate = self  // Track window events
        // Don't set backgroundColor - let it use default

        // USE THE WINDOW'S DEFAULT CONTENT VIEW - don't create a custom one
        // This matches the Steinberg SDK approach exactly
        guard let containerView = window.contentView else {
            print("❌ VST3WindowManager: Window has no contentView!")
            return nil
        }

        // Enable layer backing - some modern plugins (Metal/CoreAnimation) require this
        containerView.wantsLayer = true

        containerViews[effectId] = containerView
        pluginNames[effectId] = pluginName
        windowToEffectId[window] = effectId

        print("🪟 VST3WindowManager: Using window's default contentView: \(containerView), frame=\(containerView.frame)")
        print("🪟 VST3WindowManager: ContentView wantsLayer=\(containerView.wantsLayer)")

        // Position window - use saved position if provided, otherwise center
        if let pos = position {
            window.setFrameOrigin(pos)
            print("🪟 VST3WindowManager: Restored window position to (\(pos.x), \(pos.y))")
        } else {
            window.center()
        }

        // Track window BEFORE showing
        windows[effectId] = window

        // Show window - this is when attached() will be called by Dart
        window.makeKeyAndOrderFront(nil)
        print("🪟 VST3WindowManager: Window made key and ordered front")

        print("✅ VST3WindowManager: Floating window created at \(window.frame)")
        print("✅ VST3WindowManager: Container view bounds=\(containerView.bounds), frame=\(containerView.frame)")
        print("✅ VST3WindowManager: Container view isHidden=\(containerView.isHidden)")
        print("✅ VST3WindowManager: Window isVisible=\(window.isVisible), isOnActiveSpace=\(window.isOnActiveSpace)")
        print("✅ VST3WindowManager: Container view class=\(type(of: containerView))")
        print("✅ VST3WindowManager: Container view ptr=\(Unmanaged.passUnretained(containerView).toOpaque())")

        return window
    }

    /// Get the container view pointer for an effect ID (for FFI attachment)
    func getContainerViewPointer(effectId: Int) -> UnsafeMutableRawPointer? {
        guard let view = containerViews[effectId] else {
            print("❌ VST3WindowManager: No container view for effect \(effectId)")
            return nil
        }
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        print("📍 VST3WindowManager: Container view pointer for effect \(effectId): \(ptr)")
        return ptr
    }

    /// Close a floating window
    func closeWindow(effectId: Int) {
        guard let window = windows[effectId] else { return }

        print("🔄 VST3WindowManager: Closing floating window for effect \(effectId)")

        // Notify Dart of final position before closing
        notifyWindowPosition(window: window)

        // Clean up all tracking
        containerViews.removeValue(forKey: effectId)
        pluginNames.removeValue(forKey: effectId)
        windowToEffectId.removeValue(forKey: window)

        window.close()
        windows.removeValue(forKey: effectId)
    }

    /// Close all floating windows
    func closeAllWindows() {
        print("🔄 VST3WindowManager: Closing all floating windows")

        for (_, window) in windows {
            window.close()
        }

        windows.removeAll()
        containerViews.removeAll()
        pluginNames.removeAll()
        windowToEffectId.removeAll()
    }

    /// Get window for effect ID
    func getWindow(effectId: Int) -> NSWindow? {
        return windows[effectId]
    }

    /// Check if window is open for effect
    func isWindowOpen(effectId: Int) -> Bool {
        return windows[effectId] != nil
    }

    // MARK: - NSWindowDelegate

    /// Called when window finishes moving
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        notifyWindowPosition(window: window)
    }

    /// Called when window is about to close
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let effectId = windowToEffectId[window] else { return }

        // Final position notification
        notifyWindowPosition(window: window)

        print("🔄 VST3WindowManager: Window closing for effect \(effectId)")

        // Clean up (in case closeWindow wasn't called directly)
        containerViews.removeValue(forKey: effectId)
        pluginNames.removeValue(forKey: effectId)
        windowToEffectId.removeValue(forKey: window)
        windows.removeValue(forKey: effectId)
    }

    /// Notify Dart about window position change
    private func notifyWindowPosition(window: NSWindow) {
        guard let effectId = windowToEffectId[window],
              let pluginName = pluginNames[effectId] else { return }

        let frame = window.frame
        let x = Double(frame.origin.x)
        let y = Double(frame.origin.y)

        print("📍 VST3WindowManager: Window position for \(pluginName): (\(x), \(y))")

        methodChannel?.invokeMethod("windowMoved", arguments: [
            "effectId": effectId,
            "pluginName": pluginName,
            "x": x,
            "y": y
        ])
    }
}
