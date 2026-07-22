import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// Upload Storage do chat — padrão Controle Total / Telegram: `putData` direto → URL.
abstract final class ChurchChatMediaStorage {
  ChurchChatMediaStorage._();

  static const int _maxAttempts = 3;

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
          await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
          await EcoFireDirectFirebase.ensureDefaultApp();
          await DirectStorageUrlPublish.ensureReady(requireAuth: true);
        }
        return await DirectStorageUrlPublish.uploadBytes(
          storagePath: storagePath,
          bytes: bytes,
          mimeType: contentType,
          onProgress: onProgress,
          requireAuth: true,
          // 1.ª tentativa: gate já feito no send; retry faz ensureReady acima.
          skipEnsureReady: attempt == 0,
        );
      } catch (e, st) {
        last = e;
        if (CrashlyticsService.shouldReport(e)) {
          unawaited(
            CrashlyticsService.record(e, st, reason: 'chat_putBytesFast'),
          );
        }
        if (attempt < _maxAttempts - 1 && isFirebaseNoAppError(e)) {
          continue;
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
  }) =>
      putBytesFast(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        onProgress: onProgress,
      );

  /// @deprecated Preferir [putBytesFast] com bytes lidos do picker — mantido para legado.
  static Future<String> putFile({
    required String storagePath,
    required String localPath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'putFile do chat não suportado na web — use bytes do picker.',
      );
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Ficheiro não encontrado no aparelho.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    return putBytesFast(
      storagePath: storagePath,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }
}
