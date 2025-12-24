import Cocoa
import FlutterMacOS

/// Registry for VST3 editor views - allows lookup by effect ID
/// This is needed so Dart can request attachment for a specific view
class VST3EditorViewRegistry {
    static let shared = VST3EditorViewRegistry()

    private var views: [Int: VST3EditorView] = [:]
    private let lock = NSLock()

    private init() {}

    func register(view: VST3EditorView, effectId: Int) {
        lock.lock()
        defer { lock.unlock() }
        views[effectId] = view
        print("📝 VST3EditorViewRegistry: Registered view for effect \(effectId)")
    }

    func unregister(effectId: Int) {
        lock.lock()
        defer { lock.unlock() }
        views.removeValue(forKey: effectId)
        print("📝 VST3EditorViewRegistry: Unregistered view for effect \(effectId)")
    }

    func getView(effectId: Int) -> VST3EditorView? {
        lock.lock()
        defer { lock.unlock() }
        return views[effectId]
    }

    /// Get the NSView pointer for an effect ID (for Dart FFI)
    func getViewPointer(effectId: Int) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        guard let view = views[effectId] else { return nil }
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        return Int64(Int(bitPattern: ptr))
    }
}

/// NSView wrapper for VST3 plugin editors
/// This view holds the native VST3 editor GUI and manages its lifecycle
///
/// IMPORTANT: This view uses a CHILD WINDOW approach for plugin hosting.
/// Many VST3 plugins (especially Serum) crash when attached to Flutter platform views
/// because they need a real window context for OpenGL/Metal rendering.
/// The child window is positioned over this view and moves with it.
class VST3EditorView: NSView {
    private var editorView: NSView?
    /// Child window that hosts the actual plugin view
    private var childWindow: NSWindow?
    /// The content view inside the child window that receives the plugin
    private var pluginContainerView: NSView?
    private(set) var effectId: Int = -1
    private(set) var isEditorAttached = false
    private var editorWidth: Int = 800
    private var editorHeight: Int = 600
    private var hasNotifiedReady = false

    init(frame: NSRect, effectId: Int) {
        self.effectId = effectId
        super.init(frame: frame)

        // Dark background for consistency
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1.0).cgColor

        // Register with the registry so Dart can find us
        VST3EditorViewRegistry.shared.register(view: self, effectId: effectId)

