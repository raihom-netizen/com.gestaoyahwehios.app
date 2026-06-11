import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/extended_publish_verification_services.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/storage_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isFirebaseStorageHttpUrl, sanitizeImageUrl;

/// Financeiro — comprovante único em `igrejas/{id}/financeiro/YYYY_MM/{lancamentoId}.jpg`.
abstract final class FinanceComprovantePublishService {
  FinanceComprovantePublishService._();

  static const String comprovanteUploadStateField = 'comprovanteUploadState';

  /// Grava lançamento; comprovante pode ir em seguida via [uploadComprovanteNow].
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
      patch.remove('comprovanteUrl');
    }
    final tenantId = financeCol.parent?.id ?? '';
    if (isEdit && existingRef != null) {
      await OptimisticFirestoreWrite.update(
        ref: existingRef,
        data: patch,
        module: OfflineModules.financeiro,
        tenantId: tenantId,
      );
      YahwehFlowLog.success('FINANCEIRO');
      return existingRef;
    }
    final ref = financeCol.doc();
    await OptimisticFirestoreWrite.set(
      ref: ref,
      data: patch,
      module: OfflineModules.financeiro,
      tenantId: tenantId,
    );
    YahwehFlowLog.success('FINANCEIRO');
    return ref;
  }

  /// URL para exibir — `comprovanteUrl` ou resolve `comprovanteStoragePath`.
  static Future<String> resolveComprovanteUrl(Map<String, dynamic> data) async {
    final url = sanitizeImageUrl((data['comprovanteUrl'] ?? '').toString());
    if (url.isNotEmpty) return url;
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (path.isEmpty) return '';
    try {
      return await FirebaseStorage.instance.ref(path).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  static String comprovantePathFor({
    required String tenantId,
    required String lancamentoId,
    DateTime? referenceDate,
  }) =>
      ChurchStorageLayout.financeComprovantePath(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
      );

  static Future<void> deleteComprovanteArtifacts({
    required String tenantId,
    required String lancamentoId,
    String? storagePath,
    String? downloadUrl,
    DateTime? referenceDate,
  }) async {
    final paths = <String>{
      if (storagePath != null && storagePath.trim().isNotEmpty) storagePath.trim(),
      comprovantePathFor(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
      ),
      ChurchStorageLayout.financeComprovantePathLegacy(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
      ),
    };
    for (final p in paths) {
      try {
        await FirebaseStorage.instance.ref(p).delete();
      } catch (_) {}
    }
    final u = sanitizeImageUrl((downloadUrl ?? '').trim());
    if (u.isNotEmpty && isFirebaseStorageHttpUrl(u)) {
      await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(u);
    }
  }

  /// Upload síncrono — grava URL directa + path no Firestore (receita, despesa, transferência).
  static Future<String> uploadComprovanteNow({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
  }) async {
    await ensureFirebaseCore(requireAuth: true);
    YahwehFlowLog.uploadStart('comprovante');
    final igrejaId = await FinanceiroPublishVerificationService.resolveTenant(
      seed: tenantId,
    );
    await FirebaseStorageService.ensureFinanceiroFolderPlaceholderIfAbsent(
      igrejaId,
    );

    await deleteComprovanteArtifacts(
      tenantId: igrejaId,
      lancamentoId: docRef.id,
      storagePath: previousStoragePath,
      downloadUrl: previousDownloadUrl,
      referenceDate: referenceDate,
    );

    final path = comprovantePathFor(
      tenantId: igrejaId,
      lancamentoId: docRef.id,
      referenceDate: referenceDate,
    );

    final url = await StorageService.uploadCompressedImage(
      storagePath: path,
      rawBytes: rawBytes,
      module: YahwehUploadModule.generic,
      profile: MediaImageProfile.feed,
      contentType: 'image/jpeg',
    );

    await FinanceiroPublishVerificationService.verifyStorage(path);

    await docRef.set(
      {
        'comprovanteUrl': url,
        'comprovanteStoragePath': path,
        comprovanteUploadStateField: EntityPublishStatus.published,
        'comprovanteUploadError': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await FinanceiroPublishVerificationService.verifyDoc(docRef);
    YahwehFlowLog.uploadSuccess('comprovante');
    return url;
  }

  static void scheduleComprovanteUpload({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
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
      await docRef.set(
        {
          comprovanteUploadStateField: EntityPublishStatus.error,
          'comprovanteUploadError': error.toString(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      YahwehFlowLog.error('FINANCEIRO', e, st);
    }
  }
}
