// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

bool _pathLooksLikeImage(String s) {
  final d = s.toLowerCase();
  return d.endsWith('.png') ||
      d.endsWith('.jpg') ||
      d.endsWith('.jpeg') ||
      d.endsWith('.webp') ||
      d.endsWith('.gif');
}

bool _pathLooksLikePdf(String s) {
  return s.toLowerCase().endsWith('.pdf');
}

/// Detecta imagem a partir do URL (path decodificado ou parâmetros `name` / `filename`).
bool isReceiptImageUrl(String url, String? fileName) {
  final f = (fileName ?? '').trim();
  if (_pathLooksLikeImage(f)) return true;
  try {
    final u = Uri.parse(url);
    final path = Uri.decodeComponent(u.path).toLowerCase();
    if (_pathLooksLikeImage(path)) return true;
    if (u.pathSegments.isNotEmpty) {
      final last = Uri.decodeComponent(u.pathSegments.last).toLowerCase();
      if (_pathLooksLikeImage(last)) return true;
    }
    for (final key in ['name', 'filename', 'file']) {
      final v = u.queryParameters[key] ?? '';
      if (_pathLooksLikeImage(Uri.decodeComponent(v).toLowerCase())) return true;
    }
  } catch (_) {}
  return false;
}

/// Detecta PDF a partir do URL ou nome sugerido.
bool isReceiptPdfUrl(String url, String? fileName) {
  final f = (fileName ?? '').trim().toLowerCase();
  if (_pathLooksLikePdf(f)) return true;
  try {
    final decoded = Uri.decodeFull(url).toLowerCase();
    if (decoded.contains('.pdf')) return true;
    final u = Uri.parse(url);
    for (final key in ['name', 'filename', 'file']) {
      final v = (u.queryParameters[key] ?? '').toLowerCase();
      if (v.contains('.pdf')) return true;
    }
  } catch (_) {}
  return false;
}

bool _isFirebaseStorage(String url) {
  final l = url.toLowerCase();
  return l.contains('firebasestorage.googleapis.com') || l.contains('firebasestorage.app');
}

String _googlePdfEmbedSrc(String url) =>
    'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}&embedded=true';

class _RegisteredIframe extends StatefulWidget {
  final String src;

  const _RegisteredIframe({super.key, required this.src});

  @override
  State<_RegisteredIframe> createState() => _RegisteredIframeState();
}

class _RegisteredIframeState extends State<_RegisteredIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'anexo-iframe-${widget.src.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.src
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..setAttribute('title', 'Comprovante');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}

/// Pré-visualização na web na mesma tela: [Image.network] para imagens; PDF / Storage em iframe com viewer embutido.
Widget buildAnexoWebViewer(String url, {String? fileName}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final mq = MediaQuery.sizeOf(context);
      final h = constraints.hasBoundedHeight && constraints.maxHeight.isFinite && constraints.maxHeight > 48
          ? constraints.maxHeight
          : mq.height * 0.78;
      final w = constraints.hasBoundedWidth && constraints.maxWidth.isFinite && constraints.maxWidth > 48
          ? constraints.maxWidth
          : mq.width;
      return SizedBox(
        width: w,
        height: h,
        child: isReceiptImageUrl(url, fileName)
            ? _WebImagePreview(url: url, width: w, height: h)
            : _WebPdfEmbedPreview(url: url, fileName: fileName, width: w, height: h),
      );
    },
  );
}

class _WebImagePreview extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const _WebImagePreview({required this.url, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.35,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              height: height * 0.35,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => _WebPdfEmbedPreview(url: url, fileName: null, width: width, height: height),
        ),
      ),
    );
  }
}

/// PDF (ou URL ambígua do Storage): viewer Google embutido costuma funcionar onde o iframe direto ao Storage falha.
class _WebPdfEmbedPreview extends StatelessWidget {
  final String url;
  final String? fileName;
  final double width;
  final double height;

  const _WebPdfEmbedPreview({
    required this.url,
    this.fileName,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final useGoogle = isReceiptPdfUrl(url, fileName) || _isFirebaseStorage(url);
    final src = useGoogle ? _googlePdfEmbedSrc(url) : url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF2C2C2E),
        child: _RegisteredIframe(key: ValueKey<String>(src), src: src),
      ),
    );
  }
}

/// Legado — mantido se algum import antigo referenciar.
Widget buildAnexoIframe(String url) => buildAnexoWebViewer(url, fileName: null);
