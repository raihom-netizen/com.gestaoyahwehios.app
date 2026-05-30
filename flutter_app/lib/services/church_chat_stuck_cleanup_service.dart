import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_admin_purge_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';

/// Limpar no chat (padrão Controle Total): remove do **Firestore** stubs/filas antigas
/// (`uploading` / `queued` / `sending`), `chat_uploads` e `pending_uploads` — não só memória.
abstract final class ChurchChatStuckCleanupService {
  ChurchChatStuckCleanupService._();

  static const _stuckDelivery = [
    ChurchChatService.deliveryUploading,
    ChurchChatService.deliveryQueued,
    ChurchChatService.deliverySending,
  ];

  /// Gestor/pastor: apaga **todo** o histórico do chat da igreja no Firestore (Cloud Function).
  static Future<({
    int deletedMessages,
    int clearedThreads,
    int deletedUploads,
    int deletedPending,
  })> purgeEntireChatDatabase({
    required String tenantId,
    required String role,
    List<String>? permissions,
  }) async {
    if (!AppPermissions.canManageChurchMuralEventsAgenda(
      role,
      permissions: permissions,
    )) {
      throw StateError(
        'Só gestor, pastor ou administrador pode apagar todo o histórico do chat.',
      );
    }
    return ChurchChatAdminPurgeService.purgeAllMessagesForTenant(tenantId);
  }

  /// Retorno: mensagens apagadas + metadados de fila removidos.
  static Future<({int messages, int queueDocs})> purgeAllForTenant(
    String tenantId, {
    bool includeEntireDatabase = false,
    String? role,
    List<String>? permissions,
  }) async {
    if (includeEntireDatabase) {
      final full = await purgeEntireChatDatabase(
        tenantId: tenantId,
        role: role ?? '',
        permissions: permissions,
      );
      return (
        messages: full.deletedMessages,
        queueDocs: full.deletedUploads + full.deletedPending,
      );
    }
    final tid = tenantId.trim();
    if (tid.isEmpty) return (messages: 0, queueDocs: 0);

    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}

    var queueDocs = 0;
    queueDocs += await PendingUploadsFirestoreService.cancelAllOpenForTenant(tid);
    queueDocs +=
        await PendingUploadsFirestoreService.pruneUnrecoverableOpenForTenant(tid);
    queueDocs += await _purgeAllPendingUploadsDocsForCurrentUser(tid);
    queueDocs += await _purgeOpenChatUploads(tid);
    queueDocs += await ChurchChatMediaOutboxService.clearAllJobsWithFirestore(
      tenantId: tid,
    );
    StorageUploadQueueService.instance.clearPending();

    final messages = await _purgeStuckMessagesInThreads(tid);
    return (messages: messages, queueDocs: queueDocs);
  }

  static Future<int> _purgeAllPendingUploadsDocsForCurrentUser(
    String tenantId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('pending_uploads')
          .where('ownerUid', isEqualTo: uid)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return 0;
      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      var n = 0;
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        ops++;
        n++;
        if (ops >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      return n;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _purgeOpenChatUploads(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;
    final openStatuses = [
      ChurchChatUploadsService.statusQueued,
      ChurchChatUploadsService.statusUploading,
      ChurchChatUploadsService.statusWaitingNetwork,
      ChurchChatUploadsService.statusRetrying,
      ChurchChatUploadsService.statusFailed,
    ];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('chat_uploads')
          .where('ownerUid', isEqualTo: uid)
          .where('status', whereIn: openStatuses)
          .limit(120)
          .get();
      var removed = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        final threadId = (d['threadId'] ?? '').toString();
        final messageId = (d['messageId'] ?? '').toString();
        if (threadId.isNotEmpty && messageId.isNotEmpty) {
          await ChurchChatService.abandonMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: messageId,
          );
        }
        try {
          await doc.reference.delete();
          removed++;
        } catch (_) {}
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _purgeStuckMessagesInThreads(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;

    QuerySnapshot<Map<String, dynamic>> threadsSnap;
    try {
      threadsSnap = await ChurchChatService.chatThreadsQueryForUser(
        tenantId,
        uid,
      ).limit(80).get();
    } catch (_) {
      return 0;
    }

    var deleted = 0;
    for (final threadDoc in threadsSnap.docs) {
      final threadId = threadDoc.id;
      List<QueryDocumentSnapshot<Map<String, dynamic>>> msgDocs;
      try {
        final snap = await ChurchChatService.messagesCol(tenantId, threadId)
            .where('senderUid', isEqualTo: uid)
            .where('deliveryStatus', whereIn: _stuckDelivery)
            .limit(40)
            .get();
        msgDocs = snap.docs;
      } catch (_) {
        try {
          final snap = await ChurchChatService.messagesCol(tenantId, threadId)
              .orderBy('createdAt', descending: true)
              .limit(35)
              .get();
          msgDocs = snap.docs.where((d) {
            if ((d.data()['senderUid'] ?? '').toString() != uid) return false;
            final ds = (d.data()['deliveryStatus'] ?? '').toString();
            return _stuckDelivery.contains(ds);
          }).toList();
        } catch (_) {
          continue;
        }
      }

      for (final doc in msgDocs) {
        try {
          await doc.reference.delete();
          deleted++;
        } catch (_) {
          await ChurchChatService.abandonMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: doc.id,
          );
          deleted++;
        }
      }
    }
    return deleted;
  }
}
