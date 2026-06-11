import 'package:flutter/foundation.dart' show debugPrint;

/// Legado descontinuado — SaaS directo `igrejas/{churchId}` sem `church_aliases`.
///
/// Mantido só para não quebrar imports; **não** chama Cloud Functions nem provisionamento.
abstract final class ChurchTenantConsolidationService {
  ChurchTenantConsolidationService._();

  /// No-op — evita recriar `church_aliases` / patches automáticos no Firebase.
  static void ensureConsolidated(
    String tenantId, {
    bool force = false,
    String source = 'church_panel',
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    debugPrint(
      'ChurchTenantConsolidationService: skip (direct igrejas/$tid, source=$source)',
    );
  }
}
