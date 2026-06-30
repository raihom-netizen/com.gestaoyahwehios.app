import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Repositório do chat — **única porta** para Firestore de mensagens/threads.
///
/// UI e controllers devem usar esta classe, não [ChurchChatService] directamente.
abstract final class ChatRepository {
  ChatRepository._();

  static const int defaultPageSize = ChurchChatService.defaultMessagePageSize;
  static const int maxOlderPages = ChurchChatService.maxOlderMessagePages;
  static const int threadsListLimit = YahwehPerformanceV4.chatThreadsListLimit;

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint);

  static DocumentReference<Map<String, dynamic>> threadDoc(
    String churchId,
    String threadId,
  ) =>
      ChurchChatService.threadRef(churchId, threadId);

  static CollectionReference<Map<String, dynamic>> chatsCollection(
    String churchId,
  ) =>
      ChurchUiCollections.chats(churchId);

  static CollectionReference<Map<String, dynamic>> messagesCollection(
    String churchId,
    String threadId,
  ) =>
      ChurchChatService.messagesCol(churchId, threadId);

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchRecentMessages({
    required String churchId,
    required String threadId,
    int pageSize = defaultPageSize,
  }) =>
          ChurchChatService.fetchRecentMessagesPage(
            tenantId: churchId,
            threadId: threadId,
            pageSize: pageSize,
          );

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentMessages({
    required String churchId,
    required String threadId,
    int pageSize = defaultPageSize,
  }) =>
      ChurchChatService.recentMessagesStream(
        tenantId: churchId,
        threadId: threadId,
        pageSize: pageSize,
      );

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadOlderMessages({
    required String churchId,
    required String threadId,
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int pageSize = defaultPageSize,
  }) =>
          ChurchChatService.loadOlderMessagesPage(
            tenantId: churchId,
            threadId: threadId,
            startAfterDoc: startAfterDoc,
            pageSize: pageSize,
          );

  static Future<bool> sendText({
    required String tenantId,
    required String threadId,
    required String text,
    Map<String, dynamic>? replyTo,
  }) =>
      ChurchChatService.sendTextMessage(
        tenantId: tenantId,
        threadId: threadId,
        text: text,
        replyTo: replyTo,
      );
}
