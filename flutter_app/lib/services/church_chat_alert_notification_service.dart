import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gestao_yahweh/services/notification_ios_style.dart';

import 'church_chat_notification_prefs.dart';

/// Alertas locais (foreground) para conversas, com modos:
/// sound | vibrate | silent.
///
/// **Push em segundo plano (FCM):** o servidor usa os mesmos modos e envia
/// `android.notification.channelId` (`gy_fcm_chat_*`) + APNS (`sound` / `apns-interruption-level`).
/// Os canais Android são criados aqui e no arranque da app (`registerFcmChatAndroidChannelsForBoot`).
///
/// Para som custom (estilo WhatsApp) no **foreground**, adicione:
/// - Android: `android/app/src/main/res/raw/chat_whatsapp.mp3`
/// - iOS: `Runner/chat_whatsapp.aiff` (incluir no target)
class ChurchChatAlertNotificationService {
  ChurchChatAlertNotificationService._();
  static final ChurchChatAlertNotificationService instance =
      ChurchChatAlertNotificationService._();

  /// Canais Android para **FCM** (segundo plano) — alinhados a `churchChatNotify.ts` / `notificationBranding.ts`.
  static const String fcmAndroidChannelSound = 'gy_fcm_chat_sound';
  static const String fcmAndroidChannelVibrate = 'gy_fcm_chat_vibrate';
  static const String fcmAndroidChannelSilent = 'gy_fcm_chat_silent';

  static const String _channelSoundId = 'chat_alert_sound_channel';
  static const String _channelVibrateId = 'chat_alert_vibrate_channel';
  static const String _channelSilentId = 'chat_alert_silent_channel';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Garante canais `gy_fcm_chat_*` no Android **antes** do primeiro push (cold start).
  /// Não pede permissões iOS (só Android).
  Future<void> registerFcmChatAndroidChannelsForBoot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final boot = FlutterLocalNotificationsPlugin();
    await boot.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final androidImpl = boot.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;
    await _createFcmAndroidChatChannels(androidImpl);
  }

  static Future<void> _createFcmAndroidChatChannels(
    AndroidFlutterLocalNotificationsPlugin androidImpl,
  ) async {
    await androidImpl.createNotificationChannel(
      const AndroidNotificationChannel(
        fcmAndroidChannelSound,
        'Chat — som (Super Premium · push)',
        description:
            'Mensagens do chat em segundo plano com som do sistema (FCM).',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidImpl.createNotificationChannel(
      const AndroidNotificationChannel(
        fcmAndroidChannelVibrate,
        'Chat — vibrar (push)',
        description: 'Push do chat sem som, só vibração.',
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
      ),
    );
    await androidImpl.createNotificationChannel(
      const AndroidNotificationChannel(
        fcmAndroidChannelSilent,
        'Chat — silencioso (push)',
        description: 'Push do chat sem som nem vibração.',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: initSettings);

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelSoundId,
          'Conversas (som)',
          description: 'Notificações de chat com som e vibração.',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('chat_whatsapp'),
          enableVibration: true,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelVibrateId,
          'Conversas (vibrar)',
          description: 'Notificações de chat sem som, apenas vibração.',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelSilentId,
          'Conversas (silencioso)',
          description: 'Notificações de chat silenciosas.',
          importance: Importance.defaultImportance,
          playSound: false,
          enableVibration: false,
        ),
      );
      await _createFcmAndroidChatChannels(androidImpl);
    }

    final iosImpl =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  /// `true` se mostrou notificação local (som/vibrar) — o painel pode evitar SnackBar duplicado.
  Future<bool> showForegroundAlertIfNeeded(RemoteMessage msg) async {
    if (!ChurchChatNotificationPrefs.looksLikeChatNotification(msg)) return false;
    if (kIsWeb) return false;

    final mode = await ChurchChatNotificationPrefs.resolveForegroundAlertMode(msg);
    if (mode == ChurchChatNotificationPrefs.alertModeSilent) return false;

    await _ensureInitialized();

    final title = (msg.notification?.title ?? 'Nova mensagem').trim();
    final body = (msg.notification?.body ?? 'Você recebeu nova mensagem').trim();

    late final AndroidNotificationDetails androidDetails;
    late final DarwinNotificationDetails iosDetails;
    if (mode == ChurchChatNotificationPrefs.alertModeVibrate) {
      androidDetails = const AndroidNotificationDetails(
        _channelVibrateId,
        'Conversas (vibrar)',
        channelDescription: 'Notificações de chat sem som, apenas vibração.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: false,
        enableVibration: true,
      );
      iosDetails = NotificationIosStyle.presentationDetails(
        presentSound: false,
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        _channelSoundId,
        'Conversas (som)',
        channelDescription: 'Notificações de chat com som e vibração.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chat_whatsapp'),
        enableVibration: true,
      );
      iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: true,
        sound: 'chat_whatsapp.aiff',
      );
    }

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: title.isEmpty ? 'Nova mensagem' : title,
      body: body.isEmpty ? 'Você recebeu nova mensagem' : body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      ),
      payload: 'chat_foreground',
    );
    return true;
  }
}

