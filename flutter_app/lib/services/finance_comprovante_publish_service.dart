import 'dart:async' show TimeoutException, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
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
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/services/finance_lancamento_write_service.dart';
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
/// → URL HTTPS → Firestore (`comprovanteUrl`, `hasComprovante`).
/// Resultado canónico após upload Storage + gravação Firestore.
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

  /// Campos Firestore canónicos (Controle Total) — inclui alias [comprovanteLink].
  static Map<String, dynamic> comprovanteFieldsPatch({
    required String url,
    required String storagePath,
    required String mimeType,
    required String fileName,
  }) =>
      ChurchCanonicalMediaContract.financeComprovanteWritePatch(
        url: url,
        storagePath: storagePath,
        mimeType: mimeType,
        fileName: fileName,
      );

  static Future<void> _ensureReady() async {
    await DirectStorageUrlPublish.ensureReady(requireAuth: true);
  }

  /// Compressão em isolate antes do Storage (imagens apenas).
  /// Com [alreadyCompressed] (JPEG do picker) — NÃO recomprimir (padrão CT).
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
    if (alreadyCompressed &&
        (mime.contains('jpeg') || mime.contains('jpg'))) {
      return (bytes: rawBytes, mimeType: 'image/jpeg');
    }
    final optimized = await MediaOptimizationService.optimizeForReceipt(rawBytes);
    return (bytes: optimized, mimeType: 'image/jpeg');
  }

  /// Grava lançamento (sem comprovante ou com estado uploading).
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

  /// Confirma Storage + campos no Firestore após upload (read-back servidor).
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
        'Comprovante enviado mas o Firestore não confirmou hasComprovante.',
      );
    }
    final url = (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
        .toString()
        .trim();
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (url.isEmpty && path.isEmpty) {
      throw StateError(
        'Comprovante enviado mas o link não foi gravado no lançamento.',
      );
    }
  }

  static Future<void> markComprovanteUploadFailed({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Object error,
  }) async {
    final msg = error.toString().split('\n').first;
    await runFirestorePublishWithRecovery(
      () => docRef.set(
        {
          comprovanteUploadStateField: EntityPublishStatus.error,
          'comprovanteUploadError': msg.length > 240 ? msg.substring(0, 240) : msg,
          'hasComprovante': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    ).catchError((_) {});
  }

  static Future<void> _writeFirestore(Future<void> Function() action) async {
    await runFirestorePublishWithRecovery(action);
  }

  static Future<String> resolveComprovanteUrl(Map<String, dynamic> data) async {
    final cached = YahwehMediaCacheBust.applyFromDocRevision(
      (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '').toString(),
      data,
    );
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
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
    } catch (_) {
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
      ..['updatedAt'] = FieldValue.serverTimestamp();
    await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      await AdminFeedFirestoreBridge.upsertDocRef(
        docRef: docRef,
        data: data,
        isNewDoc: false,
        directWrite: () => runFirestorePublishWithRecovery(
          () => docRef.set(data, SetOptions(merge: true)),
          maxAttempts: 4,
          criticalWrite: true,
        ),
      );
      return;
    }
    await runFirestorePublishWithRecovery(
      () => docRef.set(data, SetOptions(merge: true)),
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Comprovante enviado mas falhou ao gravar o link no Firestore.',
      ),
    );
  }

  /// Path canónico único: `igrejas/{churchId}/financeiro/YYYY_MM/{lancamentoId}.{ext}`.
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
      if (storagePath != null && storagePath.trim().isNotEmpty) storagePath.trim(),
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
      // Legado por tipo (somente limpeza retrocompatível).
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

  /// Só Storage (sem Firestore) — usar antes do `set` completo em lançamento novo.
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
      throw StateError('Igreja não identificada para o comprovante.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Arquivo vazio — selecione outra imagem ou PDF.');
    }
    final mt = mimeType.toLowerCase();
    if (mt.startsWith('video/')) {
      throw StateError('Vídeo não permitido. Use JPEG, PNG ou PDF.');
    }
    ChurchCentralStorageUpload.assertPayloadWithinRules(
      bytes: rawBytes.length,
      logLabel: 'finance_comprovante',
      maxBytes: mt.contains('pdf')
          ? kStorageRulesMaxFinanceDocBytes
          : kStorageRulesMaxFeedImageBytes,
    );

    onProgress?.call(0.08);
    // Placeholder opcional — não bloquear upload (CT: put directo).
    unawaited(
      FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(
        churchId,
      ).catchError((_) {}),
    );

    onProgress?.call(0.12);
    // Uma compressão só (CT): picker já otimizou → alreadyCompressed.
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

    // Controle Total: Storage primeiro; apagar antigo só depois do novo OK.
    final uploaded = await ChurchCentralStorageUpload.uploadAtCanonicalPath(
      storagePath: path,
      bytes: optimized.bytes,
      mimeType: optimized.mimeType,
      logLabel: 'finance_comprovante',
      onProgress: (p) => onProgress?.call(0.15 + p * 0.75),
    ).timeout(
      kComprovanteUploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload do comprovante demorou demais. Verifique a rede.',
        kComprovanteUploadTimeout,
      ),
    );

    onProgress?.call(0.90);
    // putData OK = objeto existe; verificação pesada só em background.
    unawaited(
      ChurchStorageMetadataVerify.assertExists(
        path,
        maxAttempts: 2,
        timeout: const Duration(seconds: 6),
      ).catchError((_) {}),
    );

    // Apagar só o artefacto anterior distinto do path novo (nunca o ficheiro acabado de subir).
    final prevPath = (previousStoragePath ?? '').trim();
    final prevUrl = (previousDownloadUrl ?? '').trim();
    if (prevPath.isNotEmpty && prevPath != uploaded.storagePath) {
      try {
        await firebaseDefaultStorage.ref(prevPath).delete();
      } catch (_) {}
    }
    if (prevUrl.isNotEmpty &&
        isFirebaseStorageHttpUrl(prevUrl) &&
        !prevUrl.contains(uploaded.storagePath)) {
      unawaited(
        FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(prevUrl),
      );
    }

    final safeName = (fileName ?? '').trim().isNotEmpty
        ? fileName!.trim()
        : 'comprovante.$ext';

    onProgress?.call(0.95);
    return FinanceComprovantePersistResult(
      url: uploaded.downloadUrl,
      storagePath: uploaded.storagePath,
      mimeType: optimized.mimeType,
      fileName: safeName,
    );
  }

  /// Upload Storage → Firestore — padrão Controle Total (sem verify bloqueante).
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
  }) async {
    await _ensureReady();
    YahwehFlowLog.uploadStart('comprovante_ct');
    final churchId = ChurchRepository.churchId(tenantId.trim());

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      await FirestoreWebGuard.ensureFirestoreClientAlive().catchError((_) {});
    } else {
      await runFirestorePublishWithRecovery(
        () => docRef.set(
          {
            comprovanteUploadStateField: EntityPublishStatus.uploading,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
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

      unawaited(
        verifyComprovantePersisted(
          docRef: docRef,
          storagePath: persisted.storagePath,
        ).catchError((_) {}),
      );

      YahwehFlowLog.financeiroUploadOk();
      YahwehFlowLog.financeiroSuccess();
      onProgress?.call(1.0);
      return persisted.url;
    } catch (e) {
      if (!kIsWeb && _shouldQueueComprovanteOffline(e)) {
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
      () => docRef.set(
        {
          comprovanteUploadStateField: EntityPublishStatus.uploading,
          'comprovantePendingLocal': true,
          'comprovanteStoragePath': storagePath,
          'hasComprovante': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    ).catchError((_) {});
  }

  /// Upload Storage → validar → gravar URL no Firestore (legado — delega ao CT).
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
  }) =>
      FirebaseBootstrapService.runGuarded(
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

  /// Corrige lançamentos com `comprovanteUploadState: uploading` quando o ficheiro já está no Storage.
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

      final storedPath = (data['comprovanteStoragePath'] ?? '').toString().trim();
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
          url = await ref
              .getDownloadURL()
              .timeout(const Duration(seconds: 8), onTimeout: () => '');
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
            error: 'Upload não concluído — anexe o comprovante novamente.',
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
