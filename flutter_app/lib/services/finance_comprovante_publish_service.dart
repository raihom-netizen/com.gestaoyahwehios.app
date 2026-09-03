import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'dart:async' show TimeoutException, unawaited;
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_lancamento_write_service.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/church_unified_photo_upload.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isFirebaseStorageHttpUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Financeiro — comprovante: Storage `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext`
/// ÔåÆ URL HTTPS ÔåÆ Firestore (`comprovanteUrl`, `hasComprovante`).
/// Resultado can+?nico ap+?s upload Storage + grava+?+?o Firestore.
class FinanceComprovantePersistResult {
  const FinanceComprovantePersistResult({
    required this.url,
    required this.storagePath,
    required this.mimeType,
    required this.fileName,
  });

  final String url;
  final String storagePath;
  final String mimeType;
  final String fileName;

  Map<String, dynamic> toFirestorePatch() =>
      FinanceComprovantePublishService.comprovanteFieldsPatch(
        url: url,
        storagePath: storagePath,
        mimeType: mimeType,
        fileName: fileName,
      );
}

/// Comprovante enfileirado localmente — UI trata como sucesso (Controle Total).
class FinanceComprovanteQueuedLocally implements Exception {
  const FinanceComprovanteQueuedLocally();
}

abstract final class FinanceComprovantePublishService {
  FinanceComprovantePublishService._();

  static const String comprovanteUploadStateField = 'comprovanteUploadState';

  /// Campos Firestore can+?nicos (Controle Total) ??? inclui alias [comprovanteLink].
  static Map<String, dynamic> comprovanteFieldsPatch({
    required String url,
    required String storagePath,
    required String mimeType,
    required String fileName,
  }) => ChurchCanonicalMediaContract.financeComprovanteWritePatch(
    url: url,
    storagePath: storagePath,
    mimeType: mimeType,
    fileName: fileName,
  );

  static Future<void> _ensureReady() async {
    // Aquecimento best-effort — teto em `kEnsureReadyTimeout` na fachada.
    await ChurchMediaUploadFacade.ensureReady(requireAuth: true);
  }

  /// Compressão única antes do Storage (imagens) — mesmo padrão avisos/eventos.
  /// Com [alreadyCompressed] (JPEG do picker) — NÃO recomprimir.
  static Future<({Uint8List bytes, String mimeType})> _optimizedForUpload({
    required Uint8List rawBytes,
    required String mimeType,
    bool alreadyCompressed = false,
  }) async {
    final mime = mimeType.toLowerCase();
    if (mime.contains('pdf')) {
      return (bytes: rawBytes, mimeType: mimeType);
    }
    if (mime.contains('png') && alreadyCompressed) {
      return (bytes: rawBytes, mimeType: 'image/png');
    }
    if (alreadyCompressed && (mime.contains('jpeg') || mime.contains('jpg'))) {
      return (bytes: rawBytes, mimeType: 'image/jpeg');
    }
    // Pipeline unificado (financeiro = comprovante).
    final optimized = await ChurchUnifiedPhotoUpload.prepareBytes(
      rawBytes,
      module: ChurchPhotoModules.financeiro,
    );
    return (bytes: optimized, mimeType: 'image/jpeg');
  }

