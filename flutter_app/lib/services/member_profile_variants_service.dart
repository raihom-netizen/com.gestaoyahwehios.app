import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Variantes WebP de foto de perfil — listas usam thumb; carteirinha/perfil usam full.
abstract final class MemberProfileVariantsService {
  MemberProfileVariantsService._();

  /// Thumb 200 @ 70% + full 1024 @ 80% (quadrado).
  static Future<({
    Uint8List thumb,
    Uint8List full,
  })> encodeProfileTiers(Uint8List raw) async {
    if (raw.isEmpty) throw StateError('Sem bytes de imagem.');
    final results = await Future.wait([
      _encodeWebpWithQuality(
        raw,
        YahwehPerformanceV4.profileThumbEdge,
        YahwehPerformanceV4.profileThumbQuality,
      ),
      _encodeWebpWithQuality(
        raw,
        YahwehPerformanceV4.profileFullEdge,
        YahwehPerformanceV4.profileFullQuality,
      ),
    ]);
    return (thumb: results[0], full: results[1]);
  }

  static Future<Uint8List> _encodeWebpWithQuality(
    Uint8List raw,
    int minSide,
    int quality,
  ) async {
    if (raw.isEmpty) return raw;
    try {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        quality: quality,
        format: CompressFormat.webp,
        minWidth: minSide,
        minHeight: minSide,
      );
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}
    return raw;
  }

  static Future<({
    String photoThumb,
    String photoFull,
    String fullStoragePath,
    String thumbStoragePath,
  })> uploadProfileVariants({
    required String tenantId,
    required String memberDocId,
    required Uint8List thumbBytes,
    required Uint8List fullBytes,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    final thumbPath = ChurchStorageLayout.memberProfileThumbPath(
      tenantId,
      memberDocId,
    );
    final fullPath = ChurchStorageLayout.memberProfilePhotoPath(
      tenantId,
      memberDocId,
    );

    void report(int i, double p) {
      onProgress?.call(((i + p) / 2).clamp(0.0, 1.0));
    }

    if (requireAuth) {
      await FastMediaPublishBootstrap.warmForFeedPublish();
    } else {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseBootstrapService.refreshCachedApp();
    }
    final urls = await Future.wait([
      FeedPostMediaUpload.uploadFeedPhotoBytes(
        storagePath: thumbPath,
        bytes: thumbBytes,
        onProgress: (p) => report(0, p),
        requireAuth: requireAuth,
      ),
      FeedPostMediaUpload.uploadFeedPhotoBytes(
        storagePath: fullPath,
        bytes: fullBytes,
        onProgress: (p) => report(1, p),
        requireAuth: requireAuth,
      ),
    ]);

    return (
      photoThumb: urls[0],
      photoFull: urls[1],
      fullStoragePath: fullPath,
      thumbStoragePath: thumbPath,
    );
  }

  /// URL para listas / chat / escalas / aniversariantes — **só** miniatura.
  static String? listPhotoUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final k in [
      YahwehPerformanceV4.profileThumbField,
      YahwehPerformanceV4.profileThumbFieldLegacy,
    ]) {
      final thumb = (data[k] ?? '').toString().trim();
      if (thumb.startsWith('http')) return thumb;
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
      YahwehPerformanceV4.profileFullField,
      'foto_url',
      'FOTO_URL_OU_ID',
      'photoURL',
      'photoUrl',
    ]) {
      final s = (data[k] ?? '').toString().trim();
      if (s.startsWith('http')) return s;
    }
    final full = imageUrlFromMap(data);
    return full.isNotEmpty ? full : null;
  }
}
