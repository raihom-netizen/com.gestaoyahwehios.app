import 'dart:convert';

import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mute / arquivo / rascunho / cache de lista — locais por igreja + chat TDLib.
abstract final class TdlibChatLocalPrefs {
  TdlibChatLocalPrefs._();

  static String _k(String churchId, String kind, int chatId) =>
      'tdlib_${kind}_${churchId.trim()}_$chatId';

  static String _listKey(String churchId) =>
      'tdlib_chatlist_${churchId.trim()}';

  static String _syncedPhoneKey(String churchId, int chatId) =>
      'tdlib_synced_phones_${churchId.trim()}_$chatId';

  static Future<bool> isMuted(String churchId, int chatId) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_k(churchId, 'mute', chatId)) ?? false;
  }

  static Future<void> setMuted(String churchId, int chatId, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k(churchId, 'mute', chatId), value);
  }

  static Future<bool> isArchived(String churchId, int chatId) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_k(churchId, 'arch', chatId)) ?? false;
  }

  static Future<void> setArchived(
    String churchId,
    int chatId,
    bool value,
  ) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k(churchId, 'arch', chatId), value);
  }

  static Future<String> getDraft(String churchId, int chatId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_k(churchId, 'draft', chatId)) ?? '';
  }

  static Future<void> setDraft(
    String churchId,
    int chatId,
    String text,
  ) async {
    final p = await SharedPreferences.getInstance();
    final t = text.trim();
    final key = _k(churchId, 'draft', chatId);
    if (t.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, text);
    }
  }

  static Future<void> saveChatList(
    String churchId,
    List<TdlibChatPreview> chats,
  ) async {
    final p = await SharedPreferences.getInstance();
    final payload = chats.take(80).map((c) => c.toJson()).toList();
    await p.setString(_listKey(churchId), jsonEncode(payload));
  }

  static Future<List<TdlibChatPreview>> loadChatList(String churchId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_listKey(churchId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => TdlibChatPreview.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.id != 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<Set<String>> getSyncedPhones(
    String churchId,
    int chatId,
  ) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_syncedPhoneKey(churchId, chatId)) ?? const [];
    return list.toSet();
  }

  static Future<void> markPhonesSynced(
    String churchId,
    int chatId,
    Iterable<String> phones,
  ) async {
    final p = await SharedPreferences.getInstance();
    final key = _syncedPhoneKey(churchId, chatId);
    final next = {...(p.getStringList(key) ?? const []), ...phones};
    await p.setStringList(key, next.toList());
  }

  static String _churchOnlyKey(String churchId) =>
      'tdlib_church_only_${churchId.trim()}';

  static Future<bool> isChurchOnlyMode(String churchId) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_churchOnlyKey(churchId)) ?? true;
  }

  static Future<void> setChurchOnlyMode(String churchId, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_churchOnlyKey(churchId), value);
  }

  static Future<void> setLastSyncAt(String churchId, DateTime at) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'tdlib_last_sync_${churchId.trim()}',
      at.toIso8601String(),
    );
  }

  static Future<String?> getLastSyncAt(String churchId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('tdlib_last_sync_${churchId.trim()}');
  }
}
