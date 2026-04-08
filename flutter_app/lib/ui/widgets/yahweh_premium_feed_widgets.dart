import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show resolveNoticiaSharePreviewImageUrl;
export 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show resolveNoticiaSharePreviewImageUrl, resolveNoticiaShareSheetMedia;

import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaPhotoUrls,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/firebase_storage_video_playback.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeNetworkImage,
        dedupeImageRefsByStorageIdentity,
        firebaseStorageBytesFromDownloadUrl,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        preloadNetworkImages,
        sanitizeImageUrl;

/// Shimmer estilo “feed” para capas (site público, mural). Respeita o tamanho do pai.
class YahwehPremiumFeedShimmer {
  YahwehPremiumFeedShimmer._();

  static Widget mediaCover() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Shimmer.fromColors(
          baseColor: const Color(0xFFE2E8F0),
          highlightColor: const Color(0xFFF8FAFC),
          period: const Duration(milliseconds: 1100),
          child: Container(
            width: w.isFinite ? w : double.infinity,
            height: h.isFinite ? h : double.infinity,
            color: Colors.white,
          ),
        );
      },
    );
  }

  static Widget logo(double size) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFF1F5F9),
      period: const Duration(milliseconds: 1100),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// Miniatura de vídeo no mural (fundo alinhado ao chip evento/aviso).
  static Widget videoThumbDark({required bool isEvento}) {
    final base = isEvento ? const Color(0xFF1E3A8A) : const Color(0xFF7C3AED);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: base),
        Shimmer.fromColors(
          baseColor: base.withValues(alpha: 0.75),
          highlightColor: Colors.white.withValues(alpha: 0.22),
          period: const Duration(milliseconds: 1100),
          child: const ColoredBox(color: Colors.white10),
        ),
      ],
    );
  }

  static const Color _skBase = Color(0xFFE2E8F0);
  static const Color _skHi = Color(0xFFF8FAFC);

  /// Filtros (ex.: Hoje / Semana / Mês) antes da fileira de aniversariantes.
  static Widget segmentedBarSkeleton({double height = 46}) {
    return Shimmer.fromColors(
      baseColor: _skBase,
      highlightColor: _skHi,
      period: const Duration(milliseconds: 1150),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        ),
      ),
    );
  }

  /// Fileira horizontal estilo **Stories** (dashboard de aniversariantes).
  static Widget birthdayStoriesSkeleton({
    int avatarCount = 8,
    double listHeight = 168,
  }) {
    final ring = listHeight >= 150 ? 34.0 : 28.0;
    final colW = ring * 2 + 20;
    return Shimmer.fromColors(
      baseColor: _skBase,
      highlightColor: _skHi,
      period: const Duration(milliseconds: 1150),
      child: SizedBox(
        height: listHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: avatarCount,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) => SizedBox(
            width: colW,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  width: ring * 2 + 8,
                  height: ring * 2 + 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: listHeight >= 150 ? 8 : 6),
                Container(
                  height: 10,
                  width: colW - 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 8,
                  width: (colW * 0.45).clamp(32.0, 48.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cartões empilhados como posts do mural (avisos/eventos) — carregamento inicial.
  static Widget muralFeedSkeleton({int postCount = 3}) {
    return Shimmer.fromColors(
      baseColor: _skBase,
      highlightColor: _skHi,
      period: const Duration(milliseconds: 1200),
      child: Column(
        children: List.generate(
          postCount,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 120,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 80,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  height: 180,
                  color: Colors.white,
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 180,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 200,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Painel admin: enquanto membros não chegam do Firestore (cache vazio).
  static Widget dashboardOverviewLoading() {
    Widget band(Widget child) => Shimmer.fromColors(
          baseColor: _skBase,
          highlightColor: _skHi,
          period: const Duration(milliseconds: 1150),
          child: child,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          band(
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          band(
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 14),
          birthdayStoriesSkeleton(avatarCount: 7, listHeight: 124),
          const SizedBox(height: 18),
          band(
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Partilha link `…/igreja/…/evento/…` (OG na Cloud Function) +, quando possível, **imagem anexa** (estilo WhatsApp/Instagram).
Future<void> shareChurchNoticiaForOgPreview({
  required String tenantId,
  required String noticiaId,
  required String title,
  String body = '',
  String churchSlug = '',
  Map<String, dynamic>? postFirestore,
}) async {
  final slug = churchSlug.trim();
  final link = slug.isNotEmpty
      ? AppConstants.shareNoticiaIgrejaEventoUrl(slug, noticiaId)
      : AppConstants.shareNoticiaCardUrl(tenantId, noticiaId);
  final snippet = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final short =
      snippet.length > 220 ? '${snippet.substring(0, 217)}…' : snippet;
  final buf = StringBuffer();
  buf.writeln(title);
  if (short.isNotEmpty) {
    buf.writeln();
    buf.writeln(short);
  }
  buf.writeln();
  buf.writeln(link);
  final text = buf.toString().trim();

  // Android/iOS: anexa bytes da capa quando possível. Na web, [Share.shareXFiles]
  // não envia mídia ao WhatsApp como no app — o preview vem do link OG (/igreja/.../evento/...).
  if (postFirestore != null && !kIsWeb) {
    try {
      final imgHttps = await resolveNoticiaSharePreviewImageUrl(postFirestore);
      if (imgHttps != null && isValidImageUrl(imgHttps)) {
        final u = sanitizeImageUrl(imgHttps);
        Uint8List? bytes;
        if (isFirebaseStorageHttpUrl(u)) {
          bytes = await firebaseStorageBytesFromDownloadUrl(u,
              maxBytes: 4 * 1024 * 1024);
        }
        if (bytes == null) {
          final response = await http
              .get(
                Uri.parse(u),
                headers: const {'Accept': 'image/*'},
              )
              .timeout(const Duration(seconds: 22));
          if (response.statusCode == 200 &&
              response.bodyBytes.isNotEmpty) {
            bytes = response.bodyBytes;
          }
        }
        if (bytes != null && bytes.length > 32) {
          final xFile = XFile.fromData(
            bytes,
            name: 'publicacao.jpg',
            mimeType: 'image/jpeg',
          );
          await Share.shareXFiles([xFile], text: text, subject: title);
          return;
        }
      }
    } catch (_) {}
  }

  await Share.share(text, subject: title);
}

/// Lightbox com pinch-to-zoom; usa [SafeNetworkImage] (Firebase / web sem CORS quebrado).
Future<void> showYahwehFullscreenZoomableImage(
  BuildContext context, {
  required String imageUrl,
}) async {
  final u = sanitizeImageUrl(imageUrl);
  if (u.isEmpty || !isValidImageUrl(u)) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.94),
    builder: (ctx) {
      final padding = MediaQuery.paddingOf(ctx);
      final sz = MediaQuery.sizeOf(ctx);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: PhotoView.customChild(
                backgroundDecoration:
                    const BoxDecoration(color: Colors.transparent),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3.2,
                initialScale: PhotoViewComputedScale.contained,
                child: SizedBox(
                  width: sz.width,
                  height: sz.height * 0.88,
                  child: SafeNetworkImage(
                    imageUrl: u,
                    fit: BoxFit.contain,
                    width: sz.width,
                    height: sz.height * 0.88,
                  ),
                ),
              ),
            ),
            Positioned(
              top: padding.top + 4,
              right: 4,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Baixa só o início do ficheiro (ex.: 500 KB) para aquecer cache HTTP antes do play.
Future<void> precacheHostedVideosFromFeed(
  Iterable<String> rawUrls, {
  int maxItems = 2,
  int maxBytes = 500000,
}) async {
  final client = http.Client();
  try {
    var n = 0;
    for (final raw in rawUrls) {
      if (n >= maxItems) break;
      final t = raw.trim();
      if (t.isEmpty) continue;
      try {
        final play = await resolveFirebaseStorageVideoPlayUrl(t);
        if (play.isEmpty) continue;
        final uri = Uri.tryParse(play);
        if (uri == null) continue;
        final req = http.Request('GET', uri)
          ..headers['Range'] = 'bytes=0-${maxBytes - 1}';
        final res = await client.send(req);
        var received = 0;
        await for (final chunk in res.stream) {
          received += chunk.length;
          if (received >= maxBytes) break;
        }
        n++;
      } catch (_) {}
    }
  } finally {
    client.close();
  }
}

/// Pré-carrega imagens e aquece primeiros bytes dos vídeos hospedados (feed tipo Instagram).
/// Os **3 primeiros** posts têm prioridade no pré-fetch de imagens (avisos instantâneos ao abrir).
Future<void> scheduleFeedMediaWarmup(
  BuildContext context,
  List<Map<String, dynamic>> docMaps, {
  int maxDocs = 8,
}) async {
  if (!context.mounted) return;
  final imageUrls = <String>[];
  final leadImageUrls = <String>[];
  final videoUrls = <String>[];
  var docIndex = 0;
  for (final m in docMaps.take(maxDocs)) {
    void addPhotosTo(List<String> bucket) {
      for (final p in eventNoticiaPhotoUrls(m)) {
        final s = sanitizeImageUrl(p);
        if (isValidImageUrl(s) && !looksLikeHostedVideoFileUrl(s)) {
          bucket.add(s);
        }
      }
      final poster = eventNoticiaDisplayVideoThumbnailUrl(m);
      if (poster != null && poster.isNotEmpty) {
        final s = sanitizeImageUrl(poster);
        if (isValidImageUrl(s) && !looksLikeHostedVideoFileUrl(s)) {
          bucket.add(s);
        }
      }
    }

    if (docIndex < 3) {
      addPhotosTo(leadImageUrls);
    }
    addPhotosTo(imageUrls);

    final hv = eventNoticiaHostedVideoPlayUrl(m);
    if (hv != null && hv.isNotEmpty) {
      final s = sanitizeImageUrl(hv);
      if (looksLikeHostedVideoFileUrl(s)) {
        videoUrls.add(s);
      }
    }
    docIndex++;
  }
  await preloadNetworkImages(
    context,
    dedupeImageRefsByStorageIdentity(leadImageUrls),
    maxItems: 12,
  );
  if (!context.mounted) return;
  await preloadNetworkImages(
    context,
    dedupeImageRefsByStorageIdentity(imageUrls),
    maxItems: 24,
  );
  await precacheHostedVideosFromFeed(videoUrls, maxItems: 8);
  if (kIsWeb) {
    for (final v in videoUrls.take(8)) {
      try {
        await StorageMediaService.freshPlayableMediaUrl(v);
      } catch (_) {}
    }
  }
}

/// Leve escala no hover (web); mobile mantém 1.0.
class YahwehInstagramHoverCard extends StatefulWidget {
  final Widget child;

  const YahwehInstagramHoverCard({super.key, required this.child});

  @override
  State<YahwehInstagramHoverCard> createState() =>
      _YahwehInstagramHoverCardState();
}

class _YahwehInstagramHoverCardState extends State<YahwehInstagramHoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scale = (kIsWeb && _hover) ? 1.014 : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// FABs: mapa, pedido de oração (WhatsApp), acesso ao sistema.
class YahwehPublicFloatingActions extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback? onPrayer;
  final VoidCallback? onMaps;
  /// Cor da igreja no site público (ex.: #2563EB); fallback [ThemeCleanPremium.primary].
  final Color? brandBlue;

  const YahwehPublicFloatingActions({
    super.key,
    required this.onLogin,
    this.onPrayer,
    this.onMaps,
    this.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    final blue = brandBlue ?? ThemeCleanPremium.primary;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onMaps != null) ...[
            FloatingActionButton.small(
              heroTag: 'gyh_pub_maps',
              tooltip: 'Localização',
              backgroundColor: Colors.white,
              foregroundColor: blue,
              elevation: 3,
              onPressed: onMaps,
              child: const Icon(Icons.map_rounded),
            ),
            const SizedBox(height: 10),
          ],
          if (onPrayer != null) ...[
            FloatingActionButton.small(
              heroTag: 'gyh_pub_oracao',
              tooltip: 'Pedido de oração',
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 3,
              onPressed: onPrayer,
              child: const Icon(Icons.chat_rounded),
            ),
            const SizedBox(height: 10),
          ],
          FloatingActionButton.extended(
            heroTag: 'gyh_pub_login',
            onPressed: onLogin,
            icon: const Icon(Icons.login_rounded, size: 22),
            label: const Text('Acessar sistema'),
            backgroundColor: blue,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
