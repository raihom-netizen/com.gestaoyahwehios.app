import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show showYahwehFullscreenZoomableImage;

/// Ampliar imagem do chat (pinch) — reutiliza o lightbox do feed.
Future<void> churchChatOpenImageZoom(BuildContext context, String rawUrl) {
  return showYahwehFullscreenZoomableImage(context, imageUrl: rawUrl);
}

/// Guardar imagem na galeria (Android/iOS). Web: mensagem.
Future<void> churchChatSaveImageUrl(BuildContext context, String rawUrl) async {
  if (kIsWeb) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Na web, use ampliar e depois captura de ecrã ou partilhe a partir do browser.',
      ),
    );
    return;
  }
  // Gravação na galeria via MediaStore (gal) — sem READ_MEDIA_* no manifest.
  final resolved = await _resolveMediaUrl(rawUrl);
  if (!context.mounted) return;
  if (resolved.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('URL da imagem inválida.'),
    );
    return;
  }

  try {
    final res = await http.get(Uri.parse(resolved)).timeout(const Duration(seconds: 45));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    final ext = ct.contains('png')
        ? 'png'
        : ct.contains('webp')
            ? 'webp'
            : 'jpg';
    final dir = await getTemporaryDirectory();
    final tmpPath = '${dir.path}/chat_foto_$stamp.$ext';
    final tmp = File(tmpPath);
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    try {
      await Gal.putImage(
        tmp.path,
        album: 'Gestão YAHWEH',
      );
    } catch (_) {
      // Fallback para bytes (alguns aparelhos falham no path e aceitam bytes).
      await Gal.putImageBytes(
        res.bodyBytes,
        album: 'Gestão YAHWEH',
        name: 'chat_foto_$stamp',
      );
    }
    try {
      await tmp.delete();
    } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Imagem guardada na galeria.'),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Não foi possível guardar: $e'),
    );
  }
}

/// Vídeo: descarrega para ficheiro temporário e abre a folha de partilha (rápido; permite «Guardar vídeo»).
Future<void> churchChatShareDownloadVideo(
  BuildContext context,
  String rawUrl, {
  String? fileName,
}) async {
  final resolved = await _resolveMediaUrl(rawUrl);
  if (!context.mounted) return;
  if (resolved.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('URL do vídeo inválida.'),
    );
    return;
  }

  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Na web, abra o vídeo em ecrã inteiro e use o menu do browser para descarregar.',
      ),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('A preparar vídeo…'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: ThemeCleanPremium.primary,
    ),
  );

  try {
    final res = await http.get(Uri.parse(resolved)).timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final safe =
        (fileName ?? 'chat_video').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        '${dir.path}/yahweh_chat_${DateTime.now().millisecondsSinceEpoch}_$safe.mp4';
    final f = File(path);
    await f.writeAsBytes(res.bodyBytes, flush: true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Share.shareXFiles(
      [XFile(path, mimeType: 'video/mp4')],
      text: 'Vídeo do chat',
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Não foi possível descarregar: $e'),
    );
  }
}

Future<String> _resolveMediaUrl(String raw) async {
  var t = raw.trim();
  if (t.isEmpty) return '';
  try {
    if (StorageMediaService.isFirebaseStorageMediaUrl(t) ||
        t.contains('firebasestorage')) {
      return await StorageMediaService.freshPlayableMediaUrl(t);
    }
    final alt = await StorageMediaService.downloadUrlFromPathOrUrl(t);
    return alt ?? t;
  } catch (_) {
    return sanitizeImageUrl(t);
  }
}
