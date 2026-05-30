import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Controlo Firestore de uploads de mídia do chat (retoma após fechar o app).
///
/// Coleção: `igrejas/{tenantId}/chat_uploads/{uploadId}`
abstract final class ChurchChatUploadsService {
  ChurchChatUploadsService._();

  static const statusQueued = 'queued';
  static const statusUploading = 'uploading';
  static const statusWaitingNetwork = 'waiting_network';
  static const statusRetrying = 'retrying';
  static const statusDone = 'done';
  static const statusFailed = 'failed';

  static CollectionReference<Map<String, dynamic>> _col(String tenantId) =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('chat_uploads');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

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
    await ensureFirebaseInitialized();
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

  static Future<void> markWaitingNetwork({
    required String tenantId,
    required String uploadId,
  }) async {
    await patchProgress(
      tenantId: tenantId,
      uploadId: uploadId,
      progress: 0,
      status: statusWaitingNetwork,
    );
  }

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
    await ensureFirebaseInitialized();
    final uid = _uid;
    if (uid == null) return [];
    final statuses = [
      statusQueued,
      statusUploading,
      statusWaitingNetwork,
      statusRetrying,
    ];
    final out = <Map<String, dynamic>>[];
    try {
      final snap = await FirebaseFirestore.instance
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
    unawaited(
      ensureFirebaseInitialized().then((_) async {
        final pending = await listPendingForCurrentUser();
        if (pending.isEmpty) return;
        // Retoma via outbox local (ficheiros); Firestore só marca estado.
        for (final _ in pending) {
          // Outbox já reenvia com paths locais; nada a fazer aqui sem UI.
        }
      }),
    );
  }
}
