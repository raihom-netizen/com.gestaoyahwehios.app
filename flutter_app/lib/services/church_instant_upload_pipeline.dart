import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Resultado de um slot de foto — path Storage + URL HTTPS para o Firestore.
class FeedPhotoSlotResult {
  const FeedPhotoSlotResult({
    required this.fullPath,
    required this.thumbPath,
    this.downloadUrl,
    this.thumbDownloadUrl,
  });

  final String fullPath;
  final String thumbPath;

  /// URL HTTPS do ficheiro principal (getDownloadURL após upload).
  final String? downloadUrl;

  /// URL HTTPS da miniatura (lista/painel); igual a [downloadUrl] — 1 ficheiro por slot.
  final String? thumbDownloadUrl;
}

/// Pipeline instantâneo: **1 JPEG 1080px** por foto → upload Storage (sem tiers WebP).
abstract final class ChurchInstantUploadPipeline {
  ChurchInstantUploadPipeline._();

  /// Comprime automaticamente imagens acima de 3 MB antes do upload.
  /// Avisos: teto [kAvisoCapaMaxUploadBytes] (~150 KB) para publicação rápida.
  static Future<Uint8List> prepareImageBytes(
    Uint8List raw, {
    String? localPath,
    String? postType,
  }) async {
    final isAviso = postType?.trim().toLowerCase() == 'aviso';
    Uint8List base = raw;
    if (base.isEmpty && localPath != null && localPath.isNotEmpty) {
      base = await IosPublishImagePipeline.compressForPublishFromPath(localPath);
    }
    if (base.isEmpty) return base;
    if (isAviso) {
      return ImageHelper.compressImageUnderMaxBytes(
        base,
        maxBytes: kAvisoCapaMaxUploadBytes,
      );
    }
    final isEvento = postType?.trim().toLowerCase() == 'evento';
    if (isEvento) {
      var work = base;
      if (work.length > kEventoFotoMaxUploadBytes) {
        try {
          work = await MediaService.compressImageBytes(
            work,
            profile: MediaImageProfile.feed,
          );
        } catch (_) {}
      }
      return ImageHelper.compressImageUnderMaxBytes(
        work,
        maxBytes: kEventoFotoMaxUploadBytes,
      );
    }
    if (base.length <= kAutoCompressImageThresholdBytes) return base;
    return IosPublishImagePipeline.compressForPublishBytes(base);
  }

  static String _storagePathForSlot({
    required String postType,
    required String tenantId,
    required String postId,
    required int slotIndex,
  }) {
    final t = postType.trim().toLowerCase();
    if (t == 'aviso' || t == 'noticia' || t == 'noticias') {
      return ChurchStorageLayout.avisoPostPhotoPath(tenantId, postId, slotIndex);
    }
    if (t == 'evento') {
      return ChurchStorageLayout.eventPostPhotoCanonicalPath(
        tenantId,
        postId,
        slotIndex,
      );
    }
    return FeedTenantStorageMap.feedPhotoPath(
      postType: postType,
      tenantId: tenantId,
      postDocId: postId,
      slotIndex: slotIndex,
    );
  }

  /// Upload de um slot — **1 ficheiro** `capa_aviso.jpg` / `galeria_XX.jpg` / `banner_evento.jpg`.
  static Future<FeedPhotoSlotResult> uploadFeedPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadSimpleFeedPhotoSlot(
      postType: postType.trim().toLowerCase(),
      tenantId: tenantId,
      postId: postId,
      slotIndex: slotIndex,
      bytes: bytes,
      localPath: localPath,
      onProgress: onProgress,
    );
  }

  static Future<FeedPhotoSlotResult> _uploadSimpleFeedPhotoSlot({
    required String postType,
    required String tenantId,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          FastMediaPublishBootstrap.resetSessionWarm();
          await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: true);
        }
        await ensureFirebaseCore(requireAuth: true);
        return await _uploadSimpleFeedPhotoSlotOnce(
          postType: postType,
          tenantId: tenantId,
          postId: postId,
          slotIndex: slotIndex,
          bytes: bytes,
          localPath: localPath,
          onProgress: onProgress,
        );
      } catch (e) {
        last = e;
        if (attempt < 2 && isFirebaseNoAppError(e)) {
          await Future<void>.delayed(
            Duration(milliseconds: 280 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    throw last ?? StateError('Upload de foto falhou.');
  }

  static Future<FeedPhotoSlotResult> _uploadSimpleFeedPhotoSlotOnce({
    required String postType,
    required String tenantId,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    void Function(double progress)? onProgress,
  }) async {
    Uint8List? prepared = bytes;
    if (prepared == null || prepared.isEmpty) {
      if (localPath != null && localPath.isNotEmpty) {
        prepared = await prepareImageBytes(
          Uint8List(0),
          localPath: localPath,
          postType: postType,
        );
      }
    } else {
      prepared = await prepareImageBytes(
        prepared,
        localPath: localPath,
        postType: postType,
      );
    }
    if (prepared == null || prepared.isEmpty) {
      throw StateError('Sem imagem para enviar.');
    }
    final storagePath = _storagePathForSlot(
      postType: postType,
      tenantId: tenantId,
      postId: postId,
      slotIndex: slotIndex,
    );
    final downloadUrl = await FeedPostMediaUpload.uploadFeedPhotoBytes(
      storagePath: storagePath,
      bytes: prepared,
      onProgress: onProgress,
    );
    final clean = sanitizeImageUrl(downloadUrl);
    if (!isValidImageUrl(clean)) {
      throw StateError('Upload concluiu sem URL de download válida.');
    }
    await ChurchStorageMetadataVerify.assertExists(storagePath);
    return FeedPhotoSlotResult(
      fullPath: storagePath,
      thumbPath: storagePath,
      downloadUrl: clean,
      thumbDownloadUrl: clean,
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
