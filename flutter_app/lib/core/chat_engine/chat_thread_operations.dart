import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_message_repository.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

export 'package:gestao_yahweh/services/church_chat_service.dart'
    show ChurchChatTypingActivity;

/// Operações da conversa (thread) — porta UI; implementação em [ChurchChatService].
abstract final class ChatThreadOperations {
  ChatThreadOperations._();

  // ─── Entrega / typing ───────────────────────────────────────────────────────
  static const String deliveryUploading = ChurchChatService.deliveryUploading;
  static const String deliverySending = ChurchChatService.deliverySending;
  static const String deliveryQueued = ChurchChatService.deliveryQueued;
  static const String deliverySent = ChurchChatService.deliverySent;
  static const String deliveryRead = ChurchChatService.deliveryRead;
  static const String typingLabelRecording = ChurchChatService.typingLabelRecording;
  static int get maxOlderMessagePages => ChurchChatService.maxOlderMessagePages;

  static String formatInstantSendError(Object e) =>
      ChurchChatService.formatInstantSendError(e);

  static String senderDisplayNameForNewMessage() =>
      ChurchChatService.senderDisplayNameForNewMessage();

  // ─── Streams / leitura ──────────────────────────────────────────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> recentMessagesStream({
    required String tenantId,
    required String threadId,
    int pageSize = ChurchChatService.defaultMessagePageSize,
  }) =>
      ChurchChatService.recentMessagesStream(
        tenantId: tenantId,
        threadId: threadId,
        pageSize: pageSize,
      );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> threadSnapshots(
    String tenantId,
    String threadId,
  ) =>
      ChurchChatService.threadSnapshots(tenantId, threadId);

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderMessagesPage({
    required String tenantId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int pageSize = ChurchChatService.defaultMessagePageSize,
  }) =>
      ChurchChatService.loadOlderMessagesPage(
        tenantId: tenantId,
        threadId: threadId,
        startAfterDoc: startAfterDoc,
        pageSize: pageSize,
      );

  // ─── Presença / leitura do thread ─────────────────────────────────────────
  static Future<void> markThreadLastSeen({
    required String tenantId,
    required String threadId,
  }) =>
      ChurchChatService.markThreadLastSeen(
        tenantId: tenantId,
        threadId: threadId,
      );

  static Future<void> markOutboundMessagesReadUpTo({
    required String tenantId,
    required String threadId,
    required DateTime peerSeenAt,
  }) =>
      ChurchChatService.markOutboundMessagesReadUpTo(
        tenantId: tenantId,
        threadId: threadId,
        peerSeenAt: peerSeenAt,
      );

  static Future<Map<String, bool>> fetchPresenceOnlineMap({
    required String tenantId,
    required Iterable<String> authUids,
  }) =>
      ChurchChatService.fetchPresenceOnlineMap(
        tenantId: tenantId,
        authUids: authUids,
      );

  // ─── Typing ─────────────────────────────────────────────────────────────────
  static Future<void> setTypingActive({
    required String tenantId,
    required String threadId,
    required bool active,
    String? displayLabel,
  }) =>
      ChurchChatService.setTypingActive(
        tenantId: tenantId,
        threadId: threadId,
        active: active,
        displayLabel: displayLabel,
      );

  static Future<void> clearTypingForMe({
    required String tenantId,
    required String threadId,
  }) =>
      ChurchChatService.clearTypingForMe(
        tenantId: tenantId,
        threadId: threadId,
      );

  static Future<ChurchChatTypingActivity> fetchActiveTyping({
    required String tenantId,
    required String threadId,
    required String myUid,
  }) =>
      ChurchChatService.fetchActiveTyping(
        tenantId: tenantId,
        threadId: threadId,
        myUid: myUid,
      );

  // ─── Mensagens ──────────────────────────────────────────────────────────────
  static bool messageHiddenForMe(Map<String, dynamic> m, String uid) =>
      ChurchChatService.messageHiddenForMe(m, uid);

  static Future<bool> hideMessageForMe({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) =>
      ChurchChatService.hideMessageForMe(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );

  static Future<bool> deleteMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) async {
    try {
      await ChatMessageRepository.deleteForEveryone(
        churchId: tenantId,
        chatId: threadId,
        messageId: messageId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setMyReactionOnMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
    String? emoji,
  }) =>
      ChurchChatService.setMyReactionOnMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        emoji: emoji,
      );

  // ─── Mídia ──────────────────────────────────────────────────────────────────
  static Future<({String messageId, String storagePath})> beginMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String kind,
    String? fileName,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? forwardedFrom,
    String? senderDisplayName,
    String? albumGroupId,
    int albumIndex = 0,
    int albumCount = 1,
  }) =>
      ChurchChatService.beginMediaUploadMessage(
        tenantId: tenantId,
        threadId: threadId,
        kind: kind,
        fileName: fileName,
        replyTo: replyTo,
        forwardedFrom: forwardedFrom,
        senderDisplayName: senderDisplayName,
        albumGroupId: albumGroupId,
        albumIndex: albumIndex,
        albumCount: albumCount,
      );

  static Future<void> patchMediaUploadProgress({
    required String tenantId,
    required String threadId,
    required String messageId,
    required double progress,
    bool force = false,
  }) =>
      ChurchChatService.patchMediaUploadProgress(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
        progress: progress,
        force: force,
      );

  static Future<void> abandonMediaUploadMessage({
    required String tenantId,
    required String threadId,
    required String messageId,
  }) =>
      ChurchChatService.abandonMediaUploadMessage(
        tenantId: tenantId,
        threadId: threadId,
        messageId: messageId,
      );

  // ─── Grupo / departamento ───────────────────────────────────────────────────
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchActiveDepartmentMembers({
    required String tenantId,
    required String departmentId,
  }) =>
      ChurchChatService.fetchActiveDepartmentMembers(
        tenantId: tenantId,
        departmentId: departmentId,
      );

  static Future<bool> deleteGroupThread({
    required String tenantId,
    required String threadId,
  }) =>
      ChurchChatService.deleteGroupThread(
        tenantId: tenantId,
        threadId: threadId,
      );

  /// Limpa TODAS as mensagens (e mídia no Storage via CF) — DM ou grupo.
  static Future<bool> purgeThreadMessagesCompletely({
    required String tenantId,
    required String threadId,
  }) =>
      ChurchChatService.purgeThreadMessagesCompletely(
        tenantId: tenantId,
        threadId: threadId,
      );
}
