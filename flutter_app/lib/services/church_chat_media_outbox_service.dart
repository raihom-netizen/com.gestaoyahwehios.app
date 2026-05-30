import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/optimistic_chat_media_upload.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reenvio de mídia do chat interrompida (app fechado, rede, etc.) + `chat_uploads` Firestore.
abstract final class ChurchChatMediaOutboxService {
  ChurchChatMediaOutboxService._();

  static const _prefsKey = 'church_chat_media_outbox_v1';
  static bool _connectivityBound = false;

  static Future<int> pendingJobCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> registerJob({
    required String tenantId,
    required String threadId,
    required String localId,
    required String kind,
    required String fileName,
    required String mime,
    String? firestoreMessageId,
    String? storagePath,
    String? localPath,
    Uint8List? bytes,
    String? uploadDocId,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      await ChurchChatPendingMediaCache.put(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
        bytes: bytes,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere(
      (e) =>
          (e['tenantId'] ?? '').toString() == tenantId &&
          (e['threadId'] ?? '').toString() == threadId &&
          (e['localId'] ?? '').toString() == localId,
    );
    list.add({
      'tenantId': tenantId,
      'threadId': threadId,
      'localId': localId,
      'kind': kind,
      'fileName': fileName,
      'mime': mime,
      if (firestoreMessageId != null && firestoreMessageId.isNotEmpty)
        'firestoreMessageId': firestoreMessageId,
      if (storagePath != null && storagePath.isNotEmpty)
        'storagePath': storagePath,
      if (localPath != null && localPath.isNotEmpty) 'localPath': localPath,
      if (uploadDocId != null && uploadDocId.isNotEmpty)
        'uploadDocId': uploadDocId,
      'hasBytes': bytes != null && bytes.isNotEmpty,
    });
    await prefs.setString(_prefsKey, jsonEncode(list));
    unawaited(
      ChurchChatUploadsService.upsert(
        tenantId: tenantId,
        threadId: threadId,
        kind: kind,
        localId: localId,
        uploadId: uploadDocId,
        messageId: firestoreMessageId,
        storagePath: storagePath,
        localPath: localPath,
        fileName: fileName,
        mime: mime,
        status: ChurchChatUploadsService.statusWaitingNetwork,
      ),
    );
    final sp = storagePath?.trim() ?? '';
    if (sp.isNotEmpty) {
      unawaited(
        PendingUploadsFirestoreService.enqueue(
          tenantId: tenantId,
          module: 'chat',
          storagePath: sp,
          localPath: localPath,
          contentType: mime,
          status: 'queued',
          meta: {
            'threadId': threadId,
            'localId': localId,
            'kind': kind,
            if (firestoreMessageId != null && firestoreMessageId.isNotEmpty)
              'messageId': firestoreMessageId,
            'source': 'chat_outbox',
          },
        ),
      );
    }
  }

  static Future<void> updateStub({
    required String tenantId,
    required String threadId,
    required String localId,
    String? firestoreMessageId,
    String? storagePath,
    String? uploadDocId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    var changed = false;
    for (final e in list) {
      if ((e['tenantId'] ?? '').toString() == tenantId &&
          (e['threadId'] ?? '').toString() == threadId &&
          (e['localId'] ?? '').toString() == localId) {
        if (firestoreMessageId != null) {
          e['firestoreMessageId'] = firestoreMessageId;
        }
        if (storagePath != null) {
          e['storagePath'] = storagePath;
        }
        if (uploadDocId != null) {
          e['uploadDocId'] = uploadDocId;
        }
        changed = true;
        break;
      }
    }
    if (changed) {
      await prefs.setString(_prefsKey, jsonEncode(list));
    }
  }

  static Future<void> clearJob({
    required String tenantId,
    required String threadId,
    required String localId,
    String? uploadDocId,
  }) async {
    await ChurchChatPendingMediaCache.remove(
      tenantId: tenantId,
      threadId: threadId,
      localId: localId,
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    String? docId = uploadDocId;
    list.removeWhere((e) {
      final match = (e['tenantId'] ?? '').toString() == tenantId &&
          (e['threadId'] ?? '').toString() == threadId &&
          (e['localId'] ?? '').toString() == localId;
      if (match && docId == null) {
        docId = (e['uploadDocId'] ?? '').toString();
      }
      return match;
    });
    await prefs.setString(_prefsKey, jsonEncode(list));
    final idToDelete = docId?.trim();
    if (idToDelete != null && idToDelete.isNotEmpty) {
      await ChurchChatUploadsService.deleteDoc(
        tenantId: tenantId,
        uploadId: idToDelete,
      );
    }
  }

  static void resumePendingOnAppStart() {
    unawaited(_resumeAll());
    bindConnectivityResume();
  }

  static void bindConnectivityResume() {
    if (_connectivityBound) return;
    _connectivityBound = true;
    AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) unawaited(_resumeAll());
    });
  }

  static Future<void> _resumeAll() async {
    await runFirebaseBackgroundTask<void>(
      () async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          await _retryFromJson(m);
        }
      },
      debugLabel: 'chat_outbox_resume',
    ).catchError((_) {});
  }

  static Future<void> _retryFromJson(Map<String, dynamic> json) async {
    final tenantId = (json['tenantId'] ?? '').toString();
    final threadId = (json['threadId'] ?? '').toString();
    final localId = (json['localId'] ?? '').toString();
    if (tenantId.isEmpty || threadId.isEmpty || localId.isEmpty) return;

    final kind = (json['kind'] ?? 'image').toString();
    final fileName = (json['fileName'] ?? 'media').toString();
    final mime = (json['mime'] ?? 'application/octet-stream').toString();
    final localPath = (json['localPath'] ?? '').toString();
    final hasBytes = json['hasBytes'] == true;
    final uploadDocId = (json['uploadDocId'] ?? '').toString();

    if (uploadDocId.isNotEmpty) {
      await ChurchChatUploadsService.markRetrying(
        tenantId: tenantId,
        uploadId: uploadDocId,
      );
    }

    Uint8List? bytes;
    if (hasBytes) {
      bytes = await ChurchChatPendingMediaCache.get(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
      );
    }

    final pathOk = !kIsWeb &&
        localPath.isNotEmpty &&
        File(localPath).existsSync();
    if (bytes == null && !pathOk) {
      await clearJob(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
        uploadDocId: uploadDocId.isEmpty ? null : uploadDocId,
      );
      return;
    }

    final pending = ChurchChatOutboundPending(
      localId: localId,
      kind: kind,
      fileName: fileName,
      mime: mime,
      previewBytes: bytes,
      localPath: pathOk ? localPath : null,
    );
    pending.firestoreMessageId =
        (json['firestoreMessageId'] ?? '').toString().trim().isEmpty
            ? null
            : (json['firestoreMessageId'] ?? '').toString();
    pending.storagePath = (json['storagePath'] ?? '').toString().trim().isEmpty
        ? null
        : (json['storagePath'] ?? '').toString();

    await OptimisticChatMediaUpload.flush(
      pending: pending,
      tenantId: tenantId,
      threadId: threadId,
      bytes: bytes?.toList(),
      localPath: pathOk ? localPath : null,
      replyTo: null,
      uploadDocId: uploadDocId.isEmpty ? null : uploadDocId,
      onProgress: (_) {},
      onSuccess: () => unawaited(clearJob(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
        uploadDocId: uploadDocId.isEmpty ? null : uploadDocId,
      )),
      onFailed: (msg) {
        final sp = pending.storagePath?.trim() ?? '';
        if (sp.isNotEmpty) {
          unawaited(
            PendingUploadsFirestoreService.recordFailedBytesUpload(
              tenantId: tenantId,
              module: 'chat',
              storagePath: sp,
              error: StateError(msg),
              localPath: pathOk ? localPath : null,
              meta: {
                'threadId': threadId,
                'localId': localId,
                'source': 'chat_outbox_retry',
              },
            ),
          );
        }
      },
      onWaitingForNetwork: () {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[chat_outbox] aguardando rede: $localId');
        }
      },
    );
  }
}
