import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_video_platform.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Enquadramento do painel “teatro” para Shorts / vídeo vertical (9:16), reduzindo barras vs. 16:9.
const double kChurchVideoTheaterAspect = 9 / 16;

/// 1.º passo (estilo YouTube): painel “teatro” deslizante; depois o utilizador pode ir a **tela cheia**.
Future<void> showChurchHostedVideoTheater(
  BuildContext context, {
  required String videoUrl,
  String? thumbnailUrl,
  bool autoPlay = true,
  String title = '',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetCtx) => _ChurchHostedVideoTheaterSheet(
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      autoPlay: autoPlay,
      title: title,
      parentContext: context,
    ),
  );
}

/// Igual ao fluxo YouTube: primeiro [showChurchHostedVideoTheater], depois tela cheia opcional.
Future<void> showChurchHostedVideoDialog(
  BuildContext context, {
  required String videoUrl,
  String? thumbnailUrl,
  bool autoPlay = true,
  String title = '',
}) async {
  await showChurchHostedVideoTheater(
    context,
    videoUrl: videoUrl,
    thumbnailUrl: thumbnailUrl,
    autoPlay: autoPlay,
    title: title,
  );
}

/// 2.º passo: reprodução imersiva (tela cheia) com enquadramento seguro na web e nativo.
Future<void> openChurchHostedVideoImmersive(
  BuildContext context, {
  required String videoUrl,
  String? thumbnailUrl,
  String title = '',
}) async {
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (ctx, _, __) => _ChurchVideoImmersivePage(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        title: title,
      ),
      transitionsBuilder: (ctx, anim, _, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

class _ChurchVideoImmersivePage extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final String title;

  const _ChurchVideoImmersivePage({
    required this.videoUrl,
    this.thumbnailUrl,
    this.title = '',
  });

  @override
  State<_ChurchVideoImmersivePage> createState() =>
      _ChurchVideoImmersivePageState();
}

class _ChurchVideoImmersivePageState extends State<_ChurchVideoImmersivePage> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChurchHostedVideoFullscreenPage(
      videoUrl: widget.videoUrl,
      thumbnailUrl: widget.thumbnailUrl,
      title: widget.title,
    );
  }
}

/// Página de vídeo em tela cheia (reutilizável — eventos, mural, site).
class ChurchHostedVideoFullscreenPage extends StatelessWidget {
  final String videoUrl;
  final String title;
  final String? thumbnailUrl;

  const ChurchHostedVideoFullscreenPage({
    super.key,
    required this.videoUrl,
    this.title = '',
    this.thumbnailUrl,
  });

