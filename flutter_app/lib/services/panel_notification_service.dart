import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canais Android para push do painel (avisos, eventos, escalas, cadastros, aniversários).
/// Alinhado a `notificationBranding.ts` → `gy_fcm_panel_default`.
class PanelNotificationService {
  PanelNotificationService._();
  static final PanelNotificationService instance = PanelNotificationService._();

  static const String fcmAndroidChannelId = 'gy_fcm_panel_default';

  bool _bootChannelsReady = false;

  Future<void> registerAndroidChannelsForBoot() async {
    if (_bootChannelsReady) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        fcmAndroidChannelId,
        'Painel da igreja',
        description:
            'Avisos, eventos, escalas, cadastros e aniversários (Gestão YAHWEH).',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    _bootChannelsReady = true;
  }

  /// Android 13+ — permissão explícita além do [FirebaseMessaging.requestPermission].
  Future<bool> ensureAndroidPostNotificationsPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? true;
  }
}
