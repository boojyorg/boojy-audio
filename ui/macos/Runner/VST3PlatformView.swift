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

    /// Dim all child windows (when a Flutter modal dialog is shown)
    func dimAllChildWindows() {
        lock.lock()
        defer { lock.unlock() }
        for (_, view) in views {
            view.setChildWindowDimmed(true)
        }
    }

    /// Restore all child windows (when a Flutter modal dialog is dismissed)
    func restoreAllChildWindows() {
        lock.lock()
        defer { lock.unlock() }
        for (_, view) in views {
            view.setChildWindowDimmed(false)
        }
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
    private static var nextInstanceId: Int = 0
    let instanceId: Int

    private var editorView: NSView?
    /// Child window that hosts the actual plugin view
    private var childWindow: NSWindow?
    /// The content view inside the child window (visual size)
    private var pluginContainerView: NSView?
    /// Subview of container at NATIVE size — plugin attaches here.
    /// CATransform3D on this view's layer handles visual scaling.
    private var pluginHostView: NSView?
    private(set) var effectId: Int = -1
    private(set) var isEditorAttached = false
    private var editorWidth: Int = 800
    private var editorHeight: Int = 600
    private var hasNotifiedReady = false

    /// Plugin's native/preferred size
    var nativeWidth: Int = 800
    var nativeHeight: Int = 600

    /// Whether child window is currently hidden (tab switch away)
    private var isChildWindowHidden = false

    /// Tag for debug logs
    private var logTag: String { "VST3EditorView#\(instanceId)[fx\(effectId)]" }

    init(frame: NSRect, effectId: Int) {
        self.instanceId = VST3EditorView.nextInstanceId
        VST3EditorView.nextInstanceId += 1
        self.effectId = effectId
        super.init(frame: frame)

        // Dark background for consistency
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1.0).cgColor

        // Register with the registry so Dart can find us
        VST3EditorViewRegistry.shared.register(view: self, effectId: effectId)

        print("📦 \(logTag): Created with frame \(frame)")
    }

    /// Create the child window for plugin hosting
    /// This is called when the view is added to the window hierarchy or when Dart requests attachment
    /// Returns the container view pointer for FFI attachment, or nil on failure
    func prepareForAttachment() -> Int64? {
        print("🔧 \(logTag): prepareForAttachment — isEditorAttached=\(isEditorAttached), childWindow=\(childWindow != nil)")
        // Reset state to allow re-attachment after hide/show cycles
        // This is critical for fixing the freeze on second toggle
        isEditorAttached = false

        // Destroy any existing child window before creating a new one
        if childWindow != nil {
            print("⚠️ \(logTag): Destroying existing child window before re-attachment")
            destroyChildWindow()
        }

        createChildWindow()

        // Return the PLUGIN HOST view pointer (not container) for FFI attachment.
        // The host view is at native size with CATransform3D for scaling.
        guard let hostView = pluginHostView else {
            print("❌ \(logTag): prepareForAttachment failed - no plugin host view")
            return nil
        }

        let viewPtr = Unmanaged.passUnretained(hostView).toOpaque()
        let viewPtrInt = Int64(Int(bitPattern: viewPtr))
        print("✅ \(logTag): prepareForAttachment succeeded - viewPointer=\(viewPtrInt)")
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

        print("✅ \(logTag): cleanupAfterDetachment complete (unregistered from registry)")
    }

    private func createChildWindow() {
        guard childWindow == nil, let parentWindow = window else { return }

        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = parentWindow.convertToScreen(frameInWindow)

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

        // Container at VISUAL size (matches child window)
        let container = NSView(frame: NSRect(origin: .zero, size: frameInScreen.size))
        container.wantsLayer = false
        container.autoresizingMask = []
        child.contentView = container
        pluginContainerView = container

        // Plugin host — frame matches container (visual size),
        // bounds set to native size for coordinate remapping + rendering scale.
        let host = NSView(frame: NSRect(origin: .zero, size: frameInScreen.size))
        host.wantsLayer = false  // Let the plugin manage its own layers
        if nativeWidth > 0 && nativeHeight > 0 {
            host.setBoundsSize(NSSize(width: nativeWidth, height: nativeHeight))
        }
        container.addSubview(host)
        pluginHostView = host

        parentWindow.addChildWindow(child, ordered: .above)
        child.orderFront(nil)
        childWindow = child
    }

    /// Apply scale via setBoundsSize — handles BOTH coordinate remapping
    /// (for correct mouse events) AND rendering scale (bounds→frame mapping).
    /// No CATransform3D — coordinates and visuals are both correct.
    private func applyScaleTransform() {
        guard let host = pluginHostView,
              let container = pluginContainerView,
              nativeWidth > 0, nativeHeight > 0 else { return }

        let cw = container.frame.size.width
        let ch = container.frame.size.height
        guard cw > 0, ch > 0 else { return }

        let nw = CGFloat(nativeWidth)
        let nh = CGFloat(nativeHeight)
        let scale = min(cw / nw, ch / nh, 1.0)

        let scaledW = nw * scale
        let scaledH = nh * scale

        // Center in container with letterbox
        let offsetX = (cw - scaledW) / 2
        let offsetY = (ch - scaledH) / 2

        // Frame = visual pixel size (for hit testing + rendering surface)
        host.frame = NSRect(x: offsetX, y: offsetY, width: scaledW, height: scaledH)

        // Bounds = native coordinate space (what the plugin sees).
        // AppKit maps bounds→frame for coordinates AND rendering.
        host.setBoundsSize(NSSize(width: nw, height: nh))
    }

    /// Update the child window position/size and reapply CATransform3D scale.
    private func updateChildWindowPosition() {
        guard let child = childWindow, let parentWindow = window else { return }

        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = parentWindow.convertToScreen(frameInWindow)

        child.setFrame(frameInScreen, display: true)

        if let container = pluginContainerView {
            container.frame = NSRect(origin: .zero, size: frameInScreen.size)
        }

        applyScaleTransform()
    }

    /// Destroy the child window
    private func destroyChildWindow() {
        guard let child = childWindow else { return }

        if let parent = child.parent {
            parent.removeChildWindow(child)
        }
        pluginHostView?.removeFromSuperview()
        pluginHostView = nil
        child.orderOut(nil)
        child.close()
        childWindow = nil
        pluginContainerView = nil

        print("🗑️ \(logTag): Destroyed child window")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Only log on actual state transitions — plugin render loops fire this constantly
        let isActionable = (window != nil && !hasNotifiedReady) ||
                           (window != nil && childWindow != nil && isChildWindowHidden) ||
                           (window == nil && childWindow != nil && !isChildWindowHidden)
        if isActionable {
            print("🪟 \(logTag): viewDidMoveToWindow — window=\(window != nil), hasNotifiedReady=\(hasNotifiedReady), childWindow=\(childWindow != nil), isChildWindowHidden=\(isChildWindowHidden)")
        }

        if window != nil && effectId >= 0 {
            if childWindow != nil && isChildWindowHidden {
                // Tab switch BACK — re-show the hidden child window
                isChildWindowHidden = false
                if let parentWindow = window {
                    parentWindow.addChildWindow(childWindow!, ordered: .above)
                    childWindow!.orderFront(nil)
                    updateChildWindowPosition()
                    print("🪟 \(logTag): Re-shown child window")
                }
            } else if childWindow == nil && !hasNotifiedReady {
                // First time in window — notify Dart to create child window + attach editor
                hasNotifiedReady = true
                print("🔔 \(logTag): Notifying Dart that view is ready")

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    print("🔔 \(self.tag): Sending viewReady via platform channel")
                    VST3PlatformChannelHandler.shared.notifyViewReady(
                        effectId: self.effectId,
                        viewPointer: 0
                    )
                }
            } else {
                // Suppress — plugin render loop fires this constantly
            }
        } else if window == nil && childWindow != nil && !isChildWindowHidden {
            // Tab switch AWAY — hide child window, don't destroy.
            // Plugin editor stays attached in C++.
            isChildWindowHidden = true
            if let child = childWindow, let parent = child.parent {
                parent.removeChildWindow(child)
                child.orderOut(nil)
            }
            print("🪟 \(logTag): Hidden child window")
        } else if window == nil {
            print("🪟 \(logTag): viewDidMoveToWindow(nil) — no child window to hide")
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

    private var lastLoggedSize: NSSize = .zero

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateChildWindowPosition()

        // Throttled debug: only log when size changes significantly (>10px)
        if abs(newSize.width - lastLoggedSize.width) > 10 || abs(newSize.height - lastLoggedSize.height) > 10 {
            lastLoggedSize = newSize
            if let container = pluginContainerView {
                print("📐 [RESIZE] view.frame=\(newSize), container.frame=\(container.frame.size), container.bounds=\(container.bounds.size), native=\(nativeWidth)x\(nativeHeight)")
            } else {
                print("📐 [RESIZE] view.frame=\(newSize), NO container yet")
            }
        }
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

    /// Called by Dart after FFI attachment succeeds.
    /// width/height are the plugin's native size (from vst3GetEditorSize after open).
    func markAsAttached(width: Int, height: Int) {
        isEditorAttached = true
        editorWidth = width
        editorHeight = height
        nativeWidth = width
        nativeHeight = height

        // Reapply scale with real native size (applyScaleTransform sets frame + bounds)
        applyScaleTransform()

        print("✅ \(logTag): Marked as attached, nativeSize=\(width)x\(height)")
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

    /// Hide the child window when a modal dialog appears so the dialog
    /// renders cleanly. The plugin returns instantly when the dialog closes.
    private var isHiddenForDialog = false

    func setChildWindowDimmed(_ dimmed: Bool) {
        guard let child = childWindow, !isChildWindowHidden else { return }
        if dimmed && !isHiddenForDialog {
            isHiddenForDialog = true
            child.alphaValue = 0.0
            child.ignoresMouseEvents = true
        } else if !dimmed && isHiddenForDialog {
            isHiddenForDialog = false
            child.alphaValue = 1.0
            child.ignoresMouseEvents = false
        }
    }

    /// Get the preferred editor size
    func getPreferredSize() -> NSSize {
        return NSSize(width: editorWidth, height: editorHeight)
    }

    deinit {
        print("🗑️ \(logTag): deinit — isEditorAttached=\(isEditorAttached), childWindow=\(childWindow != nil)")

        // Only unregister if WE are still the registered view.
        // A new view for the same effectId may already have registered itself.
        if VST3EditorViewRegistry.shared.getView(effectId: effectId) === self {
            VST3EditorViewRegistry.shared.unregister(effectId: effectId)
            print("🗑️ \(logTag): Unregistered from registry (was still registered)")
        } else {
            print("🗑️ \(logTag): Skipped unregister (new view already registered)")
        }

        // Clean up child window (may already be done in cleanupAfterDetachment)
        destroyChildWindow()

        detachEditor()
        print("🗑️ \(logTag): Deallocated")
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

        // Read frame size (visual display) and native size (plugin coordinate space)
        let width = args["width"] as? Int ?? 800
        let height = args["height"] as? Int ?? 600
        let nativeWidth = args["nativeWidth"] as? Int ?? width
        let nativeHeight = args["nativeHeight"] as? Int ?? height

        // Force cleanup of any existing view for this effectId.
        // When switching tracks, the old view may not have been deinited yet
        // (registry holds a strong reference). Clean it up now to destroy
        // its child window and release the reference before creating a new one.
        if let existing = VST3EditorViewRegistry.shared.getView(effectId: effectId) {
            print("🧹 VST3PlatformViewFactory: Cleaning up existing view for effect \(effectId)")
            existing.cleanupAfterDetachment()
        }

        let editorView = VST3EditorView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            effectId: effectId
        )
        editorView.nativeWidth = nativeWidth
        editorView.nativeHeight = nativeHeight

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
