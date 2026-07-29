import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

/// Upload Storage do chat — padrão Controle Total / Telegram: `putData` direto → URL.
abstract final class ChurchChatMediaStorage {
  ChurchChatMediaStorage._();

  static Future<String> putBytesFast({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    // Fachada unificada: warmup token + Storage (session-cache) antes do putData.
    // O pipeline subjacente já faz retry e recover de no-app.
    final module = YahwehMediaUploadPipeline.moduleFromStoragePath(storagePath);
    try {
      return await ChurchMediaUploadFacade.uploadFromPipeline(
        storagePath: storagePath,
        bytes: bytes,
        module: module == YahwehUploadModule.chat
            ? module
            : YahwehUploadModule.generic,
        onProgress: onProgress,
      );
    } catch (e, st) {
      if (CrashlyticsService.shouldReport(e)) {
        unawaited(
          CrashlyticsService.record(e, st, reason: 'chat_putBytesFast'),
        );
      }
      if (e is Exception) rethrow;
      throw StateError(e.toString());
    }
  }

  static Future<String> putBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) => putBytesFast(
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
