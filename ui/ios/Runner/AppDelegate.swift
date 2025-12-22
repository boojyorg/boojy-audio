import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure audio session for low-latency audio playback and recording
    configureAudioSession()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      // Set category for playback and recording with options:
      // - defaultToSpeaker: Route audio to speaker by default
      // - allowBluetooth: Allow Bluetooth audio devices
      // - allowBluetoothA2DP: Allow high-quality Bluetooth audio
      // - mixWithOthers: Don't interrupt other audio apps
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
      )

      // Set preferred buffer duration for low latency (5ms = 0.005 seconds)
      // Lower values = lower latency but higher CPU usage
      try session.setPreferredIOBufferDuration(0.005)

      // Set preferred sample rate to 48kHz (matches Boojy Audio engine)
      try session.setPreferredSampleRate(48000)

      // Activate the audio session
      try session.setActive(true)

      print("🎵 [Boojy Audio] Audio session configured successfully")
      print("   Buffer duration: \(session.ioBufferDuration * 1000)ms")
      print("   Sample rate: \(session.sampleRate)Hz")
    } catch {
      print("❌ [Boojy Audio] Audio session setup failed: \(error)")
    }
  }

  // Handle audio session interruptions (phone calls, alarms, etc.)
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)

    // Reactivate audio session when app becomes active
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("⚠️ [Boojy Audio] Failed to reactivate audio session: \(error)")
    }
  }
}
