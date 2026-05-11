import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'church_chat_notification_prefs.dart';

/// Alertas locais (foreground) para conversas, com modos:
/// sound | vibrate | silent.
///
/// Para som custom (estilo WhatsApp), adicione:
/// - Android: `android/app/src/main/res/raw/chat_whatsapp.mp3`
/// - iOS: `Runner/chat_whatsapp.aiff` (incluir no target)
class ChurchChatAlertNotificationService {
  ChurchChatAlertNotificationService._();
  static final ChurchChatAlertNotificationService instance =
      ChurchChatAlertNotificationService._();

  static const String _channelSoundId = 'chat_alert_sound_channel';
  static const String _channelVibrateId = 'chat_alert_vibrate_channel';
  static const String _channelSilentId = 'chat_alert_silent_channel';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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

  Future<void> showForegroundAlertIfNeeded(RemoteMessage msg) async {
    if (!ChurchChatNotificationPrefs.looksLikeChatNotification(msg)) return;
    if (kIsWeb) return;

    final mode = await ChurchChatNotificationPrefs.getChatAlertMode();
    if (mode == ChurchChatNotificationPrefs.alertModeSilent) return;

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
      iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
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
  }
}

