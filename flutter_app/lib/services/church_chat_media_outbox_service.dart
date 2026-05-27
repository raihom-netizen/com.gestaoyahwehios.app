import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/church_chat_pending_media_cache.dart';
import 'package:gestao_yahweh/services/optimistic_chat_media_upload.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reenvio de mídia do chat interrompida (app fechado, rede, etc.).
abstract final class ChurchChatMediaOutboxService {
  ChurchChatMediaOutboxService._();

  static const _prefsKey = 'church_chat_media_outbox_v1';

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
      'hasBytes': bytes != null && bytes.isNotEmpty,
    });
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static Future<void> updateStub({
    required String tenantId,
    required String threadId,
    required String localId,
    String? firestoreMessageId,
    String? storagePath,
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
    list.removeWhere(
      (e) =>
          (e['tenantId'] ?? '').toString() == tenantId &&
          (e['threadId'] ?? '').toString() == threadId &&
          (e['localId'] ?? '').toString() == localId,
    );
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static void resumePendingOnAppStart() {
    unawaited(() async {
      try {
        await ensureFirebaseInitialized();
      } catch (_) {
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          await _retryFromJson(m);
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('ChurchChatMediaOutbox resume: $e');
        }
      }
    }());
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
      onProgress: (_) {},
      onSuccess: () => unawaited(clearJob(
        tenantId: tenantId,
        threadId: threadId,
        localId: localId,
      )),
      onFailed: (_) {},
    );
  }
}