  /// Grava lan+?amento (sem comprovante ou com estado uploading).
  static Future<DocumentReference<Map<String, dynamic>>> saveLancamentoFirst({
    required CollectionReference<Map<String, dynamic>> financeCol,
    required Map<String, dynamic> payload,
    required bool isEdit,
    DocumentReference<Map<String, dynamic>>? existingRef,
    DocumentReference<Map<String, dynamic>>? preGeneratedRef,
    bool hasNewComprovante = false,
    Map<String, dynamic>? previousPayloadForSaldo,
  }) async {
    YahwehFlowLog.financeiroStart();
    final patch = Map<String, dynamic>.from(payload);
    if (hasNewComprovante) {
      patch[comprovanteUploadStateField] = EntityPublishStatus.uploading;
      patch['hasComprovante'] = false;
      patch.remove('comprovanteUrl');
      patch.remove('comprovanteStoragePath');
      patch.remove('comprovanteMimeType');
      patch.remove('comprovanteFileName');
    }
    final tenantId = financeCol.parent?.id ?? '';
    DocumentReference<Map<String, dynamic>> targetRef;
    if (isEdit && existingRef != null) {
      try {
        await _writeFirestore(
          () => FinanceLancamentoWriteService.commitInTransaction(
            churchId: tenantId,
            lancamentoRef: existingRef,
            payload: patch,
            merge: true,
            previousPayload: previousPayloadForSaldo,
          ),
        );
      } catch (e) {
        if (!EcoFireResilientPublish.shouldQueueSilently(e)) {
          try {
            await _writeFirestore(
              () => OptimisticFirestoreWrite.update(
                ref: existingRef,
                data: patch,
                module: OfflineModules.financeiro,
                tenantId: tenantId,
              ),
            );
          } catch (e2) {
            if (!EcoFireResilientPublish.shouldQueueSilently(e2)) rethrow;
            await EcoFireResilientPublish.queueFinanceLancamento(
              churchId: tenantId,
              docRef: existingRef,
              payload: patch,
              isEdit: true,
            );
            EcoFireResilientPublish.scheduleSync(reason: 'finance_save_edit');
          }
        } else {
          await EcoFireResilientPublish.queueFinanceLancamento(
            churchId: tenantId,
            docRef: existingRef,
            payload: patch,
            isEdit: true,
          );
          EcoFireResilientPublish.scheduleSync(reason: 'finance_save_edit');
        }
      }
      YahwehFlowLog.financeiroFirestoreOk();
      return existingRef;
    }
    targetRef = preGeneratedRef ?? financeCol.doc();
    try {
      await _writeFirestore(
        () => FinanceLancamentoWriteService.commitInTransaction(
          churchId: tenantId,
          lancamentoRef: targetRef,
          payload: patch,
          merge: false,
        ),
      );
    } catch (e) {
      if (!EcoFireResilientPublish.shouldQueueSilently(e)) {
        try {
          await _writeFirestore(
            () => OptimisticFirestoreWrite.set(
              ref: targetRef,
              data: patch,
              module: OfflineModules.financeiro,
              tenantId: tenantId,
            ),
          );
        } catch (e2) {
          if (!EcoFireResilientPublish.shouldQueueSilently(e2)) rethrow;
          await EcoFireResilientPublish.queueFinanceLancamento(
            churchId: tenantId,
            docRef: targetRef,
            payload: patch,
            isEdit: false,
          );
          EcoFireResilientPublish.scheduleSync(reason: 'finance_save_new');
        }
      } else {
        await EcoFireResilientPublish.queueFinanceLancamento(
          churchId: tenantId,
          docRef: targetRef,
          payload: patch,
          isEdit: false,
        );
        EcoFireResilientPublish.scheduleSync(reason: 'finance_save_new');
      }
    }
    YahwehFlowLog.financeiroFirestoreOk();
    return targetRef;
  }

  /// Confirma Storage + campos no Firestore ap+?s upload (read-back servidor).
  static Future<void> verifyComprovantePersisted({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String storagePath,
  }) async {
    unawaited(
      ChurchStorageMetadataVerify.assertExists(
        storagePath,
        maxAttempts: 2,
        timeout: const Duration(seconds: 8),
      ).catchError((_) {}),
    );
    final snap = await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.get(const GetOptions(source: Source.serverAndCache)),
      maxAttempts: 4,
    );
    final data = snap.data() ?? {};
    if (data['hasComprovante'] != true) {
      throw StateError(
        'Comprovante enviado mas o Firestore n+?o confirmou hasComprovante.',
      );
    }
    final url = (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
        .toString()
        .trim();
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (url.isEmpty && path.isEmpty) {
      throw StateError(
        'Comprovante enviado mas o link n+?o foi gravado no lan+?amento.',
      );
    }
  }

  static Future<void> markComprovanteUploadFailed({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Object error,
  }) async {
    final msg = error.toString().split('\n').first;
    await runFirestorePublishWithRecovery(
      () => docRef.set({
        comprovanteUploadStateField: EntityPublishStatus.error,
        'comprovanteUploadError': msg.length > 240
            ? msg.substring(0, 240)
            : msg,
        'updatedAt': YahwehFv.serverTimestamp,
      }, SetOptions(merge: true)),
    ).catchError((_) {});
  }

