import AVFoundation
import Flutter

/// Configures iOS AVAudioSession for background voice chat, Bluetooth headsets, and local music mixing.
final class BubbleAudioSessionPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.bubble/audio_session",
      binaryMessenger: registrar.messenger()
    )
    let instance = BubbleAudioSessionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "activateVoiceSession":
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playAndRecord,
          mode: .voiceChat,
          options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true)
        result(true)
      } catch {
        result(FlutterError(code: "AUDIO_SESSION_ERROR", message: error.localizedDescription, details: nil))
      }

    case "deactivateVoiceSession":
      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        result(true)
      } catch {
        result(false)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
