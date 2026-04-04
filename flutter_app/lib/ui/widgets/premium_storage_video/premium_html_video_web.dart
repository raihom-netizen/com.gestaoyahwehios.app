// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show sanitizeImageUrl;

/// Vídeo nativo do navegador: controles completos (velocidade, PiP, download conforme browser).
/// iOS Safari: autoplay exige [muted] = true; para hero institucional use muted + loop.
///
/// URLs do Firebase Storage são renovadas com token antes de definir `src` (igual ao [PremiumHtmlFeedVideo]).
Widget buildPremiumHtmlVideo(
  String url, {
  bool autoplay = false,
  bool loop = false,
  bool muted = false,
  bool controls = true,
}) {
  return _PremiumHtmlVideoPlayer(
    url: url,
    autoplay: autoplay,
    loop: loop,
    muted: muted,
    controls: controls,
  );
}

class _PremiumHtmlVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoplay;
  final bool loop;
  final bool muted;
  final bool controls;

  const _PremiumHtmlVideoPlayer({
    required this.url,
    required this.autoplay,
    required this.loop,
    required this.muted,
    required this.controls,
  });

  @override
  State<_PremiumHtmlVideoPlayer> createState() => _PremiumHtmlVideoPlayerState();
}

class _PremiumHtmlVideoPlayerState extends State<_PremiumHtmlVideoPlayer> {
  late final String _viewType;
  late final html.VideoElement _video;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _viewType = 'yahweh-html-video-${DateTime.now().microsecondsSinceEpoch}';
    _video = html.VideoElement()
      ..controls = widget.controls
      ..autoplay = widget.autoplay
      ..loop = widget.loop
      ..muted = widget.muted
      ..preload = 'auto'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

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
    _video.src = use;
    _video.load();
    setState(() => _resolving = false);
  }

  @override
  void didUpdateWidget(covariant _PremiumHtmlVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (sanitizeImageUrl(oldWidget.url) != sanitizeImageUrl(widget.url)) {
      setState(() => _resolving = true);
      unawaited(_applyPlayableUrl());
    } else if (oldWidget.controls != widget.controls ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.loop != widget.loop ||
        oldWidget.muted != widget.muted) {
      _video.controls = widget.controls;
      _video.autoplay = widget.autoplay;
      _video.loop = widget.loop;
      _video.muted = widget.muted;
    }
  }

  @override
  void dispose() {
    try {
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
