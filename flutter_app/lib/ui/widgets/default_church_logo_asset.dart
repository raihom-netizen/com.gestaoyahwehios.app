import 'package:flutter/material.dart';

/// Logo padrão do app quando a igreja ainda não enviou logo (`assets/icon/app_icon.png`).
const String kDefaultChurchLogoAssetPath = 'assets/icon/app_icon.png';

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
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Icon(
        Icons.church_rounded,
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
