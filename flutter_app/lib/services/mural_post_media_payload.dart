import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageObjectPathFromHttpUrl, isValidImageUrl, normalizeFirebaseStorageObjectPath, sanitizeImageUrl;

/// Campos de mídia partilhados entre editor do mural e reenvio em background.
abstract final class MuralPostMediaPayload {
  MuralPostMediaPayload._();

  static Future<String> uploadPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required Uint8List bytes,
    required int slotIndex,
    void Function(double progress)? onProgress,
  }) async {
    final storagePath = postType == 'evento'
        ? ChurchStorageLayout.eventPostPhotoPath(tenantId, postId, slotIndex)
        : ChurchStorageLayout.avisoPostPhotoPath(tenantId, postId, slotIndex);
    return FeedPostMediaUpload.uploadFeedPhotoBytes(
      storagePath: storagePath,
      bytes: bytes,
      onProgress: onProgress,
    );
  }

  static Map<String, dynamic> buildMediaFields({
    required List<String> allUrls,
    required double aspectRatio,
    required bool hasVideo,
    bool allowDeleteSentinels = true,
  }) {
    final firstUrl = allUrls.isNotEmpty ? allUrls[0] : '';
    final patch = <String, dynamic>{};
    patch['imageUrl'] = firstUrl;
    patch['imageUrls'] = allUrls;
    patch['defaultImageUrl'] = firstUrl;
    if (firstUrl.isNotEmpty) {
      patch['imagemUrl'] = firstUrl;
      patch['imagem_url'] = firstUrl;
    } else if (allowDeleteSentinels) {
      patch['imagemUrl'] = FieldValue.delete();
      patch['imagem_url'] = FieldValue.delete();
    }
    if (allUrls.isNotEmpty) {
      patch['media_info'] = <String, dynamic>{
        'url_original': firstUrl,
        'aspect_ratio': aspectRatio,
        'tipo': hasVideo ? 'video' : 'image',
      };
    } else if (allowDeleteSentinels) {
      patch['media_info'] = FieldValue.delete();
    }
    if (allUrls.isEmpty) {
      if (allowDeleteSentinels) {
        patch['imageStoragePath'] = FieldValue.delete();
        patch['imageStoragePaths'] = FieldValue.delete();
      }
    } else {
      final paths = _pathsFromImageUrls(allUrls);
      if (paths != null && paths.isNotEmpty) {
        patch['imageStoragePath'] = paths.first;
        patch['imageStoragePaths'] = paths;
      }
    }
    return patch;
  }

  static List<String>? _pathsFromImageUrls(List<String> urls) {
    final paths = <String>[];
    for (final u in urls) {
      final s = sanitizeImageUrl(u.trim());
      if (!isValidImageUrl(s)) return null;
      final p = firebaseStorageObjectPathFromHttpUrl(s);
      if (p == null || p.isEmpty) return null;
      paths.add(normalizeFirebaseStorageObjectPath(p));
    }
    return paths;
  }
}
