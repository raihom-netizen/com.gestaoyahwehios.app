import 'dart:async' show TimeoutException, unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/firebase_apps_diagnostic.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp;
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload unificado — Web, Android e iOS usam o mesmo pipeline ([MediaUploadService]
/// + bootstrap + retry). A Web é a referência; nativos usam [putFile] quando há path local.
abstract final class UnifiedUploadService {
  UnifiedUploadService._();

  static String get platformLabel {
    if (kIsWeb) return 'WEB';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'ANDROID',
      TargetPlatform.iOS => 'IOS',
      _ => 'NATIVE',
    };
  }

  static Future<void> _ensureReady({String? module}) async {
    if (EcoFireFlow.directStorageUpload) {
      await ensureFirebaseCore(requireAuth: true);
      return;
    }
    if (FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      try {
        await firebaseDefaultAuth.currentUser
            ?.getIdToken(false)
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
      return;
    }
    final chatModule = module == YahwehUploadModule.chat.name;
    if (chatModule) {
      await ensureFirebaseReadyForChatSend();
    } else {
      await FirebaseBootstrapService.ensureReadyForStorageUpload();
    }
    logFirebaseAppsBeforeOperation('ensure_ready', module: module);
  }

  static Future<String> uploadImage({
    required String storagePath,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String? localPath,
    YahwehUploadModule module = YahwehUploadModule.generic,
    bool chatJpegFast = false,
    bool skipClientPrepare = false,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    int maxAttempts = 3,
    bool useOfflineQueue = false,
  }) async {
    await _ensureReady(module: module.name);
    logFirebasePublishPhase('UPLOAD_START', '$platformLabel|${module.name}|$storagePath|image');
    try {
      Future<T> withUploadTimeout<T>(Future<T> fut) {
        final secs = bytes.length <= 3 * 1024 * 1024 ? 30 : 60;
        return fut.timeout(
          Duration(seconds: secs),
          onTimeout: () => throw TimeoutException(
            'Upload excedeu ${secs}s ($storagePath)',
          ),
        );
      }
      if (!kIsWeb &&
          localPath != null &&
          localPath.trim().isNotEmpty &&
          await File(localPath).exists() &&
          (skipClientPrepare || module == YahwehUploadModule.chat)) {
        final url = await withUploadTimeout(
          MediaUploadService.uploadFileWithRetry(
            storagePath: storagePath,
            file: File(localPath),
            contentType: contentType,
            maxAttempts: maxAttempts,
            useOfflineQueue: useOfflineQueue,
            skipRecompress: skipClientPrepare,
            chatJpegFast: chatJpegFast,
            onProgress: onProgress,
            onUploadTaskCreated: onUploadTaskCreated,
          ),
        );
        logFirebasePublishPhase('UPLOAD_SUCCESS', '$platformLabel|$storagePath');
        return url;
      }

      final String url;
      if (skipClientPrepare) {
        url = await withUploadTimeout(
          YahwehMediaUploadPipeline.uploadPreparedBytes(
            storagePath: storagePath,
            bytes: bytes,
            contentType: contentType,
            maxAttempts: maxAttempts,
            onProgress: onProgress,
            onUploadTaskCreated: onUploadTaskCreated,
          ),
        );
      } else {
        url = await withUploadTimeout(
          YahwehMediaUploadPipeline.uploadBytes(
            storagePath: storagePath,
            bytes: bytes,
            contentType: _guessImageContentType(bytes, skipClientPrepare),
            module: module,
            localFilePathForRetry: localPath,
            chatJpegFast: chatJpegFast,
            useOfflineQueue: useOfflineQueue,
            onProgress: onProgress,
            onUploadTaskCreated: onUploadTaskCreated,
            maxAttempts: maxAttempts,
          ),
        );
      }
      logFirebasePublishPhase('UPLOAD_SUCCESS', '$platformLabel|$storagePath');
      return url;
    } catch (e, st) {
      logFirebasePublishPhase(
        'UPLOAD_ERROR',
        '$platformLabel|$storagePath',
        error: e,
        stack: st,
      );
      unawaited(
        CrashlyticsService.record(e, st, reason: 'unified_upload_image_${module.name}'),
      );
      rethrow;
    }
  }

  static Future<String> uploadVideo({
    required String storagePath,
    required String localPath,
    required String contentType,
    void Function(double progress)? onProgress,
    int maxAttempts = 3,
  }) async {
    await _ensureReady(module: 'video');
    logFirebasePublishPhase('UPLOAD_START', '$platformLabel|$storagePath|video');
    try {
      if (kIsWeb) {
        throw UnsupportedError('Vídeo por ficheiro local não suportado na web neste serviço.');
      }
      final file = File(localPath);
      if (!await file.exists()) {
        throw StateError('Vídeo não encontrado no aparelho.');
      }
      final compressed = await YahwehMediaUploadPipeline.compressVideoFile(file);
      final url = await MediaUploadService.uploadFileWithRetry(
        storagePath: storagePath,
        file: compressed,
        contentType: contentType,
        maxAttempts: maxAttempts,
        useOfflineQueue: false,
        skipRecompress: true,
        onProgress: onProgress,
      );
      logFirebasePublishPhase('UPLOAD_END', '$platformLabel|$storagePath');
      return url;
    } catch (e, st) {
      logFirebasePublishPhase(
        'UPLOAD_ERROR',
        '$platformLabel|$storagePath',
        error: e,
        stack: st,
      );
      unawaited(CrashlyticsService.record(e, st, reason: 'unified_upload_video'));
      rethrow;
    }
  }

  static Future<String> uploadFile({
    required String storagePath,
    required String localPath,
    required String contentType,
    YahwehUploadModule module = YahwehUploadModule.generic,
    void Function(double progress)? onProgress,
    int maxAttempts = 3,
  }) async {
    await _ensureReady(module: module.name);
    logFirebasePublishPhase('UPLOAD_START', '$platformLabel|$storagePath|file');
    try {
      if (kIsWeb) {
        throw UnsupportedError('uploadFile por path só no mobile.');
      }
      final url = await MediaUploadService.uploadFileWithRetry(
        storagePath: storagePath,
        file: File(localPath),
        contentType: contentType,
        maxAttempts: maxAttempts,
        useOfflineQueue: false,
        skipRecompress: true,
        onProgress: onProgress,
      );
      logFirebasePublishPhase('UPLOAD_END', '$platformLabel|$storagePath');
      return url;
    } catch (e, st) {
      logFirebasePublishPhase(
        'UPLOAD_ERROR',
        '$platformLabel|$storagePath',
        error: e,
        stack: st,
      );
      unawaited(CrashlyticsService.record(e, st, reason: 'unified_upload_file'));
      rethrow;
    }
  }

  /// Capa de template de evento — substitui `FirebaseStorage.instance` na UI.
  static Future<String> uploadJpegBytes({
    required String storagePath,
    required Uint8List bytes,
  }) async {
    await _ensureReady(module: 'event_template');
    logFirebasePublishPhase('UPLOAD_START', '$platformLabel|$storagePath|template');
    try {
      final url = await MediaUploadService.uploadBytesWithRetry(
        storagePath: storagePath,
        bytes: bytes,
        contentType: 'image/jpeg',
        useOfflineQueue: false,
        maxAttempts: 3,
      );
      logFirebasePublishPhase('UPLOAD_END', '$platformLabel|$storagePath');
      return url;
    } catch (e, st) {
      logFirebasePublishPhase('UPLOAD_ERROR', '$platformLabel|$storagePath', error: e, stack: st);
      unawaited(CrashlyticsService.record(e, st, reason: 'unified_upload_template'));
      rethrow;
    }
  }

  static String _guessImageContentType(Uint8List bytes, bool skipClientPrepare) {
    if (skipClientPrepare && bytesLookLikeWebp(bytes)) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
