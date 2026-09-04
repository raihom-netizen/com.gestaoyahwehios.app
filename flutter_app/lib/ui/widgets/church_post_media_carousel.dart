import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart'
    show ChurchHostedVideoSurface;
import 'package:gestao_yahweh/ui/widgets/church_youtube/church_youtube_player_shell.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/youtube_url_helper.dart';

/// Tipo de mídia numa publicação (aviso / evento).
enum ChurchPostMediaKind { image, video, youtube }

/// Um item do carrossel — foto, vídeo hospedado ou vídeo do YouTube.
class ChurchPostMediaItem {
  const ChurchPostMediaItem._({
    required this.kind,
    required this.url,
    required this.thumbUrl,
    required this.youtubeId,
  });

  factory ChurchPostMediaItem.image(String url) => ChurchPostMediaItem._(
    kind: ChurchPostMediaKind.image,
    url: url.trim(),
    thumbUrl: '',
    youtubeId: '',
  );

  factory ChurchPostMediaItem.video({
    required String url,
    String thumbUrl = '',
  }) => ChurchPostMediaItem._(
    kind: ChurchPostMediaKind.video,
    url: url.trim(),
    thumbUrl: thumbUrl.trim(),
    youtubeId: '',
  );

  factory ChurchPostMediaItem.youtube({
    required String youtubeId,
    String thumbUrl = '',
  }) => ChurchPostMediaItem._(
    kind: ChurchPostMediaKind.youtube,
    url: 'https://www.youtube.com/watch?v=$youtubeId',
    thumbUrl: thumbUrl.trim().isNotEmpty
        ? thumbUrl.trim()
        : 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
    youtubeId: youtubeId.trim(),
  );

  final ChurchPostMediaKind kind;
  final String url;
  final String thumbUrl;
  final String youtubeId;

  bool get isImage => kind == ChurchPostMediaKind.image;
  bool get isVideo => !isImage;
}

/// Monta a lista do carrossel a partir dos campos já existentes do post.
///
/// O vídeo entra **em primeiro** (é o que prende o olhar) e as fotos a seguir,
/// tudo num único carrossel — antes o vídeo aparecia num bloco separado por
/// cima da galeria e o utilizador não percebia que havia mais mídia por baixo.
List<ChurchPostMediaItem> buildChurchPostMedia({
  required List<String> imageUrls,
  String hostedVideoUrl = '',
  String videoThumbUrl = '',
  String youtubeVideoId = '',
}) {
  final out = <ChurchPostMediaItem>[];
  final seen = <String>{};

  final yt = youtubeVideoId.trim();
  final hosted = hostedVideoUrl.trim();
  final hostedAsYoutube = hosted.isEmpty
      ? null
      : YoutubeUrlHelper.extractVideoId(hosted);

  if (yt.isNotEmpty) {
    out.add(
      ChurchPostMediaItem.youtube(youtubeId: yt, thumbUrl: videoThumbUrl),
    );
  } else if (hostedAsYoutube != null && hostedAsYoutube.isNotEmpty) {
    out.add(
      ChurchPostMediaItem.youtube(
        youtubeId: hostedAsYoutube,
        thumbUrl: videoThumbUrl,
      ),
    );
  } else if (hosted.isNotEmpty) {
    out.add(ChurchPostMediaItem.video(url: hosted, thumbUrl: videoThumbUrl));
  }

  final thumb = videoThumbUrl.trim();
  for (final raw in imageUrls) {
    final u = raw.trim();
    if (u.isEmpty) continue;
    // A miniatura do vídeo não é uma segunda foto do post.
    if (thumb.isNotEmpty && u == thumb) continue;
    if (!seen.add(u)) continue;
    out.add(ChurchPostMediaItem.image(u));
  }
  return out;
}

/// `5 fotos · 1 vídeo` — o texto do aviso de arrasto.
String churchPostMediaCountLabel(List<ChurchPostMediaItem> items) {
  final fotos = items.where((e) => e.isImage).length;
  final videos = items.length - fotos;
  final parts = <String>[
    if (fotos == 1) '1 foto' else if (fotos > 1) '$fotos fotos',
    if (videos == 1) '1 vídeo' else if (videos > 1) '$videos vídeos',
  ];
  return parts.join(' · ');
}

