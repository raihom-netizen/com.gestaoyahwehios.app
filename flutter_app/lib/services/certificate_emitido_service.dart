import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gestao_yahweh/core/certificate_protocol_id.dart';

/// Certificados emitidos: **dados completos** em `igrejas/{tenantId}/certificados_emitidos/{id}`.
///
/// Validação pública (QR sem saber a igreja): índice mínimo `certificados_protocol_index/{id}`
/// com só `tenantId` (não duplica o snapshot do certificado).
///
/// Legado: leitura ainda aceita `certificados_emitidos/{id}` na raiz até migração.
class CertificateEmitidoService {
  CertificateEmitidoService._();

  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _emitidosCol(String tid) =>
      _fs.collection('igrejas').doc(tid).collection('certificados_emitidos');

  static DocumentReference<Map<String, dynamic>> _protocolIndex(String certId) =>
      _fs.collection('certificados_protocol_index').doc(certId);

  /// Grava protocolo e devolve o [certificadoId] (UUID) para o QR.
  static Future<String> registerEmissao({
    required String tenantId,
    required Map<String, dynamic> snapshot,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw ArgumentError('tenantId vazio');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilizador não autenticado');
    }
    final certificadoId = generateCertificateProtocolId();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    final payload = <String, dynamic>{
      ...snapshot,
      'certificadoId': certificadoId,
      'tenantId': tid,
      'emitidoPorUid': uid,
      'emitidoPorEmail': email,
      'dataEmissao': FieldValue.serverTimestamp(),
    };

    final batch = _fs.batch();
    batch.set(_emitidosCol(tid).doc(certificadoId), payload);
    batch.set(_protocolIndex(certificadoId), {
      'tenantId': tid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return certificadoId;
  }

  /// Várias emissões num único batch (ex.: PDF único em lote).
  static Future<List<String>> registerEmissaoBatch({
    required String tenantId,
    required List<Map<String, dynamic>> snapshots,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) throw ArgumentError('tenantId vazio');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Utilizador não autenticado');
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (snapshots.isEmpty) return [];

    final batch = _fs.batch();

    final ids = <String>[];
    for (final snapshot in snapshots) {
      final certificadoId = generateCertificateProtocolId();
      ids.add(certificadoId);
      final payload = <String, dynamic>{
        ...snapshot,
        'certificadoId': certificadoId,
        'tenantId': tid,
        'emitidoPorUid': uid,
        'emitidoPorEmail': email,
        'dataEmissao': FieldValue.serverTimestamp(),
      };
      batch.set(_emitidosCol(tid).doc(certificadoId), payload);
      batch.set(_protocolIndex(certificadoId), {
        'tenantId': tid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
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

    final idx = await _protocolIndex(id).get();
    final idxData = idx.data();
    if (idx.exists && idxData != null) {
      final tid = (idxData['tenantId'] ?? '').toString().trim();
      if (tid.isNotEmpty) {
        final doc = await _emitidosCol(tid).doc(id).get();
        if (doc.exists) return doc;
      }
    }

    return _fs.collection('certificados_emitidos').doc(id).get();
  }

  /// Histórico no painel (mesma coleção que o protocolo completo).
  static Query<Map<String, dynamic>> historicoQuery(String tenantId) {
    return _emitidosCol(tenantId.trim())
        .orderBy('dataEmissao', descending: true)
        .limit(300);
  }
}