        print("📦 VST3EditorView: Created for effect \(effectId) with frame \(frame)")
    }

    /// Create the child window for plugin hosting
    /// This is called when the view is added to the window hierarchy or when Dart requests attachment
    /// Returns the container view pointer for FFI attachment, or nil on failure
    func prepareForAttachment() -> Int64? {
        // Reset state to allow re-attachment after hide/show cycles
        // This is critical for fixing the freeze on second toggle
        isEditorAttached = false

        // Destroy any existing child window before creating a new one
        if childWindow != nil {
            print("⚠️ VST3EditorView: Destroying existing child window before re-attachment")
            destroyChildWindow()
        }

        createChildWindow()

        // Return the container view pointer for FFI attachment
        guard let container = pluginContainerView else {
            print("❌ VST3EditorView: prepareForAttachment failed - no container view")
            return nil
        }

        let viewPtr = Unmanaged.passUnretained(container).toOpaque()
        let viewPtrInt = Int64(Int(bitPattern: viewPtr))
        print("✅ VST3EditorView: prepareForAttachment succeeded - viewPointer=\(viewPtrInt)")
        return viewPtrInt
    }

    /// Cleanup when detaching the editor
    /// This is called BEFORE the view is removed from the tree
    func cleanupAfterDetachment() {
        isEditorAttached = false
        hasNotifiedReady = false
        destroyChildWindow()

        // IMPORTANT: Unregister from registry NOW, not in deinit
        // This prevents race conditions when a new view is created immediately
        VST3EditorViewRegistry.shared.unregister(effectId: effectId)

        print("✅ VST3EditorView: cleanupAfterDetachment complete (unregistered from registry)")
    }

    private func createChildWindow() {
        guard childWindow == nil, let parentWindow = window else { return }

        // Calculate the screen position for the child window
        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = parentWindow.convertToScreen(frameInWindow)

        // Create a borderless child window
        let child = NSWindow(
            contentRect: frameInScreen,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        child.isOpaque = false
        child.backgroundColor = NSColor.clear
        child.hasShadow = false
        child.isReleasedWhenClosed = false
        child.ignoresMouseEvents = false
        child.level = parentWindow.level

        // Create the container view for the plugin
        let container = NSView(frame: NSRect(origin: .zero, size: frameInScreen.size))
        container.wantsLayer = false  // No layer backing for plugin
        container.autoresizingMask = [.width, .height]
        child.contentView = container
        pluginContainerView = container

        // Add as child window so it moves with parent
        parentWindow.addChildWindow(child, ordered: .above)

        // Show the child window
        child.orderFront(nil)

        childWindow = child

        print("🪟 VST3EditorView: Created child window at \(frameInScreen)")
    }

    /// Update the child window position to match this view
    private func updateChildWindowPosition() {
        guard let child = childWindow, let parentWindow = window else { return }

        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = parentWindow.convertToScreen(frameInWindow)

        child.setFrame(frameInScreen, display: true)
    }

    /// Destroy the child window
    private func destroyChildWindow() {
        guard let child = childWindow else { return }

        if let parent = child.parent {
            parent.removeChildWindow(child)
        }
        child.orderOut(nil)
        child.close()
        childWindow = nil
        pluginContainerView = nil

        print("🗑️ VST3EditorView: Destroyed child window")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        print("🪟 VST3EditorView: viewDidMoveToWindow - window=\(window != nil), hasNotifiedReady=\(hasNotifiedReady)")

        if window != nil && !hasNotifiedReady && effectId >= 0 {
            // View is now in a window hierarchy - notify Dart that we're ready
            // Dart will then call attachEditor to create the child window and get the view pointer
            hasNotifiedReady = true
            print("🔔 VST3EditorView: Notifying Dart that view is ready for effect \(effectId)")

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Send simple ready notification without view pointer
                // Dart will call attachEditor which creates child window and returns the pointer
                VST3PlatformChannelHandler.shared.notifyViewReady(
                    effectId: self.effectId,
                    viewPointer: 0  // Placeholder - actual pointer returned by attachEditor
                )
            }
        } else if window == nil {
            // View removed from window - cleanup
            hasNotifiedReady = false
            destroyChildWindow()
        }
    }

    override func layout() {
        super.layout()

        // DISABLED: Automatic notification is temporarily disabled for debugging
        // updateChildWindowPosition()
        //
        // // Also try to notify when we have valid bounds
        // if !hasNotifiedReady && bounds.width > 0 && bounds.height > 0 && effectId >= 0 && window != nil {
        //     print("📐 VST3EditorView: layout - bounds=\(bounds), notifying ready")
        //     notifyViewReady()
        // }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateChildWindowPosition()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateChildWindowPosition()
    }

    /// Notify Dart that this view is ready for editor attachment
    private func notifyViewReady() {
        guard !hasNotifiedReady else { return }

        // Wait for child window and container to be created
        guard let child = childWindow, let container = pluginContainerView else {
            print("⏳ VST3EditorView: No child window/container yet, waiting...")
            DispatchQueue.main.async { [weak self] in
                self?.notifyViewReady()
            }
            return
        }

        // Verify the parent window is fully set up
        guard let parentWindow = window else {
            print("⏳ VST3EditorView: No parent window yet, waiting...")
            DispatchQueue.main.async { [weak self] in
                self?.notifyViewReady()
            }
            return
        }

        // Ensure the child window is visible
        guard child.isVisible || child.screen != nil else {
            print("⏳ VST3EditorView: Child window not visible yet, waiting...")
            DispatchQueue.main.async { [weak self] in
                self?.notifyViewReady()
            }
            return
        }

        hasNotifiedReady = true

        // Get the CONTAINER view pointer from the CHILD WINDOW
        // This is the key difference - we're using a real window's content view
        let viewPtr = Unmanaged.passUnretained(container).toOpaque()
        let viewPtrInt = Int64(Int(bitPattern: viewPtr))

        print("🔔 VST3EditorView: Notifying Dart that view is ready for effect \(effectId)")
        print("🔔 VST3EditorView: Container view ptr=\(viewPtr), class=\(type(of: container))")
        print("🔔 VST3EditorView: Parent window=\(parentWindow.title), child window visible=\(child.isVisible)")
        print("🔔 VST3EditorView: Container bounds=\(container.bounds), frame=\(container.frame)")
        print("🔔 VST3EditorView: Child window frame=\(child.frame)")

        // Defer the notification slightly to ensure everything is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            print("🔔 VST3EditorView: Sending viewReady notification after delay")

            // Send notification to Dart via Platform Channel
            // Dart will then call FFI to open and attach the editor
            VST3PlatformChannelHandler.shared.notifyViewReady(
                effectId: self.effectId,
                viewPointer: viewPtrInt
            )
        }
    }

    /// Called by Dart after FFI attachment succeeds
    func markAsAttached(width: Int, height: Int) {
        isEditorAttached = true
        editorWidth = width
        editorHeight = height
        print("✅ VST3EditorView: Marked as attached for effect \(effectId), size \(width)x\(height)")

        // Force redraw
        needsDisplay = true
        needsLayout = true
    }

    /// Attach a native VST3 editor view (for subview management)
    func attachEditor(view: NSView) {
        // Remove existing editor if any
        detachEditor()

        // Add the new editor view
        editorView = view
        addSubview(view)

        // Position the editor view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
    }

    /// Detach and remove the current editor view
    func detachEditor() {
        editorView?.removeFromSuperview()
        editorView = nil
    }

    /// Get the preferred editor size
    func getPreferredSize() -> NSSize {
        return NSSize(width: editorWidth, height: editorHeight)
    }

    deinit {
        // Unregister from registry (may already be done in cleanupAfterDetachment)
        // The registry handles duplicate unregister calls gracefully
        VST3EditorViewRegistry.shared.unregister(effectId: effectId)

        // DON'T notify Dart about view closed - Dart already knows and may have
        // already started creating a new view. Sending a notification here can
        // cause race conditions and crashes.
        // The editor is closed by Dart BEFORE calling detachEditor, so we don't
        // need to close it again here.

        // Clean up child window (may already be done in cleanupAfterDetachment)
        destroyChildWindow()

        detachEditor()
        print("🗑️ VST3EditorView: Deallocated for effect \(effectId)")
    }
}

