import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/fornecedor_compromisso_comprovante_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

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

  static Future<void> attachComprovante({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    final ext = FinanceComprovanteAttachService.extensionForMime(mimeType);
    final url = await FornecedorCompromissoComprovanteService.upload(
      churchId: cid,
      fornecedorId: fornecedorId,
      compromissoId: compromissoId,
      bytes: bytes,
      contentType: mimeType,
      ext: ext,
    );
    final storagePath = ChurchStorageLayout.fornecedorCompromissoComprovantePath(
      tenantId: cid,
      fornecedorId: fornecedorId,
      compromissoId: compromissoId,
      ext: ext,
    );
    final patch = ChurchCanonicalMediaContract.financeComprovanteWritePatch(
      url: url,
      storagePath: storagePath,
      mimeType: mimeType,
      fileName: fileName,
    );
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
    await runFirestorePublishWithRecovery(
      () => docRef.set(
        ChurchCanonicalMediaContract.comprovanteClearFirestorePatch(),
        SetOptions(merge: true),
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
