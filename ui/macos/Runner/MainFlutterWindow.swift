import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var vst3PlatformChannel: VST3PlatformChannel?

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

    // KNOWN ISSUE (deferred to v0.4): the window title is LEFT-aligned.
    // An empty NSToolbar with .unifiedCompact keeps the compact chrome height
    // but leading-aligns the title; .expanded centers it BUT adds an empty
    // toolbar row that makes the title bar noticeably taller. Neither native
    // option gives "centered + compact". Proper fix: hide the native title
    // (window_manager TitleBarStyle.hidden, keep the traffic lights) and draw a
    // centered title in Flutter as part of the top chrome.
    let toolbar = NSToolbar(identifier: "MainToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

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
  }
}
