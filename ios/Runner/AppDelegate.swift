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

    // 4️⃣ Continue with Flutter's startup
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}