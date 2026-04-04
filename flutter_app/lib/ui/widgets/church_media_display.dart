import 'package:flutter/material.dart';

import 'safe_network_image.dart';

/// Exibição de mídia (fotos de membros, eventos, igreja) com fallback amigável.
/// Usa [FreshFirebaseStorageImage] (EcoFire: refresh token + SafeNetworkImage).
/// memCacheWidth: null = full res (site público); 1200 = alta res sem pixelizar; valores baixos (ex.: 88) deixam a imagem pixelada.
class ChurchMediaDisplay extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  /// null = máxima resolução (evita pixelização no site público). 1200 = alta res para cards.
  final int? memCacheWidth;
  final Widget? placeholder;
  final Widget? errorWidget;

  const ChurchMediaDisplay({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth = 1200,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final url = sanitizeImageUrl(imageUrl);
    if (url.isEmpty || !isValidImageUrl(url)) {
      return _buildErrorPlaceholder();
    }

    final ph = SizedBox(
      width: width,
      height: height,
      child: Center(child: placeholder ?? const CircularProgressIndicator(strokeWidth: 2)),
    );

    return FreshFirebaseStorageImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheWidth != null ? (memCacheWidth! * 0.75).round() : null,
      placeholder: ph,
      errorWidget: _buildErrorPlaceholder(),
    );
  }

  Widget _buildErrorPlaceholder() {
    if (errorWidget != null) return errorWidget!;
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.grey.shade400, size: 40),
          const SizedBox(height: 8),
          Text(
            'Imagem indisponível',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
