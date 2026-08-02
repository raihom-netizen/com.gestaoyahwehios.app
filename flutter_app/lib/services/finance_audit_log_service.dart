import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/services/tenant_audit_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Hist├│rico de exclus├Áes e altera├º├Áes relevantes no m├│dulo financeiro (quem, quando).
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
    // N├úo gravar payload enorme (pode falhar regras / limites).
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
      'dadosAntes': ?slim,
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
    // Best-effort ÔÇö exclus├úo do lan├ºamento n├úo depende disto.
  }
}