/// Carrossel de mídia do post — fotos **e** vídeos juntos, estilo Instagram.
///
/// Na lista os vídeos mostram só a capa com o botão de play: iniciar o
/// descodificador dentro de um `ListView` era o que fazia o painel travar.
/// A reprodução acontece no visualizador em tela cheia.
class ChurchPostMediaCarousel extends StatefulWidget {
  const ChurchPostMediaCarousel({
    super.key,
    required this.items,
    this.accent = const Color(0xFFE1306C),
    this.borderRadius = 18,
    this.aspectRatio = 4 / 5,
    this.maxHeight,
    this.title = '',
  });

  final List<ChurchPostMediaItem> items;
  final Color accent;
  final double borderRadius;
  final double aspectRatio;
  final double? maxHeight;
  final String title;

  @override
  State<ChurchPostMediaCarousel> createState() =>
      _ChurchPostMediaCarouselState();
}

class _ChurchPostMediaCarouselState extends State<ChurchPostMediaCarousel> {
  final _pageCtrl = PageController();
  int _index = 0;
  bool _hintDismissed = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    // O aviso some sozinho ao fim de 6s — já cumpriu o papel de dizer
    // «há mais coisa aqui, arraste».
    _hintTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _hintDismissed = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _open(int index) {
    unawaited(
      showChurchPostMediaViewer(
        context,
        items: widget.items,
        initialIndex: index,
        accent: widget.accent,
        title: widget.title,
      ),
    );
  }

  /// Altura do bloco de indicadores (espaco + bolinhas) — entra na conta da
  /// altura total para o carrossel NUNCA passar da caixa do pai.
  static const double _dotsBlockHeight = 17;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final multiple = items.length > 1;
    final dotsH = multiple ? _dotsBlockHeight : 0.0;

    // ⚠️ NAO usar `Column(AspectRatio)` solto: numa Column os filhos recebem
    // altura infinita no eixo principal, por isso a foto ficava maior do que a
    // caixa e o excedente era PINTADO POR CIMA da legenda e dos botoes (o
    // texto do evento aparecia sobre a foto). Aqui a altura da midia e
    // calculada e limitada — nunca transborda.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 360.0;
        final ar = widget.aspectRatio > 0 ? widget.aspectRatio : 4 / 5;
        var mediaH = w / ar;
        final caps = <double>[
          if (widget.maxHeight != null && widget.maxHeight!.isFinite)
            widget.maxHeight! - dotsH,
          if (constraints.maxHeight.isFinite && constraints.maxHeight > 0)
            constraints.maxHeight - dotsH,
        ];
        for (final cap in caps) {
          mediaH = math.min(mediaH, math.max(120.0, cap));
        }
        return _gallery(items, multiple, w, mediaH);
      },
    );
  }

  Widget _gallery(
    List<ChurchPostMediaItem> items,
    bool multiple,
    double width,
    double mediaHeight,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: width,
            height: mediaHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageCtrl,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _hintDismissed = true;
                  }),
                  itemBuilder: (_, i) => items[i].isImage
                      ? GestureDetector(
                          onTap: () => _open(i),
                          child: _MediaPagePreview(item: items[i]),
                        )
                      : _MediaPagePreview(
                          item: items[i],
                          onOpenViewer: () => _open(i),
                        ),
                ),
                if (multiple)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _Pill(
                      child: Text(
                        '${_index + 1}/${items.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (multiple && !_hintDismissed)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _SwipeHint(
                      label: churchPostMediaCountLabel(items),
                    ),
                  )
                else
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _Pill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            items[_index].isVideo
                                ? Icons.play_arrow_rounded
                                : Icons.zoom_out_map_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            items[_index].isVideo ? 'Assistir' : 'Ampliar',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (multiple) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 7,
            child: _Dots(
              count: items.length,
              index: _index,
              accent: widget.accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// Página do carrossel na lista: foto, ou capa de vídeo com botão de play.
class _MediaPagePreview extends StatelessWidget {
  const _MediaPagePreview({required this.item, this.onOpenViewer});

  final ChurchPostMediaItem item;

  /// Toque no slide de video: abre o visualizador em tela cheia.
  final VoidCallback? onOpenViewer;

  @override
  Widget build(BuildContext context) {
    if (item.isImage) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: SafeNetworkImage(imageUrl: item.url, fit: BoxFit.cover),
      );
    }
    // YouTube na lista = capa + botao de play. Montar o player do YouTube em
    // cada card do feed era o que deixava o mural pesado (e na web nem
    // chegava a tocar): a reproducao acontece no visualizador em tela cheia.
    if (item.kind == ChurchPostMediaKind.youtube) {
      return GestureDetector(
        onTap: onOpenViewer,
        child: ColoredBox(
          color: const Color(0xFF0F172A),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.thumbUrl.isNotEmpty)
                SafeNetworkImage(imageUrl: item.thumbUrl, fit: BoxFit.cover),
              const ColoredBox(color: Color(0x55000000)),
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: ChurchHostedVideoSurface(
        videoUrl: item.url,
        thumbnailUrl: item.thumbUrl.isEmpty ? null : item.thumbUrl,
        autoPlay: false,
        layoutAspectRatio: 4 / 5,
        showFullscreenOverlay: true,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );
}

/// `5 fotos · 1 vídeo   arraste ⇢` com a setinha a pulsar.
class _SwipeHint extends StatefulWidget {
  const _SwipeHint({required this.label});

  final String label;

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
      ),
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'arraste',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 2),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Transform.translate(
            offset: Offset(4 * _ctrl.value, 0),
            child: child,
          ),
          child: const Icon(
            Icons.keyboard_double_arrow_right_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      ],
    ),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.accent});

  final int count;
  final int index;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(
      count,
      (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: i == index ? 18 : 7,
        height: 7,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: i == index ? accent : Colors.grey.shade300,
        ),
      ),
    ),
  );
}

