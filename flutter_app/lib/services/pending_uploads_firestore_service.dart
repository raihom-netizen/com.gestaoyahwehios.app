import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/services/upload_bytes_core.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Fila por igreja: `igrejas/{tenantId}/pending_uploads/{id}`.
/// Espelho global (Master / painel): `pendingUploads/{tenantId}__{id}`.
abstract final class PendingUploadsFirestoreService {
  PendingUploadsFirestoreService._();

  static const String globalCollectionId = 'pendingUploads';

  static Future<void> _ensureReady() async {
    await ensureFirebaseReadyForMediaUpload();
  }

  static CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection('pending_uploads');

  static CollectionReference<Map<String, dynamic>> get _globalCol =>
      firebaseDefaultFirestore.collection(globalCollectionId);

  static String _globalDocId(String tenantId, String uploadId) =>
      '${tenantId.trim()}__$uploadId';

  static String? tenantFromStoragePath(String storagePath) =>
      FeedTenantStorageMap.tenantIdFromStoragePath(storagePath);

  static YahwehUploadModule moduleFromStoragePath(String storagePath) =>
      YahwehMediaUploadPipeline.moduleFromStoragePath(storagePath);

  static Future<void> _mirrorGlobal(
    String tenantId,
    String uploadId,
    Map<String, dynamic> data, {
    bool delete = false,
  }) async {
    try {
      final ref = _globalCol.doc(_globalDocId(tenantId, uploadId));
      if (delete) {
        await ref.delete();
        return;
      }
      await ref.set(
        {
          ...data,
          'tenantUploadId': uploadId,
          'globalKey': _globalDocId(tenantId, uploadId),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Regista job pendente (Firestore tenant + global + disco local no mobile).
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
    unawaited(_mirrorGlobal(tenantId, id, data));
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
      unawaited(_mirrorGlobal(tenantId, uploadId, patch));
    } catch (_) {}
  }

  static Future<void> markCompleted(String tenantId, String uploadId) async {
    try {
      await _col(tenantId).doc(uploadId).delete();
      unawaited(_mirrorGlobal(tenantId, uploadId, {}, delete: true));
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
      unawaited(_mirrorGlobal(tenantId, uploadId, patch));
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
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (tenantId.isEmpty || uid.isEmpty) {
      return const Stream.empty();
    }
    return _col(tenantId)
        .where('ownerUid', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'failed', 'uploading', 'queued'])
        .limit(25)
        .snapshots();
  }

  /// Índice global — operador Master vê todos; utilizador só os seus.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchGlobalIndex({
    bool masterSeeAll = false,
    int limit = 40,
  }) {
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    if (uid.isEmpty) return const Stream.empty();
    if (masterSeeAll) {
      return _globalCol.limit(limit).snapshots();
    }
    return _globalCol
        .where('ownerUid', isEqualTo: uid)
        .limit(limit)
        .snapshots();
  }

  static Future<void> resumeAllForTenant(String tenantId) async {
    if (tenantId.isEmpty) return;
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
        if (!kIsWeb && localPath.isNotEmpty) {
          final f = File(localPath);
          if (!await f.exists()) {
            await markFailed(
              tenantId,
              doc.id,
              StateError('Ficheiro local não encontrado: $localPath'),
            );
            continue;
          }
          final bytes = await f.readAsBytes();
          await uploadStoragePutDataWithRetry(
            storagePath: storagePath,
            bytes: bytes,
            contentType: contentType,
            maxAttempts: 3,
            useOfflineQueue: false,
            localFilePathForRetry: localPath,
          );
          try {
            await f.delete();
          } catch (_) {}
          await markCompleted(tenantId, doc.id);
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
