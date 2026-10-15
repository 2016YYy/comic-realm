import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "comic_realm/cookies", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "getCookies",
              let url = call.arguments as? [String: Any],
              let urlString = url["url"] as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let nsUrl = URL(string: urlString) else {
          result([])
          return
        }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
          let filtered = cookies.filter { cookie in
            nsUrl.host?.hasSuffix(cookie.domain) == true || cookie.domain.hasSuffix(nsUrl.host ?? "")
          }
          let resultArray = filtered.map { "\($0.name)=\($0.value)" }
          result(resultArray)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
