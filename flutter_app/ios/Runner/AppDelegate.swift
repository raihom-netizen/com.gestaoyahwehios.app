import Flutter
import UIKit
import UserNotifications
import WidgetKit
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

private let widgetAppGroupId = "group.com.gestaoyahwehios.app.widget"
private let widgetKind = "GestaoYahwehWidget"
private let widgetJsonKey = "widget_events_json"

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.gestaoyahweh.app/deep_link"
  private var pendingDeepLinkPath: String?
  private var deepLinkChannel: FlutterMethodChannel?
  private var widgetSyncChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      pendingDeepLinkPath = Self.pathFrom(url: url)
    }
    // Banner/popup com app aberto (paridade Controle Total).
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    // Registra APNs cedo; o Flutter pede permissão e o FCM aguarda o token.
    application.registerForRemoteNotifications()

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
      registerWidgetSyncChannel(binaryMessenger: controller.binaryMessenger)
    }
    return ok
  }

  private func registerWidgetSyncChannel(binaryMessenger: FlutterBinaryMessenger) {
    if widgetSyncChannel != nil { return }
    let channel = FlutterMethodChannel(
      name: "gestaoyahweh/widget_sync",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "persistWidgetJson":
        guard let args = call.arguments as? [String: Any],
              let json = args["json"] as? String else {
          result(FlutterError(code: "bad_args", message: "json required", details: nil))
          return
        }
        let key = (args["key"] as? String) ?? widgetJsonKey
        self.persistWidgetJsonNative(key: key, json: json)
        result(true)
      case "forceWidgetRedraw":
        self.forceWidgetRedrawNative()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    widgetSyncChannel = channel
  }

  /// Grava JSON no App Group e recarrega timelines do widget.
  private func persistWidgetJsonNative(key: String, json: String) {
    if let defaults = UserDefaults(suiteName: widgetAppGroupId) {
      defaults.set(json, forKey: key)
      defaults.synchronize()
    }
    forceWidgetRedrawNative()
  }

  private func forceWidgetRedrawNative() {
    if let defaults = UserDefaults(suiteName: widgetAppGroupId) {
      defaults.synchronize()
    }
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  /// Banner/som na tela com app aberto (FCM + flutter_local_notifications).
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Garante que o FCM recebe o token APNs (mesmo se o swizzling falhar).
    #if canImport(FirebaseMessaging)
    Messaging.messaging().apnsToken = deviceToken
    #endif
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("GestaoYahweh APNs register failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
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
    // Deep link do widget: gestaoyahweh://module/N
    if url.scheme?.lowercased() == "gestaoyahweh" {
      let host = (url.host ?? "").lowercased()
      if host == "module" {
        let idx = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/module/\(idx)"
      }
      if !url.path.isEmpty {
        return url.path
      }
    }
    var path = url.path
    if path.isEmpty { path = "/" }
    if let query = url.query, !query.isEmpty {
      return "\(path)?\(query)"
    }
    return path
  }
}
