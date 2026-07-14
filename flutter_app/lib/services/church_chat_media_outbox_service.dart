import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/church_chat_uploads_service.dart';
import 'package:gestao_yahweh/services/church_chat_sync_send_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Reenvio de mídia do chat interrompida (app fechado, rede, etc.) + `chat_uploads` Firestore.
abstract final class ChurchChatMediaOutboxService {
  ChurchChatMediaOutboxService._();

  static const _prefsKey = 'church_chat_media_outbox_v1';
  static bool _connectivityBound = false;

  static Future<int> pendingJobCount() async =>
      recoverablePendingJobCount();

  /// Só jobs com ficheiro/bytes — evita banner «28 pendentes» fantasma.
  static Future<int> recoverablePendingJobCount({String? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final tid = tenantId?.trim() ?? '';
      var n = 0;
      for (final m in list) {
        if (tid.isNotEmpty && (m['tenantId'] ?? '').toString() != tid) {
          continue;
        }
        if (await _jobIsRecoverable(m)) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> _jobIsRecoverable(Map<String, dynamic> m) async {
    final tenantId = (m['tenantId'] ?? '').toString();
    final threadId = (m['threadId'] ?? '').toString();
    final localId = (m['localId'] ?? '').toString();
    if (tenantId.isEmpty || threadId.isEmpty || localId.isEmpty) {
      return false;
    }
    final localPath = (m['localPath'] ?? '').toString();
    final pathOk =
        !kIsWeb && localPath.isNotEmpty && File(localPath).existsSync();
    if (pathOk) return true;
    if (m['hasBytes'] == true) {
      final bytes = await ChurchChatPendingMediaCache.get(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
      );
      if (bytes != null && bytes.isNotEmpty) return true;
    }
    return false;
  }

  /// Apaga toda a fila local (SharedPreferences) — botão Limpar no hub.
  static Future<int> wipeAllLocalJobs({String? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    final tid = tenantId?.trim() ?? '';
    if (tid.isEmpty) {
      await prefs.remove(_prefsKey);
      return (jsonDecode(raw) as List).length;
    }
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final kept =
        list.where((e) => (e['tenantId'] ?? '').toString() != tid).toList();
    final removed = list.length - kept.length;
    if (kept.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(kept));
    }
    return removed;
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
    final pathOk = !kIsWeb &&
        localPath != null &&
        localPath.trim().isNotEmpty &&
        File(localPath.trim()).existsSync();
    final hasPayload =
        (bytes != null && bytes.isNotEmpty) || pathOk;
    if (!hasPayload) return;

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
      'attempts': 0,
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
        status: ChurchChatUploadsService.statusQueued,
      ),
    );
    final sp = storagePath?.trim() ?? '';
    if (sp.isNotEmpty &&
        !kIsWeb &&
        FirebaseUploadPolicy.firestorePendingQueueEnabled) {
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
      await PendingUploadsFirestoreService.cancelJob(tenantId, idToDelete);
    }
  }

  /// Reenvio explícito (botão Reenviar / arranque) — aguardável.
  static Future<void> resumeRecoverableNow() async {
    await pruneUnrecoverableJobs();
    await _resumeAll();
  }

  /// Reenvia jobs locais desta conversa (abrir thread / voltar do fundo).
  static Future<void> resumeForThread({
    required String tenantId,
    required String threadId,
  }) async {
    final tid = tenantId.trim();
    final th = threadId.trim();
    if (tid.isEmpty || th.isEmpty) return;
    await runFirebaseBackgroundTask<void>(
      () async {
        await ensureFirebaseReadyForChatSend();
        await FirestoreWebGuard.prepareForChatWrite().catchError((_) {});
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final jobs = list
            .where(
              (e) =>
                  (e['tenantId'] ?? '').toString() == tid &&
                  (e['threadId'] ?? '').toString() == th,
            )
            .take(_maxJobsPerResumeWave)
            .toList();
        for (var i = 0; i < jobs.length; i += 2) {
          final batch = jobs.sublist(
            i,
            (i + 2 > jobs.length) ? jobs.length : i + 2,
          );
          await Future.wait(
            batch.map(_retryFromJson),
            eagerError: false,
          );
        }
      },
      debugLabel: 'chat_outbox_thread_resume',
    ).catchError((e, st) {
      if (kDebugMode) {
        debugPrint('ChurchChatMediaOutboxService.resumeForThread: $e\n$st');
      }
    });
  }

  static void resumePendingOnAppStart() {
    if (_resumeScheduled) return;
    _resumeScheduled = true;
    unawaited(() async {
      try {
        await resumeRecoverableNow();
      } finally {
        _resumeScheduled = false;
      }
    }());
    bindConnectivityResume();
  }

  static void bindConnectivityResume() {
    if (_connectivityBound) return;
    _connectivityBound = true;
    AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) unawaited(_resumeAll());
    });
  }

  static const int _maxJobsPerResumeWave = 4;
  static bool _resumeScheduled = false;

  /// Remove fila local do chat e apaga stubs no Firestore (botão Limpar).
  static Future<int> clearAllJobs({String? tenantId}) async {
    return clearAllJobsWithFirestore(tenantId: tenantId);
  }

  /// Igual [clearAllJobs] + `abandonMediaUploadMessage` / `chat_uploads` por job.
  static Future<int> clearAllJobsWithFirestore({String? tenantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final tid = tenantId?.trim() ?? '';

    final toRemove = tid.isEmpty
        ? List<Map<String, dynamic>>.from(list)
        : list
            .where((e) => (e['tenantId'] ?? '').toString() == tid)
            .toList();

    for (final m in toRemove) {
      final t = (m['tenantId'] ?? '').toString();
      final threadId = (m['threadId'] ?? '').toString();
      final localId = (m['localId'] ?? '').toString();
      if (t.isEmpty || threadId.isEmpty || localId.isEmpty) continue;
      await clearJob(
        tenantId: t,
        threadId: threadId,
        localId: localId,
        uploadDocId: (m['uploadDocId'] ?? '').toString().isEmpty
            ? null
            : (m['uploadDocId'] ?? '').toString(),
      );
    }

    if (tid.isEmpty) {
      await prefs.remove(_prefsKey);
      return toRemove.length;
    }
    final kept = list
        .where((e) => (e['tenantId'] ?? '').toString() != tid)
        .toList();
    if (kept.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(kept));
    }
    return toRemove.length;
  }

  static Future<void> _resumeAll() async {
    await runFirebaseBackgroundTask<void>(
      () async {
        await ensureFirebaseReadyForChatSend();
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final wave = list.take(_maxJobsPerResumeWave).toList();
        for (var i = 0; i < wave.length; i += 2) {
          final batch = wave.sublist(
            i,
            (i + 2 > wave.length) ? wave.length : i + 2,
          );
          await Future.wait(
            batch.map(_retryFromJson),
            eagerError: false,
          );
        }
      },
      debugLabel: 'chat_outbox_resume',
    ).catchError((e, st) {
      if (kDebugMode) {
        debugPrint('ChurchChatMediaOutboxService._resumeAll: $e\n$st');
      }
    });
  }

  /// Limpa envios sem bytes/path (web) — evita fila infinita de «25 pendentes».
  static Future<int> pruneUnrecoverableJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    var removed = 0;
    for (final m in List<Map<String, dynamic>>.from(list)) {
      final tenantId = (m['tenantId'] ?? '').toString();
      final threadId = (m['threadId'] ?? '').toString();
      final localId = (m['localId'] ?? '').toString();
      if (tenantId.isEmpty || threadId.isEmpty || localId.isEmpty) continue;
      final hasBytes = m['hasBytes'] == true;
      final localPath = (m['localPath'] ?? '').toString();
      final pathOk =
          !kIsWeb && localPath.isNotEmpty && File(localPath).existsSync();
      if (pathOk) continue;
      if (hasBytes) {
        final bytes = await ChurchChatPendingMediaCache.get(
          tenantId: tenantId,
          threadId: threadId,
          localId: localId,
        );
        if (bytes != null && bytes.isNotEmpty) continue;
      }
      removed++;
      final uploadDocId = (m['uploadDocId'] ?? '').toString();
      await clearJob(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
        uploadDocId: uploadDocId.isEmpty ? null : uploadDocId,
      );
    }
    return removed;
  }

  static Future<void> _bumpAttempt(
    String tenantId,
    String threadId,
    String localId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    for (final e in list) {
      if ((e['tenantId'] ?? '').toString() == tenantId &&
          (e['threadId'] ?? '').toString() == threadId &&
          (e['localId'] ?? '').toString() == localId) {
        final n = e['attempts'] is num
            ? (e['attempts'] as num).toInt()
            : int.tryParse('${e['attempts']}') ?? 0;
        e['attempts'] = n + 1;
        break;
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(list));
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

    if (bytes == null && kIsWeb && localPath.isNotEmpty) {
      try {
        final raw = await XFile(localPath).readAsBytes();
        if (raw.isNotEmpty) {
          bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
        }
      } catch (_) {}
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
      byteSize: bytes?.length,
    );
    pending.firestoreMessageId =
        (json['firestoreMessageId'] ?? '').toString().trim().isEmpty
            ? null
            : (json['firestoreMessageId'] ?? '').toString();
    pending.storagePath = (json['storagePath'] ?? '').toString().trim().isEmpty
        ? null
        : (json['storagePath'] ?? '').toString();

    await _bumpAttempt(tenantId, threadId, localId);

    try {
      await ChurchChatSyncSendService.sendMedia(
        tenantId: tenantId,
        threadId: threadId,
        pending: pending,
        bytes: bytes?.toList(),
        localPath: pathOk ? localPath : null,
        onProgress: (progress) {
          if (uploadDocId.isNotEmpty) {
            unawaited(
              ChurchChatUploadsService.patchProgress(
                tenantId: tenantId,
                uploadId: uploadDocId,
                progress: progress,
                status: ChurchChatUploadsService.statusUploading,
              ),
            );
          }
        },
        onSuccess: () => unawaited(clearJob(
          tenantId: tenantId,
          threadId: threadId,
          localId: localId,
          uploadDocId: uploadDocId.isEmpty ? null : uploadDocId,
        )),
        onError: (msg) => throw StateError(msg),
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[chat_outbox] falha $localId: $e');
      }
      if (uploadDocId.isNotEmpty) {
        unawaited(
          ChurchChatUploadsService.markQueued(
            tenantId: tenantId,
            uploadId: uploadDocId,
          ),
        );
      }
      final sp = pending.storagePath?.trim() ?? '';
      if (sp.isNotEmpty) {
        unawaited(
          PendingUploadsFirestoreService.recordFailedBytesUpload(
            tenantId: tenantId,
            module: 'chat',
            storagePath: sp,
            error: e,
            localPath: pathOk ? localPath : null,
            meta: {
              'threadId': threadId,
              'localId': localId,
              'source': 'chat_outbox_retry',
            },
          ),
        );
      }
    }
  }
}
