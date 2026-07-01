import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload Storage do chat — delega a [YahwehMediaUploadPipeline] / [MediaUploadService]
/// após bootstrap (`ensureStorageAlwaysLinked` / `EcoFirePublishBootstrap`).
abstract final class ChurchChatMediaStorage {
  ChurchChatMediaStorage._();

  static const int _maxAttempts = 3;

  static Future<void> _ensureChatStorageReady({bool fast = false}) async {
    await AppFinalizeBootstrap.ensureSessionForPublish(logLabel: 'chat_storage');
    await ensureFirebaseReadyForMediaUpload();
    if (FirebaseBootstrapService.isStorageUploadBootstrapFresh) {
      try {
        FirebaseBootstrapService.probeStorageLinked();
        return;
      } catch (_) {
        FirebaseBootstrapService.invalidateStorageUploadBootstrap();
      }
    }
    if (fast) {
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: true,
      );
      return;
    }
    await EcoFirePublishBootstrap.ensureHard(
      logLabel: 'chat_storage',
      strict: true,
    );
  }

  /// Caminho rápido: bootstrap + upload → URL https (EcoFire / Controle Total).
  static Future<String> putBytesFast({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () => _putBytesInternal(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        onProgress: onProgress,
      ),
      debugLabel: 'chat_putBytesFast',
    );
  }

  static Future<String> putBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () async {
        await _ensureChatStorageReady();
        return _putBytesInternal(
          storagePath: storagePath,
          bytes: bytes,
          contentType: contentType,
          onProgress: onProgress,
        );
      },
      debugLabel: 'chat_putBytes',
    );
  }

  static Future<String> _putBytesInternal({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    await _ensureChatStorageReady(fast: true);
    try {
      return await YahwehMediaUploadPipeline.uploadPreparedBytes(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        maxAttempts: _maxAttempts,
        onProgress: onProgress,
      );
    } catch (e, st) {
      if (CrashlyticsService.shouldReport(e)) {
        unawaited(
          CrashlyticsService.record(e, st, reason: 'chat_putBytes'),
        );
      }
      rethrow;
    }
  }

  static Future<String> putFile({
    required String storagePath,
    required String localPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('putFile do chat não suportado na web.');
    }
    return FirebaseBootstrapService.runGuarded(
      () async {
        await _ensureChatStorageReady();
        final file = File(localPath);
        if (!await file.exists()) {
          throw StateError('Ficheiro não encontrado no aparelho.');
        }
        try {
          return await MediaUploadService.uploadFileWithRetry(
            storagePath: storagePath,
            file: file,
            contentType: contentType,
            maxAttempts: _maxAttempts,
            onProgress: onProgress,
            skipRecompress: true,
          );
        } catch (e, st) {
          if (CrashlyticsService.shouldReport(e)) {
            unawaited(
              CrashlyticsService.record(e, st, reason: 'chat_putFile'),
            );
          }
          rethrow;
        }
      },
      debugLabel: 'chat_putFile',
    );
  }
}
