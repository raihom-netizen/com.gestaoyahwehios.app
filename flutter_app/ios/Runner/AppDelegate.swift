import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.gestaoyahweh.app/deep_link"
  private var pendingDeepLinkPath: String?
  private var deepLinkChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      pendingDeepLinkPath = Self.pathFrom(url: url)
    }
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: channelName,
        binaryMessenger: controller.binaryMessenger
      )
      deepLinkChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "getInitialPath":
          result(self?.pendingDeepLinkPath)
          self?.pendingDeepLinkPath = nil
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return ok
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let path = Self.pathFrom(url: url)
    if let path = path, let channel = deepLinkChannel {
      channel.invokeMethod("onDeepLink", arguments: path)
    } else {
      pendingDeepLinkPath = path
    }
    return super.application(app, open: url, options: options)
  }

  private static func pathFrom(url: URL) -> String? {
    var path = url.path
    if path.isEmpty { path = "/" }
    if let query = url.query, !query.isEmpty {
      return "\(path)?\(query)"
    }
    return path
  }
}
