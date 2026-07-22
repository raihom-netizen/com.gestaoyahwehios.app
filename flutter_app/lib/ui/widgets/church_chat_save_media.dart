import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gestao_yahweh/services/church_chat_media_resolver.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_original_media_viewer.dart'
    show showYahwehOriginalImageZoom;

/// Ampliar imagem do chat (pinch) — tamanho original.
Future<void> churchChatOpenImageZoom(BuildContext context, String rawUrl) {
  return showYahwehOriginalImageZoom(context, imageUrl: rawUrl);
}

/// Pré-visualização moderna de mídia já recebida (imagem ou vídeo).
Future<void> churchChatOpenReceivedMediaPreview(
  BuildContext context, {
  required String type,
  required Map<String, dynamic> data,
  String? tenantId,
  String? messageId,
}) async {
  final sp = ChurchChatMessageFields.storagePath(data);
  final legacy = ChurchChatMessageFields.mediaUrl(data);
  var resolved = await ChurchChatMediaResolver.resolveDownloadUrl(
        storagePath: sp.isNotEmpty ? sp : legacy,
        tenantId: tenantId,
        messageId: messageId,
      ) ??
      legacy;
  if (resolved.trim().isEmpty && type == 'image') {
    // Fallback: miniatura resolvível — melhor mostrar a foto do que falhar.
    final thumbSp = ChurchChatMessageFields.thumbStoragePath(data);
    if (thumbSp.isNotEmpty) {
      resolved = await ChurchChatMediaResolver.resolveDownloadUrl(
            storagePath: thumbSp,
            tenantId: tenantId,
            messageId: messageId,
          ) ??
          '';
    }
    if (resolved.trim().isEmpty) {
      resolved = ChurchChatMessageFields.thumbnailUrl(data);
    }
  }
  if (resolved.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Ficheiro ainda não disponível. Tente novamente em instantes.',
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (type == 'video') {
    await showChurchHostedVideoTheater(
      context,
      videoUrl: resolved,
      thumbnailUrl: ChurchChatMessageFields.thumbnailUrl(data),
      title: ChurchChatMessageFields.fileName(data).isNotEmpty
          ? ChurchChatMessageFields.fileName(data)
          : 'Vídeo',
      autoPlay: true,
    );
    return;
  }
  await churchChatOpenImageZoom(context, resolved);
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
