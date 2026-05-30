import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/services/analytics_service.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_migration.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Módulos com fila, compressão, retry, pending e progresso unificados.
enum YahwehUploadModule { chat, aviso, evento, generic }

/// Pipeline: comprimir → backup local → fila/retry → Storage → URL (Firestore no caller).
abstract final class YahwehMediaUploadPipeline {
  YahwehMediaUploadPipeline._();

  static void bindOnAppStart() {
    if (FirebaseUploadPolicy.memoryQueueOnNetworkError) {
      StorageUploadQueueService.instance.start();
    }
    unawaited(StorageUploadPersistenceService.resumePendingOnAppStart());
    unawaited(PendingUploadsMigration.migrateAwayFromFirestoreQueueIfNeeded());
    if (FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      unawaited(PendingUploadsFirestoreService.resumeForCurrentUserTenant());
    }
  }

  static YahwehUploadModule moduleFromStoragePath(String storagePath) {
    final p = storagePath.toLowerCase();
    if (p.contains('/chat/') || p.contains('chat_media')) {
      return YahwehUploadModule.chat;
    }
    if (p.contains('/avisos/')) return YahwehUploadModule.aviso;
    if (p.contains('/eventos/') || p.contains('/noticias/')) {
      return YahwehUploadModule.evento;
    }
    return YahwehUploadModule.generic;
  }

  static String? tenantFromStoragePath(String storagePath) =>
      FeedTenantStorageMap.tenantIdFromStoragePath(storagePath);

  /// Comprime imagem conforme módulo (feed 1920/80% ou chat mais leve).
  static Future<Uint8List> compressImageBytes({
    required YahwehUploadModule module,
    required Uint8List bytes,
    required String contentType,
    bool chatJpegFast = false,
  }) async {
    final ct = contentType.toLowerCase();
    if (!ct.startsWith('image/')) return bytes;
    if (ct == 'image/webp') {
      return FeedPostMediaUpload.prepareFeedWebpBytes(bytes);
    }
    final profile = module == YahwehUploadModule.chat
        ? MediaImageProfile.chat
        : MediaImageProfile.feed;
    var out = await MediaService.compressImageBytes(bytes, profile: profile);
    if (module != YahwehUploadModule.chat && out.length > 1200000) {
      out = await ImageHelper.compressImageUnderMaxBytes(out);
    } else if (chatJpegFast && out.length < 900 * 1024) {
      return out;
    }
    return out;
  }

  /// Comprime vídeo no mobile (web: devolve o ficheiro original).
  static Future<File> compressVideoFile(File file) async {
    if (kIsWeb) return file;
    final info = await MediaService.compressVideo(file);
    if (info?.file != null && await info!.file!.exists()) {
      return info.file!;
    }
    return file;
  }

