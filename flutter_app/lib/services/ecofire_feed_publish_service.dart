import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        isValidImageUrl,
        sanitizeImageUrl;

/// Resultado de um slot — URL + path directo em `igrejas/{id}/eventos|avisos/{postId}/`.
class EcoFireFeedPhotoSlot {
  const EcoFireFeedPhotoSlot({
    required this.fullUrl,
    required this.thumbUrl,
    required this.fullPath,
    required this.thumbPath,
  });

  final String fullUrl;
  final String thumbUrl;
  final String fullPath;
  final String thumbPath;
}

/// Publicação de fotos aviso/evento — upload **directo** no Storage (pasta do post).
///
/// Ex.: `igrejas/{churchId}/eventos/{postId}/banner_evento.jpg`
abstract final class EcoFireFeedPublishService {
  EcoFireFeedPublishService._();

  static const Duration uploadTimeout = Duration(seconds: 45);

  static bool _isEventoPostType(String postType) {
    final t = postType.trim().toLowerCase();
    return t == 'evento' || t == 'noticia' || t == 'noticias';
  }

  static String _mainStoragePath({
    required String churchId,
    required String postType,
    required String postId,
    required int slotIndex,
  }) {
    if (_isEventoPostType(postType)) {
      return ChurchStorageLayout.eventPostPhotoPath(churchId, postId, slotIndex);
    }
    return ChurchStorageLayout.avisoPostPhotoPath(churchId, postId, slotIndex);
  }

  /// Um slot — comprime, envia **um** ficheiro, devolve URL HTTPS.
  static Future<EcoFireFeedPhotoSlot> uploadPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    await ensureFirebaseCore(requireAuth: true);
    EcoFireFlow.log('FEED_PHOTO slot $postType/$postId#$slotIndex');

    Uint8List raw;
    if (bytes != null && bytes.isNotEmpty) {
      raw = bytes;
    } else if (!kIsWeb && localPath != null && localPath.trim().isNotEmpty) {
      raw = await IosPublishImagePipeline.compressForPublishFromPath(
        localPath.trim(),
      );
    } else {
      throw StateError('Sem imagem para enviar.');
    }

    final processed = await EcoFireImageProcess.processForFeedPhoto(raw);
    final churchId = tenantId.trim();
    final storagePath = _mainStoragePath(
      churchId: churchId,
      postType: postType,
      postId: postId,
      slotIndex: slotIndex,
    );

    final url = await EcoFireStorageUpload.putData(
      storagePath: storagePath,
      bytes: processed.bytes,
      mimeType: processed.mime,
      onProgress: onProgress,
    ).timeout(
      uploadTimeout,
      onTimeout: () => throw TimeoutException(
        'Upload da foto ${slotIndex + 1} demorou demais. Verifique a rede.',
      ),
    );

    return EcoFireFeedPhotoSlot(
      fullUrl: url,
      thumbUrl: url,
      fullPath: storagePath,
      thumbPath: storagePath,
    );
  }

  /// Lote — web (bytes) ou mobile (paths).
  static Future<List<EcoFireFeedPhotoSlot>> uploadPendingPhotoSlots({
    required String tenantId,
    required String postType,
    required String postId,
    required int startSlotIndex,
    List<Uint8List>? bytesList,
    List<String>? localPaths,
    void Function(double progress)? onProgress,
  }) async {
    final slots = <EcoFireFeedPhotoSlot>[];
    if (kIsWeb) {
      final images = bytesList ?? const <Uint8List>[];
      for (var i = 0; i < images.length; i++) {
        slots.add(
          await uploadPhotoSlot(
            tenantId: tenantId,
            postType: postType,
            postId: postId,
            slotIndex: startSlotIndex + i,
            bytes: images[i],
            onProgress: onProgress == null
                ? null
                : (p) => onProgress((i + p) / images.length),
          ),
        );
      }
      return slots;
    }

    final paths = localPaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    for (var i = 0; i < paths.length; i++) {
      final f = File(paths[i]);
      if (!await f.exists()) {
        throw StateError('Foto ${i + 1} não encontrada no aparelho.');
      }
      slots.add(
        await uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          slotIndex: startSlotIndex + i,
          localPath: paths[i],
          onProgress: onProgress == null
              ? null
              : (p) => onProgress((i + p) / paths.length),
        ),
      );
    }
    return slots;
  }

  /// Converte paths ou URLs mistos em URLs HTTPS para o Firestore.
  static Future<List<String>> refsToPlayableUrls(List<String> refs) async {
    final out = <String>[];
    for (final raw in refs) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('http')) {
        final u = sanitizeImageUrl(t);
        if (isValidImageUrl(u)) out.add(u);
        continue;
      }
      final u = await EcoFireStorageUpload.downloadUrlFromStoragePath(t);
      if (u != null && u.isNotEmpty) {
        out.add(sanitizeImageUrl(u));
      }
    }
    return dedupeImageRefsByStorageIdentity(out);
  }
}
