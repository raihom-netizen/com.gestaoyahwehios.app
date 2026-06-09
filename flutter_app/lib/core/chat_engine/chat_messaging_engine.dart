import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_engine_audit.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_engine_paths.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_local_cache_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_message_repository.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_presence_engine.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_thread_repository.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/church_chat_instant_send_service.dart';

/// **Motor de Mensagens** — porta única do Chat Igreja (estilo WhatsApp, sem adaptações).
///
/// Firestore: `igrejas/{churchId}/chats/{chatId}/messages`
/// Storage:   `igrejas/{churchId}/chat_media/{images|videos|audio|documents}/`
abstract final class ChatMessagingEngine {
  ChatMessagingEngine._();

  static int get messagesPageSize => FirebasePerformanceLimits.chatMessagesPage;
  static int get maxOlderPages => ChatMessageRepository.maxOlderPages;

  static String churchId([String? hint]) => ChatEnginePaths.resolveChurchId(hint);

  // ─── Leitura / realtime ───────────────────────────────────────────────────

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      openConversation({
    required String churchId,
    required String chatId,
  }) async {
    final sw = ChatEngineAudit.start('open_conversation');
    final cached = await ChatLocalCacheEngine.loadMessagesPage(
      churchId: churchId,
      chatId: chatId,
    );
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      unawaited(
        ChatPresenceEngine.markThreadRead(
          churchId: churchId,
          chatId: chatId,
          uid: uid,
        ),
      );
    }
    try {
      final fresh = await ChatMessageRepository.fetchRecentPage(
        churchId: churchId,
        chatId: chatId,
      );
      ChatEngineAudit.recordConversationOpen(
        DateTime.now().difference(sw.startedAt).inMilliseconds,
      );
      ChatEngineAudit.end(sw, docs: fresh.length);
      return fresh;
    } catch (e) {
      ChatEngineAudit.end(sw, docs: cached.length, fromCache: true, error: '$e');
      return cached;
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentMessages({
    required String churchId,
    required String chatId,
    int? pageSize,
  }) =>
      ChatMessageRepository.watchRecentTail(
        churchId: churchId,
        chatId: chatId,
        limit: pageSize,
      );

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchRecentMessagesPage({
    required String churchId,
    required String chatId,
    int? pageSize,
  }) =>
      ChatMessageRepository.fetchRecentPage(
        churchId: churchId,
        chatId: chatId,
        limit: pageSize,
      );

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderMessagesPage({
    required String churchId,
    required String chatId,
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int? pageSize,
  }) =>
      ChatMessageRepository.loadOlderPage(
        churchId: churchId,
        chatId: chatId,
        startAfter: startAfterDoc,
        limit: pageSize,
      );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchThread({
    required String churchId,
    required String chatId,
  }) =>
      ChatThreadRepository.watchThread(churchId: churchId, chatId: chatId);

  static Query<Map<String, dynamic>> threadsQueryForUser({
    required String churchId,
    required String uid,
    int? limit,
  }) =>
      ChatThreadRepository.threadsForUser(
        churchId: churchId,
        uid: uid,
        limit: limit,
      );

  static Future<Map<String, bool>> fetchPresenceOnlineMap({
    required String churchId,
    required Iterable<String> authUids,
  }) =>
      ChatPresenceEngine.fetchOnlineMap(
        churchId: churchId,
        authUids: authUids,
      );

  // ─── Envio otimista ─────────────────────────────────────────────────────────

  /// Texto: aparece instantâneo → Firestore → upload em background (se houver mídia depois).
  static void sendText({
    required String churchId,
    required String chatId,
    required String text,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    List<String>? mentionedUids,
    void Function(bool ok)? onComplete,
    void Function(String message)? onError,
  }) {
    ChurchChatInstantSendService.enqueueText(
      tenantId: churchId,
      threadId: chatId,
      text: text,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      senderDisplayName: senderDisplayName,
      mentionedUids: mentionedUids,
      onComplete: onComplete,
      onError: onError,
    );
  }

  // ─── Presença ─────────────────────────────────────────────────────────────

  static Future<void> setTyping({
    required String churchId,
    required String chatId,
    required String uid,
    String preview = '',
    bool recordingAudio = false,
  }) =>
      ChatPresenceEngine.setTyping(
        churchId: churchId,
        chatId: chatId,
        uid: uid,
        preview: preview,
        recordingAudio: recordingAudio,
      );

  static Future<void> clearTyping({
    required String churchId,
    required String chatId,
    required String uid,
  }) =>
      ChatPresenceEngine.clearTyping(
        churchId: churchId,
        chatId: chatId,
        uid: uid,
      );

  static String? typingLabel(
    Map<String, dynamic> threadData,
    String myUid, {
    Map<String, String>? namesByUid,
  }) =>
      ChatPresenceEngine.typingLabelFromThreadData(
        threadData,
        myUid,
        namesByUid: namesByUid,
      );

  // ─── Moderação / exclusão ─────────────────────────────────────────────────

  static Future<void> deleteMessageForEveryone({
    required String churchId,
    required String chatId,
    required String messageId,
  }) =>
      ChatMessageRepository.deleteForEveryone(
        churchId: churchId,
        chatId: chatId,
        messageId: messageId,
      );

  static Future<void> hideMessageForMe({
    required String churchId,
    required String chatId,
    required String messageId,
    required String uid,
  }) =>
      ChatMessageRepository.hideForMe(
        churchId: churchId,
        chatId: chatId,
        messageId: messageId,
        uid: uid,
      );

  static Future<void> hideThreadForUser({
    required String churchId,
    required String chatId,
    required String uid,
  }) =>
      ChatThreadRepository.hideThreadForUser(
        churchId: churchId,
        chatId: chatId,
        uid: uid,
      );

  static Future<void> clearConversationLocal({
    required String churchId,
    required String chatId,
  }) =>
      ChatLocalCacheEngine.clearConversationLocal(
        churchId: churchId,
        chatId: chatId,
      );

  // ─── Grupos ───────────────────────────────────────────────────────────────

  static Future<String> createGroup({
    required String churchId,
    required String nome,
    required List<String> participants,
    required List<String> admins,
    String? foto,
  }) =>
      ChatThreadRepository.createGroup(
        churchId: churchId,
        nome: nome,
        participants: participants,
        admins: admins,
        foto: foto,
      );

  static Future<void> updateGroup({
    required String churchId,
    required String chatId,
    String? nome,
    String? foto,
    List<String>? participants,
    List<String>? admins,
  }) =>
      ChatThreadRepository.updateGroup(
        churchId: churchId,
        chatId: chatId,
        nome: nome,
        foto: foto,
        participants: participants,
        admins: admins,
      );

  static Future<void> deleteGroupForEveryone({
    required String churchId,
    required String chatId,
    required String actorUid,
  }) =>
      ChatThreadRepository.deleteGroupForEveryone(
        churchId: churchId,
        chatId: chatId,
        actorUid: actorUid,
      );

  // ─── Storage paths ────────────────────────────────────────────────────────

  static String mediaStoragePath({
    required String churchId,
    required String chatId,
    required ChatMessageType type,
    required String uid,
    required int timestampMs,
    required String fileName,
  }) =>
      ChatEnginePaths.buildMediaObjectPath(
        churchId: churchId,
        chatId: chatId,
        type: type,
        uid: uid,
        timestampMs: timestampMs,
        fileName: fileName,
      );

  static String thumbnailStoragePath({
    required String churchId,
    required String uid,
    required int timestampMs,
    String suffix = 'thumb',
  }) =>
      ChatEnginePaths.buildThumbnailPath(
        churchId: churchId,
        uid: uid,
        timestampMs: timestampMs,
        suffix: suffix,
      );

  // ─── Auditoria ────────────────────────────────────────────────────────────

  static String auditReport() => ChatEngineAudit.toReport();

  static List<ChatMessage> parseMessages(
    String churchId,
    String chatId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      ChatMessageRepository.parseDocs(churchId, chatId, docs);
}
