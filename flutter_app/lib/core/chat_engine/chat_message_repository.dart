import 'dart:async' show StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/chat_engine/chat_engine_audit.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_local_cache_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/performance/stream_listener_registry.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Repositório de mensagens — paginação 30, realtime controlado, sem scan completo.
abstract final class ChatMessageRepository {
  ChatMessageRepository._();

  static const String timestampField = 'createdAt';
  static int get pageSize => FirebasePerformanceLimits.chatMessagesPage;
  static const int maxOlderPages = 50;

  static CollectionReference<Map<String, dynamic>> _messagesCol(
    String churchId,
    String chatId,
  ) =>
      ChurchFirestoreAccess.collectionRef(churchId, 'chats')
          .doc(chatId)
          .collection('messages');

  static String _cacheKey(String churchId, String chatId) =>
      'chat_engine_msgs_${churchId.trim()}_$chatId';

  static Query<Map<String, dynamic>> recentQuery({
    required String churchId,
    required String chatId,
    int? limit,
  }) =>
      _messagesCol(churchId, chatId)
          .orderBy(timestampField, descending: true)
          .limit(limit ?? pageSize);

  /// Cache local → rede. Nunca carrega histórico inteiro.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchRecentPage({
    required String churchId,
    required String chatId,
    int? limit,
  }) async {
    final sw = ChatEngineAudit.start('fetch_recent');
    final capped = limit ?? pageSize;
    try {
      await ChatLocalCacheEngine.loadMessagesPage(
        churchId: churchId,
        chatId: chatId,
      );
      final snap = await FirestoreReadResilience.getQuery(
        recentQuery(churchId: churchId, chatId: chatId, limit: capped),
        cacheKey: _cacheKey(churchId, chatId),
      );
      await ChatLocalCacheEngine.saveMessagesPage(
        churchId: churchId,
        chatId: chatId,
        docs: snap.docs,
      );
      ChatEngineAudit.end(sw, docs: snap.docs.length);
      return snap.docs;
    } catch (e) {
      ChatEngineAudit.end(sw, error: '$e');
      rethrow;
    }
  }

  /// Realtime da cauda (30) — 1 listener por conversa.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentTail({
    required String churchId,
    required String chatId,
    int? limit,
  }) {
    final q = recentQuery(churchId: churchId, chatId: chatId, limit: limit);
    return FirestoreStreamUtils.queryWatchBootstrap(q);
  }

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
      bindRecentTailListener({
    required String churchId,
    required String chatId,
    required void Function(QuerySnapshot<Map<String, dynamic>> snap) onData,
    void Function(Object error)? onError,
    int? limit,
  }) {
    final key = 'chat_msgs_${churchId}_$chatId';
    final sub = watchRecentTail(
      churchId: churchId,
      chatId: chatId,
      limit: limit,
    ).listen(
      (snap) {
        unawaited(
          ChatLocalCacheEngine.saveMessagesPage(
            churchId: churchId,
            chatId: chatId,
            docs: snap.docs,
          ),
        );
        onData(snap);
      },
      onError: onError,
    );
    StreamListenerRegistry.register(key: key, subscription: sub);
    return sub;
  }

  static Future<void> cancelListener(String churchId, String chatId) =>
      StreamListenerRegistry.cancel('chat_msgs_${churchId}_$chatId');

  /// Scroll infinito — `startAfter` sem baixar histórico completo.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderPage({
    required String churchId,
    required String chatId,
    required DocumentSnapshot<Map<String, dynamic>> startAfter,
    int? limit,
  }) async {
    final sw = ChatEngineAudit.start('load_older');
    try {
      final snap = await _messagesCol(churchId, chatId)
          .orderBy(timestampField, descending: true)
          .startAfterDocument(startAfter)
          .limit(limit ?? pageSize)
          .get();
      ChatEngineAudit.end(sw, docs: snap.docs.length);
      return snap.docs;
    } catch (e) {
      ChatEngineAudit.end(sw, error: '$e');
      rethrow;
    }
  }

  static List<ChatMessage> parseDocs(
    String churchId,
    String chatId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .map((d) => ChatMessage.fromDoc(churchId, chatId, d))
          .toList();

  static Future<DocumentReference<Map<String, dynamic>>> createMessage({
    required String churchId,
    required String chatId,
    required Map<String, dynamic> payload,
    String? messageId,
  }) async {
    final col = _messagesCol(churchId, chatId);
    if (kIsWeb) {
      return FirestoreWebGuard.runChatWriteWithRecovery(() async {
        if (messageId != null && messageId.isNotEmpty) {
          await col.doc(messageId).set(payload);
          return col.doc(messageId);
        }
        return col.add(payload);
      });
    }
    if (messageId != null && messageId.isNotEmpty) {
      await col.doc(messageId).set(payload);
      return col.doc(messageId);
    }
    return col.add(payload);
  }

  static Future<void> patchMessage({
    required String churchId,
    required String chatId,
    required String messageId,
    required Map<String, dynamic> patch,
    bool merge = true,
  }) async {
    final ref = _messagesCol(churchId, chatId).doc(messageId);
    if (kIsWeb) {
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => ref.set(patch, SetOptions(merge: merge)),
      );
      return;
    }
    await ref.set(patch, SetOptions(merge: merge));
  }

  static Future<void> deleteForEveryone({
    required String churchId,
    required String chatId,
    required String messageId,
  }) async {
    final ref = _messagesCol(churchId, chatId).doc(messageId);
    Map<String, dynamic>? before;
    try {
      final snap = await ref.get();
      before = snap.data();
    } catch (_) {}
    if (kIsWeb) {
      await FirestoreWebGuard.runChatWriteWithRecovery(() => ref.delete());
    } else {
      await ref.delete();
    }
    try {
      final u = FirebaseAuth.instance.currentUser;
      await ChurchFirestoreAccess.collectionRef(churchId, 'chat_audit').add({
        'action': 'message_deleted',
        'chatId': chatId,
        'messageId': messageId,
        'actorUid': u?.uid,
        'at': FieldValue.serverTimestamp(),
        if (before != null) ...{
          if (before['storagePath'] != null)
            'storagePath': before['storagePath'],
          if (before['thumbnailStoragePath'] != null)
            'thumbnailStoragePath': before['thumbnailStoragePath'],
        },
      });
    } catch (_) {}
  }

  static Future<void> hideForMe({
    required String churchId,
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    await patchMessage(
      churchId: churchId,
      chatId: chatId,
      messageId: messageId,
      patch: {
        'hiddenForUids': FieldValue.arrayUnion([uid]),
      },
    );
  }
}