/// Visualizador em tela cheia — preto, arrastável, com botão de voltar.
///
/// Fotos com zoom, vídeos a tocar, tudo na mesma sequência do carrossel.
Future<void> showChurchPostMediaViewer(
  BuildContext context, {
  required List<ChurchPostMediaItem> items,
  int initialIndex = 0,
  Color accent = const Color(0xFFE1306C),
  String title = '',
}) {
  if (items.isEmpty) return Future<void>.value();
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, _) => FadeTransition(
        opacity: animation,
        child: _ChurchPostMediaViewerPage(
          items: items,
          initialIndex: initialIndex.clamp(0, items.length - 1),
          accent: accent,
          title: title,
        ),
      ),
    ),
  );
}

class _ChurchPostMediaViewerPage extends StatefulWidget {
  const _ChurchPostMediaViewerPage({
    required this.items,
    required this.initialIndex,
    required this.accent,
    required this.title,
  });

  final List<ChurchPostMediaItem> items;
  final int initialIndex;
  final Color accent;
  final String title;

  @override
  State<_ChurchPostMediaViewerPage> createState() =>
      _ChurchPostMediaViewerPageState();
}

class _ChurchPostMediaViewerPageState
    extends State<_ChurchPostMediaViewerPage> {
  late final PageController _pageCtrl = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _ViewerPage(
              item: items[i],
              active: i == _index,
              title: widget.title,
            ),
          ),
          // Topo: voltar + contador. Gradiente para o texto ler sobre foto clara.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 6,
                bottom: 14,
                left: 6,
                right: 14,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                    iconSize: 26,
                    tooltip: 'Voltar',
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (items.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFF58529),
                            Color(0xFFDD2A7B),
                            Color(0xFF8134AF),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_index + 1} / ${items.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 18,
              child: _Dots(
                count: items.length,
                index: _index,
                accent: widget.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewerPage extends StatelessWidget {
  const _ViewerPage({
    required this.item,
    required this.active,
    required this.title,
  });

  final ChurchPostMediaItem item;
  final bool active;
  final String title;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case ChurchPostMediaKind.image:
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: SafeNetworkImage(imageUrl: item.url, fit: BoxFit.contain),
          ),
        );
      case ChurchPostMediaKind.youtube:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ChurchYoutubePlayerShell(
              youtubeVideoId: item.youtubeId,
              posterUrl: item.thumbUrl,
              // Só a página visível toca — evita dois players em memória.
              autoplay: active,
              borderRadius: 16,
            ),
          ),
        );
      case ChurchPostMediaKind.video:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ChurchHostedVideoSurface(
              videoUrl: item.url,
              thumbnailUrl: item.thumbUrl.isEmpty ? null : item.thumbUrl,
              autoPlay: active,
              showFullscreenOverlay: false,
            ),
          ),
        );
    }
  }
}
