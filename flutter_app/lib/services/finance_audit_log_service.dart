import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Histórico de exclusões e alterações relevantes no módulo financeiro (quem, quando).
Future<void> logFinanceiroAuditoria({
  required String tenantId,
  required String acao,
  required String lancamentoId,
  Map<String, dynamic>? dadosAntes,
}) async {
  try {
    await ensureFirebaseReadyForPublishUpload();
    final u = firebaseDefaultAuth.currentUser;
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    // Não gravar payload enorme (pode falhar regras / limites).
    Map<String, dynamic>? slim;
    if (dadosAntes != null) {
      slim = <String, dynamic>{};
      for (final e in dadosAntes.entries) {
        if (e.key == 'dadosAntes') continue;
        final v = e.value;
        if (v is List || v is Map) continue;
        final s = '$v';
        if (s.length >= 800) continue;
        slim[e.key] = v;
        if (slim.length >= 24) break;
      }
    }
    await ChurchUiCollections.financeLogs(op).add({
      'acao': acao,
      'lancamentoId': lancamentoId,
      'uid': u?.uid,
      'email': u?.email,
      'criadoEm': FieldValue.serverTimestamp(),
      if (slim != null) 'dadosAntes': slim,
    });
    await TenantAuditService.log(
      tenantId: tenantId,
      module: OfflineModules.financeiro,
      action: acao,
      docPath: 'igrejas/$op/finance/$lancamentoId',
      docId: lancamentoId,
      before: slim,
    );
  } catch (_) {
    // Best-effort — exclusão do lançamento não depende disto.
  }
}