  static Future<void> _writeFirestore(Future<void> Function() action) async {
    await runFirestorePublishWithRecovery(action);
  }

  static Future<String> resolveComprovanteUrl(Map<String, dynamic> data) async {
    final ref = ChurchCanonicalMediaContract.resolveFinanceComprovante(data);
    final cached = YahwehMediaCacheBust.applyFromDocRevision(
      ref.downloadUrl,
      data,
    );
    final path = ref.storagePath.trim();
    if (path.isEmpty) return cached;
    try {
      await ensureFirebaseCore(requireAuth: false);
      Future<String> loadUrl() async {
        final fresh = await firebaseDefaultStorage
            .ref(path)
            .getDownloadURL()
            .timeout(const Duration(seconds: 8), onTimeout: () => '');
        return YahwehMediaCacheBust.applyFromDocRevision(fresh, data);
      }

      if (kIsWeb) {
        return await FirestoreWebGuard.runWithWebRecovery(
          loadUrl,
          maxAttempts: 4,
        );
      }
      return await loadUrl();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('object-not-found') ||
          msg.contains('No object exists')) {
        return '';
      }
      return cached;
    }
  }

  static const Duration kComprovantePublishTimeout = Duration(seconds: 55);
  static const Duration kComprovanteUploadTimeout = Duration(seconds: 60);

  static Future<void> _mergeComprovantePatch({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> patch,
  }) async {
    final data = Map<String, dynamic>.from(patch)
      ..['updatedAt'] = YahwehFv.serverTimestamp;
    await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
    Future<void> write() async {
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
        await AdminFeedFirestoreBridge.upsertDocRef(
          docRef: docRef,
          data: data,
          isNewDoc: false,
          directWrite: () => runFirestorePublishWithRecovery(
            () => YahwehDocWrite.set(docRef, data),
            maxAttempts: 4,
            criticalWrite: true,
          ),
        );
        return;
      }
      await runFirestorePublishWithRecovery(
        () => YahwehDocWrite.set(docRef, data),
      );
    }

    await write().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Comprovante enviado mas falhou ao gravar o link no Firestore.',
      ),
    );
  }

  /// Path can+?nico +?nico: `igrejas/{churchId}/financeiro/YYYY_MM/{lancamentoId}.{ext}`.
  static String comprovantePathFor({
    required String tenantId,
    required String lancamentoId,
    DateTime? referenceDate,
    String ext = 'jpg',
  }) {
    return ChurchStorageLayout.financeComprovantePath(
      tenantId: tenantId,
      lancamentoId: lancamentoId,
      referenceDate: referenceDate,
      ext: ext,
    );
  }

  static DateTime? referenceDateFromMap(Map<String, dynamic> data) {
    for (final key in ['date', 'createdAt']) {
      final raw = data[key];
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is String && raw.length >= 10) {
        return DateTime.tryParse(raw.substring(0, 10));
      }
      if (raw is Map) {
        final sec = raw['seconds'] ?? raw['_seconds'];
        if (sec is num) {
          return DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
        }
      }
    }
    return null;
  }

  static Future<void> deleteComprovanteArtifacts({
    required String tenantId,
    required String lancamentoId,
    String? storagePath,
    String? downloadUrl,
    DateTime? referenceDate,
    String? ext,
  }) async {
    final paths = <String>{
      if (storagePath != null && storagePath.trim().isNotEmpty)
        storagePath.trim(),
      comprovantePathFor(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
        ext: ext ?? 'jpg',
      ),
      comprovantePathFor(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
        ext: 'pdf',
      ),
      comprovantePathFor(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
        ext: 'png',
      ),
      // Legado por tipo (somente limpeza retrocompat+?vel).
      ChurchStorageLayout.financeComprovantePathByTipo(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        tipo: 'receita',
        ext: ext ?? 'jpg',
      ),
      ChurchStorageLayout.financeComprovantePathByTipo(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        tipo: 'despesa',
        ext: ext ?? 'jpg',
      ),
      ChurchStorageLayout.financeComprovantePathByTipo(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        tipo: 'transferencia',
        ext: ext ?? 'jpg',
      ),
      ChurchStorageLayout.financeComprovantePathLegacy(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
      ),
    };
    for (final p in paths) {
      try {
        await firebaseDefaultStorage.ref(p).delete();
      } catch (_) {}
    }
    final u = sanitizeImageUrl((downloadUrl ?? '').trim());
    if (u.isNotEmpty && isFirebaseStorageHttpUrl(u)) {
      await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
    }
  }

  /// S+? Storage (sem Firestore) ??? usar antes do `set` completo em lan+?amento novo.
  static Future<FinanceComprovantePersistResult> uploadComprovanteStorageOnly({
    required String tenantId,
    required String lancamentoId,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () => _uploadComprovanteStorageCore(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        rawBytes: rawBytes,
        mimeType: mimeType,
        fileName: fileName,
        referenceDate: referenceDate,
        previousStoragePath: previousStoragePath,
        previousDownloadUrl: previousDownloadUrl,
        onProgress: onProgress,
        alreadyCompressed: alreadyCompressed,
      ),
      debugLabel: 'finance_comprovante_storage',
      requireAuth: true,
    );
  }

  static Future<FinanceComprovantePersistResult> _uploadComprovanteStorageCore({
    required String tenantId,
    required String lancamentoId,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
  }) async {
    await _ensureReady();
    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) {
      throw StateError('Igreja n+?o identificada para o comprovante.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Arquivo vazio — selecione outra imagem ou PDF.');
    }
    FinanceComprovanteAttachService.assertSupportedPayload(rawBytes);
    final mt = mimeType.toLowerCase();
    if (mt.startsWith('video/') ||
        (!mt.startsWith('image/') && !mt.contains('pdf'))) {
      throw StateError('V+?deo n+?o permitido. Use JPEG, PNG ou PDF.');
    }
    ChurchCentralStorageUpload.assertPayloadWithinRules(
      bytes: rawBytes.length,
      logLabel: 'finance_comprovante',
      maxBytes: mt.contains('pdf')
          ? kStorageRulesMaxFinanceDocBytes
          : kStorageRulesMaxFeedImageBytes,
    );

    onProgress?.call(0.08);
    // Placeholder opcional ??? n+?o bloquear upload (CT: put directo).
    unawaited(
      FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(
        churchId,
      ).catchError((_) {}),
    );

    onProgress?.call(0.12);
    // Uma compress+?o s+? (CT): picker j+? otimizou ??? alreadyCompressed.
    final optimized = await _optimizedForUpload(
      rawBytes: rawBytes,
      mimeType: mimeType,
      alreadyCompressed: alreadyCompressed,
    );
    final ext = optimized.mimeType.contains('pdf')
        ? 'pdf'
        : (optimized.mimeType.contains('png') ? 'png' : 'jpg');
    onProgress?.call(0.15);

    final path = comprovantePathFor(
      tenantId: churchId,
      lancamentoId: lancamentoId,
      referenceDate: referenceDate,
      ext: ext,
    );

    // Controle Total: Storage primeiro; apagar antigo s+? depois do novo OK.
    // Progresso: bytes 15%???96% (nunca -?grudar-+ em 90% +? espera da URL).
    final uploaded =
        await ChurchCentralStorageUpload.uploadAtCanonicalPath(
          storagePath: path,
          bytes: optimized.bytes,
          mimeType: optimized.mimeType,
          logLabel: 'finance_comprovante',
          onProgress: (p) => onProgress?.call(0.15 + p.clamp(0.0, 1.0) * 0.81),
          skipEnsureReady: true,
        ).timeout(
          kComprovanteUploadTimeout,
          onTimeout: () => throw TimeoutException(
            'Upload do comprovante demorou demais. Verifique a rede.',
            kComprovanteUploadTimeout,
          ),
        );

    onProgress?.call(0.97);
    // putData OK = objeto existe; verifica+?+?o pesada s+? em background.
    unawaited(
      ChurchStorageMetadataVerify.assertExists(
        path,
        maxAttempts: 2,
        timeout: const Duration(seconds: 6),
      ).catchError((_) {}),
    );

    // Apagar s+? o artefacto anterior distinto do path novo (nunca o ficheiro acabado de subir).
    final safeName = (fileName ?? '').trim().isNotEmpty
        ? fileName!.trim()
        : 'comprovante.$ext';

    onProgress?.call(0.99);
    return FinanceComprovantePersistResult(
      url: uploaded.downloadUrl,
      storagePath: uploaded.storagePath,
      mimeType: optimized.mimeType,
      fileName: safeName,
    );
  }

  /// Upload Storage ??? Firestore ??? padr+?o Controle Total (sem verify bloqueante).
  static Future<String> uploadComprovanteControleTotal({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
    bool queueOnTransientFailure = true,
  }) async {
    await _ensureReady();
    YahwehFlowLog.uploadStart('comprovante_ct');
    final churchId = ChurchRepository.churchId(tenantId.trim());

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      await FirestoreWebGuard.ensureFirestoreClientAlive().catchError((_) {});
    } else {
      await runFirestorePublishWithRecovery(
        () => docRef.set({
          comprovanteUploadStateField: EntityPublishStatus.uploading,
          'updatedAt': YahwehFv.serverTimestamp,
        }, SetOptions(merge: true)),
      ).catchError((_) {});
    }

    try {
      final persisted = await _uploadComprovanteStorageCore(
        tenantId: tenantId,
        lancamentoId: docRef.id,
        rawBytes: rawBytes,
        mimeType: mimeType,
        fileName: fileName,
        referenceDate: referenceDate,
        previousStoragePath: previousStoragePath,
        previousDownloadUrl: previousDownloadUrl,
        onProgress: onProgress,
        alreadyCompressed: alreadyCompressed,
      );

      await _mergeComprovantePatch(
        docRef: docRef,
        patch: persisted.toFirestorePatch(),
      );

      await verifyComprovantePersisted(
        docRef: docRef,
        storagePath: persisted.storagePath,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Comprovante enviado, mas a vinculacao nao foi confirmada.',
        ),
      );

      final prevPath = (previousStoragePath ?? '').trim();
      final prevUrl = (previousDownloadUrl ?? '').trim();
      if (prevPath.isNotEmpty && prevPath != persisted.storagePath) {
        unawaited(
          firebaseDefaultStorage.ref(prevPath).delete().catchError((_) {}),
        );
      } else if (prevPath.isEmpty &&
          prevUrl.isNotEmpty &&
          isFirebaseStorageHttpUrl(prevUrl)) {
        unawaited(
          FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(prevUrl),
        );
      }

      YahwehFlowLog.financeiroUploadOk();
      YahwehFlowLog.financeiroSuccess();
      onProgress?.call(1.0);
      return persisted.url;
    } catch (e) {
      if (queueOnTransientFailure &&
          !kIsWeb &&
          _shouldQueueComprovanteOffline(e)) {
        final ext = mimeType.toLowerCase().contains('pdf') ? 'pdf' : 'jpg';
        final path = comprovantePathFor(
          tenantId: churchId,
          lancamentoId: docRef.id,
          referenceDate: referenceDate,
          ext: ext,
        );
        await _enqueueComprovanteLocalRetry(
          tenantId: tenantId,
          docRef: docRef,
          bytes: rawBytes,
          mimeType: mimeType,
          storagePath: path,
        );
        throw const FinanceComprovanteQueuedLocally();
      }

      rethrow;
    }
  }

  static bool _shouldQueueComprovanteOffline(Object e) {
    final msg = e.toString().toLowerCase();
    return e is TimeoutException ||
        msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('unavailable') ||
        msg.contains('connection') ||
        msg.contains('offline') ||
        msg.contains('failed host lookup');
  }

  static Future<void> _enqueueComprovanteLocalRetry({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    required String storagePath,
  }) async {
    if (!kIsWeb && bytes.isNotEmpty) {
      try {
        await StorageUploadPersistenceService.enqueueBytesJob(
          storagePath: storagePath,
          bytes: bytes,
          contentType: mimeType,
        );
      } catch (_) {}
    }

    await runFirestorePublishWithRecovery(
      () => docRef.set({
        comprovanteUploadStateField: EntityPublishStatus.uploading,
        'comprovantePendingLocal': true,
        'comprovanteStoragePath': storagePath,
        'hasComprovante': true,
        'updatedAt': YahwehFv.serverTimestamp,
      }, SetOptions(merge: true)),
    ).catchError((_) {});
  }

  /// Upload Storage ÔåÆ validar ÔåÆ gravar URL no Firestore (legado — delega ao CT).
  static Future<String> uploadComprovanteNow({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
  }) => FirebaseBootstrapService.runGuarded(
    () => uploadComprovanteControleTotal(
      tenantId: tenantId,
      docRef: docRef,
      rawBytes: rawBytes,
      mimeType: mimeType,
      fileName: fileName,
      referenceDate: referenceDate,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
      onProgress: onProgress,
      alreadyCompressed: alreadyCompressed,
    ),
    debugLabel: 'finance_comprovante_upload',
    requireAuth: true,
  );

  static Future<void> removeComprovante({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
  }) async {
    await _ensureReady();
    final churchId = ChurchRepository.churchId(tenantId.trim());
    await _mergeComprovantePatch(
      docRef: docRef,
      patch: ChurchCanonicalMediaContract.comprovanteClearFirestorePatch(),
    );
    unawaited(
      deleteComprovanteArtifacts(
        tenantId: churchId,
        lancamentoId: docRef.id,
        storagePath: (data['comprovanteStoragePath'] ?? '').toString(),
        downloadUrl: (data['comprovanteUrl'] ?? '').toString(),
        referenceDate: referenceDateFromMap(data),
      ),
    );
  }

  /// Corrige lan+?amentos com `comprovanteUploadState: uploading` quando o ficheiro j+? est+? no Storage.
  static Future<void> reconcileStuckComprovantes({
    required String tenantId,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int maxChecks = 16,
  }) async {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) return;
    var checked = 0;
    for (final doc in docs) {
      if (checked >= maxChecks) break;
      final data = doc.data();
      final state = (data[comprovanteUploadStateField] ?? '').toString();
      if (state != EntityPublishStatus.uploading) continue;
      checked++;

      final storedPath = (data['comprovanteStoragePath'] ?? '')
          .toString()
          .trim();
      final paths = <String>{
        if (storedPath.isNotEmpty) storedPath,
        comprovantePathFor(
          tenantId: churchId,
          lancamentoId: doc.id,
          referenceDate: referenceDateFromMap(data),
          ext: 'jpg',
        ),
        comprovantePathFor(
          tenantId: churchId,
          lancamentoId: doc.id,
          referenceDate: referenceDateFromMap(data),
          ext: 'pdf',
        ),
        comprovantePathFor(
          tenantId: churchId,
          lancamentoId: doc.id,
          referenceDate: referenceDateFromMap(data),
          ext: 'png',
        ),
      };

      String? foundPath;
      String? url;
      for (final path in paths) {
        try {
          final ref = firebaseDefaultStorage.ref(path);
          await ref.getMetadata().timeout(const Duration(seconds: 8));
          foundPath = path;
          url = await ref.getDownloadURL().timeout(
            const Duration(seconds: 8),
            onTimeout: () => '',
          );
          if (url.isEmpty) {
            foundPath = null;
            url = null;
            continue;
          }
          break;
        } catch (_) {}
      }

      if (foundPath == null || url == null) {
        final updatedAt = data['updatedAt'];
        DateTime? at;
        if (updatedAt is Timestamp) at = updatedAt.toDate();
        if (at != null &&
            DateTime.now().difference(at) > const Duration(hours: 2)) {
          await markComprovanteUploadFailed(
            docRef: doc.reference,
            error: 'Upload n+?o conclu+?do ??? anexe o comprovante novamente.',
          );
        }
        continue;
      }

      try {
        await doc.reference.set(
          comprovanteFieldsPatch(
            url: url,
            storagePath: foundPath,
            mimeType: foundPath.endsWith('.pdf')
                ? 'application/pdf'
                : (foundPath.endsWith('.png') ? 'image/png' : 'image/jpeg'),
            fileName: foundPath.split('/').last,
          ),
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }
}
