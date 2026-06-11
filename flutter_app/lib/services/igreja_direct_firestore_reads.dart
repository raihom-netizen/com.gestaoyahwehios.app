import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Leitura **directa** de `igrejas/{id}` — sem preparePanelRead, resiliência nem scan.
///
/// Usado em Cadastro da Igreja, Configurações (licença) e Mercado Pago quando o painel
/// já conhece o tenant (mesmo path do header «Local: …»).
abstract final class IgrejaDirectFirestoreReads {
  IgrejaDirectFirestoreReads._();

  static List<String> _candidateDocIds(String tenantId) {
    final seed = tenantId.trim();
    final out = <String>{
      if (seed.isNotEmpty) seed,
      ChurchContextService.currentChurchId ?? '',
      ChurchContextService.panelChurchId(seed),
      ...TenantResolverService.anchoredClusterIdsFor(seed),
      TenantResolverService.kBpcCanonicalIgrejaDocId,
    };
    return out.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Doc raiz `igrejas/{id}` — cache + servidor (igual ao header do painel).
  static Future<({String docId, Map<String, dynamic> data})?> readIgrejaDoc(
    String tenantId,
  ) async {
    for (final id in _candidateDocIds(tenantId)) {
      try {
        final snap = await ChurchFirestoreAccess.churchDoc(id)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 12));
        if (!snap.exists) continue;
        final raw = snap.data();
        if (raw == null || raw.isEmpty) continue;
        return (
          docId: snap.id,
          data: Map<String, dynamic>.from(raw),
        );
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Subdoc `igrejas/{id}/config/{configDocId}` — ex.: mercado_pago.
  static Future<({String docId, Map<String, dynamic> data})?> readIgrejaConfig(
    String tenantId,
    String configDocId,
  ) async {
    final cfgId = configDocId.trim();
    if (cfgId.isEmpty) return null;
    for (final id in _candidateDocIds(tenantId)) {
      try {
        final snap = await ChurchFirestoreAccess.churchDoc(id)
            .collection('config')
            .doc(cfgId)
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 10));
        if (!snap.exists) continue;
        final raw = snap.data();
        if (raw == null || raw.isEmpty) continue;
        return (
          docId: id,
          data: Map<String, dynamic>.from(raw),
        );
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
