/// Níveis SaaS da plataforma (limites de membros — painel master).
abstract class SaasPlanLimits {
  SaasPlanLimits._();

  static const String kBronze = 'bronze';
  static const String kPrata = 'prata';
  static const String kOuro = 'ouro';

  /// Limite de fichas de membro; `null` = ilimitado.
  static int? memberCapForTier(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t == kBronze) return 100;
    if (t == kPrata) return 500;
    if (t == kOuro) return null;
    return null;
  }

  static String labelForTier(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case kBronze:
        return 'Bronze (até 100 membros)';
      case kPrata:
        return 'Prata (até 500 membros)';
      case kOuro:
        return 'Ouro (ilimitado + white-label)';
      default:
        return 'Não definido (tratado como Ouro)';
    }
  }

  /// Lê `saasTier` no doc da igreja ou `saas.tier`.
  static String? tierFromChurch(Map<String, dynamic>? data) {
    if (data == null) return null;
    final top = data['saasTier'] ?? data['saas_tier'];
    if (top != null && top.toString().trim().isNotEmpty) {
      return top.toString().trim().toLowerCase();
    }
    final saas = data['saas'];
    if (saas is Map) {
      final v = saas['tier'] ?? saas['saasTier'];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim().toLowerCase();
      }
    }
    return null;
  }
}
