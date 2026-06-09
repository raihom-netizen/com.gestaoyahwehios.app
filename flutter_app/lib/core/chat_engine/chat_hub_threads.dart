import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Stream da lista de conversas do hub — delega merge DM/index do serviço legado.
abstract final class ChatHubThreads {
  ChatHubThreads._();

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchForUser({
    required String churchId,
    required String uid,
  }) =>
      ChurchChatService.chatThreadsSnapshotsForUser(
        churchId.trim(),
        uid.trim(),
      );

  static void invalidateStreamCache({
    String? churchId,
    String? uid,
  }) =>
      ChurchChatService.invalidateChatThreadsStreamCache(
        tenantId: churchId,
        uid: uid,
      );
}
