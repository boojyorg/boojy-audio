import FlutterMacOS

/// Flutter Method Channel for updater functionality.
/// Bridges Dart code to the native Sparkle updater.
class UpdaterChannel {
    private static let channelName = "boojy_audio/updater"

    /// Register the method channel with the Flutter engine
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "checkForUpdates":
                SparkleUpdater.shared.checkForUpdates()
                result(nil)

            case "setAutoCheck":
                if let enabled = call.arguments as? Bool {
                    SparkleUpdater.shared.automaticallyChecksForUpdates = enabled
                    result(nil)
                } else {
                    result(FlutterError(
                        code: "INVALID_ARGUMENT",
                        message: "Expected boolean argument",
                        details: nil
                    ))
                }

            case "getAutoCheck":
                result(SparkleUpdater.shared.automaticallyChecksForUpdates)

            case "isUpdateInProgress":
                result(SparkleUpdater.shared.updateInProgress)

            case "getLastCheckDate":
                if let date = SparkleUpdater.shared.lastUpdateCheckDate {
                    result(date.timeIntervalSince1970 * 1000) // Return as milliseconds
                } else {
                    result(nil)
                }

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        print("UpdaterChannel: Registered method channel")
    }
}

/// Plugin registrant for the updater channel
class UpdaterChannelPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        UpdaterChannel.register(with: registrar)
    }
}
