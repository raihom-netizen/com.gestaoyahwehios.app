// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageMediaUrlLooksLike, freshFirebaseStorageDisplayUrl, sanitizeImageUrl;

/// Site divulgação (web): `<picture>` + WebP opcional, ou `<img loading="lazy">`, com URL Storage renovada.
Widget marketingClienteShowcaseImage({
  required String imageUrl,
  String? webpUrl,
  required double width,
  required double height,
  required BoxFit fit,
  required Widget placeholder,
  required Widget errorWidget,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  return _MarketingClienteShowcaseWebImg(
    imageUrl: imageUrl,
    webpUrl: webpUrl,
    width: width,
    height: height,
    fit: fit,
    placeholder: placeholder,
    errorWidget: errorWidget,
  );
}

class _MarketingClienteShowcaseWebImg extends StatefulWidget {
  const _MarketingClienteShowcaseWebImg({
    required this.imageUrl,
    this.webpUrl,
    required this.width,
    required this.height,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
  });

  final String imageUrl;
  final String? webpUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget errorWidget;

  @override
  State<_MarketingClienteShowcaseWebImg> createState() =>
      _MarketingClienteShowcaseWebImgState();
}

class _MarketingClienteShowcaseWebImgState extends State<_MarketingClienteShowcaseWebImg> {
  late final String _viewType;
  late final html.Element _host;
  late final html.ImageElement _img;
  html.Element? _source;
  StreamSubscription<html.Event>? _errSub;
  StreamSubscription<html.Event>? _loadSub;
  bool _resolving = true;
  bool _failed = false;

  static String _objectFit(BoxFit f) {
    switch (f) {
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitWidth:
      case BoxFit.fitHeight:
        return 'scale-down';
      default:
        return 'contain';
    }
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'yahweh-mkt-lazy-img-${DateTime.now().microsecondsSinceEpoch}';
    _img = html.ImageElement()
      ..setAttribute('loading', 'lazy')
      ..setAttribute('decoding', 'async')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = _objectFit(widget.fit);

    final wRaw = widget.webpUrl?.trim() ?? '';
    if (wRaw.isNotEmpty) {
      _source = html.Element.tag('source')..setAttribute('type', 'image/webp');
      final picture = html.Element.tag('picture');
      picture.append(_source!);
      picture.append(_img);
      _host = picture;
    } else {
      _host = _img;
    }

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _host);
    _errSub = _img.onError.listen((_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _resolving = false;
        });
      }
    });
    unawaited(_applySrc());
  }

  Future<String> _freshIfStorage(String u) async {
    if (!firebaseStorageMediaUrlLooksLike(u)) return u;
    try {
      return await freshFirebaseStorageDisplayUrl(u);
    } catch (_) {
      return u;
    }
  }

  Future<void> _applySrc() async {
    if (kIsWeb) {
      try {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      } catch (_) {}
    }
    var use = sanitizeImageUrl(widget.imageUrl);
    if (use.isEmpty) {
      if (mounted) {
        setState(() {
          _failed = true;
          _resolving = false;
        });
      }
      return;
    }
    use = await _freshIfStorage(use);

    final wRaw = widget.webpUrl?.trim() ?? '';
    if (_source != null && wRaw.isNotEmpty) {
      var wu = sanitizeImageUrl(wRaw);
      if (wu.isNotEmpty) {
        wu = await _freshIfStorage(wu);
        _source!.setAttribute('srcset', wu);
      }
    }

    if (!mounted) return;
    _loadSub?.cancel();
    _loadSub = _img.onLoad.listen((_) {
      if (mounted) setState(() => _resolving = false);
      _loadSub?.cancel();
      _loadSub = null;
    });
    _img.src = use;
    if (mounted && (_img.complete == true) && _img.naturalWidth > 0) {
      setState(() => _resolving = false);
      _loadSub?.cancel();
      _loadSub = null;
    }
  }

  @override
  void didUpdateWidget(covariant _MarketingClienteShowcaseWebImg oldWidget) {
    super.didUpdateWidget(oldWidget);
    final urlChanged =
        sanitizeImageUrl(oldWidget.imageUrl) != sanitizeImageUrl(widget.imageUrl);
    final webpChanged = (oldWidget.webpUrl ?? '') != (widget.webpUrl ?? '');
    if (urlChanged || webpChanged) {
      setState(() {
        _failed = false;
        _resolving = true;
      });
      _img.style.objectFit = _objectFit(widget.fit);
      unawaited(_applySrc());
    } else if (oldWidget.fit != widget.fit) {
      _img.style.objectFit = _objectFit(widget.fit);
    }
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _loadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.errorWidget;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          HtmlElementView(viewType: _viewType),
          if (_resolving) widget.placeholder,
        ],
      ),
    );
  }
}
