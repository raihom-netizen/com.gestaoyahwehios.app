import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/resumable_upload_service.dart';
import 'package:gestao_yahweh/services/background_upload_worker.dart';
import 'package:gestao_yahweh/services/upload_bytes_core.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';

/// Fila local `pendingUploads` — sobrevive a fecho da app (ficheiro em disco + manifest).
///
/// Usado para uploads grandes; bytes ficam em ficheiro temporário até sucesso.
abstract final class StorageUploadPersistenceService {
  StorageUploadPersistenceService._();

  static const _manifestKey = 'yahweh_pending_uploads_v1';

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'pending_uploads'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<void> enqueueFileJob({
    required String storagePath,
    required String localFilePath,
    required String contentType,
  }) async {
    if (kIsWeb) return;
    final file = File(localFilePath);
    if (!await file.exists()) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dest = p.join((await _dir()).path, '$id.bin');
    await file.copy(dest);

    final prefs = await SharedPreferences.getInstance();
    final list = _readManifest(prefs);
    list.add({
      'id': id,
      'storagePath': storagePath,
      'localPath': dest,
      'contentType': contentType,
    });
    await prefs.setString(_manifestKey, jsonEncode(list));
    BackgroundUploadWorker.scheduleDrain(reason: 'pending_upload_enqueue');
    if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      final tenant =
          PendingUploadsFirestoreService.tenantFromStoragePath(storagePath);
      if (tenant != null && tenant.isNotEmpty) {
        unawaited(
          PendingUploadsFirestoreService.enqueue(
            tenantId: tenant,
            module: PendingUploadsFirestoreService.moduleFromStoragePath(
              storagePath,
            ).name,
            storagePath: storagePath,
            localPath: dest,
            contentType: contentType,
            meta: const {'source': 'local_manifest'},
          ),
        );
      }
    }
  }

  /// Fila a partir de bytes em memória (Web/Android/iOS) — grava em Documents
  /// (não Temporary) e enfileira putData no worker.
  static Future<void> enqueueBytesJob({
    required String storagePath,
    required List<int> bytes,
    required String contentType,
  }) async {
    if (kIsWeb || bytes.isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dest = p.join((await _dir()).path, '$id.bin');
    await File(dest).writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    final list = _readManifest(prefs);
    list.add({
      'id': id,
      'storagePath': storagePath,
      'localPath': dest,
      'contentType': contentType,
    });
    await prefs.setString(_manifestKey, jsonEncode(list));
    BackgroundUploadWorker.scheduleDrain(reason: 'pending_upload_bytes');
    if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      final tenant =
          PendingUploadsFirestoreService.tenantFromStoragePath(storagePath);
      if (tenant != null && tenant.isNotEmpty) {
        unawaited(
          PendingUploadsFirestoreService.enqueue(
            tenantId: tenant,
            module: PendingUploadsFirestoreService.moduleFromStoragePath(
              storagePath,
            ).name,
            storagePath: storagePath,
            localPath: dest,
            contentType: contentType,
            meta: const {'source': 'bytes_manifest'},
          ),
        );
      }
    }
  }

  static List<Map<String, dynamic>> _readManifest(SharedPreferences prefs) {
    final raw = prefs.getString(_manifestKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Arranque da app — reenvia jobs pendentes (background sync leve).
  static Future<void> resumePendingOnAppStart() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _readManifest(prefs);
      if (list.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      final validJobs = <Map<String, dynamic>>[];
      for (final job in list) {
        final path = (job['localPath'] ?? '').toString();
        final storagePath = (job['storagePath'] ?? '').toString();
        final contentType = (job['contentType'] ?? 'application/octet-stream')
            .toString();
        if (path.isEmpty || storagePath.isEmpty) continue;

        final f = File(path);
        if (!await f.exists()) continue;
        validJobs.add({...job, 'localPath': path, 'storagePath': storagePath, 'contentType': contentType});
      }

      for (var i = 0; i < validJobs.length; i += 3) {
        final batch = validJobs.sublist(
          i,
          (i + 3 > validJobs.length) ? validJobs.length : i + 3,
        );
        final results = await Future.wait(
          batch.map((job) async {
            final path = job['localPath'] as String;
            final storagePath = job['storagePath'] as String;
            final contentType = job['contentType'] as String;
            final f = File(path);
            try {
              final size = await f.length();
              final url = ResumableUploadService.shouldUseFileUpload(
                contentType,
                size,
              )
                  ? await ResumableUploadService.uploadLocalFile(
                      storagePath: storagePath,
                      localFilePath: path,
                      contentType: contentType,
                    )
                  : await uploadStoragePutDataWithRetry(
                      storagePath: storagePath,
                      bytes: await f.readAsBytes(),
                      contentType: contentType,
                      maxAttempts: 3,
                      useOfflineQueue: false,
                      localFilePathForRetry: path,
                    );
              if (url.isEmpty) return job;
              try {
                await f.delete();
              } catch (_) {}
              return null;
            } catch (e, st) {
              await YahwehTelemetry.recordUploadFailure(
                e,
                st,
                context: storagePath,
              );
              if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
                unawaited(
                  PendingUploadsFirestoreService.recordFailureForStoragePath(
                    storagePath: storagePath,
                    error: e,
                    localPath: path,
                    contentType: contentType,
                  ),
                );
              }
              return job;
            }
          }),
          eagerError: false,
        );
        for (final r in results) {
          if (r != null) remaining.add(r);
        }
      }
      await prefs.setString(_manifestKey, jsonEncode(remaining));
    } catch (e, st) {
      await YahwehTelemetry.recordUploadFailure(e, st, context: 'resumePending');
    }
  }
}
