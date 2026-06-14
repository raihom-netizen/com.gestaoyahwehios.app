import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Controlo Firestore de uploads de mídia do chat (retoma após fechar o app).
///
/// Coleção: `igrejas/{tenantId}/chat_uploads/{uploadId}`
abstract final class ChurchChatUploadsService {
  ChurchChatUploadsService._();

  static const statusQueued = 'queued';
  static const statusUploading = 'uploading';
  /// Legado — usar [statusQueued]. Nunca gravar `waiting_network` (travava UI).
  @Deprecated('Use statusQueued')
  static const statusWaitingNetwork = statusQueued;
  static const statusRetrying = 'retrying';
  static const statusDone = 'done';
  static const statusFailed = 'failed';

  static CollectionReference<Map<String, dynamic>> _col(String operationalTenantId) =>
      ChurchOperationalPaths.churchDoc(operationalTenantId.trim())
          .collection('chat_uploads');

  static String? get _uid => firebaseDefaultAuth.currentUser?.uid;

  /// Regista ou atualiza o documento de upload (id estável = [uploadId] ou novo).
  static Future<String> upsert({
    required String tenantId,
    required String threadId,
    required String kind,
    required String localId,
    String? uploadId,
    String? messageId,
    String? storagePath,
    String? localPath,
    String? fileName,
    String? mime,
    double progress = 0,
    String status = statusQueued,
  }) async {
    await ensureFirebaseReadyForMediaUpload();
    final uid = _uid;
    if (uid == null) return '';
    final ref = uploadId != null && uploadId.isNotEmpty
        ? _col(tenantId).doc(uploadId)
        : _col(tenantId).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'ownerUid': uid,
      'threadId': threadId,
      'localId': localId,
      'kind': kind,
      'status': status,
      'progress': progress.clamp(0.0, 1.0),
      if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
      if (storagePath != null && storagePath.isNotEmpty)
        'storagePath': storagePath,
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath,
      if (fileName != null && fileName.isNotEmpty) 'fileName': fileName,
      if (mime != null && mime.isNotEmpty) 'mime': mime,
      'updatedAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
    return ref.id;
  }

  static Future<void> patchProgress({
    required String tenantId,
    required String uploadId,
    required double progress,
    String? status,
  }) async {
    if (uploadId.isEmpty) return;
    try {
      await _col(tenantId).doc(uploadId).set({
        if (status != null) 'status': status,
        'progress': progress.clamp(0.0, 1.0),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Fila offline — **não** bloqueia thread nem input do chat.
  static Future<void> markQueued({
    required String tenantId,
    required String uploadId,
    double progress = 0,
  }) async {
    await patchProgress(
      tenantId: tenantId,
      uploadId: uploadId,
      progress: progress,
      status: statusQueued,
    );
  }

  @Deprecated('Use markQueued')
  static Future<void> markWaitingNetwork({
    required String tenantId,
    required String uploadId,
  }) =>
      markQueued(tenantId: tenantId, uploadId: uploadId);

  static Future<void> markRetrying({
    required String tenantId,
    required String uploadId,
  }) async {
    await patchProgress(
      tenantId: tenantId,
      uploadId: uploadId,
      progress: 0,
      status: statusRetrying,
    );
  }

  static Future<void> markDone({
    required String tenantId,
    required String uploadId,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col(tenantId).doc(uploadId).set({
        'status': statusDone,
        'progress': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> markFailed({
    required String tenantId,
    required String uploadId,
    String? error,
  }) async {
    try {
      await _col(tenantId).doc(uploadId).set({
        'status': statusFailed,
        'updatedAt': FieldValue.serverTimestamp(),
        if (error != null && error.isNotEmpty) 'lastError': error,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> deleteDoc({
    required String tenantId,
    required String uploadId,
  }) async {
    if (uploadId.isEmpty) return;
    try {
      await _col(tenantId).doc(uploadId).delete();
    } catch (_) {}
  }

  /// Consulta uploads pendentes do utilizador (multi-igreja) para diagnóstico/retoma.
  static Future<List<Map<String, dynamic>>> listPendingForCurrentUser({
    int limit = 32,
  }) async {
    await ensureFirebaseReadyForMediaUpload();
    final uid = _uid;
    if (uid == null) return [];
    final statuses = [
      statusQueued,
      statusUploading,
      statusRetrying,
      'waiting_network', // legado — retomar uploads presos antes da migração
    ];
    final out = <Map<String, dynamic>>[];
    try {
      final snap = await firebaseDefaultFirestore
          .collectionGroup('chat_uploads')
          .where('ownerUid', isEqualTo: uid)
          .where('status', whereIn: statuses)
          .limit(limit)
          .get();
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['uploadId'] = d.id;
        final path = d.reference.path;
        final m = RegExp(r'^igrejas/([^/]+)/chat_uploads/').firstMatch(path);
        if (m != null) data['tenantId'] = m.group(1);
        out.add(data);
      }
    } catch (_) {}
    return out;
  }

  static void resumeWhenOnline() {
    ChurchChatMediaOutboxService.bindConnectivityResume();
    unawaited(
      ensureFirebaseReadyForMediaUpload().then((_) async {
        await ChurchChatMediaOutboxService.resumeRecoverableNow();
      }),
    );
  }
}
