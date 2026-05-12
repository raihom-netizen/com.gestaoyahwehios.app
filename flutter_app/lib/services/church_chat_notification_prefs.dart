import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'church_chat_member_prefs.dart';
import 'fcm_service.dart';

/// Preferências de push do chat da igreja — alinhado a [users/{uid}.pushChat] e FCM `gypush_*_chat`.
class ChurchChatNotificationPrefs {
  ChurchChatNotificationPrefs._();

  static const String sharedPrefsKey = 'notif_chat';
  static const String sharedPrefsAlertModeKey = 'notif_chat_alert_mode';
  static const String _firestoreAlertModeField = 'pushChatAlertMode';

  static const String alertModeSound = 'sound';
  static const String alertModeVibrate = 'vibrate';
  static const String alertModeSilent = 'silent';

  static const Set<String> _validAlertModes = {
    alertModeSound,
    alertModeVibrate,
    alertModeSilent,
  };

  static bool looksLikeChatNotification(RemoteMessage msg) {
    final mod = msg.data['gy_module']?.toString().toLowerCase().trim();
    if (mod == 'chat') return true;
    final t = msg.data['type']?.toString().toLowerCase().trim() ?? '';
    const chatTypes = <String>{
      'novo_chat',
      'chat_message',
      'church_chat',
      'chat_dm',
      'chat_grupo',
    };
    return chatTypes.contains(t);
  }

  /// `true` = receber notificações de mensagens do chat (padrão ligado).
  /// Mesma prioridade que [FcmService.syncPreferencePushTopics]: Firestore, senão SharedPreferences.
  static Future<bool> isChatPushEnabled() async {
    var pushChat = true;
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
        final d = doc.data();
        if (d != null && d['pushChat'] is bool) {
          pushChat = d['pushChat'] as bool;
        }
      } catch (_) {
        try {
          final prefs = await SharedPreferences.getInstance();
          pushChat = prefs.getBool(sharedPrefsKey) ?? true;
        } catch (_) {}
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        pushChat = prefs.getBool(sharedPrefsKey) ?? true;
      } catch (_) {}
    }
    return pushChat;
  }

  /// Suprime o SnackBar em primeiro plano quando o utilizador silenciou o chat.
  static Future<bool> shouldSuppressForegroundSnack(RemoteMessage msg) async {
    if (!looksLikeChatNotification(msg)) return false;
    return !(await isChatPushEnabled());
  }

  static Future<void> setChatPushEnabled({
    required bool enabled,
    required String tenantId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sharedPrefsKey, enabled);
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(u.uid).set(
          {'pushChat': enabled},
          SetOptions(merge: true),
        );
      } catch (_) {}
      if (!kIsWeb) {
        await FcmService.instance.syncPreferencePushTopics(
          uid: u.uid,
          tenantId: tenantId,
        );
      }
    }
  }

  static String normalizeAlertMode(String raw) {
    final m = raw.trim().toLowerCase();
    if (_validAlertModes.contains(m)) return m;
    return alertModeSound;
  }

  /// Ordem: override por `threadId` → estilo DM ou grupo → modo global da conta.
  static Future<String> resolveForegroundAlertMode(RemoteMessage msg) async {
    if (!looksLikeChatNotification(msg)) return alertModeSound;
    final global = await getChatAlertMode();
    final tenantId = (msg.data['tenantId'] ?? '').toString().trim();
    final threadId = (msg.data['threadId'] ?? '').toString().trim();
    if (tenantId.isEmpty || threadId.isEmpty) return global;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return global;

    var threadType =
        (msg.data['threadType'] ?? '').toString().trim().toLowerCase();
    if (threadType.isEmpty) {
      threadType = threadId.startsWith('dm_') ? 'dm' : 'department';
    }
    final isDm = threadType == 'dm';

    try {
      final prefs = await ChurchChatMemberPrefs.load(tenantId);
      final ov = prefs.threadNotifOverride(threadId);
      if (ov != null && _validAlertModes.contains(ov)) return ov;
      if (isDm) {
        final dm = prefs.dmNotificationStyle;
        if (dm != null && _validAlertModes.contains(dm)) return dm;
      } else {
        final g = prefs.groupNotificationStyle;
        if (g != null && _validAlertModes.contains(g)) return g;
      }
    } catch (_) {}
    return global;
  }

  static Future<String> getChatAlertMode() async {
    var mode = alertModeSound;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final d = doc.data();
        final raw = d?[_firestoreAlertModeField];
        if (raw is String && raw.trim().isNotEmpty) {
          mode = normalizeAlertMode(raw);
        }
      } catch (_) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final local = prefs.getString(sharedPrefsAlertModeKey) ?? alertModeSound;
          mode = normalizeAlertMode(local);
        } catch (_) {}
      }
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final local = prefs.getString(sharedPrefsAlertModeKey) ?? alertModeSound;
        mode = normalizeAlertMode(local);
      } catch (_) {}
    }
    return mode;
  }

  static Future<void> setChatAlertMode({
    required String mode,
  }) async {
    final norm = normalizeAlertMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sharedPrefsAlertModeKey, norm);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {_firestoreAlertModeField: norm},
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }

  /// Feedback para mensagem de chat em primeiro plano, estilo conversa.
  static Future<void> playForegroundChatAlertIfNeeded(RemoteMessage msg) async {
    if (!looksLikeChatNotification(msg)) return;
    final mode = await resolveForegroundAlertMode(msg);
    if (mode == alertModeSilent) return;
    if (mode == alertModeVibrate) {
      await HapticFeedback.mediumImpact();
      return;
    }
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.lightImpact();
  }
}
