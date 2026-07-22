import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gestao_yahweh/services/notification_ios_style.dart';

/// Canais Android para push do painel (avisos, eventos, escalas, cadastros, aniversários).
/// Alinhado a `notificationBranding.ts` → `gy_fcm_panel_default`.
class PanelNotificationService {
  PanelNotificationService._();
  static final PanelNotificationService instance = PanelNotificationService._();

  static const String fcmAndroidChannelId = 'gy_fcm_panel_default';

  bool _bootChannelsReady = false;
  FlutterLocalNotificationsPlugin? _plugin;

  Future<FlutterLocalNotificationsPlugin> _pluginReady() async {
    if (_plugin != null) return _plugin!;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _plugin = plugin;
    return plugin;
  }

  Future<void> registerAndroidChannelsForBoot() async {
    if (_bootChannelsReady) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final plugin = await _pluginReady();
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
    final plugin = await _pluginReady();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? true;
  }

  /// iOS — permissão do plugin local (banner/list), paridade Controle Total.
  Future<void> ensureIosLocalNotificationPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final plugin = await _pluginReady();
    await NotificationIosStyle.ensureLocalPermissions(plugin);
  }
}
