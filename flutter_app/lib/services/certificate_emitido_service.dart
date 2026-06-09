import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gestao_yahweh/core/certificate_protocol_id.dart';
import 'package:gestao_yahweh/services/church_document_version_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_repository.dart';

/// Certificados emitidos: **dados completos** em `igrejas/{tenantId}/certificados_emitidos/{id}`.
///
/// Validação pública (QR): índice mínimo `igrejas/{tenantId}/certificados_protocol_index/{id}`
/// (collection group) — legado: `certificados_protocol_index/{id}` na raiz com `tenantId`.
///
/// Legado: leitura ainda aceita `certificados_emitidos/{id}` na raiz até migração.
class CertificateEmitidoService {
  CertificateEmitidoService._();

  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _emitidosCol(String operationalId) =>
      ChurchOperationalPaths.churchDoc(operationalId).collection('certificados_emitidos');

  static DocumentReference<Map<String, dynamic>> _protocolIndexDoc(
    String operationalId,
    String certId,
  ) =>
      ChurchOperationalPaths.churchDoc(operationalId)
          .collection('certificados_protocol_index')
          .doc(certId);

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
    final op = ChurchRepository.churchId(tid);
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
    final op = await ChurchOperationalPaths.resolveCached(tid);
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

    final idxRoot = await _fs.collection('certificados_protocol_index').doc(id).get();
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

  /// Reemissão no painel: leitura direta em `igrejas/{tenantId}/certificados_emitidos`.
  /// Não depende do índice público nem de `collectionGroup` (evita «Protocolo não encontrado»
  /// quando as regras ou o índice não expõem o protocolo ao utilizador autenticado).
  static Future<DocumentSnapshot<Map<String, dynamic>>> getForTenant(
    String tenantId,
    String certificadoId,
  ) async {
    final id = certificadoId.trim();
    final tid = tenantId.trim();
    if (id.isEmpty || tid.isEmpty) {
      return _fs.collection('certificados_emitidos').doc('__invalid__').get();
    }
    final op = await ChurchOperationalPaths.resolveCached(tid);
    final local = await _emitidosCol(op).doc(id).get();
    if (local.exists) return local;
    return getPublic(id);
  }

  /// Histórico no painel (mesma coleção que o protocolo completo).
  /// [tenantId] deve ser o ID operacional (já resolvido pelo painel).
  static Query<Map<String, dynamic>> historicoQuery(String tenantId) {
    return _emitidosCol(tenantId.trim())
        .orderBy('dataEmissao', descending: true)
        .limit(300);
  }

  static Future<Query<Map<String, dynamic>>> historicoQueryResolved(
    String tenantId,
  ) async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId);
    return historicoQuery(op);
  }
}
