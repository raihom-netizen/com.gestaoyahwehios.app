import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Recentes locais (por igreja) para emojis e figurinhas no chat.
class ChurchChatExpressionPrefs {
  ChurchChatExpressionPrefs._();

  static String _stickersKey(String tenantId) =>
      'church_chat_recent_stickers_v1_${tenantId.trim()}';

  static String _emojisKey(String tenantId) =>
      'church_chat_recent_emojis_v1_${tenantId.trim()}';

  static Future<List<Map<String, dynamic>>> recentStickers(
      String tenantId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_stickersKey(tenantId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> rememberStickerSent({
    required String tenantId,
    required String mediaUrl,
    String? storagePath,
    required String stickerSource,
  }) async {
    final url = mediaUrl.trim();
    if (url.isEmpty) return;
    var list = await recentStickers(tenantId);
    final sp = storagePath?.trim() ?? '';
    list.removeWhere((m) => (m['mediaUrl'] ?? '').toString() == url);
    list.insert(0, {
      'mediaUrl': url,
      'storagePath': sp,
      'stickerSource': stickerSource,
    });
    while (list.length > 18) {
      list.removeLast();
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_stickersKey(tenantId), jsonEncode(list));
  }

  static Future<List<String>> recentEmojis(String tenantId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_emojisKey(tenantId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> rememberEmoji(String tenantId, String emojiChar) async {
    final c = emojiChar.trim();
    if (c.isEmpty) return;
    var list = await recentEmojis(tenantId);
    list.removeWhere((e) => e == c);
    list.insert(0, c);
    if (list.length > 28) {
      list = list.sublist(0, 28);
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_emojisKey(tenantId), jsonEncode(list));
  }
}
