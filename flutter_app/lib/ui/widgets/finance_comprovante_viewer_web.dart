// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

bool _looksLikeImage(String mime, String fileName, String url) {
  if (mime.startsWith('image/')) return true;
  final f = fileName.toLowerCase();
  if (f.endsWith('.png') || f.endsWith('.jpg') || f.endsWith('.jpeg') || f.endsWith('.webp')) {
    return true;
  }
  return url.toLowerCase().contains('.png') ||
      url.toLowerCase().contains('.jpg') ||
      url.toLowerCase().contains('.jpeg');
}

bool _looksLikePdf(String mime, String fileName, String url) {
  if (mime.contains('pdf')) return true;
  return fileName.toLowerCase().endsWith('.pdf') || url.toLowerCase().contains('.pdf');
}

class _ComprovanteIframe extends StatefulWidget {
  const _ComprovanteIframe({required this.src});

  final String src;

  @override
  State<_ComprovanteIframe> createState() => _ComprovanteIframeState();
}

class _ComprovanteIframeState extends State<_ComprovanteIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'gy-comprovante-${widget.src.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
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
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

/// Web: embed URL Firebase directamente — sem http.get (CORS).
Future<void> showFinanceComprovanteWebEmbed({
  required BuildContext context,
  required String url,
  required String fileName,
  required String mimeType,
}) async {
  if (url.trim().isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFF1C1C1E),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.of(ctx).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _looksLikeImage(mimeType, fileName, url)
                      ? InteractiveViewer(
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _ComprovanteIframe(src: url),
                          ),
                        )
                      : _looksLikePdf(mimeType, fileName, url)
                          ? _ComprovanteIframe(src: url)
                          : _ComprovanteIframe(src: url),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
