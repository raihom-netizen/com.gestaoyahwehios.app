/// Limites de listagem Firestore (padrão Controle Total — 1.ª pintura rápida).
abstract final class ChurchTenantListLimits {
  ChurchTenantListLimits._();

  /// Feed mural, chat, listas iniciais — nunca `collection.get()` sem limite.
  static const int defaultPageSize = 20;

  /// Painel home / resumos (pode carregar mais em segundo plano).
  static const int panelFeedPreview = 20;

  /// Máximo ao expandir «ver mais» no mural.
  static const int muralFeedMax = 60;
}
