import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:shimmer/shimmer.dart';

/// Imagem de rede alinhada ao pipeline do Gestão YAHWEH (Storage na web, token, CORS).
///
/// **Não** usa [CachedNetworkImage] em URLs do Firebase Storage — costuma falhar ou travar no web.
/// Delega para [FreshFirebaseStorageImage] / [SafeNetworkImage].
///
/// - [isLogo]: limita cache de decode (~400px), [BoxFit.contain] no fallback da marca.
/// - Placeholder padrão: [Shimmer] (feedback claro de carregamento).
/// - URL vazia/inválida ou erro com [isLogo]: `assets/LOGO_GESTAO_YAHWEH.png`.
class YahwehImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// Ajusta memória de decode e fallback visual para logos (igreja / tenant).
  final bool isLogo;

  const YahwehImage({
    super.key,
    this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
    this.isLogo = false,
  });

  static const String _brandAsset = 'assets/LOGO_GESTAO_YAHWEH.png';

  Widget _brandFallback() {
    return Image.asset(
      _brandAsset,
      width: width,
      height: height,
      fit: isLogo ? BoxFit.contain : BoxFit.cover,
      errorBuilder: (_, __, ___) => Icon(
        Icons.church_rounded,
        size: isLogo ? 40 : 32,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _shimmerPlaceholder() {
    final w = width;
    final h = height ?? (isLogo ? 96.0 : 120.0);
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: w ?? double.infinity,
        height: h,
        color: Colors.white,
      ),
    );
  }

  static Widget _defaultErrorIcon() => Icon(
        Icons.broken_image_outlined,
        size: 32,
        color: Colors.grey.shade400,
      );

  @override
  Widget build(BuildContext context) {
    final u = sanitizeImageUrl(imageUrl ?? '');
    if (!isValidImageUrl(u)) {
      if (isLogo) return _brandFallback();
      return errorWidget ?? _defaultErrorIcon();
    }

    final defaultMw = isLogo ? 400 : 800;
    final mw = memCacheWidth ?? defaultMw;
    final mh = memCacheHeight;

    final ph = placeholder ?? _shimmerPlaceholder();
    final err = errorWidget ?? (isLogo ? _brandFallback() : _defaultErrorIcon());

    if (isFirebaseStorageHttpUrl(u) || firebaseStorageMediaUrlLooksLike(u)) {
      return FreshFirebaseStorageImage(
        imageUrl: u,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: mw,
        memCacheHeight: mh,
        placeholder: ph,
        errorWidget: err,
      );
    }
    return SafeNetworkImage(
      imageUrl: u,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: mw,
      memCacheHeight: mh,
      placeholder: ph,
      errorWidget: err,
    );
  }
}
