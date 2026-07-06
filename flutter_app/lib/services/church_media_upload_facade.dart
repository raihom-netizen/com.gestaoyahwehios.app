import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart'
    show formatUploadErrorForUser;
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';

export 'package:gestao_yahweh/services/upload_storage_task.dart'
    show formatUploadErrorForUser, isRetryableUploadError;

/// Sessão de upload cancelável — guarde [task] e chame [cancel] na UI.
class ChurchCancellableUpload {
  ChurchCancellableUpload(this.task);

  final UploadTask task;
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await task.cancel();
    } catch (_) {}
  }
}

/// Item para upload em lote paralelo.
class ChurchMediaUploadBatchItem {
  const ChurchMediaUploadBatchItem({
    required this.bytes,
    required this.storagePath,
    this.logLabel = 'batch_photo',
    this.alreadyCompressed = false,
  });

  final Uint8List bytes;
  final String storagePath;
  final String logLabel;
  final bool alreadyCompressed;
}

/// Resultado por slot no lote — sucesso ou erro individual.
class ChurchMediaUploadBatchResult {
  const ChurchMediaUploadBatchResult({
    required this.index,
    this.result,
    this.error,
  });

  final int index;
  final ChurchCentralUploadResult? result;
  final Object? error;

  bool get ok => result != null && error == null;
}

/// **Ponto único** de upload de mídia no painel igreja (Eventos, Avisos, Membros,
/// Património, Financeiro, Chat, Cadastro).
///
/// Ordem obrigatória nas telas: validar → [ensureReady] → upload(s) → Firestore.
/// Não criar uploads soltos na UI — delegar aqui ou em [ChurchCentralStorageUpload].
abstract final class ChurchMediaUploadFacade {
  ChurchMediaUploadFacade._();

  static const Duration kDefaultTimeout = Duration(seconds: 60);

  /// Alias pedido no prompt — bytes + path canónico `igrejas/{churchId}/…`.
  static Future<ChurchCentralUploadResult> uploadMidia({
    required Uint8List bytes,
    required String storagePath,
    String logLabel = 'media',
    bool alreadyCompressed = false,
    bool compressForFeed = true,
    void Function(double progress)? onProgress,
    void Function(ChurchCancellableUpload handle)? onUploadStarted,
    Duration timeout = kDefaultTimeout,
    int maxBytes = kStorageRulesMaxFeedImageBytes,
  }) async {
    return uploadImageAtPath(
      storagePath: storagePath,
      rawBytes: bytes,
      logLabel: logLabel,
      alreadyCompressed: alreadyCompressed,
      compressForFeed: compressForFeed,
      onProgress: onProgress,
      onUploadTaskCreated: (task) {
        onUploadStarted?.call(ChurchCancellableUpload(task));
      },
      timeout: timeout,
      maxBytes: maxBytes,
    );
  }

  /// Upload com compressão + timeout + progresso + cancelamento.
  static Future<ChurchCentralUploadResult> uploadImageAtPath({
    required String storagePath,
    required Uint8List rawBytes,
    required String logLabel,
    bool alreadyCompressed = false,
    bool compressForFeed = true,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
    Duration timeout = kDefaultTimeout,
    int maxBytes = kStorageRulesMaxFeedImageBytes,
  }) async {
    await ensureReady();
    try {
      return await ChurchCentralStorageUpload.uploadImageAtPath(
        storagePath: storagePath,
        rawBytes: rawBytes,
        logLabel: logLabel,
        alreadyCompressed: alreadyCompressed,
        compressForFeed: compressForFeed,
        onProgress: onProgress,
        onUploadTaskCreated: onUploadTaskCreated,
        maxBytes: maxBytes,
      ).timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Upload demorou demais ($logLabel). Verifique a rede ou toque em Cancelar.',
          timeout,
        ),
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'facade_upload_error',
        '$logLabel path=$storagePath',
        error: e,
        stack: st,
      );
      unawaited(CrashlyticsService.record(e, st, reason: 'church_media_upload_$logLabel'));
      rethrow;
    }
  }

  /// Várias fotos em paralelo (limite [mediaFeedUploadMaxConcurrent]) — erro por item.
  static Future<List<ChurchMediaUploadBatchResult>> uploadBatchParallel({
    required List<ChurchMediaUploadBatchItem> items,
    void Function(int index, double progress)? onItemProgress,
    void Function(int completed, int total)? onBatchProgress,
    Duration timeoutPerItem = kDefaultTimeout,
  }) async {
    if (items.isEmpty) return const [];
    await ensureReady();

    final concurrency = mediaFeedUploadMaxConcurrent.clamp(1, 6);
    final results = List<ChurchMediaUploadBatchResult?>.filled(items.length, null);
    var completed = 0;
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex;
        nextIndex++;
        if (i >= items.length) return;
        final item = items[i];
        try {
          final uploaded = await uploadImageAtPath(
            storagePath: item.storagePath,
            rawBytes: item.bytes,
            logLabel: item.logLabel,
            alreadyCompressed: item.alreadyCompressed,
            onProgress: onItemProgress == null
                ? null
                : (p) => onItemProgress(i, p),
            timeout: timeoutPerItem,
          );
          results[i] = ChurchMediaUploadBatchResult(index: i, result: uploaded);
        } catch (e) {
          results[i] = ChurchMediaUploadBatchResult(index: i, error: e);
        }
        completed++;
        onBatchProgress?.call(completed, items.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return results.map((r) => r!).toList(growable: false);
  }

  /// Primeiro upload falhou no lote — agrega mensagens reais.
  static Object? firstBatchError(List<ChurchMediaUploadBatchResult> batch) {
    for (final r in batch) {
      if (r.error != null) return r.error;
    }
    return null;
  }

  /// Gate Firebase + Storage + Firestore antes de qualquer módulo.
  static Future<void> ensureReady({
    YahwehMediaModule? module,
    bool withPhotos = true,
  }) async {
    await DirectStorageUrlPublish.ensureReady();
    await YahwehModuleMediaGate.assertReadyForUploadAction(withPhotos: withPhotos);
  }

  /// Atalho por módulo (Eventos, Avisos, Chat, Património, Financeiro, Cadastro).
  static Future<void> ensureModuleReady(
    YahwehMediaModule module, {
    bool withPhotos = true,
  }) =>
      ensureReady(module: module, withPhotos: withPhotos);

  /// Mensagem amigável com código real — use no `catch` das telas.
  static String mensagemAmigavel(Object error) => formatUploadErrorForUser(error);

  /// Chat / ficheiros genéricos — delega a [UnifiedUploadService].
  static Future<String> uploadFromPipeline({
    required Uint8List bytes,
    required String storagePath,
    YahwehUploadModule module = YahwehUploadModule.generic,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    await ensureReady();
    ChurchCentralStorageUpload.assertPayloadWithinRules(
      bytes: bytes.length,
      logLabel: module.name,
    );
    return UnifiedUploadService.uploadImage(
      storagePath: storagePath,
      bytes: bytes,
      module: module,
      onProgress: onProgress,
      onUploadTaskCreated: onUploadTaskCreated,
    );
  }
}
