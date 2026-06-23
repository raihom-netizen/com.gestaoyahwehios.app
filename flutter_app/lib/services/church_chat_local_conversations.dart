import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// Cache local da lista Â«ConversasÂ» â€” equivalente a `userChats/{uid}` no spec.
///
/// Garante que threads com mensagens enviadas **permanecem visÃ­veis** mesmo se o
/// stream Firestore falhar temporariamente. SÃ³ some com Â«Apagar conversaÂ» (hidden).
class ChurchChatLocalConversationEntry {
  const ChurchChatLocalConversationEntry({
    required this.threadId,
    required this.peerUid,
    required this.displayName,
    required this.lastMessage,
    required this.lastMessageType,
    required this.lastMessageAtMs,
    required this.lastSenderUid,
  });

  final String threadId;
  final String peerUid;
  final String displayName;
  final String lastMessage;
  final String lastMessageType;
  final int lastMessageAtMs;
  final String lastSenderUid;

  Map<String, dynamic> toJson() => {
        'threadId': threadId,
        'peerUid': peerUid,
        'displayName': displayName,
        'lastMessage': lastMessage,
        'lastMessageType': lastMessageType,
        'lastMessageAtMs': lastMessageAtMs,
        'lastSenderUid': lastSenderUid,
      };

  static ChurchChatLocalConversationEntry? fromJson(Map<String, dynamic>? m) {
    if (m == null) return null;
    final threadId = (m['threadId'] ?? '').toString().trim();
    if (threadId.isEmpty) return null;
    return ChurchChatLocalConversationEntry(
      threadId: threadId,
      peerUid: (m['peerUid'] ?? '').toString().trim(),
      displayName: (m['displayName'] ?? '').toString().trim(),
      lastMessage: (m['lastMessage'] ?? '').toString(),
      lastMessageType: (m['lastMessageType'] ?? 'text').toString(),
      lastMessageAtMs: (m['lastMessageAtMs'] is num)
          ? (m['lastMessageAtMs'] as num).toInt()
          : 0,
      lastSenderUid: (m['lastSenderUid'] ?? '').toString().trim(),
    );
  }
}

/// Notifica o hub para recarregar a lista local.
abstract final class ChurchChatLocalConversations {
  ChurchChatLocalConversations._();

  static const int _maxEntries = 160;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String _prefsKey(String tenantId, String uid) =>
      'church_chat_local_conv_v1_${tenantId}_$uid';

  /// Grava/atualiza apÃ³s qualquer envio (texto, foto, vÃ­deo, Ã¡udio).
  static Future<void> recordFromOutbound({
    required String tenantId,
    required String myUid,
    required String threadId,
    required String preview,
    required String messageType,
    String? peerUid,
    String? displayName,
  }) async {
    final uid = myUid.trim();
    final tid = threadId.trim();
    if (uid.isEmpty || tid.isEmpty || !tid.startsWith('dm_')) return;

    final peer = (peerUid ?? ChurchChatService.otherUidInDmThread(tid, uid) ?? '')
        .trim();
    final name = (displayName ?? '').trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = preview.trim().isEmpty ? 'Mensagem' : preview.trim();

    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(tenantId, uid);
    final list = await _readList(prefs, key);
    final byId = {for (final e in list) e.threadId: e};
    byId[tid] = ChurchChatLocalConversationEntry(
      threadId: tid,
      peerUid: peer,
      displayName: name.isNotEmpty ? name : (byId[tid]?.displayName ?? peer),
      lastMessage: msg.length > 120 ? '${msg.substring(0, 117)}â€¦' : msg,
      lastMessageType: messageType,
      lastMessageAtMs: now,
      lastSenderUid: uid,
    );
    final sorted = byId.values.toList()
      ..sort((a, b) => b.lastMessageAtMs.compareTo(a.lastMessageAtMs));
    final capped = sorted.take(_maxEntries).toList();
    await prefs.setString(
      key,
      jsonEncode(capped.map((e) => e.toJson()).toList()),
    );
    revision.value++;
  }

  static Future<List<ChurchChatLocalConversationEntry>> listForUser({
    required String tenantId,
    String? uid,
  }) async {
    final u = (uid ?? firebaseDefaultAuth.currentUser?.uid ?? '').trim();
    if (u.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs, _prefsKey(tenantId, u));
  }

  static Future<void> remove({
    required String tenantId,
    required String threadId,
    String? uid,
  }) async {
    final u = (uid ?? firebaseDefaultAuth.currentUser?.uid ?? '').trim();
    if (u.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(tenantId, u);
    final list = await _readList(prefs, key);
    final next = list.where((e) => e.threadId != threadId).toList();
    if (next.length == list.length) return;
    await prefs.setString(
      key,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
    revision.value++;
  }

  static Future<List<ChurchChatLocalConversationEntry>> _readList(
    SharedPreferences prefs,
    String key,
  ) async {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <ChurchChatLocalConversationEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final e = ChurchChatLocalConversationEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (e != null) out.add(e);
        }
      }
      out.sort((a, b) => b.lastMessageAtMs.compareTo(a.lastMessageAtMs));
      return out;
    } catch (_) {
      return [];
    }
  }
}

