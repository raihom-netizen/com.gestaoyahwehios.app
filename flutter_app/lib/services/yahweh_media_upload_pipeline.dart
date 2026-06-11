import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_media_upload.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_firestore_meta.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/storage_upload_metadata.dart';
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
import 'package:gestao_yahweh/services/upload_queue_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart'
    hide formatUploadErrorForUser;

/// Módulos com fila, compressão, retry, pending e progresso unificados.
enum YahwehUploadModule { chat, aviso, evento, generic }

/// Pipeline: comprimir → backup local → fila/retry → Storage → URL (Firestore no caller).
abstract final class YahwehMediaUploadPipeline {
  YahwehMediaUploadPipeline._();

  static void bindOnAppStart() {
    if (EcoFireFlow.disableUploadQueues) {
      EcoFireFlow.log('filas de upload desligadas');
      return;
    }
    if (FirebaseUploadPolicy.memoryQueueOnNetworkError) {
      UploadQueueService.instance.start();
    }
    unawaited(PendingUploadsMigration.migrateAwayFromFirestoreQueueIfNeeded());
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

  static EcoFireMediaProfile ecofireProfileFromPath(
    String storagePath, {
    YahwehUploadModule? module,
  }) {
    final p = storagePath.toLowerCase();
    if (p.contains('/membros/') || p.contains('foto_perfil')) {
      return p.contains('/thumbs/') || p.contains('thumb')
          ? EcoFireMediaProfile.memberThumb
          : EcoFireMediaProfile.memberProfile;
    }
    if (p.contains('/patrimonio/')) return EcoFireMediaProfile.patrimonio;
    if (p.contains('/configuracoes/') ||
        p.contains('/logo/') ||
        p.contains('logo_igreja')) {
      return EcoFireMediaProfile.logo;
    }
    if (module == YahwehUploadModule.chat || p.contains('/chat_media/')) {
      return EcoFireMediaProfile.chat;
    }
    if (p.contains('/financeiro/') || p.contains('.pdf')) {
      return EcoFireMediaProfile.document;
    }
    return EcoFireMediaProfile.feedPhoto;
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
    bool useOfflineQueue = false, // Controle Total: directo; fila só se caller pedir
    String? pendingUploadId,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    int maxAttempts = 4,
  }) async {
    if (EcoFireFlow.directStorageUpload) {
      final mod = module ?? moduleFromStoragePath(storagePath);
      final profile = ecofireProfileFromPath(storagePath, module: mod);
      showProgress(switch (mod) {
        YahwehUploadModule.chat => 'A enviar no chat…',
        YahwehUploadModule.aviso => 'A enviar foto do aviso…',
        YahwehUploadModule.evento => 'A enviar mídia do evento…',
        YahwehUploadModule.generic => 'A enviar ficheiro…',
      });
      try {
        return await EcoFireMediaUpload.uploadBytes(
          storagePath: storagePath,
          bytes: bytes,
          contentType: contentType,
          profile: profile,
          onProgress: progressBridge(onProgress),
        );
      } finally {
        hideProgress();
      }
    }
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

    final progressLabel = switch (mod) {
      YahwehUploadModule.chat => 'A enviar no chat…',
      YahwehUploadModule.aviso => 'A enviar foto do aviso…',
      YahwehUploadModule.evento => 'A enviar mídia do evento…',
      YahwehUploadModule.generic => 'A enviar ficheiro…',
    };
    showProgress(progressLabel);

    try {
      String url;
      try {
        url = await _putDataDirect(
          storagePath: storagePath,
          bytes: prepared,
          contentType: contentType,
          maxAttempts: maxAttempts,
          onProgress: progressBridge(onProgress),
          onTaskStarted: onUploadTaskCreated,
          skipBootstrap: true,
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
      throw StateError(formatUploadErrorForUser(e));
    } finally {
      hideProgress();
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

  /// Repassa progresso do [UploadTask.snapshotEvents] para UI global + callback local.
  static void Function(double progress) progressBridge([
    void Function(double progress)? onProgress,
  ]) {
    return (double p) {
      final clamped = p.clamp(0.0, 1.0);
      if (GlobalUploadProgress.instance.state.value != null) {
        GlobalUploadProgress.instance.update(clamped);
      }
      onProgress?.call(clamped);
    };
  }

  /// Bytes já comprimidos (ex. patrimônio WebP) — `putData` directo, sem fila offline.
  /// [requireAuth] false: cadastro público de membro (Storage permite write sem login).
  static Future<String> uploadPreparedBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    int maxAttempts = 4,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    bool requireAuth = true,
  }) async {
    if (EcoFireFlow.directStorageUpload) {
      final profile = ecofireProfileFromPath(storagePath);
      return EcoFireMediaUpload.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        profile: profile,
        onProgress: onProgress,
      );
    }
    if (!FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      await _ensureStorageBootstrap(
        storagePath: storagePath,
        requireAuth: requireAuth,
      );
    }
    return _putDataDirect(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      maxAttempts: maxAttempts,
      onProgress: progressBridge(onProgress),
      onTaskStarted: onUploadTaskCreated,
      skipBootstrap: true,
      requireAuth: requireAuth,
    );
  }

  static Future<void> _ensureStorageBootstrap({
    required String storagePath,
    required bool requireAuth,
  }) async {
    if (requireAuth) {
      await ensureUploadBootstrapForStoragePath(storagePath);
      return;
    }
    await FirebaseBootstrap.ensureInitialized();
    FirebaseBootstrapService.refreshCachedApp();
  }

  static Future<String> _putDataDirect({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    int maxAttempts = 4,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onTaskStarted,
    String cacheControl = 'public, max-age=31536000',
    bool skipBootstrap = false,
    bool requireAuth = true,
  }) async {
    if (!skipBootstrap) {
      await _ensureStorageBootstrap(
        storagePath: storagePath,
        requireAuth: requireAuth,
      );
    }
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final ref = firebaseStorageRef(storagePath);
        final ct = StorageUploadMetadata.contentTypeForPut(
          contentType: contentType,
          storagePath: storagePath,
        );
        final task = ref.putData(
          bytes,
          SettableMetadata(
            contentType: ct,
            cacheControl: StorageUploadMetadata.cacheControl,
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
        if (isFirebaseNoAppError(e) && attempt < maxAttempts) {
          FirebaseBootstrapService.invalidateStorageUploadBootstrap();
          try {
            await FirebaseBootstrapService.ensureAlwaysOn(
              refreshAuthToken: false,
            );
            await ensureUploadBootstrapForStoragePath(storagePath);
          } catch (_) {}
          continue;
        }
        if (attempt >= maxAttempts) break;
        onProgress?.call(0);
        await Future.delayed(
          Duration(milliseconds: 120 * math.pow(2, attempt - 1).toInt()),
        );
      }
    }
    throw StateError(
      formatUploadErrorForUser(lastError ?? StateError('Falha de upload')),
    );
  }
}
