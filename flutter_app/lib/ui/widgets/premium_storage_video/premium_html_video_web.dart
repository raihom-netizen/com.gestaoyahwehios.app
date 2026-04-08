// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageMediaUrlLooksLike, freshFirebaseStorageDisplayUrl, sanitizeImageUrl;

/// Vídeo nativo do navegador: controles completos (velocidade, PiP, download conforme browser).
/// iOS Safari: autoplay exige [muted] = true; para hero institucional use muted + loop.
///
/// [preload] padrão `metadata`: não tenta baixar o ficheiro inteiro antes do play (melhor para MP4 no site público).
/// [posterUrl]: imagem estática (primeiro frame ou capa) — evita área preta enquanto carrega.
///
/// URLs do Firebase Storage são renovadas com token antes de definir `src` (igual ao [PremiumHtmlFeedVideo]).
Widget buildPremiumHtmlVideo(
  String url, {
  bool autoplay = false,
  bool loop = false,
  bool muted = false,
  bool controls = true,
  bool objectFitContain = false,
  String? posterUrl,
  String preload = 'metadata',
}) {
  return _PremiumHtmlVideoPlayer(
    url: url,
    autoplay: autoplay,
    loop: loop,
    muted: muted,
    controls: controls,
    objectFitContain: objectFitContain,
    posterUrl: posterUrl,
    preload: preload,
  );
}

class _PremiumHtmlVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoplay;
  final bool loop;
  final bool muted;
  final bool controls;
  /// Galeria divulgação: vídeos verticais (9:16) sem cortar — `contain` + fundo escuro.
  final bool objectFitContain;
  final String? posterUrl;
  final String preload;

  const _PremiumHtmlVideoPlayer({
    required this.url,
    required this.autoplay,
    required this.loop,
    required this.muted,
    required this.controls,
    this.objectFitContain = false,
    this.posterUrl,
    this.preload = 'metadata',
  });

  @override
  State<_PremiumHtmlVideoPlayer> createState() => _PremiumHtmlVideoPlayerState();
}

class _PremiumHtmlVideoPlayerState extends State<_PremiumHtmlVideoPlayer> {
  late final String _viewType;
  late final html.VideoElement _video;
  bool _resolving = true;

  void _detachHls() {
    try {
      final fn = js.context['yahwehDetachHls'];
      if (fn != null) {
        js.context.callMethod('yahwehDetachHls', [_video]);
      }
    } catch (_) {}
  }

  void _setVideoSource(String use) {
    final lower = use.toLowerCase();
    final looksHls =
        lower.contains('.m3u8') || lower.contains('application/x-mpegurl');
    if (looksHls) {
      try {
        final fn = js.context['yahwehAttachHls'];
        if (fn != null) {
          js.context.callMethod('yahwehAttachHls', [_video, use]);
          return;
        }
      } catch (_) {}
    }
    _detachHls();
    _video.src = use;
    _video.load();
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'yahweh-html-video-${DateTime.now().microsecondsSinceEpoch}';
    _video = html.VideoElement()
      ..controls = widget.controls
      ..autoplay = widget.autoplay
      ..loop = widget.loop
      ..muted = widget.muted
      ..preload = widget.preload
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = widget.objectFitContain ? 'contain' : 'cover';

    _video.setAttribute('playsinline', 'true');
    _video.setAttribute('webkit-playsinline', 'true');

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _video);
    unawaited(_applyPlayableUrl());
  }

  Future<void> _applyPlayableUrl() async {
    if (kIsWeb) {
      try {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      } catch (_) {}
    }
    final cleaned = sanitizeImageUrl(widget.url);
    if (cleaned.isEmpty) {
      if (mounted) setState(() => _resolving = false);
      return;
    }
    var use = cleaned;
    if (StorageMediaService.isFirebaseStorageMediaUrl(cleaned)) {
      try {
        use = await StorageMediaService.freshPlayableMediaUrl(cleaned);
      } catch (_) {
        use = cleaned;
      }
    }
    if (!mounted) return;
    await _applyPosterIfAny();
    if (!mounted) return;
    _setVideoSource(use);
    setState(() => _resolving = false);
  }

  Future<void> _applyPosterIfAny() async {
    final raw = widget.posterUrl?.trim() ?? '';
    if (raw.isEmpty) {
      _video.poster = '';
      return;
    }
    var pu = sanitizeImageUrl(raw);
    if (pu.isEmpty) return;
    if (firebaseStorageMediaUrlLooksLike(pu)) {
      try {
        pu = await freshFirebaseStorageDisplayUrl(pu);
      } catch (_) {}
    }
    if (!mounted) return;
    _video.poster = pu;
  }

  @override
  void didUpdateWidget(covariant _PremiumHtmlVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.url) != sanitizeImageUrl(widget.url) ||
        (oldWidget.posterUrl ?? '') != (widget.posterUrl ?? '') ||
        oldWidget.preload != widget.preload) {
      setState(() => _resolving = true);
      unawaited(_applyPlayableUrl());
    } else if (oldWidget.controls != widget.controls ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.loop != widget.loop ||
        oldWidget.muted != widget.muted ||
        oldWidget.objectFitContain != widget.objectFitContain) {
      _video.controls = widget.controls;
      _video.autoplay = widget.autoplay;
      _video.loop = widget.loop;
      _video.muted = widget.muted;
      _video.preload = widget.preload;
      _video.style.objectFit = widget.objectFitContain ? 'contain' : 'cover';
    }
  }

  @override
  void dispose() {
    try {
      _detachHls();
      _video.pause();
      _video.src = '';
      _video.load();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (_resolving)
          const ColoredBox(
            color: Color(0xFF0F172A),
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            ),
          ),
      ],
    );
  }
}
