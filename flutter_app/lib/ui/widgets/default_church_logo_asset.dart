import 'package:flutter/material.dart';

/// Logo/ícone oficial Gestão YAHWEH — escudo em [assets/icon/app_icon.png].
///
/// [kGestaoYahwehBrandLogoAsset] e [kDefaultChurchLogoAssetPath] apontam para a mesma arte.
/// `assets/LOGO_GESTAO_YAHWEH.png` é cópia sincronizada (login, master, sidebar).
/// Regenerar plataformas: `flutter_app/scripts/atualizar_icone_web.ps1`
const String kDefaultChurchLogoAssetPath = 'assets/icon/app_icon.png';

/// Alias usado em login, painel master e site de divulgação (PNG sincronizado com [app_icon]).
const String kGestaoYahwehBrandLogoAsset = 'assets/LOGO_GESTAO_YAHWEH.png';

/// Exibe o ícone Gestão YAHWEH grande no espaço reservado à logo da igreja.
class DefaultChurchLogoAsset extends StatelessWidget {
  const DefaultChurchLogoAsset({
    super.key,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    /// Fração da menor dimensão (0.88 ≈ quase todo o quadro).
    this.fractionOfBox = 0.88,
    this.borderRadius,
  });

  final double width;
  final double height;
  final BoxFit fit;
  final double fractionOfBox;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final side = (width < height ? width : height) * fractionOfBox.clamp(0.5, 1.0);
    Widget img = Image.asset(
      kDefaultChurchLogoAssetPath,
      width: side,
      height: side,
      fit: fit,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shield_rounded,
        size: side * 0.45,
        color: Colors.grey.shade400,
      ),
    );
    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return SizedBox(
      width: width,
      height: height,
      child: Center(child: img),
    );
  }
}
