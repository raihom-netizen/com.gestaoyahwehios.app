import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/services/upload_bytes_core.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Fila por igreja: `igrejas/{tenantId}/pending_uploads/{id}`.
/// A coleção raiz `pendingUploads` está descontinuada (legado — migrar/apagar).
abstract final class PendingUploadsFirestoreService {
  PendingUploadsFirestoreService._();

  /// Legado — só para UI/migração; não escrever novos docs na raiz.
  static const String legacyRootCollectionId = 'pendingUploads';

  static Future<void> _ensureReady() async {
    await ensureFirebaseReadyForMediaUpload();
  }

  static CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection('pending_uploads');

  static String? tenantFromStoragePath(String storagePath) =>
      FeedTenantStorageMap.tenantIdFromStoragePath(storagePath);

  static YahwehUploadModule moduleFromStoragePath(String storagePath) =>
      YahwehMediaUploadPipeline.moduleFromStoragePath(storagePath);

  /// Regista job pendente (Firestore tenant + disco local no mobile).
  static Future<String> enqueue({
    required String tenantId,
    required String module,
    required String storagePath,
    String? localPath,
    String contentType = 'application/octet-stream',
    double progress = 0,
    String status = 'pending',
    Map<String, dynamic>? meta,
  }) async {
    await _ensureReady();
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sessão expirada. Entre de novo no painel.');
    }
    final id = '${DateTime.now().millisecondsSinceEpoch}_${uid.hashCode.abs()}';
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
        unawaited(
          StorageUploadPersistenceService.enqueueFileJob(
            storagePath: storagePath,
            localFilePath: localPath,
            contentType: contentType,
          ),
        );
      }
      return id;
    }
    final alias = FeedTenantStorageMap.canonicalIgrejasPathHint(storagePath);
    final data = <String, dynamic>{
      'id': id,
      'userId': uid,
      'ownerUid': uid,
      'tenantId': tenantId,
      'module': module,
      'type': module,
      'storagePath': storagePath,
      'status': status,
      'progress': progress,
      'contentType': contentType,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath,
      if (alias != null && alias.isNotEmpty) 'canonicalPathHint': alias,
      if (meta != null) ...meta,
    };
    await _col(tenantId).doc(id).set(data);
    if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      unawaited(
        StorageUploadPersistenceService.enqueueFileJob(
          storagePath: storagePath,
          localFilePath: localPath,
          contentType: contentType,
        ),
      );
    }
    return id;
  }

  static Future<String?> findOpenJobId(
    String tenantId,
    String storagePath,
  ) async {
    if (tenantId.isEmpty || storagePath.isEmpty) return null;
    await _ensureReady();
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return null;
    try {
      final snap = await _col(tenantId)
          .where('ownerUid', isEqualTo: uid)
          .where('storagePath', isEqualTo: storagePath)
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        final st = (doc.data()['status'] ?? '').toString();
        if (st == 'pending' ||
            st == 'failed' ||
            st == 'uploading' ||
            st == 'queued') {
          return doc.id;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> recordQueuedBytesUpload({
    required String tenantId,
    required String module,
    required String storagePath,
    String? localPath,
    String contentType = 'application/octet-stream',
    Map<String, dynamic>? meta,
  }) async {
    if (tenantId.isEmpty) return null;
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) return null;
    try {
      final existing = await findOpenJobId(tenantId, storagePath);
      if (existing != null) {
        await markProgress(tenantId, existing, progress: 0, status: 'queued');
        return existing;
      }
      return await enqueue(
        tenantId: tenantId,
        module: module,
        storagePath: storagePath,
        localPath: localPath,
        contentType: contentType,
        status: 'queued',
        meta: {
          'source': 'offline_queue',
          if (meta != null) ...meta,
        },
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> markProgress(
    String tenantId,
    String uploadId, {
    required double progress,
    String status = 'uploading',
  }) async {
    final patch = {
      'progress': progress.clamp(0.0, 1.0),
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col(tenantId).doc(uploadId).set(patch, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> markCompleted(String tenantId, String uploadId) async {
    try {
      await _col(tenantId).doc(uploadId).delete();
    } catch (_) {}
  }

  static Future<void> cancelJob(String tenantId, String uploadId) async {
    if (tenantId.isEmpty || uploadId.isEmpty) return;
    try {
      await _col(tenantId).doc(uploadId).delete();
    } catch (_) {}
  }

  static Future<void> markFailed(
    String tenantId,
    String uploadId,
    Object error,
  ) async {
    final patch = {
      'status': 'failed',
      'lastError': error.toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col(tenantId).doc(uploadId).set(patch, SetOptions(merge: true));
    } catch (_) {}
    unawaited(
      CrashlyticsService.record(error, StackTrace.current, reason: 'pending_upload'),
    );
  }

  /// Contagem de jobs abertos do utilizador actual (tenant).
  static Future<int> countOpenForTenant(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;
    try {
      final snap = await _col(tenantId)
          .where('ownerUid', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'failed', 'uploading', 'queued'])
          .limit(30)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Stream de jobs abertos (painel / banner).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchOpenForTenant(
    String tenantId,
  ) {
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      return const Stream.empty();
    }
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (tenantId.isEmpty || uid.isEmpty) {
      return const Stream.empty();
    }
    return _col(tenantId)
        .where('ownerUid', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'failed', 'uploading', 'queued'])
        .limit(25)
        .watchSafe();
  }

  /// Remove registos antigos de `pending_uploads` (builds com fila Firestore ligada).
  static Future<int> purgeAllLegacyOpenForTenant(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    await _ensureReady();
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;
    var total = 0;
    for (var wave = 0; wave < 30; wave++) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _col(tenantId)
            .where('ownerUid', isEqualTo: uid)
            .limit(100)
            .get();
      } catch (_) {
        break;
      }
      if (snap.docs.isEmpty) break;
      await _abandonChatStubsFromPendingDocs(tenantId, snap.docs);
      var batch = firebaseDefaultFirestore.batch();
      var ops = 0;
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        ops++;
        total++;
        if (ops >= 400) {
          await batch.commit();
          batch = firebaseDefaultFirestore.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      if (snap.docs.length < 100) break;
    }
    return total;
  }

  /// Todas as igrejas — collection group `pending_uploads` (Master vê tudo).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAllTenantsPendingIndex({
    bool masterSeeAll = false,
    int limit = 40,
  }) {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return const Stream.empty();
    final group =
        firebaseDefaultFirestore.collectionGroup('pending_uploads');
    if (masterSeeAll) {
      return group.limit(limit).watchSafe();
    }
    return group.where('ownerUid', isEqualTo: uid).limit(limit).watchSafe();
  }

  /// @deprecated Use [watchAllTenantsPendingIndex].
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchGlobalIndex({
    bool masterSeeAll = false,
    int limit = 40,
  }) =>
      watchAllTenantsPendingIndex(
        masterSeeAll: masterSeeAll,
        limit: limit,
      );

  static Future<void> resumeAllForTenant(String tenantId) async {
    if (tenantId.isEmpty) return;
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) return;
    await ensureFirebaseReadyForMediaUpload();
    final snap = await _col(tenantId)
        .where('status', whereIn: ['pending', 'failed', 'uploading', 'queued'])
        .limit(20)
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      final storagePath = (d['storagePath'] ?? '').toString();
      final localPath = (d['localPath'] ?? '').toString();
      final contentType =
          (d['contentType'] ?? 'application/octet-stream').toString();
      if (storagePath.isEmpty) continue;
      try {
        await markProgress(tenantId, doc.id, progress: 0.05, status: 'uploading');
        Uint8List? bytes;
        if (!kIsWeb && localPath.isNotEmpty) {
          final f = File(localPath);
          if (await f.exists()) {
            bytes = await f.readAsBytes();
          }
        }
        if (bytes == null || bytes.isEmpty) {
          final meta = d['meta'];
          if (meta is Map) {
            final threadId = (meta['threadId'] ?? '').toString();
            final localId = (meta['localId'] ?? '').toString();
            if (threadId.isNotEmpty && localId.isNotEmpty) {
              bytes = await ChurchChatPendingMediaCache.get(
                tenantId: tenantId,
                threadId: threadId,
                localId: localId,
              );
            }
          }
        }
        if (bytes != null && bytes.isNotEmpty) {
          await uploadStoragePutDataWithRetry(
            storagePath: storagePath,
            bytes: bytes,
            contentType: contentType,
            maxAttempts: 3,
            useOfflineQueue: false,
            localFilePathForRetry: localPath.isNotEmpty ? localPath : null,
          );
          if (!kIsWeb && localPath.isNotEmpty) {
            try {
              await File(localPath).delete();
            } catch (_) {}
          }
          await markCompleted(tenantId, doc.id);
        } else if (kIsWeb) {
          await markFailed(
            tenantId,
            doc.id,
            StateError('Sem ficheiro na web — use Limpar ou reenvie da conversa.'),
          );
        }
      } catch (e, st) {
        await markFailed(tenantId, doc.id, e);
        if (kDebugMode) {
          debugPrint('PendingUploads resume ${doc.id}: $e\n$st');
        }
      }
    }
  }

  static Future<String?> resolveTenantForCurrentUser() async {
    await _ensureReady();
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return null;
    return _resolveTenantId(user.uid);
  }

  static Future<void> resumeForCurrentUserTenant() async {
    try {
      await _ensureReady();
      final user = firebaseDefaultAuth.currentUser;
      if (user == null || user.isAnonymous) return;
      final tenant = await _resolveTenantId(user.uid);
      if (tenant == null || tenant.isEmpty) return;
      await resumeAllForTenant(tenant);
      if (!kIsWeb) {
        await StorageUploadPersistenceService.resumePendingOnAppStart();
      }
    } catch (e, st) {
      await CrashlyticsService.record(e, st, reason: 'pending_uploads_resume');
    }
  }

  static Future<String?> _resolveTenantId(String uid) async {
    final u = await firebaseDefaultFirestore.doc('users/$uid').get();
    final data = u.data();
    if (data == null) return null;
    final t = data['tenantId'] ?? data['igrejaId'];
    return t?.toString();
  }

  static Future<void> recordFailedBytesUpload({
    required String tenantId,
    required String module,
    required String storagePath,
    required Object error,
    String? localPath,
    String contentType = 'application/octet-stream',
    Map<String, dynamic>? meta,
  }) async {
    if (!FirebaseUploadPolicy.firestorePendingQueueEnabled) return;
    try {
      final existing = await findOpenJobId(tenantId, storagePath);
      if (existing != null) {
        await markFailed(tenantId, existing, error);
        return;
      }
      final id = await enqueue(
        tenantId: tenantId,
        module: module,
        storagePath: storagePath,
        localPath: localPath,
        contentType: contentType,
        status: 'failed',
        meta: {
          'lastError': error.toString(),
          if (meta != null) ...meta,
        },
      );
      await markFailed(tenantId, id, error);
    } catch (_) {}
  }

  static const _openStatuses = ['pending', 'failed', 'uploading', 'queued'];

  /// Remove jobs abertos do utilizador (Limpar no chat) — inclui Firestore + espelho global.
  static Future<int> cancelAllOpenForTenant(
    String tenantId, {
    String? module,
    bool abandonChatMessages = true,
  }) async {
    if (tenantId.isEmpty) return 0;
    await _ensureReady();
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _col(tenantId)
          .where('ownerUid', isEqualTo: uid)
          .where('status', whereIn: _openStatuses)
          .limit(50)
          .get();
    } catch (_) {
      return 0;
    }

    final toDelete = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (module != null && module.isNotEmpty) {
        final m = (d['module'] ?? d['type'] ?? '').toString().toLowerCase();
        if (m != module.toLowerCase() && !m.contains('chat')) continue;
      }
      toDelete.add(doc);
    }
    if (toDelete.isEmpty) return 0;

    if (abandonChatMessages) {
      await _abandonChatStubsFromPendingDocs(tenantId, toDelete);
    }

    var batch = firebaseDefaultFirestore.batch();
    var ops = 0;
    var deleted = 0;
    for (final doc in toDelete) {
      batch.delete(doc.reference);
      ops++;
      deleted++;
      if (ops >= 400) {
        await batch.commit();
        batch = firebaseDefaultFirestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return deleted;
  }

  /// Web / jobs antigos sem ficheiro local — não dá para reenviar; remove da fila.
  static Future<int> pruneUnrecoverableOpenForTenant(String tenantId) async {
    if (tenantId.isEmpty) return 0;
    await _ensureReady();
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return 0;

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _col(tenantId)
          .where('ownerUid', isEqualTo: uid)
          .where('status', whereIn: _openStatuses)
          .limit(50)
          .get();
    } catch (_) {
      return 0;
    }

    final stale = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final now = DateTime.now();
    for (final doc in snap.docs) {
      final d = doc.data();
      final localPath = (d['localPath'] ?? '').toString();
      final pathOk =
          !kIsWeb && localPath.isNotEmpty && File(localPath).existsSync();
      if (pathOk) continue;

      final updated = d['updatedAt'];
      if (updated is Timestamp) {
        if (now.difference(updated.toDate()).inHours < 2 && !kIsWeb) continue;
      }
      stale.add(doc);
    }
    if (stale.isEmpty) return 0;

    await _abandonChatStubsFromPendingDocs(tenantId, stale);

    var batch = firebaseDefaultFirestore.batch();
    var ops = 0;
    var removed = 0;
    for (final doc in stale) {
      batch.delete(doc.reference);
      ops++;
      removed++;
      if (ops >= 400) {
        await batch.commit();
        batch = firebaseDefaultFirestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) await batch.commit();
    return removed;
  }

  static Future<void> _abandonChatStubsFromPendingDocs(
    String tenantId,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      final d = doc.data();
      final meta = d['meta'];
      var threadId = '';
      var messageId = '';
      if (meta is Map) {
        threadId = (meta['threadId'] ?? '').toString();
        messageId = (meta['messageId'] ?? '').toString();
      }
      threadId = threadId.isNotEmpty
          ? threadId
          : (d['threadId'] ?? '').toString();
      messageId = messageId.isNotEmpty
          ? messageId
          : (d['messageId'] ?? '').toString();
      if (threadId.isEmpty || messageId.isEmpty) continue;
      try {
        await ChurchChatService.abandonMediaUploadMessage(
          tenantId: tenantId,
          threadId: threadId,
          messageId: messageId,
        );
      } catch (_) {}
    }
  }

  static Future<void> recordFailureForStoragePath({
    required String storagePath,
    required Object error,
    String? localPath,
    String? contentType,
    String? module,
    Map<String, dynamic>? meta,
  }) async {
    final tenant = tenantFromStoragePath(storagePath);
    if (tenant == null || tenant.isEmpty) return;
    await recordFailedBytesUpload(
      tenantId: tenant,
      module: module ?? moduleFromStoragePath(storagePath).name,
      storagePath: storagePath,
      error: error,
      localPath: localPath,
      contentType: contentType ?? 'application/octet-stream',
      meta: meta,
    );
  }
}
