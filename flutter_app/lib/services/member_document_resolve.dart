import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Fonte canónica de dados de pessoas da igreja: [igrejas/{tenantId}/membros].
///
/// Resolve por id do documento, [authUid], CPF (11 dígitos) ou [codigoMembro].
abstract final class MemberDocumentResolve {
  MemberDocumentResolve._();

  static CollectionReference<Map<String, dynamic>> membrosCol(
    FirebaseFirestore db,
    String tenantId,
  ) =>
      db.collection('igrejas').doc(tenantId.trim()).collection('membros');

  /// Ordem: `doc(hint)` → `authUid` → `doc(cpf)` → `CPF` → `codigoMembro`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> findByHint(
    CollectionReference<Map<String, dynamic>> membersCol,
    String hint, {
    String? cpfDigits,
  }) async {
    final h = hint.trim();
    if (h.isEmpty) return null;
    final cacheNs = membersCol.path;
    try {
      final byId = await FirestoreReadResilience.getDocument(
        membersCol.doc(h),
        cacheKey: '$cacheNs/member_doc_$h',
      );
      if (byId.exists) return byId;
    } catch (_) {}
    try {
      final q =
          await membersCol.where('authUid', isEqualTo: h).limit(1).get(
                const GetOptions(source: Source.serverAndCache),
              );
      if (q.docs.isNotEmpty) return q.docs.first;
    } catch (_) {}
    final cpf = (cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (cpf.length >= 11) {
      try {
        final byCpf = await FirestoreReadResilience.getDocument(
          membersCol.doc(cpf),
          cacheKey: '$cacheNs/member_cpf_doc_$cpf',
        );
        if (byCpf.exists) return byCpf;
        final q2 = await membersCol.where('CPF', isEqualTo: cpf).limit(1).get(
              const GetOptions(source: Source.serverAndCache),
            );
        if (q2.docs.isNotEmpty) return q2.docs.first;
        final q2b = await membersCol.where('cpf', isEqualTo: cpf).limit(1).get(
              const GetOptions(source: Source.serverAndCache),
            );
        if (q2b.docs.isNotEmpty) return q2b.docs.first;
      } catch (_) {}
    }
    try {
      final q3 = await membersCol
          .where('codigoMembro', isEqualTo: h)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (q3.docs.isNotEmpty) return q3.docs.first;
    } catch (_) {}
    return null;
  }
}
