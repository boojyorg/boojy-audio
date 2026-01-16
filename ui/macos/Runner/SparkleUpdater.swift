import Cocoa
import Sparkle

/// Wrapper class for Sparkle update functionality.
/// Provides a singleton interface for checking updates and configuring auto-update settings.
class SparkleUpdater: NSObject {
    static let shared = SparkleUpdater()

    private var updaterController: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // Initialize Sparkle with automatic update checking enabled
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Trigger a manual check for updates (shows UI)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether to automatically check for updates on launch
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether an update check is currently in progress
    var updateInProgress: Bool {
        return updaterController.updater.sessionInProgress
    }

    /// The last time an update check was performed
    var lastUpdateCheckDate: Date? {
        return updaterController.updater.lastUpdateCheckDate
    }
}
