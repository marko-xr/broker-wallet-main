import UIKit
import Flutter
import FirebaseCore
import GoogleMaps 

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 1️⃣ Initialize Firebase
    FirebaseApp.configure()

    // 2️⃣ Initialize Google Maps SDK - USE THE SAME KEY AS ANDROID
    GMSServices.provideAPIKey("AIzaSyCRZjgq_0AxXDWyZ2a44EKnP7wHkFavmtE")

    // 3️⃣ Register all the Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // Scanner: mark the Scanner's private folder and working files as excluded
    // from iCloud / device backup (they hold the user's scanned documents).
    if let controller = window?.rootViewController as? FlutterViewController {
      let backupChannel = FlutterMethodChannel(
        name: "com.example.broker_wallet/backup_exclusion",
        binaryMessenger: controller.binaryMessenger)
      backupChannel.setMethodCallHandler { call, result in
        guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(FlutterError(code: "EXCLUDE_FAILED",
                              message: "Could not exclude the item from backup",
                              details: nil))
        }
      }
    }

    // 4️⃣ Continue with Flutter's startup
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}