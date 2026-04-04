import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'safe_network_image.dart'
    show FreshFirebaseStorageImage, isValidImageUrl, sanitizeImageUrl;

/// Exibição de mídia (fotos de membros, painel, site) com cache e fallback.
/// Na **web**, [Image.network] costuma falhar com URLs do Firebase Storage (CanvasKit);
/// usamos [StorageFriendlyImage] (HTTP + memória), igual patrimônio/certificados.
class MediaView extends StatelessWidget {
  final String url;
  final double size;
  final double borderRadius;
  final BoxFit fit;

  const MediaView({
    super.key,
    required this.url,
    this.size = 100,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  String get _normalized => sanitizeImageUrl(url);

  bool get _isValidUrl => isValidImageUrl(_normalized);

  @override
  Widget build(BuildContext context) {
    if (!_isValidUrl) return _errorPlaceholder();

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: FreshFirebaseStorageImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: fit,
          memCacheWidth: (size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0)).round().clamp(48, 1024),
          memCacheHeight: (size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0)).round().clamp(48, 1024),
          placeholder: _loadingPlaceholder(),
          errorWidget: _errorPlaceholder(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: FreshFirebaseStorageImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: fit,
        memCacheWidth:
            (size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0))
                .round()
                .clamp(48, 1024),
        memCacheHeight:
            (size * (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0))
                .round()
                .clamp(48, 1024),
        placeholder: _loadingPlaceholder(),
        errorWidget: _errorPlaceholder(),
      ),
    );
  }

  Widget _loadingPlaceholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.4,
          height: size * 0.4,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _errorPlaceholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(Icons.person_rounded, size: size * 0.5, color: Colors.grey.shade500),
    );
  }
}
