// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;
import 'package:visibility_detector/visibility_detector.dart';

/// Vídeo HTML estável (um [VideoElement] por instância), autoplay em mudo quando ≥50% visível.
/// Com [startLoadingImmediately] e [preload=auto], o buffer começa ao montar (feed estilo Instagram).
class PremiumHtmlFeedVideo extends StatefulWidget {
  const PremiumHtmlFeedVideo({
    super.key,
    required this.videoUrl,
    required this.visibilityKey,
    this.showControls = true,
    this.onMostlyVisible,
    this.posterUrl,
    this.startLoadingImmediately = false,
    /// No feed estilo Instagram: `true` evita corte agressivo (letterbox).
    this.videoObjectFitContain = true,
  });

  final String videoUrl;
  final String visibilityKey;
  final bool showControls;
  final VoidCallback? onMostlyVisible;
  final String? posterUrl;
  final bool startLoadingImmediately;
  final bool videoObjectFitContain;

  @override
  State<PremiumHtmlFeedVideo> createState() => _PremiumHtmlFeedVideoState();
}

class _PremiumHtmlFeedVideoState extends State<PremiumHtmlFeedVideo> {
  late final String _viewType;
  late final html.VideoElement _video;
  double _progress = 0;
  bool _firedMostlyVisible = false;
  bool _resolvingUrl = true;
  bool _srcRequested = false;

  Future<void> _applyPlayableUrl(String raw) async {
    final cleaned = sanitizeImageUrl(raw);
    if (cleaned.isEmpty) {
      if (mounted) setState(() => _resolvingUrl = false);
      return;
    }
    var use = cleaned;
    if (StorageMediaService.isFirebaseStorageMediaUrl(cleaned)) {
      use = await StorageMediaService.freshPlayableMediaUrl(cleaned);
    }
    if (!isValidImageUrl(use)) {
      final fromPath =
          await StorageMediaService.downloadUrlFromPathOrUrl(cleaned);
      if (fromPath != null && fromPath.trim().isNotEmpty) {
        use = sanitizeImageUrl(fromPath);
      }
    }
    if (!mounted) return;
    _video.src = use;
    _video.load();
    setState(() => _resolvingUrl = false);
  }

  @override
  void initState() {
    super.initState();
    final safeKey = widget.visibilityKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    _viewType = 'yahweh-feed-$safeKey-${widget.videoUrl.hashCode.abs()}';

    _video = html.VideoElement()
      ..controls = widget.showControls
      ..autoplay = false
      ..loop = false
      ..muted = true
      ..preload = widget.startLoadingImmediately ? 'auto' : 'metadata'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit =
          widget.videoObjectFitContain ? 'contain' : 'cover';

    _video.setAttribute('playsinline', 'true');
    _video.setAttribute('webkit-playsinline', 'true');
    _applyPosterAttribute();

    _video.onTimeUpdate.listen((_) {
      if (!mounted) return;
      final d = _video.duration;
      if (d.isFinite && d > 0) {
        setState(() => _progress = (_video.currentTime / d).clamp(0.0, 1.0));
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _video);

    if (widget.startLoadingImmediately) {
      _srcRequested = true;
      unawaited(_applyPlayableUrl(widget.videoUrl));
    }
  }

  void _applyPosterAttribute() {
    final raw = (widget.posterUrl ?? '').trim();
    if (raw.isEmpty) {
      _video.removeAttribute('poster');
      return;
    }
    final s = sanitizeImageUrl(raw);
    if (isValidImageUrl(s)) {
      _video.poster = s;
    }
  }

  @override
  void didUpdateWidget(covariant PremiumHtmlFeedVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoObjectFitContain != widget.videoObjectFitContain) {
      _video.style.objectFit =
          widget.videoObjectFitContain ? 'contain' : 'cover';
    }
    if (oldWidget.posterUrl != widget.posterUrl) {
      _applyPosterAttribute();
    }
    if (oldWidget.startLoadingImmediately != widget.startLoadingImmediately) {
      _video.preload = widget.startLoadingImmediately ? 'auto' : 'metadata';
    }
    if (sanitizeImageUrl(oldWidget.videoUrl) != sanitizeImageUrl(widget.videoUrl)) {
      setState(() => _resolvingUrl = true);
      _srcRequested = true;
      unawaited(_applyPlayableUrl(widget.videoUrl));
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

  void _applyVisibility(double fraction) {
    if (!_srcRequested &&
        fraction >= 0.08 &&
        !widget.startLoadingImmediately) {
      _srcRequested = true;
      unawaited(_applyPlayableUrl(widget.videoUrl));
    }
    if (fraction >= 0.5) {
      if (!_firedMostlyVisible) {
        _firedMostlyVisible = true;
        widget.onMostlyVisible?.call();
      }
      _video.muted = true;
      unawaited(_video.play().catchError((Object _) {}));
    } else if (fraction < 0.15) {
      _video.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('html-vid-${widget.visibilityKey}'),
      onVisibilityChanged: (info) => _applyVisibility(info.visibleFraction),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: HtmlElementView(viewType: _viewType),
            ),
            if (_resolvingUrl)
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 3,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 3,
                backgroundColor: Colors.black26,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF472B6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
