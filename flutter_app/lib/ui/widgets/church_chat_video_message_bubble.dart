import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Bolha de vídeo no chat — **sem** [VideoPlayer]/PlatformView na lista.
///
/// Mostra miniatura + botão play; reprodução só no teatro (tap).
/// Evita crash JNI (`platform_view_android_jni_impl`) em Android 13–15 / HyperOS.
class ChurchChatVideoMessageBubble extends StatelessWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final String? fileName;
  final bool mine;
  final Future<void> Function(String url, {String fileName})? onDownload;

  const ChurchChatVideoMessageBubble({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.fileName,
    this.mine = false,
    this.onDownload,
  });

  String? get _resolvedThumb {
    final t = (thumbnailUrl ?? '').trim();
    if (t.isNotEmpty && isValidImageUrl(sanitizeImageUrl(t))) return t;
    return null;
  }

  Future<void> _openTheater(BuildContext context) async {
    try {
      await showChurchHostedVideoTheater(
        context,
        videoUrl: videoUrl,
        thumbnailUrl: _resolvedThumb,
        title: (fileName ?? '').trim().isNotEmpty
            ? fileName!.trim()
            : 'Vídeo',
        autoPlay: true,
      );
    } catch (e, st) {
      if (!kIsWeb) {
        unawaited(
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason: 'church_chat_video_theater_open',
            fatal: false,
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o vídeo. Tente novamente.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _resolvedThumb;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const bubbleW = 260.0;
    final memW = (dpr * bubbleW).round().clamp(160, 480);
    final memH = (memW * 9 / 16).round();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.black,
              child: InkWell(
                onTap: () => unawaited(_openTheater(context)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null)
                        FreshFirebaseStorageImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          width: bubbleW,
                          height: bubbleW * 9 / 16,
                          memCacheWidth: memW,
                          memCacheHeight: memH,
                          placeholder: ColoredBox(color: Colors.grey.shade900),
                          errorWidget: ColoredBox(color: Colors.grey.shade900),
                        )
                      else
                        ColoredBox(color: Colors.grey.shade900),
                      const ColoredBox(color: Color(0x44000000)),
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(14),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF0F172A).withValues(alpha: 0.92),
                    const Color(0xFF1E293B).withValues(alpha: 0.95),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            'Toque para reproduzir',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(
                            ThemeCleanPremium.minTouchTarget,
                            ThemeCleanPremium.minTouchTarget,
                          ),
                        ),
                        onPressed: () => unawaited(_openTheater(context)),
                        icon: const Icon(Icons.fullscreen_rounded, size: 22),
                        label: const Text(
                          'Ampliar',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (onDownload != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget,
                            ),
                          ),
                          onPressed: () => unawaited(
                            onDownload!(
                              videoUrl,
                              fileName: fileName ?? '',
                            ),
                          ),
                          icon:
                              const Icon(Icons.download_rounded, size: 22),
                          label: const Text(
                            'Baixar',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
