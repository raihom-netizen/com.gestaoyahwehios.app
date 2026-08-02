import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_credentials.dart';
import 'package:libtdjson/libtdjson.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistência mínima para o isolate de background reabrir a sessão TDLib.
abstract final class TdlibBackgroundPushStore {
  TdlibBackgroundPushStore._();

  static const churchIdKey = 'tdlib_bg_church_id';
  static const dbDirKey = 'tdlib_bg_db_dir';
  static const filesDirKey = 'tdlib_bg_files_dir';

  static Future<void> saveSessionPaths({
    required String churchId,
    required String dbDir,
    required String filesDir,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(churchIdKey, churchId.trim());
    await prefs.setString(dbDirKey, dbDir);
    await prefs.setString(filesDirKey, filesDir);
  }
}

/// Handler FCM com app em background / morto — processa payload TDLib e notifica.
@pragma('vm:entry-point')
Future<void> tdlibFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  try {
    await loadTdlibDotEnv();
  } catch (_) {}

  final payload = _extractPayload(message);
  if (payload == null || payload.isEmpty) {
    await _showPlainRemote(message);
    return;
  }

  try {
    await _processWithTdlib(payload, message);
  } catch (e) {
    debugPrint('[TdlibBG] process falhou: $e');
    await _showPlainRemote(message);
  }
}

String? _extractPayload(RemoteMessage message) {
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

Future<void> _showPlainRemote(RemoteMessage message) async {
  final title = (message.notification?.title ??
          message.data['title'] ??
          'Yahweh Chat')
      .toString()
      .trim();
  final body = (message.notification?.body ??
          message.data['body'] ??
          message.data['message'] ??
          'Nova mensagem')
      .toString()
      .trim();
  await _showLocal(title: title, body: body);
}

Future<void> _showLocal({
  required String title,
  required String body,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  const android = AndroidNotificationDetails(
    'gy_tdlib_push',
    'Yahweh Chat (Telegram)',
    channelDescription: 'Mensagens Telegram via TDLib',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
  );
  const ios = DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentList: true,
    presentBadge: true,
    presentSound: true,
  );
  await plugin.show(
    id: DateTime.now().millisecondsSinceEpoch % 1000000,
    title: title.isEmpty ? 'Yahweh Chat' : title,
    body: body.isEmpty ? 'Nova mensagem' : body,
    notificationDetails: const NotificationDetails(android: android, iOS: ios),
    payload: 'tdlib_bg',
  );
}

Future<void> _processWithTdlib(String payload, RemoteMessage message) async {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;

  final prefs = await SharedPreferences.getInstance();
  var dbDir = (prefs.getString(TdlibBackgroundPushStore.dbDirKey) ?? '').trim();
  var filesDir =
      (prefs.getString(TdlibBackgroundPushStore.filesDirKey) ?? '').trim();
  final churchId =
      (prefs.getString(TdlibBackgroundPushStore.churchIdKey) ?? '').trim();

  if (dbDir.isEmpty || filesDir.isEmpty) {
    final support = await getApplicationSupportDirectory();
    final key = churchId.isEmpty ? 'default' : churchId;
    dbDir = p.join(support.path, 'tdlib', key, 'db');
    filesDir = p.join(support.path, 'tdlib', key, 'files');
  }

  await Directory(dbDir).create(recursive: true);
  await Directory(filesDir).create(recursive: true);

  if (!kTelegramCredentialsConfigured) {
    await ensureTelegramCredentialsLoaded();
  }
  if (!kTelegramCredentialsConfigured) {
    await _showPlainRemote(message);
    return;
  }

  final completer = Completer<void>();
  String? notifTitle;
  String? notifBody;

  final params = <String, dynamic>{
    'api_id': telegramApiId,
    'api_hash': telegramApiHash,
    'database_directory': dbDir,
    'files_directory': filesDir,
    'use_file_database': true,
    'use_chat_info_database': true,
    'use_message_database': true,
    'use_secret_chats': false,
    'system_language_code': 'pt-br',
    'device_model': Platform.isIOS ? 'iPhone' : 'Android',
    'system_version': Platform.operatingSystemVersion,
    'application_version': '11.2.305',
  };

  final useProcess = Platform.isIOS || Platform.isMacOS;
  late final td.Service svc;
  svc = td.Service(
    tdlibParameters: params,
    file: useProcess ? null : 'libtdjson.so',
    newVerbosityLevel: 0,
    timeout: 8,
    start: true,
    afterReceive: (obj) {
      final type = obj['@type']?.toString();
      if (type == 'updateNotificationGroup') {
        final chatId = obj['chat_id'];
        notifTitle = 'Yahweh Chat';
        final added = obj['added_notifications'];
        if (added is List && added.isNotEmpty) {
          notifBody = 'Nova mensagem';
          for (final raw in added) {
            if (raw is! Map) continue;
            final t = raw['type'];
            if (t is Map) {
              final content = t['content'] ?? t['message'];
              if (content is Map) {
                final text = content['text'];
                if (text is Map && (text['text'] ?? '').toString().isNotEmpty) {
                  notifBody = text['text'].toString();
                }
              }
            }
          }
        }
        if (chatId != null) {
          notifTitle = 'Chat $chatId';
        }
        if (!completer.isCompleted) completer.complete();
      }
    },
    onReceiveError: (_) {},
    onStreamError: (_) {},
  );

  try {
    await svc.sendSync({
      '@type': 'setOption',
      'name': 'notification_group_count_max',
      'value': {'@type': 'optionValueInteger', 'value': 25},
    });
    await svc.sendSync({
      '@type': 'setOption',
      'name': 'notification_group_size_max',
      'value': {'@type': 'optionValueInteger', 'value': 10},
    });
    await svc.sendSync({
      '@type': 'processPushNotification',
      'payload': payload,
    });
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );
  } finally {
    try {
      await svc.stop();
    } catch (_) {}
  }

  if ((notifBody ?? '').isNotEmpty) {
    await _showLocal(
      title: (notifTitle ?? 'Yahweh Chat').trim(),
      body: notifBody!.trim(),
    );
  } else {
    await _showPlainRemote(message);
  }
}
