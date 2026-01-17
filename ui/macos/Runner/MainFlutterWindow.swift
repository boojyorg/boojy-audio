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

    // Set minimum window size (800x600) for responsive panel layout
    self.minSize = NSSize(width: 800, height: 600)

    // Dark title bar appearance
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

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
