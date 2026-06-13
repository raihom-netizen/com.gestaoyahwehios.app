import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/storage_upload_metadata.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Upload Storage do chat — `putData`/`putFile` com timeout e deteção de paragem.
abstract final class ChurchChatMediaStorage {
  ChurchChatMediaStorage._();

  static const int _maxAttempts = 3;

  static Future<void> putBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    await EcoFirePublishBootstrap.ensureHard(logLabel: 'chat_storage_putBytes');
    Object? last;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          await Future<void>.delayed(Duration(milliseconds: 320 * attempt));
        }
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
        await awaitStorageUploadTask(
          task,
          payloadBytes: bytes.length,
          onProgress: onProgress,
        );
        onProgress?.call(1.0);
        return;
      } catch (e) {
        last = e;
        if (!isRetryableUploadError(e) || attempt >= _maxAttempts) break;
      }
    }
    throw last ?? StateError('Falha ao enviar ficheiro no chat.');
  }

  static Future<void> putFile({
    required String storagePath,
    required String localPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('putFile do chat não suportado na web.');
    }
    await EcoFirePublishBootstrap.ensureHard(logLabel: 'chat_storage_putFile');
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Ficheiro não encontrado no aparelho.');
    }
    final byteLen = await file.length();
    Object? last;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          await Future<void>.delayed(Duration(milliseconds: 320 * attempt));
        }
        final ref = firebaseStorageRef(storagePath);
        final ct = StorageUploadMetadata.contentTypeForPut(
          contentType: contentType,
          storagePath: storagePath,
        );
        final task = ref.putFile(
          file,
          SettableMetadata(
            contentType: ct,
            cacheControl: StorageUploadMetadata.cacheControl,
          ),
        );
        await awaitStorageUploadTask(
          task,
          payloadBytes: byteLen,
          onProgress: onProgress,
        );
        onProgress?.call(1.0);
        return;
      } catch (e) {
        last = e;
        if (!isRetryableUploadError(e) || attempt >= _maxAttempts) break;
      }
    }
    throw last ?? StateError('Falha ao enviar ficheiro no chat.');
  }
}
