import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/transactional_media_publish_pipeline.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:image_picker/image_picker.dart' show XFile;

export 'package:gestao_yahweh/services/transactional_media_publish_pipeline.dart'
    show
        TransactionalMediaModule,
        TransactionalMediaPhase,
        TransactionalUploadResult;

/// Pipeline **único** Web / iOS / Android — seleção via [XFile], compactação híbrida,
/// upload Storage e gravação Firestore transacional.
///
/// Camada partilhada: **nunca** `dart:io` / `File` — só [XFile.readAsBytes].
/// Mobile usa `flutter_image_compress`; Web usa [WebImageCompressService] (Dart puro).
abstract final class CrossPlatformMediaPipeline {
  CrossPlatformMediaPipeline._();

  static bool _busy = false;

  /// Evita duplo clique em Salvar/Enviar enquanto o pipeline corre.
  static bool get isBusy => _busy;

  /// Lê bytes de qualquer plataforma — API idêntica na Web e no mobile.
  static Future<Uint8List> readBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    return bytes;
  }

  /// Path local só no mobile (vídeo / retry offline). Na Web devolve `null`.
  static String? localPathIfAvailable(XFile file) {
    if (kIsWeb) return null;
    final p = file.path.trim();
    return p.isNotEmpty ? p : null;
  }

  /// Compactação adaptada à plataforma — saída leve (JPEG/WebP) para Storage.
  static Future<({Uint8List bytes, String contentType})> prepareImage(
    XFile file, {
    MediaImageProfile profile = MediaImageProfile.feed,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);
    final prepared = await MediaService.compressXFile(file, profile: profile);
    onProgress?.call(1.0);
    return prepared;
  }

  /// A) progresso → B) compactar → C) upload Storage → URL.
  static Future<TransactionalUploadResult> compressAndUploadXFile({
    required XFile file,
    required String storagePath,
    String? contentType,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    bool useOfflineQueue = false,
  }) {
    return TransactionalMediaPublishPipeline.compressAndUploadXFile(
      file: file,
      storagePath: storagePath,
      contentType: contentType,
      module: module,
      onProgress: onProgress,
      useOfflineQueue: useOfflineQueue,
    );
  }

  static MediaImageProfile profileForModule(TransactionalMediaModule module) =>
      TransactionalMediaPublishPipeline.profileForModule(module);

  /// Fluxo completo strict: compactar → Storage → Firestore (com retry unificado).
  static Future<T> publishXFileWithFirestore<T>({
    required XFile file,
    required String storagePath,
    String? contentType,
    required Future<T> Function(TransactionalUploadResult upload) saveFirestore,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    String? progressLabel,
    int firestoreMaxAttempts = 4,
  }) async {
    if (_busy) {
      throw StateError('Já existe um envio em curso. Aguarde a conclusão.');
    }
    _busy = true;
    final label = progressLabel ?? _defaultProgressLabel(module);
    GlobalUploadProgress.instance.start(label);
    try {
      return await TransactionalMediaPublishPipeline.publishXFileWithMedia(
        file: file,
        storagePath: storagePath,
        contentType: contentType,
        saveFirestore: saveFirestore,
        module: module,
        onProgress: (phase, p) {
          GlobalUploadProgress.instance.update(
            TransactionalMediaPublishPipeline.combinedProgress(phase, p),
          );
          onProgress?.call(phase, p);
        },
        firestoreMaxAttempts: firestoreMaxAttempts,
      );
    } catch (e) {
      throw StateError(formatUploadErrorForUser(e));
    } finally {
      _busy = false;
      GlobalUploadProgress.instance.end();
    }
  }

  /// Upload de imagem (sem Firestore) — mesma UX em todas as plataformas.
  static Future<String> uploadImageXFile({
    required XFile file,
    required String storagePath,
    YahwehUploadModule module = YahwehUploadModule.generic,
    void Function(double progress)? onProgress,
    bool chatJpegFast = false,
  }) async {
    if (_busy) {
      throw StateError('Já existe um envio em curso. Aguarde a conclusão.');
    }
    _busy = true;
    try {
      return await UnifiedUploadService.uploadFromXFile(
        file: file,
        storagePath: storagePath,
        module: module,
        chatJpegFast: chatJpegFast,
        onProgress: onProgress,
      );
    } catch (e) {
      throw StateError(formatUploadErrorForUser(e));
    } finally {
      _busy = false;
    }
  }

  static String _defaultProgressLabel(TransactionalMediaModule module) {
    return switch (module) {
      TransactionalMediaModule.strict => 'A preparar e enviar…',
      TransactionalMediaModule.optimisticLocal => 'A enviar…',
    };
  }
}