/// Handler for Platform Channel calls TO Swift FROM Dart
/// This is separate from VST3PlatformChannel which handles calls FROM Swift TO Dart
class VST3PlatformChannelHandler {
    static let shared = VST3PlatformChannelHandler()

    private var methodChannel: FlutterMethodChannel?

    private init() {}

    func setup(messenger: FlutterBinaryMessenger) {
        // This channel is for Swift -> Dart notifications
        methodChannel = FlutterMethodChannel(
            name: "boojy_audio.vst3.editor.native",
            binaryMessenger: messenger
        )
        print("✅ VST3PlatformChannelHandler: Setup complete")
    }

    /// Notify Dart that a view is ready for editor attachment
    func notifyViewReady(effectId: Int, viewPointer: Int64) {
        methodChannel?.invokeMethod("viewReady", arguments: [
            "effectId": effectId,
            "viewPointer": viewPointer
        ])
    }

    /// Notify Dart that a view was closed and editor should be detached
    func notifyViewClosed(effectId: Int) {
        methodChannel?.invokeMethod("viewClosed", arguments: [
            "effectId": effectId
        ])
    }

    /// Called by Dart to confirm attachment succeeded
    func handleAttachmentConfirmed(effectId: Int, width: Int, height: Int) {
        if let view = VST3EditorViewRegistry.shared.getView(effectId: effectId) {
            view.markAsAttached(width: width, height: height)
        }
    }
}

/// Flutter platform view factory for VST3 editors
class VST3PlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        guard let args = args as? [String: Any],
              let effectId = args["effectId"] as? Int else {
            print("❌ VST3PlatformView: Missing effectId argument")
            return NSView()
        }

        print("✅ VST3PlatformViewFactory: Creating view for effect \(effectId)")

        // Create the editor view container with a default size
        // The actual size will be set when the editor is attached in viewDidMoveToWindow()
        let editorView = VST3EditorView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            effectId: effectId
        )

        // DON'T attach here - let viewDidMoveToWindow() handle it
        // when the view is properly in the window hierarchy.
        // This fixes the issue where the editor wasn't rendering because
        // the view had zero frame and wasn't in the hierarchy yet.

        return editorView
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
