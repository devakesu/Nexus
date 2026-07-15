import Flutter
import GoogleMaps
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // TODO: Replace with a real Google Maps Platform API key before shipping
    // chat location sharing - see AndroidManifest.xml for the Android side.
    GMSServices.provideAPIKey("AIzaSyDbTXQUK7Frxicc5CSaD4X9A9xCzga8toM")

    // Lets the periodic prekey-replenish background task (registered from
    // Dart in background_prekey_task.dart) reach other plugins - notably
    // flutter_secure_storage, which the Supabase session and Signal key
    // vault both depend on - from its own background isolate/engine.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
