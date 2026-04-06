import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show ResilientNetworkImage, isValidImageUrl, sanitizeImageUrl;

/// Miniatura estável para o módulo de patrimônio (fotos do bem, notas, etiquetas).
///
/// Com URL **https** no Firestore, usa de imediato (lista rápida); [ResilientNetworkImage] renova
/// token no decode se precisar. Sem https, resolve path/gs via [StorageMediaService] / [AppStorageImageService].
class FotoPatrimonioWidget extends StatefulWidget {
  /// Caminho no bucket (ex.: `igrejas/{id}/patrimonio/...`) alinhado ao índice em [fotoStoragePaths].
  final String? storagePath;
  final List<String> candidateUrls;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget placeholder;
  final Widget errorWidget;

  const FotoPatrimonioWidget({
    super.key,
    this.storagePath,
    required this.candidateUrls,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    required this.placeholder,
    required this.errorWidget,
  });

  @override
  State<FotoPatrimonioWidget> createState() => _FotoPatrimonioWidgetState();
}

class _FotoPatrimonioWidgetState extends State<FotoPatrimonioWidget> {
  static final LinkedHashMap<int, String> _resolvedUrlCache =
      LinkedHashMap<int, String>();
  static const int _kMaxResolvedCache = 200;

  String? _url;
  bool _resolveFinished = false;
  int _resolveGen = 0;

  static int _candidatesHash(List<String> urls, String? storagePath) =>
      Object.hash(Object.hashAll(urls.map((e) => e.hashCode)), storagePath ?? '');

  static void _rememberResolved(int hash, String url) {
    _resolvedUrlCache.remove(hash);
    _resolvedUrlCache[hash] = url;
    while (_resolvedUrlCache.length > _kMaxResolvedCache) {
      _resolvedUrlCache.remove(_resolvedUrlCache.keys.first);
    }
  }

  @override
  void initState() {
    super.initState();
    _startResolve(fromDidUpdate: false);
  }

  @override
  void didUpdateWidget(covariant FotoPatrimonioWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameUrls(oldWidget.candidateUrls, widget.candidateUrls) ||
        oldWidget.storagePath != widget.storagePath) {
      _startResolve(fromDidUpdate: true);
    }
  }

  bool _sameUrls(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Caminho rápido: URL https do Firestore aparece na hora; [ResilientNetworkImage] /
  /// [FreshFirebaseStorageImage] renovam token se precisar (sem bloquear a lista inteira).
  void _startResolve({required bool fromDidUpdate}) {
    _resolveGen++;
    final gen = _resolveGen;
    final h = _candidatesHash(widget.candidateUrls, widget.storagePath);
    final cached = _resolvedUrlCache[h];
    if (cached != null && isValidImageUrl(cached)) {
      _url = sanitizeImageUrl(cached);
      _resolveFinished = true;
      if (fromDidUpdate) setState(() {});
      return;
    }
    for (final raw in widget.candidateUrls) {
      final s = sanitizeImageUrl(raw);
      if (s.isEmpty) continue;
      if (isValidImageUrl(s) &&
          (s.startsWith('https://') || s.startsWith('http://'))) {
        _rememberResolved(h, s);
        _url = s;
        _resolveFinished = true;
        if (fromDidUpdate) setState(() {});
        return;
      }
    }
    _url = null;
    _resolveFinished = false;
    if (fromDidUpdate) setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _resolveBestCandidate(gen));
  }

  Future<void> _resolveBestCandidate(int gen) async {
    if (!mounted || gen != _resolveGen) return;

    String? found;
    final h = _candidatesHash(widget.candidateUrls, widget.storagePath);
    try {
      final path = widget.storagePath?.trim();

      // Só entra aqui sem https válido: path, gs://, caminho relativo — precisa getDownloadURL.
      for (final raw in widget.candidateUrls) {
        if (!mounted || gen != _resolveGen) return;
        final s = sanitizeImageUrl(raw);
        if (s.isEmpty) continue;
        if (isValidImageUrl(s) &&
            (s.startsWith('https://') || s.startsWith('http://'))) {
          continue;
        }
        try {
          final u = await StorageMediaService.downloadUrlFromPathOrUrl(s)
              .timeout(const Duration(seconds: 8), onTimeout: () => null);
          if (!mounted || gen != _resolveGen) return;
          final fu = sanitizeImageUrl(u ?? '');
          if (isValidImageUrl(fu)) {
            _rememberResolved(h, fu);
            found = fu;
            break;
          }
        } catch (_) {}
      }

      // Fallback: só [storagePath] no bucket.
      if (found == null && path != null && path.isNotEmpty) {
        final firstRaw =
            widget.candidateUrls.isEmpty ? '' : widget.candidateUrls.first;
        final first = sanitizeImageUrl(firstRaw);
        final preferUrl =
            first.isNotEmpty && isValidImageUrl(first) ? first : null;
        try {
          final u0 = await AppStorageImageService.instance
              .resolveImageUrl(
                storagePath: path,
                imageUrl: preferUrl,
              )
              .timeout(const Duration(seconds: 22), onTimeout: () => null);
          if (!mounted || gen != _resolveGen) return;
          final fu = sanitizeImageUrl(u0 ?? '');
          if (isValidImageUrl(fu)) {
            _rememberResolved(h, fu);
            found = fu;
          }
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      if (mounted && gen == _resolveGen) {
        setState(() {
          if (found != null) _url = found;
          _resolveFinished = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _url;
    if (u != null && isValidImageUrl(u)) {
      return ResilientNetworkImage(
        imageUrl: u,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        memCacheWidth: widget.memCacheWidth,
        memCacheHeight: widget.memCacheHeight,
        placeholder: widget.placeholder,
        errorWidget: widget.errorWidget,
      );
    }
    final waitingForPath = (widget.storagePath?.trim().isNotEmpty ?? false) ||
        widget.candidateUrls.isNotEmpty;
    if (waitingForPath && !_resolveFinished) {
      return widget.placeholder;
    }
    return widget.errorWidget;
  }
}
