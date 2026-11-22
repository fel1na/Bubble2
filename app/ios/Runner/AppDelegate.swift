import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let audioRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "BubbleAudioSessionPlugin") {
      BubbleAudioSessionPlugin.register(with: audioRegistrar)
    }
    if let multipeerRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "BubbleMultipeerPlugin") {
      BubbleMultipeerPlugin.register(with: multipeerRegistrar)
    }
  }
}
