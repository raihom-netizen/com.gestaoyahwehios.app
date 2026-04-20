import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventNoticiaPhotoStoragePathAt;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show defaultImageErrorWidget, sanitizeImageUrl;

/// Galeria em tela cheia (painel, site público, partilha) — URLs e paths Storage.
class NoticiaPhotoGalleryPage extends StatefulWidget {
  final List<String> imageRefs;
  final Map<String, dynamic>? firestoreData;
  final String title;
  final bool isEvento;
  final int initialIndex;

  const NoticiaPhotoGalleryPage({
    super.key,
    required this.imageRefs,
    this.firestoreData,
    required this.title,
    required this.isEvento,
    this.initialIndex = 0,
  });

  @override
  State<NoticiaPhotoGalleryPage> createState() => _NoticiaPhotoGalleryPageState();
}

class _NoticiaPhotoGalleryPageState extends State<NoticiaPhotoGalleryPage> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    final n = widget.imageRefs.length;
    if (n == 0) {
      _current = 0;
      _pageCtrl = PageController();
    } else {
      final i = widget.initialIndex.clamp(0, n - 1);
      _current = i;
      _pageCtrl = PageController(initialPage: i);
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  static String _sanitizeUrl(String u) {
    final t = u.trim();
    if (t.isEmpty) return t;
    try {
      final uri = Uri.parse(t);
      if (uri.scheme == 'http' || uri.scheme == 'https') return uri.toString();
    } catch (_) {}
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageRefs
        .map(_sanitizeUrl)
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_rounded,
                  size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text('Sem foto disponível',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          urls.length > 1
              ? '${_current + 1} / ${urls.length}'
              : (widget.title.isEmpty
                  ? (widget.isEvento ? 'Evento' : 'Aviso')
                  : widget.title),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: urls.length,
        onPageChanged: (p) => setState(() => _current = p),
        itemBuilder: (_, i) {
          final ref = urls[i];
          final path = widget.firestoreData != null
              ? eventNoticiaPhotoStoragePathAt(widget.firestoreData!, i)
              : null;
          final low = ref.toLowerCase();
          final isGs = low.startsWith('gs://');
          return LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth.isFinite && c.maxWidth > 0
                  ? c.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final h = c.maxHeight.isFinite && c.maxHeight > 0
                  ? c.maxHeight
                  : MediaQuery.sizeOf(context).height * 0.85;
              final dpr = MediaQuery.devicePixelRatioOf(context);
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: StableStorageImage(
                    key: ValueKey('fs_$i$ref'),
                    storagePath: path,
                    imageUrl: isGs ? null : sanitizeImageUrl(ref),
                    gsUrl: isGs ? ref : null,
                    fit: BoxFit.contain,
                    width: w,
                    height: h,
                    memCacheWidth: (w * dpr).round().clamp(64, 4096),
                    memCacheHeight: (h * dpr).round().clamp(64, 4096),
                    placeholder: const Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                    errorWidget: defaultImageErrorWidget(
                        message: 'Falha ao carregar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
