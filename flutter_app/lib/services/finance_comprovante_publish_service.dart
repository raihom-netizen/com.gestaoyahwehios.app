import 'dart:async' show TimeoutException;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isFirebaseStorageHttpUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Financeiro — comprovante: Storage `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext`
/// → URL HTTPS → Firestore (`comprovanteUrl`, `hasComprovante`).
abstract final class FinanceComprovantePublishService {
  FinanceComprovantePublishService._();

  static const String comprovanteUploadStateField = 'comprovanteUploadState';

  static Future<void> _ensureReady() async {
    await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
    await ensureFirebaseCore(requireAuth: true);
    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: 'finance_comprovante',
    ).timeout(const Duration(seconds: 20), onTimeout: () {});
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
  }

  /// Grava lançamento (sem comprovante ou com estado uploading).
  static Future<DocumentReference<Map<String, dynamic>>> saveLancamentoFirst({
    required CollectionReference<Map<String, dynamic>> financeCol,
    required Map<String, dynamic> payload,
    required bool isEdit,
    DocumentReference<Map<String, dynamic>>? existingRef,
    bool hasNewComprovante = false,
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
    if (isEdit && existingRef != null) {
      await _writeFirestore(
        () => OptimisticFirestoreWrite.update(
          ref: existingRef,
          data: patch,
          module: OfflineModules.financeiro,
          tenantId: tenantId,
        ),
      );
      YahwehFlowLog.financeiroFirestoreOk();
      return existingRef;
    }
    final ref = financeCol.doc();
    await _writeFirestore(
      () => OptimisticFirestoreWrite.set(
        ref: ref,
        data: patch,
        module: OfflineModules.financeiro,
        tenantId: tenantId,
      ),
    );
    YahwehFlowLog.financeiroFirestoreOk();
    return ref;
  }

  static Future<void> _writeFirestore(Future<void> Function() action) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      await FirestoreWebGuard.runWithWebRecovery(action, maxAttempts: 4);
      return;
    }
    await action();
  }

  static Future<String> resolveComprovanteUrl(Map<String, dynamic> data) async {
    final url = sanitizeImageUrl((data['comprovanteUrl'] ?? '').toString());
    if (url.isNotEmpty) return url;
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (path.isEmpty) return '';
    try {
      await ensureFirebaseCore(requireAuth: false);
      return await firebaseDefaultStorage.ref(path).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  static String comprovantePathFor({
    required String tenantId,
    required String lancamentoId,
    DateTime? referenceDate,
    String ext = 'jpg',
  }) =>
      ChurchStorageLayout.financeComprovantePath(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
        ext: ext,
      );

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

  static String _extFromMime(String mimeType, String? fileName) {
    final m = mimeType.toLowerCase();
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('png')) return 'png';
    final fn = (fileName ?? '').toLowerCase();
    if (fn.endsWith('.pdf')) return 'pdf';
    if (fn.endsWith('.png')) return 'png';
    return 'jpg';
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

  /// Upload Storage → validar → gravar URL no Firestore (síncrono, sem falso sucesso).
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
  }) async {
    return FirebaseBootstrapService.runGuarded(
      () async {
        await _ensureReady();
        YahwehFlowLog.uploadStart('comprovante');

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

        onProgress?.call(0.05);
        await FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(
          churchId,
        );

        final ext = _extFromMime(mimeType, fileName);
        await deleteComprovanteArtifacts(
          tenantId: churchId,
          lancamentoId: docRef.id,
          storagePath: previousStoragePath,
          downloadUrl: previousDownloadUrl,
          referenceDate: referenceDate,
          ext: ext,
        );
        onProgress?.call(0.12);

        final path = comprovantePathFor(
          tenantId: churchId,
          lancamentoId: docRef.id,
          referenceDate: referenceDate,
          ext: ext,
        );

        final contentType = ext == 'pdf'
            ? 'application/pdf'
            : (ext == 'png' ? 'image/png' : 'image/jpeg');

        final url = await EcoFireStorageUpload.putData(
          storagePath: path,
          bytes: rawBytes,
          mimeType: contentType,
          onProgress: (p) => onProgress?.call(0.12 + p * 0.78),
        ).timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException(
            'Upload do comprovante demorou demais. Verifique a rede.',
          ),
        );

        onProgress?.call(0.92);
        await ChurchStorageMetadataVerify.assertExists(
          path,
          maxAttempts: 4,
          timeout: const Duration(seconds: 12),
        );

        final safeName = (fileName ?? '').trim().isNotEmpty
            ? fileName!.trim()
            : 'comprovante.$ext';

        final firestorePatch = {
          'comprovanteUrl': sanitizeImageUrl(url),
          'comprovanteStoragePath': path,
          'comprovanteMimeType': contentType,
          'comprovanteFileName': safeName,
          'hasComprovante': true,
          comprovanteUploadStateField: EntityPublishStatus.published,
          'comprovanteUploadError': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await FirestoreWebGuard.runWithWebRecovery(
          () => docRef.set(firestorePatch, SetOptions(merge: true)),
          maxAttempts: 4,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            'Comprovante enviado mas falhou ao gravar o link no Firestore.',
          ),
        );

        YahwehFlowLog.financeiroUploadOk();
        YahwehFlowLog.financeiroSuccess();
        onProgress?.call(1.0);
        return url;
      },
      debugLabel: 'finance_comprovante_upload',
      requireAuth: true,
    );
  }

  static Future<void> removeComprovante({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
  }) async {
    await _ensureReady();
    final churchId = ChurchRepository.churchId(tenantId.trim());
    await deleteComprovanteArtifacts(
      tenantId: churchId,
      lancamentoId: docRef.id,
      storagePath: (data['comprovanteStoragePath'] ?? '').toString(),
      downloadUrl: (data['comprovanteUrl'] ?? '').toString(),
      referenceDate: referenceDateFromMap(data),
    );
    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(
        {
          'hasComprovante': false,
          comprovanteUploadStateField: FieldValue.delete(),
          'comprovanteUrl': FieldValue.delete(),
          'comprovanteStoragePath': FieldValue.delete(),
          'comprovanteMimeType': FieldValue.delete(),
          'comprovanteFileName': FieldValue.delete(),
          'comprovanteUploadError': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    );
  }
}
