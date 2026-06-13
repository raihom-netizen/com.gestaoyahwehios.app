import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/chat_strict_publish_service.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Recuperação automática de mensagens presas (`sending` / `uploading` / `queued`).
///
/// Não apaga histórico — tenta `sent` (texto) ou `abandon` (mídia sem URL).
abstract final class ChurchChatAutoRecoveryService {
  ChurchChatAutoRecoveryService._();

  static const Duration _stuckOlderThan = Duration(minutes: 12);

  static const _stuckStatuses = [
    ChurchChatService.deliverySending,
    ChurchChatService.deliveryUploading,
    ChurchChatService.deliveryQueued,
  ];

  /// Arranque / resume — leve, por tenant do utilizador.
  static Future<void> recoverOnSessionStart() async {
    try {
      await ensureFirebaseReadyForChatSend();
      final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
      if (uid.isEmpty) return;
      final tenantId = (ChurchContext.currentChurchId ?? '').trim();
      if (tenantId.isEmpty) return;
      YahwehFlowLog.chatStart();
      final n = await recoverStuckForTenant(tenantId, uid: uid);
      await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
      if (n > 0) {
        YahwehFlowLog.chatAutoRecover(n);
      }
      YahwehFlowLog.chatSuccess();
    } catch (e, st) {
      YahwehFlowLog.error('CHAT', e, st);
    }
  }

