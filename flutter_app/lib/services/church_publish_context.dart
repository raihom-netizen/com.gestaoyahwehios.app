import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// churchId único para gravações — Web / Android / iOS (sem tenant/alias).
abstract final class ChurchPublishContext {
  ChurchPublishContext._();

    static String churchIdForPublish(String seedTenantId) {
        final raw = seedTenantId.trim();
        if (raw.isNotEmpty) {
            final mapped = TenantResolverService.mapLegacySeedToCanonical(raw);
            if (mapped != null && mapped.isNotEmpty) return mapped;
            if (RegExp(r'^igreja_[a-z0-9_]+$').hasMatch(raw)) return raw;
        }

        final ctx = ChurchRepository.currentChurchId?.trim() ?? '';
        if (ctx.isNotEmpty) return ctx;

        return ChurchRepository.requireChurchId(raw);
    }

  static Future<String> churchIdForPublishAsync(String seedTenantId) async =>
      churchIdForPublish(seedTenantId);
}
