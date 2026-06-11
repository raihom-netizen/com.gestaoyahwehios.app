import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Fases do publish transacional — UI pode mapear para barra de progresso.
enum TransactionalMediaPhase {
  compressing,
  uploading,
  savingFirestore,
}

/// Módulo de origem — define compressão e política de UI.
enum TransactionalMediaModule {
  /// Cadastro, patrimônio, avisos — doc Firestore só após Storage OK.
  strict,

  /// Chat / escalas — UI optimista local + retry (ver [ChurchChatMediaOutboxService]).
  optimisticLocal,
}

/// Resultado de compressão + upload concluído (antes do Firestore).
class TransactionalUploadResult {
  const TransactionalUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
    required this.compressedBytes,
  });

  final String downloadUrl;
  final String storagePath;
  final String contentType;
  final Uint8List compressedBytes;
}

/// Pipeline híbrido: **compactação imediata** → **upload com timeout** → **Firestore transacional**.
///
/// Cadastro, Patrimônio e Avisos: [TransactionalMediaModule.strict] — aborta se qualquer etapa falhar.
/// Chat: [TransactionalMediaModule.optimisticLocal] — stub na UI + outbox local para reenvio.
abstract final class TransactionalMediaPublishPipeline {
  TransactionalMediaPublishPipeline._();

  static MediaImageProfile profileForModule(TransactionalMediaModule module) {
    return switch (module) {
      TransactionalMediaModule.strict => MediaImageProfile.feed,
      TransactionalMediaModule.optimisticLocal => MediaImageProfile.chat,
    };
  }

  static YahwehUploadModule yahwehModuleForPath(String storagePath) =>
      YahwehMediaUploadPipeline.moduleFromStoragePath(storagePath);

  /// Compactação agressiva 1024 px / 80 % — reduz fotos de 5–6 MB para ~200–300 KB.
  static Future<Uint8List> compressForUpload({
    required Uint8List rawBytes,
    MediaImageProfile profile = MediaImageProfile.feed,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);
    if (rawBytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outra imagem.');
    }
    final out = await MediaService.compressImageBytes(rawBytes, profile: profile);
    if (out.isEmpty) {
      throw StateError(
        'Não foi possível compactar a imagem. Tente outro formato ou foto menor.',
      );
    }
    onProgress?.call(1.0);
    return out;
  }

  /// [XFile] → bytes → compactar → upload (sem `dart:io` na camada partilhada).
  static Future<TransactionalUploadResult> compressAndUploadXFile({
    required XFile file,
    required String storagePath,
    String? contentType,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    bool useOfflineQueue = false,
  }) async {
    final raw = await MediaService.readXFileBytes(file);
    final profile = profileForModule(module);
    final ct = contentType ??
        MediaService.contentTypeForProfile(
          profile,
          await MediaService.compressImageBytes(raw, profile: profile),
        );
    return compressAndUpload(
      rawBytes: raw,
      storagePath: storagePath,
      contentType: ct,
      module: module,
      onProgress: onProgress,
      useOfflineQueue: useOfflineQueue,
    );
  }

  /// Etapas A+B: compactar → upload Storage (timeout curto para ficheiros leves).
  static Future<TransactionalUploadResult> compressAndUpload({
    required Uint8List rawBytes,
    required String storagePath,
    required String contentType,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    bool useOfflineQueue = false,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw ArgumentError('storagePath vazio.');
    }

    onProgress?.call(TransactionalMediaPhase.compressing, 0);
    final profile = profileForModule(module);
    final compressed = await compressForUpload(
      rawBytes: rawBytes,
      profile: profile,
      onProgress: (p) => onProgress?.call(TransactionalMediaPhase.compressing, p),
    );
    onProgress?.call(TransactionalMediaPhase.compressing, 1);

    onProgress?.call(TransactionalMediaPhase.uploading, 0);
    final yModule = yahwehModuleForPath(path);
    final url = await YahwehMediaUploadPipeline.uploadBytes(
      storagePath: path,
      bytes: compressed,
      contentType: contentType,
      module: yModule,
      useOfflineQueue: useOfflineQueue && module == TransactionalMediaModule.optimisticLocal,
      onProgress: (p) => onProgress?.call(TransactionalMediaPhase.uploading, p),
    );
    onProgress?.call(TransactionalMediaPhase.uploading, 1);

    return TransactionalUploadResult(
      downloadUrl: url,
      storagePath: path,
      contentType: contentType,
      compressedBytes: compressed,
    );
  }

