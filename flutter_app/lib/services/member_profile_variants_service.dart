import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/yahweh_unified_image_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Foto de perfil do membro — um único ficheiro em
/// `igrejas/{tenant}/membros/{authUid|docId}/foto_perfil.jpg`.
abstract final class MemberProfileVariantsService {
  MemberProfileVariantsService._();

  /// Full 1024 @ 80% (quadrado) — usado como único upload.
  static Future<({
    Uint8List thumb,
    Uint8List full,
  })> encodeProfileTiers(Uint8List raw) =>
      YahwehUnifiedImagePipeline.encodeMemberProfileTiers(raw);

  /// Full `foto_perfil.jpg` + thumb `membros/thumbs/{id}.webp` (sobrescreve ao trocar).
  static Future<({
    String photoThumb,
    String photoFull,
    String fullStoragePath,
    String thumbStoragePath,
  })> uploadProfileVariants({
    required String tenantId,
    required String storageFolderId,
    required Uint8List fullBytes,
    Uint8List? thumbBytes,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    final fullPath = ChurchStorageLayout.memberProfilePhotoPath(
      tenantId,
      storageFolderId,
    );
    final thumbPath = ChurchStorageLayout.memberProfileThumbPathFlatWebpLegacy(
      tenantId,
      storageFolderId,
    );

    if (requireAuth) {
      await FastMediaPublishBootstrap.warmForFeedPublish();
    } else {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
    }

    void report(double p) => onProgress?.call(p * 0.85);

    final fullUrl = await FeedPostMediaUpload.uploadFeedPhotoBytes(
      storagePath: fullPath,
      bytes: fullBytes,
      onProgress: report,
      requireAuth: requireAuth,
    );
    if (fullUrl.trim().isEmpty) {
      throw StateError('Upload da foto concluiu sem URL de download.');
    }

    var thumbUrl = fullUrl;
    var thumbPathResolved = fullPath;
    final tb = thumbBytes;
    if (tb != null && tb.isNotEmpty) {
      try {
        thumbUrl = await FeedPostMediaUpload.uploadFeedPhotoBytes(
          storagePath: thumbPath,
          bytes: tb,
          onProgress: (p) => onProgress?.call(0.85 + p * 0.15),
          requireAuth: requireAuth,
        );
        thumbPathResolved = thumbPath;
      } catch (_) {
        thumbUrl = fullUrl;
        thumbPathResolved = fullPath;
      }
    }
    onProgress?.call(1.0);

    return (
      photoThumb: thumbUrl,
      photoFull: fullUrl,
      fullStoragePath: fullPath,
      thumbStoragePath: thumbPathResolved,
    );
  }

  /// URL para listas / chat / escalas / aniversariantes.
  static String? listPhotoUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final k in [
      'photoThumbStoragePath',
      'fotoThumbPath',
      'photoStoragePath',
      'fotoPath',
      YahwehPerformanceV4.profileThumbField,
      YahwehPerformanceV4.profileThumbFieldLegacy,
      YahwehPerformanceV4.profileFullField,
    ]) {
      final thumb = (data[k] ?? '').toString().trim();
      if (thumb.isEmpty) continue;
      if (thumb.startsWith('http') ||
          thumb.startsWith('gs://') ||
          thumb.contains('igrejas/')) {
        return thumb;
      }
    }
    final pv = data['photoVariants'];
    if (pv is Map) {
      for (final k in const ['thumb_200', 'thumb', 'profile_thumb']) {
        final e = pv[k];
        final u = e is Map ? (e['url'] ?? e['downloadUrl']) : e;
        final s = '$u'.trim();
        if (s.startsWith('http')) return s;
      }
    }
    return null;
  }

  /// URL full — carteirinha, PDF, ecrã de perfil detalhado.
  static String? profilePhotoUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final k in [
      'photoStoragePath',
      'fotoPath',
      YahwehPerformanceV4.profileFullField,
      'foto_url',
      'FOTO_URL_OU_ID',
      'photoURL',
      'photoUrl',
    ]) {
      final s = (data[k] ?? '').toString().trim();
      if (s.isEmpty) continue;
      if (s.startsWith('http') ||
          s.startsWith('gs://') ||
          s.contains('igrejas/')) {
        return s;
      }
    }
    final full = imageUrlFromMap(data);
    return full.isNotEmpty ? full : null;
  }
}
