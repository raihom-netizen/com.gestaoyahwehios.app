import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_video_platform.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show freshFirebaseStorageDisplayUrl, sanitizeImageUrl;
import 'package:video_player/video_player.dart';

/// Campos opcionais no Firestore (`igrejas/{id}` ou `app_public/site`) para vídeo institucional.
bool mapHasInstitutionalVideo(Map<String, dynamic>? data) {
  if (data == null) return false;
  final url = _directVideoUrlFromMap(data);
  if (url != null && url.isNotEmpty) return true;
  final path = _storagePathFromMap(data);
  return path != null && path.isNotEmpty;
}

String? _directVideoUrlFromMap(Map<String, dynamic> data) {
  for (final k in const [
    'institutionalVideoUrl',
    'videoInstitucionalUrl',
    'videoHeroUrl',
    'heroVideoUrl',
    'videoUrl',
    'institutional_video_url',
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isEmpty) continue;
    final s = sanitizeImageUrl(v);
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
  }
  return null;
}

String? _storagePathFromMap(Map<String, dynamic> data) {
  for (final k in const [
    'institutionalVideoStoragePath',
    'videoHeroStoragePath',
    'heroVideoStoragePath',
    'institutional_video_storage_path',
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v.replaceAll('\\', '/');
  }
  return null;
}

String? _posterUrlFromMap(Map<String, dynamic> data) {
  for (final k in const [
    'institutionalVideoPosterUrl',
    'heroVideoPosterUrl',
    'videoPosterUrl',
    'institutional_video_poster_url',
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isEmpty) continue;
    final s = sanitizeImageUrl(v);
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
  }
  return null;
}

String? _posterStoragePathFromMap(Map<String, dynamic> data) {
  for (final k in const [
    'institutionalVideoPosterStoragePath',
    'heroVideoPosterStoragePath',
    'videoPosterStoragePath',
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v.replaceAll('\\', '/');
  }
  return null;
}

/// Card estilo EcoFire: borda 16, sombra suave, legenda abaixo, vídeo HTML na web (PiP / velocidade / download).
class PremiumInstitutionalVideoCard extends StatefulWidget {
  /// URL direta (https) do vídeo.
  final String? videoUrl;

  /// Caminho no Firebase Storage (ex.: `public/videos/institucional.mp4`).
  final String? storagePath;

  final double height;
  final String caption;
  final String? hintBelow;

  /// Hero: autoplay silencioso em loop (web). Conteúdo: use false.
  final bool heroAutoplay;

  /// Galeria pública: mostra o vídeo inteiro (vertical 9:16) sem cortar — fundo escuro + `contain`.
  final bool letterbox;

  /// Frame estático (web) enquanto o MP4 carrega — URL https ou renovada no Storage.
  final String? posterUrl;

  /// Alternativa a [posterUrl]: caminho no bucket (ex. `public/.../poster.webp`).
  final String? posterStoragePath;

  const PremiumInstitutionalVideoCard({
    super.key,
    this.videoUrl,
    this.storagePath,
    this.height = 280,
    this.caption = 'VÍDEO INSTITUCIONAL',
    this.hintBelow,
    this.heroAutoplay = true,
    this.letterbox = false,
    this.posterUrl,
    this.posterStoragePath,
  });

  /// Monta a partir do documento da igreja (painel / site público da igreja).
  factory PremiumInstitutionalVideoCard.fromChurchDoc(
    Map<String, dynamic> data, {
    double height = 260,
    String caption = 'VÍDEO INSTITUCIONAL',
    String? hintBelow,
    bool heroAutoplay = true,
  }) {
    return PremiumInstitutionalVideoCard(
      videoUrl: _directVideoUrlFromMap(data),
      storagePath: _storagePathFromMap(data),
      height: height,
      caption: caption,
      hintBelow: hintBelow,
      heroAutoplay: heroAutoplay,
      posterUrl: _posterUrlFromMap(data),
      posterStoragePath: _posterStoragePathFromMap(data),
    );
  }

  @override
  State<PremiumInstitutionalVideoCard> createState() =>
      _PremiumInstitutionalVideoCardState();
}

class _PremiumInstitutionalVideoCardState
    extends State<PremiumInstitutionalVideoCard> {
  String? _resolved;
  String? _posterResolved;
  String? _err;
  bool _loading = true;
  bool _mobileInitFailed = false;
  VideoPlayerController? _mobile;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PremiumInstitutionalVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.posterStoragePath != widget.posterStoragePath) {
      _mobile?.dispose();
      _mobile = null;
      _resolved = null;
      _posterResolved = null;
      _err = null;
      _loading = true;
      _mobileInitFailed = false;
      _resolve();
    }
  }

  Future<void> _resolvePoster() async {
    final direct = widget.posterUrl?.trim() ?? '';
    if (direct.isNotEmpty) {
      final u = sanitizeImageUrl(direct);
      if (u.startsWith('http://') || u.startsWith('https://')) {
        try {
          final out = await freshFirebaseStorageDisplayUrl(u);
          if (mounted) setState(() => _posterResolved = out);
        } catch (_) {
          if (mounted) setState(() => _posterResolved = u);
        }
      }
      return;
    }
    final path = widget.posterStoragePath?.trim() ?? '';
    if (path.isEmpty) {
      if (mounted) setState(() => _posterResolved = null);
      return;
    }
    try {
      final ref = FirebaseStorage.instance.ref(path);
      final u = await ref.getDownloadURL();
      if (mounted) setState(() => _posterResolved = u);
    } catch (_) {
      if (mounted) setState(() => _posterResolved = null);
    }
  }

  Future<void> _resolve() async {
    unawaited(_resolvePoster());
    final direct = widget.videoUrl?.trim() ?? '';
    if (direct.isNotEmpty) {
      final u = sanitizeImageUrl(direct);
      if (u.startsWith('http://') || u.startsWith('https://')) {
        // Web + mobile: renovar token do Storage (padrão EcoFire — URL fresca antes do <video> / player).
        var play = '';
        for (var attempt = 0; attempt < 2; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 450));
            if (!mounted) return;
          }
          try {
            play = await resolveFirebaseStorageVideoPlayUrl(u);
            if (play.trim().isNotEmpty) break;
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _resolved = play.isNotEmpty ? play : null;
            _loading = false;
            _err = play.isNotEmpty ? null : 'URL de vídeo indisponível';
            _mobileInitFailed = false;
          });
        }
        if (play.isNotEmpty && !kIsWeb) _initMobile(play);
        return;
      }
    }
    final path = widget.storagePath?.trim() ?? '';
    if (path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    Future<void> tryPath() async {
      final ref = FirebaseStorage.instance.ref(path);
      final u = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _resolved = u;
        _loading = false;
        _err = null;
        _mobileInitFailed = false;
      });
      if (!kIsWeb) _initMobile(u);
    }

    try {
      await tryPath();
    } catch (e) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      try {
        await tryPath();
      } catch (e2) {
        if (!mounted) return;
        setState(() {
          _err = e2.toString();
          _loading = false;
          _resolved = null;
        });
      }
    }
  }

  Future<void> _initMobile(String url, {bool allowRetry = true}) async {
    if (kIsWeb) return;
    if (mounted) {
      setState(() {
        _mobileInitFailed = false;
        _err = null;
      });
    }
    final resolved = await resolveFirebaseStorageVideoPlayUrl(url);
    final c = networkVideoControllerForUrl(resolved);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.setLooping(widget.heroAutoplay);
      if (widget.heroAutoplay) {
        c.setVolume(0);
        await c.play();
      }
      setState(() => _mobile = c);
    } catch (e) {
      await c.dispose();
      if (allowRetry) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        await _initMobile(url, allowRetry: false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _mobile = null;
        _mobileInitFailed = true;
        _err = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _mobile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(
        child: SizedBox(
          height: widget.height,
          child: const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (_err != null || _resolved == null || _resolved!.isEmpty) {
      return const SizedBox.shrink();
    }
    final url = _resolved!;
    final fit = widget.letterbox ? BoxFit.contain : BoxFit.cover;

    final videoChild = kIsWeb
        ? SizedBox(
            height: widget.height,
            width: double.infinity,
            child: ColoredBox(
              color: widget.letterbox
                  ? const Color(0xFF0B1120)
                  : Colors.transparent,
              child: buildPremiumHtmlVideo(
                url,
                autoplay: widget.heroAutoplay,
                loop: widget.heroAutoplay,
                muted: widget.heroAutoplay,
                controls: true,
                objectFitContain: widget.letterbox,
                posterUrl: _posterResolved,
              ),
            ),
          )
        : _mobile != null && _mobile!.value.isInitialized
            ? SizedBox(
                height: widget.height,
                width: double.infinity,
                child: ColoredBox(
                  color: widget.letterbox
                      ? const Color(0xFF0B1120)
                      : Colors.transparent,
                  child: Center(
                    child: FittedBox(
                      fit: fit,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _mobile!.value.size.width,
                        height: _mobile!.value.size.height,
                        child: VideoPlayer(_mobile!),
                      ),
                    ),
                  ),
                ),
              )
            : SizedBox(
                height: widget.height,
                child: _mobileInitFailed
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_off_rounded,
                                  size: 38, color: Colors.grey),
                              const SizedBox(height: 10),
                              Text(
                                'Falha ao carregar vídeo.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () => _initMobile(url),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hintBelow != null && widget.hintBelow!.isNotEmpty) ...[
          Text(
            widget.hintBelow!,
            style: TextStyle(
              fontSize: 13,
              color: ThemeCleanPremium.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
        ],
        _shell(child: ClipRRect(borderRadius: BorderRadius.circular(16), child: videoChild)),
        if (widget.caption.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Site de divulgação: lê `app_public/site` (opcional) + fallback de path no Storage.
class PremiumMarketingHeroVideo extends StatelessWidget {
  final double height;
  final String defaultStoragePath;

  const PremiumMarketingHeroVideo({
    super.key,
    this.height = 280,
    this.defaultStoragePath = 'public/videos/institucional.mp4',
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('app_public')
          .doc('site')
          .snapshots(),
      builder: (context, snap) {
        Map<String, dynamic>? data;
        if (snap.hasData && snap.data!.exists) {
          data = snap.data!.data();
        }
        String? url;
        String? path;
        if (data != null) {
          url = _directVideoUrlFromMap(data);
          path = _storagePathFromMap(data);
        }
        if ((url == null || url.isEmpty) && (path == null || path.isEmpty)) {
          path = defaultStoragePath;
        }
        final posterU = data != null ? _posterUrlFromMap(data) : null;
        final posterP = data != null ? _posterStoragePathFromMap(data) : null;
        return PremiumInstitutionalVideoCard(
          key: ValueKey('marketing_${url ?? ''}_$path'),
          videoUrl: url,
          storagePath: path,
          height: height,
          caption: 'VÍDEO INSTITUCIONAL',
          hintBelow:
              'Assista à demonstração em alta qualidade (até 4K quando o arquivo permitir).',
          heroAutoplay: true,
          posterUrl: posterU,
          posterStoragePath: posterP,
        );
      },
    );
  }
}