  /// [XFile] + Firestore strict — mesma garantia transacional em Web e mobile.
  static Future<T> publishXFileWithMedia<T>({
    required XFile file,
    required String storagePath,
    String? contentType,
    required Future<T> Function(TransactionalUploadResult upload) saveFirestore,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    int firestoreMaxAttempts = 4,
  }) async {
    final raw = await MediaService.readXFileBytes(file);
    final profile = profileForModule(module);
    final ct = contentType ??
        MediaService.contentTypeForProfile(
          profile,
          await MediaService.compressImageBytes(raw, profile: profile),
        );
    return publishWithMedia(
      rawBytes: raw,
      storagePath: storagePath,
      contentType: ct,
      saveFirestore: saveFirestore,
      module: module,
      onProgress: onProgress,
      firestoreMaxAttempts: firestoreMaxAttempts,
    );
  }

  /// Etapas A+B+C fechadas — **strict**: falha em qualquer ponto cancela o Firestore.
  static Future<T> publishWithMedia<T>({
    required Uint8List rawBytes,
    required String storagePath,
    required String contentType,
    required Future<T> Function(TransactionalUploadResult upload) saveFirestore,
    TransactionalMediaModule module = TransactionalMediaModule.strict,
    void Function(TransactionalMediaPhase phase, double progress)? onProgress,
    int firestoreMaxAttempts = 4,
  }) async {
    if (module != TransactionalMediaModule.strict) {
      throw ArgumentError(
        'publishWithMedia exige strict — chat/escalas usam outbox optimista.',
      );
    }

    TransactionalUploadResult? upload;
    try {
      upload = await compressAndUpload(
        rawBytes: rawBytes,
        storagePath: storagePath,
        contentType: contentType,
        module: module,
        onProgress: onProgress,
        useOfflineQueue: false,
      );

      onProgress?.call(TransactionalMediaPhase.savingFirestore, 0);
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
      }
      final result = await FirestoreWebGuard.runWithWebRecovery(
        () => saveFirestore(upload!),
        maxAttempts: firestoreMaxAttempts,
      );
      onProgress?.call(TransactionalMediaPhase.savingFirestore, 1);
      return result;
    } catch (e) {
      // Strict: nunca deixa doc incompleto — caller mostra erro real.
      rethrow;
    }
  }

  /// Gravação Firestore isolada (quando upload já concluiu noutro serviço strict).
  static Future<void> saveFirestoreWithRecovery({
    required Future<void> Function() write,
    int maxAttempts = 4,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
    await FirestoreWebGuard.runWithWebRecovery(write, maxAttempts: maxAttempts);
  }

  /// Progresso combinado (compress 15 % + upload 75 % + firestore 10 %).
  static double combinedProgress(TransactionalMediaPhase phase, double phaseProgress) {
    final p = phaseProgress.clamp(0.0, 1.0);
    return switch (phase) {
      TransactionalMediaPhase.compressing => p * 0.15,
      TransactionalMediaPhase.uploading => 0.15 + p * 0.75,
      TransactionalMediaPhase.savingFirestore => 0.90 + p * 0.10,
    };
  }

  /// Timeout efectivo para imagem já compactada (~200 KB–1 MB).
  static Duration compressedImageUploadTimeout(Uint8List bytes) {
    if (bytes.length <= kStorageUploadCompressedImageMaxBytes) {
      return Duration(seconds: kStorageUploadCompressedImageMaxSeconds);
    }
    return Duration(seconds: kStorageUploadImageMaxSeconds);
  }
}
