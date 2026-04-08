import 'package:flutter/material.dart';

/// Dimensões e proporções canónicas por módulo — reduz [Layout Shift] ao reservar espaço antes do decode.
/// Logos/banners no Storage podem ter outras resoluções; estes valores guiam UI + [memCacheWidth]/[AspectRatio].
class UiAssetLayoutConstants {
  UiAssetLayoutConstants._();
  /// Logos na galeria de clientes (site divulgação / marketing): quadrado, alvo WebP ~200×200 lógicos.
  static const double marketingClientLogoLogicalPx = 200;

  /// Banners de eventos (cartazes, capas): 16:9.
  static const double eventBannerAspectW = 16;
  static const double eventBannerAspectH = 9;

  /// Foto de membro (carteirinha, lista): quadrada com recorte facial no fluxo de upload.
  static const double memberPhotoAspectRatio = 1;

  /// Fotos de património: proporção típica de câmera 4:3.
  static const double patrimonioPhotoAspectW = 4;
  static const double patrimonioPhotoAspectH = 3;

  static double get eventBannerAspectRatio =>
      eventBannerAspectW / eventBannerAspectH;

  static double get patrimonioPhotoAspectRatio =>
      patrimonioPhotoAspectW / patrimonioPhotoAspectH;

  /// Largura máxima para decode/cache de logo de cliente em ecrãs Retina (≈ 200×DPR).
  static int marketingClientLogoMemCacheWidth(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (marketingClientLogoLogicalPx * dpr).round().clamp(96, 800);
  }
}