  /// Ao abrir um thread — recupera envios presos desta conversa (cutoff mais curto).
  static Future<int> recoverStuckForThread({
    required String tenantId,
    required String threadId,
    required String uid,
    Duration maxAge = const Duration(minutes: 4),
  }) async {
    if (tenantId.trim().isEmpty || threadId.trim().isEmpty || uid.isEmpty) {
      return 0;
    }
    final cutoff = DateTime.now().subtract(maxAge);
    var fixed = 0;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> stuck;
    try {
      final snap = await ChurchChatService.messagesCol(tenantId, threadId)
          .where('senderUid', isEqualTo: uid)
          .where('deliveryStatus', whereIn: _stuckStatuses)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      stuck = snap.docs;
    } catch (_) {
      try {
        final snap = await ChurchChatService.messagesCol(tenantId, threadId)
            .orderBy('createdAt', descending: true)
            .limit(25)
            .get();
        stuck = snap.docs.where((d) {
          final data = d.data();
          if ((data['senderUid'] ?? '').toString() != uid) return false;
          final ds =
              (data['deliveryStatus'] ?? data['status'] ?? '').toString();
          return _stuckStatuses.contains(ds);
        }).toList();
      } catch (e, st) {
        YahwehFlowLog.error('CHAT', e, st);
        return 0;
      }
    }

    for (final doc in stuck) {
      final data = doc.data();
      final created = data['createdAt'];
      final type = (data['type'] ?? 'text').toString();
      final mediaUrl = (data['mediaUrl'] ?? data['fileUrl'] ?? '').toString();

      // Storage OK mas Firestore ainda em uploading — finaliza sem esperar cutoff.
      if (type != 'text' &&
          ChurchChatMessageFields.isUploadInProgress(data)) {
        final sp = ChurchChatMessageFields.storagePath(data);
        if (sp.isNotEmpty) {
          final finalized = await ChatStrictPublishService.tryFinalizeIfStorageReady(
            tenantId: tenantId,
            threadId: threadId,
            messageId: doc.id,
            data: data,
          );
          if (finalized) {
            fixed++;
            continue;
          }
        }
      }

      if (created is Timestamp && created.toDate().isAfter(cutoff)) {
        continue;
      }
      if (mediaUrl.trim().isNotEmpty) {
        try {
          await FirestoreWebGuard.runWithWebRecovery(() => doc.reference.update({
                'deliveryStatus': ChurchChatService.deliverySent,
                'status': ChurchChatService.deliverySent,
                'uploadProgress': 1,
              }));
          fixed++;
          continue;
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
        }
      }
      if (type != 'text') {
        try {
          await ChurchChatService.abandonMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: doc.id,
          );
          fixed++;
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
        }
      }
    }
    return fixed;
  }

  static Future<int> recoverStuckForTenant(
    String tenantId, {
    required String uid,
  }) async {
    final cutoff = DateTime.now().subtract(_stuckOlderThan);
    var fixed = 0;

    QuerySnapshot<Map<String, dynamic>> threadsSnap;
    try {
      threadsSnap = await ChurchChatService.chatThreadsQueryForUser(
        tenantId,
        uid,
      ).limit(40).get();
    } catch (e, st) {
      YahwehFlowLog.error('CHAT', e, st);
      return 0;
    }

    for (final threadDoc in threadsSnap.docs) {
      final threadId = threadDoc.id;
      List<QueryDocumentSnapshot<Map<String, dynamic>>> stuck;
      try {
        final snap = await ChurchChatService.messagesCol(tenantId, threadId)
            .where('senderUid', isEqualTo: uid)
            .where('deliveryStatus', whereIn: _stuckStatuses)
            .orderBy('createdAt', descending: true)
            .limit(25)
            .get();
        stuck = snap.docs;
      } catch (_) {
        try {
          final snap = await ChurchChatService.messagesCol(tenantId, threadId)
              .orderBy('createdAt', descending: true)
              .limit(30)
              .get();
          stuck = snap.docs.where((d) {
            final data = d.data();
            if ((data['senderUid'] ?? '').toString() != uid) return false;
            final ds = (data['deliveryStatus'] ?? data['status'] ?? '')
                .toString();
            return _stuckStatuses.contains(ds);
          }).toList();
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
          continue;
        }
      }

      for (final doc in stuck) {
        final data = doc.data();
        final created = data['createdAt'];
        final type = (data['type'] ?? 'text').toString();
        final ds = (data['deliveryStatus'] ?? '').toString();
        final text = (data['text'] ?? '').toString();
        final mediaUrl = (data['mediaUrl'] ?? data['fileUrl'] ?? '').toString();

        if (type != 'text' &&
            ChurchChatMessageFields.isUploadInProgress(data)) {
          final sp = ChurchChatMessageFields.storagePath(data);
          if (sp.isNotEmpty) {
            final finalized =
                await ChatStrictPublishService.tryFinalizeIfStorageReady(
              tenantId: tenantId,
              threadId: threadId,
              messageId: doc.id,
              data: data,
            );
            if (finalized) {
              fixed++;
              continue;
            }
          }
        }

        if (created is Timestamp) {
          if (created.toDate().isAfter(cutoff)) continue;
        }

        if (type == 'text' && text.trim().isNotEmpty) {
          try {
            await doc.reference.update({
              'deliveryStatus': ChurchChatService.deliverySent,
              'status': ChurchChatService.deliverySent,
            });
            fixed++;
            continue;
          } catch (e, st) {
            YahwehFlowLog.error('CHAT', e, st);
          }
        }

        if (mediaUrl.trim().isNotEmpty) {
          try {
            await doc.reference.update({
              'deliveryStatus': ChurchChatService.deliverySent,
              'status': ChurchChatService.deliverySent,
              'uploadProgress': 1,
            });
            fixed++;
            continue;
          } catch (e, st) {
            YahwehFlowLog.error('CHAT', e, st);
          }
        }

        if (ds == ChurchChatService.deliverySending && text.trim().isNotEmpty) {
          try {
            await ChurchChatService.finalizeTextMessage(
              tenantId: tenantId,
              threadId: threadId,
              messageId: doc.id,
              text: text,
            );
            fixed++;
            continue;
          } catch (_) {}
        }

        try {
          await ChurchChatService.abandonMediaUploadMessage(
            tenantId: tenantId,
            threadId: threadId,
            messageId: doc.id,
          );
          fixed++;
        } catch (e, st) {
          YahwehFlowLog.error('CHAT', e, st);
        }
      }
    }

    await _closeOrphanChatUploads(tenantId, uid);
    return fixed;
  }

  static Future<void> _closeOrphanChatUploads(String tenantId, String uid) async {
    try {
      final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
      final snap = await           ChurchOperationalPaths.churchDoc(op)
          .collection('chat_uploads')
          .where('ownerUid', isEqualTo: uid)
          .where(
            'status',
            whereIn: [
              ChurchChatUploadsService.statusQueued,
              ChurchChatUploadsService.statusUploading,
              ChurchChatUploadsService.statusRetrying,
            ],
          )
          .limit(40)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final updated = d['updatedAt'];
        if (updated is Timestamp &&
            updated.toDate().isAfter(DateTime.now().subtract(_stuckOlderThan))) {
          continue;
        }
        await doc.reference.delete();
      }
    } catch (e, st) {
      YahwehFlowLog.error('CHAT', e, st);
    }
  }
}
