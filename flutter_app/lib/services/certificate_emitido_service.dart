import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/certificate_protocol_id.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_document_version_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Certificados emitidos: **dados completos** em `igrejas/{churchId}/certificados_emitidos/{id}`.
///
/// Validação pública (QR): índice mínimo `igrejas/{churchId}/certificados_protocol_index/{id}`
/// (collection group) — legado: `certificados_protocol_index/{id}` na raiz com `tenantId`.
///
/// Legado: leitura ainda aceita `certificados_emitidos/{id}` na raiz até migração.
class CertificateEmitidoService {
  CertificateEmitidoService._();

  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _historicoRam = {};

  static const Duration _historicoRamTtl = Duration(minutes: 8);

  static String _churchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static CollectionReference<Map<String, dynamic>> _emitidosCol(
    String tenantHint,
  ) =>
      ChurchUiCollections.certificados(_churchId(tenantHint));

  static DocumentReference<Map<String, dynamic>> _protocolIndexDoc(
    String tenantHint,
    String certId,
  ) {
    final churchId = _churchId(tenantHint);
    return ChurchUiCollections.churchDoc(churchId)
        .collection('certificados_protocol_index')
        .doc(certId);
  }

  static void invalidateHistoricoCache(String tenantHint) {
    final key = _churchId(tenantHint);
    if (key.isNotEmpty) _historicoRam.remove(key);
  }

