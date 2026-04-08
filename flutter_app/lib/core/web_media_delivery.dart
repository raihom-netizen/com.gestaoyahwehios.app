// Entrega de mídia na Web: Storage + memCache limitado; CDN com resize dinâmico exige URLs próprias (Cloudinary etc.).

/// Largura em *pixels* para cache/decode, a partir do tamanho lógico na tela.
int decodePixelsForViewportWidth(
  double logicalWidth, {
  double devicePixelRatio = 1.0,
  int minPx = 64,
  int maxPx = 2048,
}) {
  final dpr = devicePixelRatio.clamp(1.0, 3.0);
  return (logicalWidth * dpr).round().clamp(minPx, maxPx);
}
