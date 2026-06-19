/// Dimensões canónicas — cartão digital na tela, PNG e PDF partilham a mesma proporção CR80.
abstract final class MemberCardCnhLayout {
  MemberCardCnhLayout._();

  /// Largura lógica da captura (igual ao preview na [MemberCardPage]).
  static const double captureLogicalWidth = 380;

  /// Altura proporcional CR80 portrait (~54 × 86 mm).
  static const double captureLogicalHeight = captureLogicalWidth * (244 / 153);

  /// Tamanho físico no PDF (pontos tipográficos ≈ CR80).
  static const double cardWidthPt = 153;
  static const double cardHeightPt = 244;

  static const double cardAspectRatio = cardWidthPt / cardHeightPt;
}