  /// Histórico no painel — `igrejas/{churchId}/certificados_emitidos`.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadHistorico(
    String tenantHint, {
    int limit = 300,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(tenantHint);
    if (churchId.isEmpty) return const [];

    if (!forceRefresh) {
      final hit = _historicoRam[churchId];
      if (hit != null &&
          DateTime.now().difference(hit.at) < _historicoRamTtl) {
        return hit.docs;
      }
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final snap = await FirestoreWebGuard.runWithWebRecovery(
      () => _emitidosCol(churchId)
          .orderBy('dataEmissao', descending: true)
          .limit(limit)
          .get(),
      maxAttempts: 4,
    );
    final docs = snap.docs;
    if (docs.isNotEmpty) {
      _historicoRam[churchId] = (docs: List.from(docs), at: DateTime.now());
    }
    return docs;
  }

  /// Query legada (preferir [loadHistorico] na UI web/mobile).
  static Query<Map<String, dynamic>> historicoQuery(String tenantHint) {
    return _emitidosCol(tenantHint)
        .orderBy('dataEmissao', descending: true)
        .limit(300);
  }

  static Future<Query<Map<String, dynamic>>> historicoQueryResolved(
    String tenantHint,
  ) async {
    return historicoQuery(_churchId(tenantHint));
  }

  /// Grava protocolo e devolve o [certificadoId] (UUID) para o QR.
  static Future<String> registerEmissao({
    required String tenantId,
    required Map<String, dynamic> snapshot,
    String? certificadoId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw ArgumentError('tenantId vazio');
    }
    final op = _churchId(tid);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilizador não autenticado');
    }
    final id = (certificadoId ?? '').trim();
    final certificadoIdResolved =
        id.isNotEmpty ? id : generateCertificateProtocolId();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    final fp = ChurchDocumentVersionService.fingerprintFromMap(snapshot);
    final existing = snapshot[ChurchDocumentVersionService.pdfPathField];
    final pdfPath = (existing ?? '').toString().trim();
    final version = pdfPath.isNotEmpty
        ? ChurchDocumentVersionService.nextVersion(
            snapshot,
            ChurchDocumentVersionService.pdfVersionField,
          )
        : 1;

    final payload = <String, dynamic>{
      ...snapshot,
      'certificadoId': certificadoIdResolved,
      'tenantId': op,
      'emitidoPorUid': uid,
      'emitidoPorEmail': email,
      'dataEmissao': FieldValue.serverTimestamp(),
      if (pdfPath.isNotEmpty) ...ChurchDocumentVersionService.afterGenerate(
            version: version,
            storagePath: pdfPath,
            fingerprint: fp,
            versionField: ChurchDocumentVersionService.pdfVersionField,
            pathField: ChurchDocumentVersionService.pdfPathField,
          ),
    };

    final batch = _fs.batch();
    batch.set(_emitidosCol(op).doc(certificadoIdResolved), payload);
    batch.set(_protocolIndexDoc(op, certificadoIdResolved), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    invalidateHistoricoCache(op);
    return certificadoIdResolved;
  }

  /// Várias emissões num único batch (ex.: PDF único em lote).
  static Future<List<String>> registerEmissaoBatch({
    required String tenantId,
    required List<Map<String, dynamic>> snapshots,
    List<String>? certificadoIds,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) throw ArgumentError('tenantId vazio');
    final op = _churchId(tid);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Utilizador não autenticado');
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (snapshots.isEmpty) return [];

    /// Firestore limita 500 operações por batch; cada emissão = 2 sets.
    const chunkSize = 200;
    final ids = <String>[];
    for (var offset = 0; offset < snapshots.length; offset += chunkSize) {
      final end = offset + chunkSize > snapshots.length
          ? snapshots.length
          : offset + chunkSize;
      final batch = _fs.batch();
      for (var i = offset; i < end; i++) {
        final snapshot = snapshots[i];
        final preset = certificadoIds != null && i < certificadoIds.length
            ? certificadoIds[i].trim()
            : '';
        final certificadoId =
            preset.isNotEmpty ? preset : generateCertificateProtocolId();
        ids.add(certificadoId);
        final payload = <String, dynamic>{
          ...snapshot,
          'certificadoId': certificadoId,
          'tenantId': op,
          'emitidoPorUid': uid,
          'emitidoPorEmail': email,
          'dataEmissao': FieldValue.serverTimestamp(),
        };
        batch.set(_emitidosCol(op).doc(certificadoId), payload);
        batch.set(_protocolIndexDoc(op, certificadoId), {
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    invalidateHistoricoCache(op);
    return ids;
  }

  /// Leitura pública (validação QR): índice → documento na igreja; fallback raiz legado.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getPublic(
    String certificadoId,
  ) async {
    final id = certificadoId.trim();
    if (id.isEmpty) {
      return _fs.collection('certificados_emitidos').doc('__invalid__').get();
    }

    try {
      final cg = await _fs
          .collectionGroup('certificados_protocol_index')
          .where(FieldPath.documentId, isEqualTo: id)
          .limit(1)
          .get();
      if (cg.docs.isNotEmpty) {
        final idxDoc = cg.docs.first;
        final tid = idxDoc.reference.parent.parent?.id ?? '';
        if (tid.isNotEmpty) {
          final doc = await _emitidosCol(tid).doc(id).get();
          if (doc.exists) return doc;
        }
      }
    } catch (_) {
      /* índice ou permissões: tenta legado abaixo */
    }

    final idxRoot =
        await _fs.collection('certificados_protocol_index').doc(id).get();
    final idxRootData = idxRoot.data();
    if (idxRoot.exists && idxRootData != null) {
      final tid = (idxRootData['tenantId'] ?? '').toString().trim();
      if (tid.isNotEmpty) {
        final doc = await _emitidosCol(tid).doc(id).get();
        if (doc.exists) return doc;
      }
    }

    return _fs.collection('certificados_emitidos').doc(id).get();
  }

  /// Reemissão no painel: leitura directa em `igrejas/{churchId}/certificados_emitidos`.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getForTenant(
    String tenantId,
    String certificadoId,
  ) async {
    final id = certificadoId.trim();
    final tid = tenantId.trim();
    if (id.isEmpty || tid.isEmpty) {
      return _fs.collection('certificados_emitidos').doc('__invalid__').get();
    }
    final op = _churchId(tid);
    final local = await _emitidosCol(op).doc(id).get();
    if (local.exists) return local;
    return getPublic(id);
  }
}