  /// Upload com bootstrap, progresso, fila offline, pending Firestore e analytics.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    YahwehUploadModule? module,
    String? tenantId,
    String? localFilePathForRetry,
    bool chatJpegFast = false,
    bool useOfflineQueue = false,
    String? pendingUploadId,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    int maxAttempts = 4,
  }) async {
    final mod = module ?? moduleFromStoragePath(storagePath);
    final tenant = tenantId ?? tenantFromStoragePath(storagePath) ?? '';
    await ensureUploadBootstrapForStoragePath(storagePath);

    unawaited(
      AnalyticsService.logUploadPipeline(
        module: mod.name,
        phase: 'compress_start',
      ),
    );

    final prepared = await compressImageBytes(
      module: mod,
      bytes: bytes,
      contentType: contentType,
      chatJpegFast: chatJpegFast,
    );

    if (!kIsWeb && localFilePathForRetry != null && localFilePathForRetry.isNotEmpty) {
      unawaited(
        StorageUploadPersistenceService.enqueueFileJob(
          storagePath: storagePath,
          localFilePath: localFilePathForRetry,
          contentType: contentType,
        ),
      );
    }

    unawaited(
      AnalyticsService.logUploadPipeline(module: mod.name, phase: 'upload_start'),
    );

    try {
      String url;
      try {
        url = await _putDataDirect(
          storagePath: storagePath,
          bytes: prepared,
          contentType: contentType,
          maxAttempts: maxAttempts,
          onProgress: onProgress,
          onTaskStarted: onUploadTaskCreated,
        );
      } catch (e) {
        if (useOfflineQueue &&
            FirebaseUploadPolicy.memoryQueueOnNetworkError &&
            isLikelyNetworkUploadError(e)) {
          if (FirebaseUploadPolicy.firestorePendingQueueEnabled &&
              tenant.isNotEmpty) {
            unawaited(
              PendingUploadsFirestoreService.recordQueuedBytesUpload(
                tenantId: tenant,
                module: mod.name,
                storagePath: storagePath,
                localPath: localFilePathForRetry,
                contentType: contentType,
              ),
            );
          }
          url = await StorageUploadQueueService.instance.enqueuePutData(
            storagePath: storagePath,
            bytes: prepared,
            contentType: contentType,
            onProgress: onProgress,
            tenantId: tenant.isEmpty ? null : tenant,
            module: mod.name,
            localPathForRetry: localFilePathForRetry,
          );
        } else {
          rethrow;
        }
      }
      if (pendingUploadId != null &&
          tenant.isNotEmpty &&
          pendingUploadId.isNotEmpty) {
        unawaited(
          PendingUploadsFirestoreService.markCompleted(tenant, pendingUploadId),
        );
      }
      unawaited(
        AnalyticsService.logUploadPipeline(module: mod.name, phase: 'upload_ok'),
      );
      return url;
    } catch (e, st) {
      logFirebaseDiagnostic(e, st, context: 'pipeline_${mod.name}:$storagePath');
      unawaited(
        AnalyticsService.logUploadPipeline(
          module: mod.name,
          phase: 'upload_fail',
          error: e.toString(),
        ),
      );
      if (FirebaseUploadPolicy.firestorePendingQueueEnabled &&
          tenant.isNotEmpty) {
        unawaited(
          PendingUploadsFirestoreService.recordFailedBytesUpload(
            tenantId: tenant,
            module: mod.name,
            storagePath: storagePath,
            error: e,
            localPath: localFilePathForRetry,
            contentType: contentType,
          ),
        );
      }
      rethrow;
    }
  }

  static Future<void> markCompleted(String tenantId, String uploadId) =>
      PendingUploadsFirestoreService.markCompleted(tenantId, uploadId);

  /// Rótulo de progresso global para UI.
  static void showProgress(String label, {int? totalItems}) {
    if (totalItems != null && totalItems > 0) {
      GlobalUploadProgress.instance.startBatch(
        itemLabel: label,
        totalItems: totalItems,
      );
    } else {
      GlobalUploadProgress.instance.start(label);
    }
  }

  static void hideProgress() => GlobalUploadProgress.instance.end();

  static Future<String> _putDataDirect({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    int maxAttempts = 4,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onTaskStarted,
    String cacheControl = 'public, max-age=31536000',
  }) async {
    await ensureUploadBootstrapForStoragePath(storagePath);
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final ref = firebaseStorageRef(storagePath);
        final task = ref.putData(
          bytes,
          SettableMetadata(
            contentType: contentType,
            cacheControl: cacheControl,
          ),
        );
        onTaskStarted?.call(task);
        final snap = await awaitStorageUploadTask(
          task,
          payloadBytes: bytes.length,
          onProgress: onProgress,
        );
        onProgress?.call(1.0);
        return await storageDownloadUrlWithRetry(snap.ref);
      } catch (e) {
        lastError = e;
        final isCanceled = e is FirebaseException && e.code == 'canceled';
        if (isCanceled) break;
        if (attempt >= maxAttempts) break;
        onProgress?.call(0);
        await Future.delayed(
          Duration(milliseconds: 120 * math.pow(2, attempt - 1).toInt()),
        );
      }
    }
    throw lastError ?? StateError('Falha de upload');
  }
}
