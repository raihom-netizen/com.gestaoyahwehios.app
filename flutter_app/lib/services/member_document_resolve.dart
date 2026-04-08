import 'package:cloud_firestore/cloud_firestore.dart';

/// Fonte canónica de dados de pessoas da igreja: [igrejas/{tenantId}/membros].
///
/// Resolve por id do documento, [authUid] ou CPF (11 dígitos).
abstract final class MemberDocumentResolve {
  MemberDocumentResolve._();

  static CollectionReference<Map<String, dynamic>> membrosCol(
    FirebaseFirestore db,
    String tenantId,
  ) =>
      db.collection('igrejas').doc(tenantId.trim()).collection('membros');

  /// Ordem: `doc(hint)` → `where authUid == hint` → `doc(cpf)` → `where CPF == cpf`.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> findByHint(
    CollectionReference<Map<String, dynamic>> membersCol,
    String hint, {
    String? cpfDigits,
  }) async {
    final h = hint.trim();
    if (h.isEmpty) return null;
    try {
      final byId = await membersCol.doc(h).get();
      if (byId.exists) return byId;
    } catch (_) {}
    try {
      final q =
          await membersCol.where('authUid', isEqualTo: h).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first;
    } catch (_) {}
    final cpf = (cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (cpf.length >= 11) {
      try {
        final byCpf = await membersCol.doc(cpf).get();
        if (byCpf.exists) return byCpf;
        final q2 =
            await membersCol.where('CPF', isEqualTo: cpf).limit(1).get();
        if (q2.docs.isNotEmpty) return q2.docs.first;
      } catch (_) {}
    }
    return null;
  }
}
