import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var vst3PlatformChannel: VST3PlatformChannel?

  // MARK: - Traffic-light placement

  /// Logical-pixel nudge for the traffic lights: right, then down. The bar
  /// beneath them is 54pt tall and AppKit parks the lights for a 28pt title
  /// bar, so they sit high and tight against the wordmark; this drops them
  /// toward the bar's controls and eases them off the edge (Tyr-tuned by eye,
  /// 2026-09-13). Spacing and behaviour stay native — we only translate the
  /// three buttons together.
  private static let trafficLightNudge = CGPoint(x: 5, y: 11)

  /// Where AppKit puts each button before we move it. AppKit re-lays out the
  /// title bar on resize (and after window_manager hides the title), which
  /// snaps the buttons back to these spots; we remember them once and nudge
  /// from there, so repeated passes never accumulate.
  private var trafficLightDefaultOrigins: [NSWindow.ButtonType: CGPoint] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Set initial window size (1280x800) and center on screen
    self.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 800), display: true)
    self.center()

    // Set minimum window size (960x600) for responsive panel layout
    self.minSize = NSSize(width: 960, height: 600)

    // Dark title bar appearance with centered title
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

    // The native title bar is hidden at runtime via window_manager
    // (TitleBarStyle.hidden, traffic lights kept) — see WindowTitleService —
    // so the Flutter transport bar becomes the top chrome and extends
    // edge-to-edge behind the traffic lights. No NSToolbar here: an empty
    // toolbar would fight fullSizeContentView and leave a translucent strip.

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register VST3 platform view factory (must happen before Flutter engine uses it)
    let messenger = flutterViewController.engine.binaryMessenger
    let vst3Factory = VST3PlatformViewFactory(messenger: messenger)
    flutterViewController.engine.registrar(forPlugin: "VST3PlatformView")
      .register(vst3Factory, withId: "boojy_audio.vst3.editor_view")

    // Initialize VST3 platform channel for method calls (Dart -> Swift)
    vst3PlatformChannel = VST3PlatformChannel(messenger: messenger)

    // Initialize VST3 platform channel handler for Swift -> Dart notifications
    VST3PlatformChannelHandler.shared.setup(messenger: messenger)

    // Register updater channel for Sparkle auto-updates
    UpdaterChannel.register(with: flutterViewController.engine.registrar(forPlugin: "UpdaterChannel"))

    print("✅ MainFlutterWindow: VST3 platform integration registered")
    print("✅ MainFlutterWindow: Updater channel registered")

    super.awakeFromNib()

    observeTrafficLightLayout()
    repositionTrafficLights()
  }

  private func observeTrafficLightLayout() {
    // didUpdate is the catch-all: it fires after every window update, which
    // covers the title-bar relayout window_manager triggers at startup (no
    // dedicated notification for that). The check is a frame comparison, so
    // the cost is nil. The others make the common cases immediate.
    let names: [Notification.Name] = [
      NSWindow.didUpdateNotification,
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
    ]
    for name in names {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(trafficLightLayoutChanged(_:)),
        name: name,
        object: self)
    }
  }

  @objc private func trafficLightLayoutChanged(_ note: Notification) {
    repositionTrafficLights()
  }

  private func repositionTrafficLights() {
    // macOS hides the lights in full screen; leave them alone there and
    // re-nudge on exit (didExitFullScreen).
    guard !styleMask.contains(.fullScreen) else { return }
    let nudge = MainFlutterWindow.trafficLightNudge
    let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for type in types {
      guard let button = standardWindowButton(type) else { continue }
      let current = button.frame.origin
      let base: CGPoint
      if let known = trafficLightDefaultOrigins[type] {
        base = known
      } else {
        base = current
        trafficLightDefaultOrigins[type] = current
      }
      // AppKit's y axis points up: moving the light down is a smaller y.
      let target = CGPoint(x: base.x + nudge.x, y: base.y - nudge.y)
      if current != target {
        button.setFrameOrigin(target)
      }
    }
  }
}
