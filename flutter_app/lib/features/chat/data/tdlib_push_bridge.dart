import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/services/church_chat_alert_notification_service.dart';

/// Ponte FCM/APNs ↔ TDLib Notification API (foreground + registo).
abstract final class TdlibPushBridge {
  TdlibPushBridge._();

  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<String>? _tokenSub;
  static bool _hooked = false;

  static Future<void> onTdlibReady() async {
    if (kIsWeb || !TdLibService.instance.isSupported) return;
    if (TdLibService.instance.currentAuth.phase != TdlibAuthPhase.ready) {
      return;
    }
    try {
      await TdLibService.instance.configureNotificationOptions();
      String? apnsHex;
      var sandbox = false;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null && apns.isNotEmpty) {
            apnsHex = apns;
            sandbox = kDebugMode;
          }
        } catch (_) {}
      }
      final token = await FirebaseMessaging.instance.getToken();
      await TdLibService.instance.registerPushDevice(
        token ?? '',
        apnsTokenHex: apnsHex,
        apnsSandbox: sandbox,
      );
      await _tokenSub?.cancel();
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        unawaited(
          TdLibService.instance.registerPushDevice(
            t,
            apnsTokenHex: apnsHex,
            apnsSandbox: sandbox,
          ),
        );
      });
    } catch (e) {
      debugPrint('[TdlibPush] register: $e');
    }
    _hookForeground();
  }

  static void _hookForeground() {
    if (_hooked) return;
    _hooked = true;
    _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen((msg) {
      unawaited(handleRemoteMessage(msg));
    });
  }

  static Future<void> handleRemoteMessage(RemoteMessage message) async {
    if (kIsWeb || !TdLibService.instance.isSupported) return;
    if (TdLibService.instance.currentAuth.phase != TdlibAuthPhase.ready) {
      return;
    }
    final payload = _payloadForTdlib(message);
    if (payload == null || payload.isEmpty) return;
    try {
      await TdLibService.instance.processPushNotification(payload);
    } catch (e) {
      debugPrint('[TdlibPush] process: $e');
      final title =
          (message.notification?.title ?? 'Yahweh Chat').toString().trim();
      final body = (message.notification?.body ?? 'Nova mensagem')
          .toString()
          .trim();
      await ChurchChatAlertNotificationService.instance.showTdlibLocalAlert(
        title: title,
        body: body,
        chatId: 0,
      );
    }
  }

  static String? _payloadForTdlib(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return null;
    final raw = data['payload'] ?? data['p'] ?? data['data'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    try {
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }
}
