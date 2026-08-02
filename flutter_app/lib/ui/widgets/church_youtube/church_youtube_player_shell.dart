import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/youtube_url_helper.dart';

import 'church_youtube_embed.dart';

/// Player estilo YouTube (Cursos): capa até o toque ▶, depois embed in-app.
class ChurchYoutubePlayerShell extends StatefulWidget {
  const ChurchYoutubePlayerShell({
    super.key,
    this.youtubeVideoId,
    this.mp4Url,
    this.posterUrl,
    this.autoplay = false,
    this.borderRadius = 16,
  });

  final String? youtubeVideoId;
  final String? mp4Url;
  final String? posterUrl;
  final bool autoplay;
  final double borderRadius;

  @override
  State<ChurchYoutubePlayerShell> createState() =>
      _ChurchYoutubePlayerShellState();
}

class _ChurchYoutubePlayerShellState extends State<ChurchYoutubePlayerShell> {
  var _playbackStarted = false;

  bool get _showEmbed => widget.autoplay || _playbackStarted;

  bool get _isYoutube =>
      (widget.youtubeVideoId ?? '').trim().isNotEmpty;

  String? get _resolvedPoster {
    final p = (widget.posterUrl ?? '').trim();
    if (p.isNotEmpty) return p;
    final yt = widget.youtubeVideoId?.trim();
    if (yt != null && yt.isNotEmpty) {
      return YoutubeUrlHelper.thumbnailUrl(yt);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _playbackStarted = widget.autoplay;
  }

  @override
  void didUpdateWidget(covariant ChurchYoutubePlayerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeVideoId != widget.youtubeVideoId ||
        oldWidget.mp4Url != widget.mp4Url) {
      if (!widget.autoplay) _playbackStarted = false;
    }
    if (widget.autoplay && !_playbackStarted) {
      _playbackStarted = true;
    }
  }

  void _startPlayback() {
    if (_playbackStarted) return;
    setState(() => _playbackStarted = true);
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _isYoutube || (widget.mp4Url ?? '').trim().isNotEmpty;
    if (!hasMedia) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: const Color(0xFF0F0F0F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_showEmbed)
                ChurchYoutubeEmbed(
                  youtubeVideoId: widget.youtubeVideoId,
                  mp4Url: widget.mp4Url,
                  autoplay: true,
                  posterUrl: _resolvedPoster,
                )
              else
                _buildPoster(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoster() {
    final poster = _resolvedPoster;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startPlayback,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (poster != null && poster.isNotEmpty)
              SafeNetworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                errorWidget: Container(
                  color: const Color(0xFF1E3A8A),
                  child: const Icon(Icons.videocam_rounded,
                      color: Colors.white54, size: 48),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 68,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xF0FF0000),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isYoutube ? 'YouTube' : 'Vídeo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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
