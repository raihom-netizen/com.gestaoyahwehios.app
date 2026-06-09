import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/media_image_variants_service.dart';

/// Resultado de um slot de foto — só paths (Firestore nunca guarda bytes nem URL fixa).
class FeedPhotoSlotResult {
  const FeedPhotoSlotResult({
    required this.fullPath,
    required this.thumbPath,
    this.imageVariants,
  });

  final String fullPath;
  final String thumbPath;

  /// Variantes por tier (`thumb_300`, `medium_800`, `full_1920`) — só `storagePath`.
  final Map<String, dynamic>? imageVariants;
}

/// Pipeline instantâneo: comprimir → upload Storage → paths (upload-first, paralelo).
abstract final class ChurchInstantUploadPipeline {
  ChurchInstantUploadPipeline._();

  /// Comprime automaticamente imagens acima de 3 MB antes do upload.
  static Future<Uint8List> prepareImageBytes(
    Uint8List raw, {
    String? localPath,
  }) async {
    if (raw.isEmpty && localPath != null && localPath.isNotEmpty) {
      return IosPublishImagePipeline.compressForPublishFromPath(localPath);
    }
    if (raw.isEmpty) return raw;
    if (raw.length <= kAutoCompressImageThresholdBytes) return raw;
    return IosPublishImagePipeline.compressForPublishBytes(raw);
  }

  static String _variantPath({
    required String postType,
    required String tenantId,
    required String postId,
    required int slotIndex,
    required String tier,
  }) {
    final t = postType.trim().toLowerCase();
    if (t == 'evento' || t == 'noticia' || t == 'noticias') {
      return ChurchStorageLayout.eventPostPhotoVariantPath(
        tenantId,
        postId,
        slotIndex,
        tier,
      );
    }
    return ChurchStorageLayout.avisoPostPhotoVariantPath(
      tenantId,
      postId,
      slotIndex,
      tier,
    );
  }

  static Map<String, dynamic> _variantsPathsOnly(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final m = Map<String, dynamic>.from(v);
      final sp = (m['storagePath'] ?? '').toString().trim();
      if (sp.isEmpty) continue;
      out[e.key] = <String, dynamic>{
        'storagePath': sp,
        'contentType': (m['contentType'] ?? 'image/webp').toString(),
      };
    }
    return out;
  }

  /// Upload de um slot do feed — Web: 3 variantes em paralelo; mobile: 1 upload + path de thumb canónico.
  static Future<FeedPhotoSlotResult> uploadFeedPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    final useWebTiers = kIsWeb;
    final useMobileTiers = !kIsWeb &&
        !IosPublishImagePipeline.useNativeFastFeedUpload;

    if (useWebTiers || useMobileTiers) {
      Uint8List? prepared = bytes;
      if (prepared == null || prepared.isEmpty) {
        if (localPath != null && localPath.isNotEmpty) {
          prepared = await prepareImageBytes(Uint8List(0), localPath: localPath);
        }
      } else {
        prepared = await prepareImageBytes(prepared);
      }
      if (prepared == null || prepared.isEmpty) {
        throw StateError('Sem imagem para enviar.');
      }

      final tiers = await MediaImageVariantsService.encodeFeedWebpTiers(
        bytes: prepared,
        localPath: localPath,
      );
      final thumbPath = _variantPath(
        postType: postType,
        tenantId: tenantId,
        postId: postId,
        slotIndex: slotIndex,
        tier: MediaImageVariantsService.tierThumb,
      );
      final mediumPath = _variantPath(
        postType: postType,
        tenantId: tenantId,
        postId: postId,
        slotIndex: slotIndex,
        tier: MediaImageVariantsService.tierMedium,
      );
      final fullPath = _variantPath(
        postType: postType,
        tenantId: tenantId,
        postId: postId,
        slotIndex: slotIndex,
        tier: MediaImageVariantsService.tierFull,
      );

      final uploaded = await MediaImageVariantsService.uploadFeedTiers(
        thumbPath: thumbPath,
        mediumPath: mediumPath,
        fullPath: fullPath,
        thumbBytes: tiers.thumb,
        mediumBytes: tiers.medium,
        fullBytes: tiers.full,
        onProgress: onProgress,
      );

      await ChurchStorageMetadataVerify.assertExists(fullPath);

      return FeedPhotoSlotResult(
        fullPath: fullPath,
        thumbPath: thumbPath,
        imageVariants: _variantsPathsOnly(uploaded.imageVariants),
      );
    }

    await IosPublishImagePipeline.uploadFeedPhotoSlot(
      tenantId: tenantId,
      postType: postType,
      postId: postId,
      slotIndex: slotIndex,
      bytes: bytes,
      localPath: localPath,
      onProgress: onProgress,
    );

    final storageFull = FeedTenantStorageMap.feedPhotoPath(
      postType: postType,
      tenantId: tenantId,
      postDocId: postId,
      slotIndex: slotIndex,
    );
    await ChurchStorageMetadataVerify.assertExists(storageFull);

    final thumbPath = _variantPath(
      postType: postType,
      tenantId: tenantId,
      postId: postId,
      slotIndex: slotIndex,
      tier: MediaImageVariantsService.tierThumb,
    );

    return FeedPhotoSlotResult(
      fullPath: storageFull,
      thumbPath: thumbPath,
    );
  }

  /// Lote paralelo — `Future.wait` com limite de concorrência (feed).
  static Future<List<T>> uploadParallel<T>({
    required int count,
    required int maxConcurrent,
    required Future<T> Function(int index, void Function(double) report) uploadOne,
  }) async {
    if (count <= 0) return const [];
    final maxConc = maxConcurrent.clamp(1, count);
    final out = List<T?>.filled(count, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next;
        next++;
        if (i >= count) return;
        out[i] = await uploadOne(i, (_) {});
      }
    }

    await Future.wait(List.generate(maxConc, (_) => worker()));
    return out.cast<T>();
  }
}
