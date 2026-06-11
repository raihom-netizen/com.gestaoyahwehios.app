import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/services/media_image_variants_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        isValidImageUrl,
        sanitizeImageUrl;

/// Resultado de um slot — URLs + paths (EcoFire: Firestore guarda só links).
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

/// Publicação de fotos aviso/evento — padrão EcoFire Smart:
/// comprimir → Storage → [getDownloadURL] → Firestore só com links + miniatura.
abstract final class EcoFireFeedPublishService {
  EcoFireFeedPublishService._();

  static bool _isEventoPostType(String postType) {
    final t = postType.trim().toLowerCase();
    return t == 'evento' || t == 'noticia' || t == 'noticias';
  }

  static String _fullPath({
    required String churchId,
    required String postType,
    required String postId,
    required int slotIndex,
  }) {
    if (_isEventoPostType(postType)) {
      return ChurchStorageLayout.eventPostPhotoVariantPath(
        churchId,
        postId,
        slotIndex,
        MediaImageVariantsService.tierFull,
      );
    }
    return ChurchStorageLayout.avisoPostPhotoVariantPath(
      churchId,
      postId,
      slotIndex,
      MediaImageVariantsService.tierFull,
    );
  }

  static String _thumbPath({
    required String churchId,
    required String postType,
    required String postId,
    required int slotIndex,
  }) {
    if (_isEventoPostType(postType)) {
      return ChurchStorageLayout.eventPostPhotoVariantPath(
        churchId,
        postId,
        slotIndex,
        MediaImageVariantsService.tierThumb,
      );
    }
    return ChurchStorageLayout.avisoPostPhotoVariantPath(
      churchId,
      postId,
      slotIndex,
      MediaImageVariantsService.tierThumb,
    );
  }

  /// Um slot — full + thumb no Storage; devolve URLs HTTPS (token Firebase).
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

    final full = await EcoFireImageProcess.processForFeedPhoto(raw);
    final thumb = await EcoFireImageProcess.processForMemberThumb(raw);
    final churchId = tenantId.trim();
    final fullPath = _fullPath(
      churchId: churchId,
      postType: postType,
      postId: postId,
      slotIndex: slotIndex,
    );
    final thumbPath = _thumbPath(
      churchId: churchId,
      postType: postType,
      postId: postId,
      slotIndex: slotIndex,
    );

    final fullUrl = await EcoFireStorageUpload.putData(
      storagePath: fullPath,
      bytes: full.bytes,
      mimeType: full.mime,
      onProgress: onProgress,
    );
    final thumbUrl = await EcoFireStorageUpload.putData(
      storagePath: thumbPath,
      bytes: thumb.bytes,
      mimeType: thumb.mime,
    );

    return EcoFireFeedPhotoSlot(
      fullUrl: fullUrl,
      thumbUrl: thumbUrl,
      fullPath: fullPath,
      thumbPath: thumbPath,
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
