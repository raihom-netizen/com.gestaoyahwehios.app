import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Estilo iOS — banner/list/sound (paridade Controle Total).
class NotificationIosStyle {
  NotificationIosStyle._();

  /// Popup na tela (banner) — iOS 14+ exige presentBanner/presentList além de presentAlert.
  static DarwinNotificationDetails presentationDetails({
    String? subtitle,
    String? threadIdentifier,
    List<DarwinNotificationAttachment>? attachments,
    bool presentSound = true,
  }) {
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: presentSound,
      subtitle: subtitle,
      threadIdentifier: threadIdentifier,
      attachments: attachments,
    );
  }

  /// Permissão explícita do plugin local (complementa FirebaseMessaging.requestPermission).
  static Future<void> ensureLocalPermissions(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
}
