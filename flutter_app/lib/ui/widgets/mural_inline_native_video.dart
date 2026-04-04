import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Vídeo MP4 no feed (Android/iOS): play automático em mudo quando ≥50% visível; pausa ao sair.
class MuralInlineNativeVideo extends StatefulWidget {
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
  State<MuralInlineNativeVideo> createState() => _MuralInlineNativeVideoState();
}

class _MuralInlineNativeVideoState extends State<MuralInlineNativeVideo> {
  VideoPlayerController? _c;
  bool _busy = false;
  String? _error;
  double _progress = 0;
  bool _firedMostlyVisible = false;

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  void _tick() {
    final ctrl = _c;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final d = ctrl.value.duration;
    if (d.inMilliseconds <= 0) return;
    final p = ctrl.value.position.inMilliseconds / d.inMilliseconds;
    if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
  }

  Future<void> _ensureController() async {
    if (_c != null || _busy || kIsWeb) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final playUrl = await resolveFirebaseStorageVideoPlayUrl(widget.videoUrl);
      final ctrl = networkVideoControllerForUrl(playUrl);
      await ctrl.initialize();
      await ctrl.setVolume(0);
      ctrl.setLooping(true);
      ctrl.addListener(_tick);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _c = ctrl);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _disposeControllerSoon() {
    final ctrl = _c;
    if (ctrl == null) return;
    ctrl.removeListener(_tick);
    ctrl.dispose();
    _c = null;
    if (mounted) setState(() => _progress = 0);
  }

  void _onVisibility(double fraction) {
    if (kIsWeb) return;
    if (fraction >= 0.5) {
      if (!_firedMostlyVisible) {
        _firedMostlyVisible = true;
        widget.onMostlyVisible?.call();
      }
      _ensureController().then((_) {
        final ctrl = _c;
        if (ctrl != null && ctrl.value.isInitialized && mounted) {
          ctrl.play();
        }
      });
    } else if (fraction < 0.12) {
      final ctrl = _c;
      if (ctrl != null && ctrl.value.isInitialized) {
        ctrl.pause();
      }
      if (fraction < 0.03) {
        _disposeControllerSoon();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumb = (widget.thumbnailUrl ?? '').trim();
    final hasThumb = thumb.startsWith('http://') || thumb.startsWith('https://');

    return VisibilityDetector(
      key: Key('native-vid-${widget.visibilityKey}'),
      onVisibilityChanged: (info) => _onVisibility(info.visibleFraction),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: Colors.black,
            child: InkWell(
              onTap: widget.onTapOpenFullscreen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_c != null && _c!.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _c!.value.size.width,
                        height: _c!.value.size.height,
                        child: VideoPlayer(_c!),
                      ),
                    )
                  else if (hasThumb)
                    SafeNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 640,
                      memCacheHeight: 360,
                      placeholder: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorWidget: const Center(
                        child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 48),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.videocam_rounded, color: Colors.white38, size: 48),
                    ),
                  if (_busy)
                    const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Toque para tentar em tela cheia',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 3,
                    child: LinearProgressIndicator(
                      value: _c != null && _c!.value.isInitialized ? _progress : null,
                      minHeight: 3,
                      backgroundColor: Colors.black38,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF472B6)),
                    ),
                  ),
                  if (_c == null || !_c!.value.isInitialized)
                    const Center(
                      child: Icon(Icons.play_circle_fill_rounded, size: 52, color: Colors.white70),
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
