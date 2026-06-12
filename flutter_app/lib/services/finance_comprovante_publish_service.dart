import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isFirebaseStorageHttpUrl, sanitizeImageUrl;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Financeiro — comprovante em `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.ext`.
abstract final class FinanceComprovantePublishService {
  FinanceComprovantePublishService._();

  static const String comprovanteUploadStateField = 'comprovanteUploadState';

  /// Grava lançamento; comprovante vai em seguida via [uploadComprovanteNow].
  static Future<DocumentReference<Map<String, dynamic>>> saveLancamentoFirst({
    required CollectionReference<Map<String, dynamic>> financeCol,
    required Map<String, dynamic> payload,
    required bool isEdit,
    DocumentReference<Map<String, dynamic>>? existingRef,
    bool hasNewComprovante = false,
  }) async {
    YahwehFlowLog.start('FINANCEIRO');
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
      YahwehFlowLog.success('FINANCEIRO');
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
    YahwehFlowLog.success('FINANCEIRO');
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

  /// URL para exibir — `comprovanteUrl` ou resolve `comprovanteStoragePath`.
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

  /// Upload síncrono — Storage primeiro, depois merge no Firestore.
  static Future<String> uploadComprovanteNow({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
  }) async {
    await ensureFirebaseCore(requireAuth: true);
    YahwehFlowLog.uploadStart('comprovante');

    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) {
      throw StateError('Igreja não identificada para o comprovante.');
    }

    await FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(
      churchId,
    );

    final ext = EcoFireImageProcess.extensionFromMime(mimeType);
    await deleteComprovanteArtifacts(
      tenantId: churchId,
      lancamentoId: docRef.id,
      storagePath: previousStoragePath,
      downloadUrl: previousDownloadUrl,
      referenceDate: referenceDate,
      ext: ext,
    );

    final path = comprovantePathFor(
      tenantId: churchId,
      lancamentoId: docRef.id,
      referenceDate: referenceDate,
      ext: ext,
    );

    final String url;
    if (mimeType.contains('pdf')) {
      url = await StorageService.uploadBytes(
        storagePath: path,
        bytes: rawBytes,
        contentType: 'application/pdf',
        module: YahwehUploadModule.generic,
        tenantId: churchId,
      );
    } else {
      final contentType =
          mimeType.contains('png') ? 'image/png' : 'image/jpeg';
      url = await StorageService.uploadCompressedImage(
        storagePath: path,
        rawBytes: rawBytes,
        module: YahwehUploadModule.generic,
        profile: MediaImageProfile.feed,
        contentType: contentType,
      );
    }

    await ChurchStorageMetadataVerify.assertExists(path);

    final safeName = (fileName ?? '').trim().isNotEmpty
        ? fileName!.trim()
        : 'comprovante.$ext';

    await _writeFirestore(
      () => docRef.set(
        {
          'comprovanteUrl': url,
          'comprovanteStoragePath': path,
          'comprovanteMimeType': mimeType,
          'comprovanteFileName': safeName,
          'hasComprovante': true,
          comprovanteUploadStateField: EntityPublishStatus.published,
          'comprovanteUploadError': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    );

    YahwehFlowLog.uploadSuccess('comprovante');
    return url;
  }

  static void scheduleComprovanteUpload({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    void Function(String url)? onSuccess,
    void Function(Object error)? onError,
  }) {
    unawaited(
      uploadComprovanteNow(
        tenantId: tenantId,
        docRef: docRef,
        rawBytes: rawBytes,
        mimeType: mimeType,
        fileName: fileName,
        referenceDate: referenceDate,
        previousStoragePath: previousStoragePath,
        previousDownloadUrl: previousDownloadUrl,
      ).then((url) => onSuccess?.call(url)).catchError((Object e, StackTrace st) {
        YahwehFlowLog.error('FINANCEIRO', e, st);
        unawaited(_markError(docRef, e));
        onError?.call(e);
      }),
    );
  }

  static Future<void> _markError(
    DocumentReference<Map<String, dynamic>> docRef,
    Object error,
  ) async {
    try {
      await _writeFirestore(
        () => docRef.set(
          {
            comprovanteUploadStateField: EntityPublishStatus.error,
            'hasComprovante': false,
            'comprovanteUploadError': error.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
      );
    } catch (e, st) {
      YahwehFlowLog.error('FINANCEIRO', e, st);
    }
  }
}
