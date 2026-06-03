import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';

/// Histórico de exclusões e alterações relevantes no módulo financeiro (quem, quando).
Future<void> logFinanceiroAuditoria({
  required String tenantId,
  required String acao,
  required String lancamentoId,
  Map<String, dynamic>? dadosAntes,
}) async {
  await ensureFirebaseReadyForPublishUpload();
  final u = firebaseDefaultAuth.currentUser;
  await firebaseDefaultFirestore
      .collection('igrejas')
      .doc(tenantId)
      .collection('finance_logs')
      .add({
    'acao': acao,
    'lancamentoId': lancamentoId,
    'uid': u?.uid,
    'email': u?.email,
    'criadoEm': FieldValue.serverTimestamp(),
    if (dadosAntes != null) 'dadosAntes': dadosAntes,
  });
  await TenantAuditService.log(
    tenantId: tenantId,
    module: OfflineModules.financeiro,
    action: acao,
    docPath: 'igrejas/$tenantId/finance/$lancamentoId',
    docId: lancamentoId,
    before: dadosAntes,
  );
}
