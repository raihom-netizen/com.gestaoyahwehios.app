import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Vídeo hospedado no feed (Android/iOS): **só capa + ícone de play** — o player só inicia ao toque
/// ([onTapOpenFullscreen]), para não descarregar MP4/HLS na lista nem acumular decoders na RAM.
class MuralInlineNativeVideo extends StatelessWidget {
  const MuralInlineNativeVideo({
    super.key,
    required this.videoUrl,
    required this.visibilityKey,
    this.thumbnailUrl,
    this.borderRadius = 12,
    this.onTapOpenFullscreen,
    this.onMostlyVisible,
  });

  final String videoUrl;
  final String visibilityKey;
  final String? thumbnailUrl;
  final double borderRadius;
  final VoidCallback? onTapOpenFullscreen;
  final VoidCallback? onMostlyVisible;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    final thumb = (thumbnailUrl ?? '').trim();
    final hasThumb =
        thumb.startsWith('http://') || thumb.startsWith('https://');

    return VisibilityDetector(
      key: Key('native-vid-${visibilityKey}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction >= 0.45) {
          onMostlyVisible?.call();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: Colors.black,
            child: InkWell(
              onTap: onTapOpenFullscreen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasThumb)
                    SafeNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 640,
                      memCacheHeight: 360,
                      placeholder: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      errorWidget: const Center(
                        child: Icon(
                          Icons.videocam_rounded,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(
                        Icons.videocam_rounded,
                        color: Colors.white38,
                        size: 48,
                      ),
                    ),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 52,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
