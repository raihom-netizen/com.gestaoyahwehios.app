import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// **Única** API de tenant no painel — slug BPC/legado → doc canónico `igrejas/{churchId}`.
///
/// Regra: nunca usar `widget.tenantId` em paths Firestore/Storage; sempre [resolve].
abstract final class ChurchPanelTenant {
  ChurchPanelTenant._();

  /// Doc canónico BPC (aceite produção) — Firestore + Storage.
  static const String bpcCanonicalDocId =
      TenantResolverService.kBpcCanonicalIgrejaDocId;

  /// ID operacional síncrono — sessão bound → mapa BPC → hint do shell.
  static String operationalChurchId([String? tenantHint]) => resolve(tenantHint);

  /// `igrejas/{churchId}` — path Firestore canónico.
  static String firestoreRootPath([String? tenantHint]) {
    final id = operationalChurchId(tenantHint);
    return id.isEmpty ? '' : 'igrejas/$id';
  }

  /// `igrejas/{churchId}/` — raiz Storage canónica.
  static String storageRootPath([String? tenantHint]) {
    final id = operationalChurchId(tenantHint);
    return id.isEmpty ? '' : 'igrejas/$id/';
  }

  /// Síncrono — mapa BPC + sessão bound + hint do shell.
  static String resolve(String? tenantHint) =>
      ChurchContext.resolveChurchId(tenantHint);

  /// Igual a [resolve]; nome explícito para gravações/publicação.
  static String forFirestore(String? tenantHint) => resolve(tenantHint);

  static String require(String? tenantHint) =>
      ChurchContext.requireChurchId(tenantHint);

  static bool isCanonicalDocId(String? id) {
    final t = resolve(id);
    return t.startsWith('igreja_') && t.length > 8;
  }
}