  Future<void> _openBrowser(BuildContext context) async {
    final u = Uri.tryParse(videoUrl);
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  /// Encaixa 16:9 no ecrã (sem “zoom” a cortar na web).
  static Widget _fitVideoBox(Widget child) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final maxH = c.maxHeight;
        if (maxW <= 0 || maxH <= 0) {
          return const SizedBox.shrink();
        }
        var w = maxW;
        var h = w * 9 / 16;
        if (h > maxH) {
          h = maxH;
          w = h * 16 / 9;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoLayer = kIsWeb
        ? _fitVideoBox(
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: buildPremiumHtmlVideo(
                videoUrl,
                autoplay: true,
                muted: false,
                loop: false,
                controls: true,
                objectFitContain: true,
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, c) {
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: c.maxWidth,
                    maxHeight: c.maxHeight,
                  ),
                  child: ChurchHostedVideoSurface(
                    videoUrl: videoUrl,
                    thumbnailUrl: thumbnailUrl,
                    autoPlay: true,
                  ),
                ),
              );
            },
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: videoLayer),
          SafeArea(
            child: Stack(
              children: [
                if (title.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 12,
                    right: 56,
                    child: IgnorePointer(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              blurRadius: 14,
                              color: Colors.black.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 4,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Fechar',
                    ),
                  ),
                ),
                if (kIsWeb)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.outlined(
                              style: IconButton.styleFrom(
                                foregroundColor: Colors.white70,
                                minimumSize: const Size(
                                  ThemeCleanPremium.minTouchTarget,
                                  ThemeCleanPremium.minTouchTarget,
                                ),
                              ),
                              onPressed: () => _openBrowser(context),
                              icon: const Icon(Icons.open_in_new_rounded),
                              tooltip: 'Navegador',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChurchHostedVideoTheaterSheet extends StatelessWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;
  final String title;
  final BuildContext parentContext;

  const _ChurchHostedVideoTheaterSheet({
    required this.videoUrl,
    this.thumbnailUrl,
    required this.autoPlay,
    required this.title,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.34,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.trim().isNotEmpty ? title.trim() : 'Vídeo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // 9:16 é “alto”; dar mais altura útil que o antigo 16:9 neste slot.
                        maxHeight: h * 0.52,
                        maxWidth: double.infinity,
                      ),
                      child: AspectRatio(
                        aspectRatio: kChurchVideoTheaterAspect,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: ChurchHostedVideoSurface(
                            videoUrl: videoUrl,
                            thumbnailUrl: thumbnailUrl,
                            autoPlay: autoPlay,
                            layoutAspectRatio: kChurchVideoTheaterAspect,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Fechar',
                          style: TextStyle(color: Colors.grey.shade300),
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!parentContext.mounted) return;
                            unawaited(
                              openChurchHostedVideoImmersive(
                                parentContext,
                                videoUrl: videoUrl,
                                thumbnailUrl: thumbnailUrl,
                                title: title,
                              ),
                            );
                          });
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.fullscreen_rounded, size: 20),
                        label: const Text('Tela cheia'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Superfície de vídeo reutilizável (mural, site público, tela cheia de eventos).
class ChurchHostedVideoSurface extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;

  /// Caixa de layout (web, loading, erro). Nativo após init usa o aspect do vídeo.
  /// No teatro vertical use [kChurchVideoTheaterAspect] (9:16) para alinhar com Shorts.
  final double? layoutAspectRatio;

  const ChurchHostedVideoSurface({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.autoPlay = true,
    this.layoutAspectRatio,
  });

  @override
  State<ChurchHostedVideoSurface> createState() =>
      _ChurchHostedVideoSurfaceState();
}

class _ChurchHostedVideoSurfaceState extends State<ChurchHostedVideoSurface> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  bool _loading = true;
  bool _failed = false;

  double get _boxAspect => widget.layoutAspectRatio ?? (16 / 9);

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loading = false;
      return;
    }
    _initNative();
  }

  Future<void> _initNative() async {
    VideoPlayerController? c;
    try {
      final playUrl = await resolveFirebaseStorageVideoPlayUrl(widget.videoUrl);
      if (!mounted) return;
      if (playUrl.isEmpty || Uri.tryParse(playUrl) == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final controller = networkVideoControllerForUrl(playUrl);
      c = controller;
      await controller
          .initialize()
          .timeout(const Duration(seconds: 22),
              onTimeout: () => throw TimeoutException('init'));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _vc = controller;
      _chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: widget.autoPlay,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : _boxAspect,
        errorBuilder: (context, message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Não foi possível reproduzir o vídeo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
        ),
      );
      setState(() => _loading = false);
    } catch (_) {
      await c?.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChurchHostedVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb) return;
    if (oldWidget.videoUrl == widget.videoUrl) return;
    _chewie?.dispose();
    _vc?.dispose();
    _chewie = null;
    _vc = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    _initNative();
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return AspectRatio(
        aspectRatio: _boxAspect,
        child: buildPremiumHtmlVideo(
          widget.videoUrl,
          autoplay: widget.autoPlay,
          muted: false,
          loop: false,
          controls: true,
          objectFitContain: true,
        ),
      );
    }

    if (_failed) {
      return AspectRatio(
        aspectRatio: _boxAspect,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: TextButton.icon(
              onPressed: () async {
                final u = Uri.tryParse(widget.videoUrl);
                if (u != null && await canLaunchUrl(u)) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70),
              label: const Text('Abrir vídeo',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      );
    }

    final thumb = sanitizeImageUrl(widget.thumbnailUrl);
    final hasThumb = isValidImageUrl(thumb);

    if (_loading) {
      final isPortraitBox = _boxAspect < 1.0;
      return AspectRatio(
        aspectRatio: _boxAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumb)
              FreshFirebaseStorageImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                memCacheWidth: isPortraitBox ? 360 : 640,
                memCacheHeight: isPortraitBox ? 640 : 360,
                placeholder: Container(color: Colors.grey.shade900),
                errorWidget: Container(color: Colors.grey.shade900),
              )
            else
              ColoredBox(color: Colors.grey.shade900),
            const ColoredBox(color: Color(0x66000000)),
            const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    final chewie = _chewie;
    final vc = _vc;
    if (chewie != null && vc != null && vc.value.isInitialized) {
      return AspectRatio(
        aspectRatio:
            vc.value.aspectRatio > 0 ? vc.value.aspectRatio : _boxAspect,
        child: Chewie(controller: chewie),
      );
    }

    return AspectRatio(
      aspectRatio: _boxAspect,
      child: ColoredBox(color: Colors.grey.shade900),
    );
  }
}
