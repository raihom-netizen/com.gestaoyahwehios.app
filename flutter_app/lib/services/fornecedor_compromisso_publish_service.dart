import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/fornecedor_compromisso_comprovante_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Gravação Web-safe de compromissos de fornecedor (Storage → CF → Firestore).
abstract final class FornecedorCompromissoPublishService {
  FornecedorCompromissoPublishService._();

  static Future<DocumentReference<Map<String, dynamic>>> saveCompromisso({
    required CollectionReference<Map<String, dynamic>> compCol,
    required String churchId,
    required String fornecedorId,
    required Map<String, dynamic> payload,
    DocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final docRef = existing?.reference ?? compCol.doc();
    final isNew = existing == null;
    final data = isNew
        ? {
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
          }
        : payload;

    await AdminFeedFirestoreBridge.upsertTenantDoc(
      churchId: churchId,
      collection: 'fornecedor_compromissos',
      docId: docRef.id,
      data: data,
      isNewDoc: isNew,
      directWrite: () => runFirestorePublishWithRecovery(
        () async {
          if (isNew) {
            await docRef.set(data);
          } else {
            await docRef.update(payload);
          }
        },
      ),
    );
    return docRef;
  }

  static Future<void> attachComprovanteControleTotal({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
  }) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: true,
      );
    }
    onProgress?.call(0.05);

    if (!kIsWeb) {
      await runFirestorePublishWithRecovery(
        () => docRef.set(
          {
            'comprovanteUploadState': 'uploading',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
      ).catchError((_) {});
    }

    try {
      final uploaded = await FornecedorCompromissoComprovanteService.upload(
        churchId: cid,
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        bytes: bytes,
        contentType: mimeType,
        onProgress: (p) => onProgress?.call(0.08 + p * 0.82),
        alreadyCompressed: alreadyCompressed,
      );
      onProgress?.call(0.92);
      final patch = ChurchCanonicalMediaContract.financeComprovanteWritePatch(
        url: uploaded.downloadUrl,
        storagePath: uploaded.storagePath,
        mimeType: uploaded.contentType,
        fileName: fileName,
      );
      patch['comprovanteUploadState'] = 'ready';
      patch['comprovantePendingLocal'] = FieldValue.delete();
      patch['updatedAt'] = FieldValue.serverTimestamp();
      await AdminFeedFirestoreBridge.upsertDocRef(
        docRef: docRef,
        data: patch,
        isNewDoc: false,
        useUpdate: true,
        directWrite: () => runFirestorePublishWithRecovery(
          () => docRef.update(patch),
        ),
      );
      onProgress?.call(1.0);
    } catch (e) {
      if (!kIsWeb && _shouldQueueComprovanteOffline(e)) {
        final ext = mimeType.toLowerCase().contains('pdf') ? 'pdf' : 'jpg';
        final path = ChurchStorageLayout.fornecedorCompromissoComprovantePath(
          tenantId: cid,
          fornecedorId: fornecedorId,
          compromissoId: compromissoId,
          ext: ext,
        );
        await _enqueueCompromissoLocalRetry(
          docRef: docRef,
          bytes: bytes,
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

  static Future<void> _enqueueCompromissoLocalRetry({
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
          'comprovanteUploadState': 'uploading',
          'comprovantePendingLocal': true,
          'comprovanteStoragePath': storagePath,
          'hasComprovante': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ),
    ).catchError((_) {});
  }

  /// Legado — delega ao fluxo CT.
  static Future<void> attachComprovante({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
    void Function(double progress)? onProgress,
    bool alreadyCompressed = false,
  }) async {
    await attachComprovanteControleTotal(
      docRef: docRef,
      churchId: churchId,
      fornecedorId: fornecedorId,
      compromissoId: compromissoId,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      onProgress: onProgress,
      alreadyCompressed: alreadyCompressed,
    );
  }

  /// Remove comprovante — Firestore + Storage (`igrejas/{churchId}/fornecedores/…`).
  static Future<void> removeComprovante({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Map<String, dynamic> data,
  }) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    final clearPatch =
        ChurchCanonicalMediaContract.comprovanteClearFirestorePatch();
    clearPatch['updatedAt'] = FieldValue.serverTimestamp();
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }
    await AdminFeedFirestoreBridge.upsertDocRef(
      docRef: docRef,
      data: clearPatch,
      isNewDoc: false,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(clearPatch, SetOptions(merge: true)),
        maxAttempts: 4,
        criticalWrite: true,
      ),
    );
    final storedPath = (data['comprovanteStoragePath'] ?? '').toString().trim();
    final paths = <String>{
      if (storedPath.isNotEmpty) storedPath,
      ChurchStorageLayout.fornecedorCompromissoComprovantePath(
        tenantId: cid,
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        ext: 'jpg',
      ),
      ChurchStorageLayout.fornecedorCompromissoComprovantePath(
        tenantId: cid,
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        ext: 'pdf',
      ),
      ChurchStorageLayout.fornecedorCompromissoComprovantePath(
        tenantId: cid,
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        ext: 'png',
      ),
    };
    for (final p in paths) {
      try {
        await firebaseDefaultStorage.ref(p).delete();
      } catch (_) {}
    }
    final url = (data['comprovanteUrl'] ?? '').toString().trim();
    if (url.isNotEmpty) {
      await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(url);
    }
  }
}
