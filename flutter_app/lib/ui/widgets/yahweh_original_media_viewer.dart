import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageBytesFromDownloadUrl,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/services/storage_media_service.dart';

/// Viewer canónico — foto/arquivo em **tamanho original** com pinch (padrão CT).
///
/// Imagem → lightbox PhotoView com bytes completos (sem memCacheWidth).
/// PDF/outro → abrir URL (viewer nativo / browser).
Future<void> showYahwehOriginalMedia(
  BuildContext context, {
  required String urlOrPath,
  String? fileName,
  String? mimeHint,
}) async {
  final raw = urlOrPath.trim();
  if (raw.isEmpty) return;

  String resolved = raw;
  try {
    if (StorageMediaService.isFirebaseStorageMediaUrl(raw) ||
        raw.contains('firebasestorage') ||
        raw.startsWith('gs://') ||
        raw.startsWith('igrejas/')) {
      resolved = await StorageMediaService.freshPlayableMediaUrl(raw);
    } else {
      final alt = await StorageMediaService.downloadUrlFromPathOrUrl(raw);
      if (alt != null && alt.isNotEmpty) resolved = alt;
    }
  } catch (_) {}

  if (!context.mounted) return;

  final name = (fileName ?? '').toLowerCase();
  final mime = (mimeHint ?? '').toLowerCase();
  final looksImage = _looksLikeImage(resolved, name, mime);

  if (looksImage) {
    await showYahwehOriginalImageZoom(context, imageUrl: resolved);
    return;
  }

  final uri = Uri.tryParse(resolved);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Link do ficheiro inválido.'),
    );
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Não foi possível abrir o ficheiro.'),
    );
  }
}

/// Ampliar imagem em resolução original (pinch até 5×).
Future<void> showYahwehOriginalImageZoom(
  BuildContext context, {
  required String imageUrl,
}) async {
  final u = sanitizeImageUrl(imageUrl);
  if (u.isEmpty || !isValidImageUrl(u)) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.94),
    builder: (ctx) => _OriginalImageDialog(imageUrl: u),
  );
}

/// Ampliar imagem a partir de bytes locais (ex.: bolha recém-enviada no chat)
/// — instantâneo, sem rede.
Future<void> showYahwehOriginalImageZoomBytes(
  BuildContext context, {
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.94),
    builder: (ctx) => _OriginalImageDialog(imageUrl: '', initialBytes: bytes),
  );
}

bool _looksLikeImage(String url, String fileName, String mime) {
  if (mime.startsWith('image/')) return true;
  final path = url.split('?').first.toLowerCase();
  const exts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.bmp'];
  for (final e in exts) {
    if (path.endsWith(e) || fileName.endsWith(e)) return true;
  }
  // Sem extensão: URLs Storage de fotos do feed/chat costumam ser imagem.
  if (isFirebaseStorageHttpUrl(url) &&
      !path.endsWith('.pdf') &&
      !path.endsWith('.mp4') &&
      !path.endsWith('.mov') &&
      !mime.contains('pdf') &&
      !mime.contains('video')) {
    return true;
  }
  return false;
}

class _OriginalImageDialog extends StatefulWidget {
  const _OriginalImageDialog({required this.imageUrl, this.initialBytes});

  final String imageUrl;
  final Uint8List? initialBytes;

  @override
  State<_OriginalImageDialog> createState() => _OriginalImageDialogState();
}

class _OriginalImageDialogState extends State<_OriginalImageDialog> {
  Uint8List? _bytes;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBytes;
    if (initial != null && initial.isNotEmpty) {
      _bytes = initial;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      Uint8List? data;
      if (isFirebaseStorageHttpUrl(widget.imageUrl) ||
          widget.imageUrl.startsWith('gs://') ||
          widget.imageUrl.contains('firebasestorage')) {
        // Até 12 MB — original para pinch sem pixelar.
        data = await firebaseStorageBytesFromDownloadUrl(
          widget.imageUrl,
          maxBytes: 12 * 1024 * 1024,
        );
      }
      if (data == null || data.isEmpty) {
        final res = await http
            .get(Uri.parse(widget.imageUrl))
            .timeout(const Duration(seconds: 45));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          data = res.bodyBytes;
        }
      }
      if (!mounted) return;
      if (data == null || data.isEmpty) {
        setState(() {
          _error = 'Imagem indisponível';
          _loading = false;
        });
        return;
      }
      setState(() {
        _bytes = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Não foi possível carregar a imagem.\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : PhotoView(
                        imageProvider: MemoryImage(_bytes!),
                        backgroundDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 5,
                        initialScale: PhotoViewComputedScale.contained,
                        filterQuality: FilterQuality.high,
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
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ),
          Positioned(
            top: padding.top + 4,
            left: 12,
            child: const IgnorePointer(
              child: Text(
                'Ampliar · tamanho original',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
