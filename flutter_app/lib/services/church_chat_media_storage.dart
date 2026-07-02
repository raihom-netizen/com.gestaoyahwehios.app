import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// Upload Storage do chat — [ChurchCentralStorageUpload] → URL https.
abstract final class ChurchChatMediaStorage {
  ChurchChatMediaStorage._();

  static const int _maxAttempts = 3;

  static Future<void> _ensureChatStorageReady() async {
    await AppFinalizeBootstrap.ensureSessionForPublish(logLabel: 'chat_storage');
    await DirectStorageUrlPublish.ensureReady();
  }

  static Future<String> putBytesFast({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 280 * attempt));
          if (isFirebaseNoAppError(last ?? '')) {
            await DirectStorageUrlPublish.ensureReady();
          }
        }
        await ensureFirebaseReadyForChatSend();
        return await _putBytesInternal(
          storagePath: storagePath,
          bytes: bytes,
          contentType: contentType,
          onProgress: onProgress,
        );
      } catch (e, st) {
        last = e;
        if (CrashlyticsService.shouldReport(e)) {
          unawaited(CrashlyticsService.record(e, st, reason: 'chat_putBytesFast'));
        }
      }
    }
    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }
    throw StateError('Falha ao enviar ficheiro do chat.');
  }

  static Future<String> putBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    await _ensureChatStorageReady();
    return _putBytesInternal(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  static Future<String> _putBytesInternal({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final result = await ChurchCentralStorageUpload.uploadAtCanonicalPath(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: contentType,
      logLabel: 'chat_media',
      onProgress: onProgress,
    );
    return result.downloadUrl;
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
    await _ensureChatStorageReady();
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Ficheiro não encontrado no aparelho.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    return _putBytesInternal(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }
}
