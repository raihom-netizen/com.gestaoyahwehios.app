import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gestao_yahweh/core/certificate_protocol_id.dart';

/// Registo de certificado emitido: raiz `certificados_emitidos` (leitura pública por ID / QR)
/// + espelho `igrejas/{tid}/certificados_historico` para listagem no painel.
class CertificateEmitidoService {
  CertificateEmitidoService._();

  static final _root = FirebaseFirestore.instance.collection('certificados_emitidos');

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

    final rootData = <String, dynamic>{
      ...snapshot,
      'certificadoId': certificadoId,
      'tenantId': tid,
      'emitidoPorUid': uid,
      'emitidoPorEmail': email,
      'dataEmissao': FieldValue.serverTimestamp(),
    };

    final histData = <String, dynamic>{
      'certificadoId': certificadoId,
      'tenantId': tid,
      'memberId': snapshot['memberId'] ?? '',
      'nomeMembro': snapshot['nomeMembro'] ?? '',
      'tipoCertificadoId': snapshot['tipoCertificadoId'] ?? '',
      'tipoCertificadoNome':
          snapshot['tipoCertificadoNome'] ?? snapshot['titulo'] ?? '',
      'titulo': snapshot['titulo'] ?? '',
      'dataEmissao': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();
    batch.set(_root.doc(certificadoId), rootData);
    batch.set(
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('certificados_historico')
          .doc(certificadoId),
      histData,
    );
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

    final batch = FirebaseFirestore.instance.batch();
    final ids = <String>[];
    final igreja = FirebaseFirestore.instance.collection('igrejas').doc(tid);

    for (final snapshot in snapshots) {
      final certificadoId = generateCertificateProtocolId();
      ids.add(certificadoId);
      final rootData = <String, dynamic>{
        ...snapshot,
        'certificadoId': certificadoId,
        'tenantId': tid,
        'emitidoPorUid': uid,
        'emitidoPorEmail': email,
        'dataEmissao': FieldValue.serverTimestamp(),
      };
      final histData = <String, dynamic>{
        'certificadoId': certificadoId,
        'tenantId': tid,
        'memberId': snapshot['memberId'] ?? '',
        'nomeMembro': snapshot['nomeMembro'] ?? '',
        'tipoCertificadoId': snapshot['tipoCertificadoId'] ?? '',
        'tipoCertificadoNome':
            snapshot['tipoCertificadoNome'] ?? snapshot['titulo'] ?? '',
        'titulo': snapshot['titulo'] ?? '',
        'dataEmissao': FieldValue.serverTimestamp(),
      };
      batch.set(_root.doc(certificadoId), rootData);
      batch.set(
        igreja.collection('certificados_historico').doc(certificadoId),
        histData,
      );
    }
    await batch.commit();
    return ids;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getPublic(
    String certificadoId,
  ) {
    return _root.doc(certificadoId.trim()).get();
  }

  static Query<Map<String, dynamic>> historicoQuery(String tenantId) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('certificados_historico')
        .orderBy('dataEmissao', descending: true)
        .limit(300);
  }
}
