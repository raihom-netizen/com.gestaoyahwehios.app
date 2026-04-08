import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_video_platform.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Abre vídeo hospedado (Firebase Storage / MP4) com miniatura durante o buffer e
/// [Chewie] no Android/iOS/desktop; na **web** usa o player HTML já usado no projeto
/// (evita CORS/CanvasKit com `VideoPlayer` nativo).
///
/// A URL é sempre renovada com [resolveFirebaseStorageVideoPlayUrl] antes do play.
Future<void> showChurchHostedVideoDialog(
  BuildContext context, {
  required String videoUrl,
  String? thumbnailUrl,
  bool autoPlay = true,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => _ChurchHostedVideoDialog(
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      autoPlay: autoPlay,
    ),
  );
}

/// Abre o vídeo em rota quase tela cheia com autoplay (Chewie nativo; HTML na web).
Future<void> openChurchHostedVideoImmersive(
  BuildContext context, {
  required String videoUrl,
  String? thumbnailUrl,
}) async {
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (ctx, _, __) => _ChurchVideoImmersivePage(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
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

  const _ChurchVideoImmersivePage({
    required this.videoUrl,
    this.thumbnailUrl,
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
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: pad.top),
              child: Center(
                child: ChurchHostedVideoSurface(
                  videoUrl: widget.videoUrl,
                  thumbnailUrl: widget.thumbnailUrl,
                  autoPlay: true,
                ),
              ),
            ),
          ),
          Positioned(
            top: pad.top + 4,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChurchHostedVideoDialog extends StatelessWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;

  const _ChurchHostedVideoDialog({
    required this.videoUrl,
    this.thumbnailUrl,
    required this.autoPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ChurchHostedVideoSurface(
              videoUrl: videoUrl,
              thumbnailUrl: thumbnailUrl,
              autoPlay: autoPlay,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Fechar',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Superfície de vídeo reutilizável (mural, site público, tela cheia de eventos).
class ChurchHostedVideoSurface extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;
  final bool autoPlay;

  const ChurchHostedVideoSurface({
    super.key,
    required this.videoUrl,
    this.thumbnailUrl,
    this.autoPlay = true,
  });

  @override
  State<ChurchHostedVideoSurface> createState() => _ChurchHostedVideoSurfaceState();
}

class _ChurchHostedVideoSurfaceState extends State<ChurchHostedVideoSurface> {
  VideoPlayerController? _vc;
  ChewieController? _chewie;
  bool _loading = true;
  bool _failed = false;

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
          .timeout(const Duration(seconds: 22), onTimeout: () => throw TimeoutException('init'));
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
        aspectRatio: controller.value.aspectRatio > 0 ? controller.value.aspectRatio : 16 / 9,
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
        aspectRatio: 16 / 9,
        child: buildPremiumHtmlVideo(
          widget.videoUrl,
          autoplay: widget.autoPlay,
          muted: false,
          loop: false,
          controls: true,
        ),
      );
    }

    if (_failed) {
      return AspectRatio(
        aspectRatio: 16 / 9,
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
              label: const Text('Abrir vídeo', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      );
    }

    final thumb = sanitizeImageUrl(widget.thumbnailUrl);
    final hasThumb = isValidImageUrl(thumb);

    if (_loading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumb)
              FreshFirebaseStorageImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                memCacheWidth: 640,
                memCacheHeight: 360,
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
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
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
        aspectRatio: vc.value.aspectRatio > 0 ? vc.value.aspectRatio : 16 / 9,
        child: Chewie(controller: chewie),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(color: Colors.grey.shade900),
    );
  }
}
