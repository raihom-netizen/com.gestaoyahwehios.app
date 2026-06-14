import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';

/// Porta única de tenant no **painel igreja** pós-login.
///
/// **Usar em todo módulo** (Membros, Financeiro, Chat, Site público embutido, etc.):
/// - `ChurchPanelTenantGateway.churchId(shellHint)` → `igrejas/{churchId}`
///
/// **Proibido no painel:** `TenantResolverService.resolveOperationalChurchDocId`,
/// `ChurchOperationalPaths.resolveCached`, cluster de docs irmãos, `collection('tenants')`.
abstract final class ChurchPanelTenantGateway {
  ChurchPanelTenantGateway._();

  /// ID canónico síncrono — preferir isto a qualquer `resolveCached` async.
  static String churchId([String? shellHint]) =>
      ChurchRepository.churchId(shellHint);

  static String requireChurchId([String? shellHint]) =>
      ChurchRepository.requireChurchId(shellHint);

  /// Alias explícito (slug BPC / sessão / hint do shell).
  static String resolve(String? tenantHint) =>
      ChurchPanelTenant.resolve(tenantHint);

  static String forFirestore(String? tenantHint) =>
      ChurchPanelTenant.forFirestore(tenantHint);
}
