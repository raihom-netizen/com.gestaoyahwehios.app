import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Operações do hub (DM, grupos, departamentos) — porta única do Chat Igreja.
abstract final class ChatHubOperations {
  ChatHubOperations._();

  static String dmThreadId(String uidA, String uidB) =>
      ChurchChatService.dmThreadId(uidA, uidB);

  static String deptThreadId(String departmentId) =>
      ChurchChatService.deptThreadId(departmentId);

  static String? otherUidInDmThread(String threadId, String myUid) =>
      ChurchChatService.otherUidInDmThread(threadId, myUid);

  static bool userParticipatesInThread({
    required String threadId,
    required Map<String, dynamic> data,
    required String uid,
  }) =>
      ChurchChatService.userParticipatesInThread(
        threadId: threadId,
        data: data,
        uid: uid,
      );

  static bool threadHasListableConversation(
    Map<String, dynamic> data, {
    String? threadId,
  }) =>
      ChurchChatService.threadHasListableConversation(data, threadId: threadId);

  static DocumentReference<Map<String, dynamic>> threadRef(
    String tenantId,
    String threadId,
  ) =>
      ChurchUiCollections.chats(tenantId).doc(threadId);

  static Future<void> ensureDmThread({
    required String tenantId,
    required String uidA,
    required String uidB,
    required String titleA,
    required String titleB,
  }) =>
      ChurchChatService.ensureDmThread(
        tenantId: tenantId,
        uidA: uidA,
        uidB: uidB,
        titleA: titleA,
        titleB: titleB,
      );

  static Future<bool> ensureDmThreadResilient({
    required String tenantId,
    required String uidA,
    required String uidB,
    required String titleA,
    required String titleB,
  }) =>
      ChurchChatService.ensureDmThreadResilient(
        tenantId: tenantId,
        uidA: uidA,
        uidB: uidB,
        titleA: titleA,
        titleB: titleB,
      );

  static Future<void> ensureDepartmentThread({
    required String tenantId,
    required String departmentId,
    required String departmentName,
    required List<String> participantUids,
  }) =>
      ChurchChatService.ensureDepartmentThread(
        tenantId: tenantId,
        departmentId: departmentId,
        departmentName: departmentName,
        participantUids: participantUids,
      );

  static Future<int> syncDmThreadsIndex(String tenantId) =>
      ChurchChatService.syncDmThreadsIndex(tenantId);

  static Future<QuerySnapshot<Map<String, dynamic>>> loadDmThreadsSnapshotFallback({
    required String tenantId,
    required String uid,
  }) =>
      ChurchChatService.loadDmThreadsSnapshotFallback(
        tenantId: tenantId,
        uid: uid,
      );

  static Future<int> threadUnreadInboundCount({
    required String tenantId,
    required String threadId,
    required String myUid,
    Timestamp? myLastSeenInThread,
    int scanLimit = 60,
  }) =>
      ChurchChatService.threadUnreadInboundCount(
        tenantId: tenantId,
        threadId: threadId,
        myUid: myUid,
        myLastSeenInThread: myLastSeenInThread,
        scanLimit: scanLimit,
      );

  static Future<void> syncUserChatProfile({
    required String tenantId,
    required List<String> departmentIds,
    String? memberDocId,
  }) =>
      ChurchChatService.syncUserChatProfile(
        tenantId: tenantId,
        departmentIds: departmentIds,
        memberDocId: memberDocId,
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
