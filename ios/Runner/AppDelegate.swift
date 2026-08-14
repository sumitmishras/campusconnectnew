import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // `FlutterAppDelegate` implements `UNUserNotificationCenterDelegate` and
    // forwards every callback to the registered plugins, so this one line
    // serves both firebase_messaging (which needs the tap that opened the app)
    // and flutter_local_notifications (which needs the tap on the alert it
    // draws while the app is in the foreground). Setting either plugin as the
    // delegate directly would cut the other one out.
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
