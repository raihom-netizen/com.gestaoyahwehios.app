import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'safe_network_image.dart'
    show FreshFirebaseStorageImage, isValidImageUrl, sanitizeImageUrl;
import 'unavailable_media_widget.dart';

/// Exibição de mídia (fotos de membros, painel, site) com cache, fallback e retry.
class MediaView extends StatefulWidget {
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

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  int _generation = 0;

  String get _normalized => sanitizeImageUrl(widget.url);

  bool get _isValidUrl => isValidImageUrl(_normalized);

  void _retry() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    if (!_isValidUrl) {
      return _errorPlaceholder(onRetry: null);
    }

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final mem = (widget.size * dpr).round().clamp(48, 1024);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: KeyedSubtree(
        key: ValueKey<int>(_generation),
        child: FreshFirebaseStorageImage(
          imageUrl: widget.url,
          width: widget.size,
          height: widget.size,
          fit: widget.fit,
          memCacheWidth: mem,
          memCacheHeight: mem,
          placeholder: _loadingPlaceholder(),
          errorWidget: _errorPlaceholder(onRetry: _retry),
        ),
      ),
    );
  }

  Widget _loadingPlaceholder() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Center(
        child: SizedBox(
          width: widget.size * 0.4,
          height: widget.size * 0.4,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _errorPlaceholder({VoidCallback? onRetry}) {
    return UnavailableMediaWidget(
      width: widget.size,
      height: widget.size,
      message: 'Imagem indisponível',
      onRetry: onRetry,
      compact: widget.size < 72,
      icon: Icons.person_rounded,
    );
  }
}
