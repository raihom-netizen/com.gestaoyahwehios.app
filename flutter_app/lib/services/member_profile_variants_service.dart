import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/network_media_quality_policy.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';

/// Variantes WebP de foto de perfil — lista usa thumb, perfil usa medium.
abstract final class MemberProfileVariantsService {
  MemberProfileVariantsService._();

  static Future<Uint8List> _encodeWebp(Uint8List raw, int minSide) async {
    if (raw.isEmpty) return raw;
    final q = await NetworkMediaQualityPolicy.webpQualityForCurrentNetwork();
    try {
      final out = await FlutterImageCompress.compressWithList(
        raw,
        quality: q,
        format: CompressFormat.webp,
        minWidth: minSide,
        minHeight: minSide,
      );
      if (out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}
    return raw;
  }

  /// Thumb 200 + medium 500 + full 1920 (canónico `foto_perfil`).
  static Future<({
    Uint8List thumb,
    Uint8List medium,
    Uint8List full,
  })> encodeProfileTiers(Uint8List raw) async {
    if (raw.isEmpty) throw StateError('Sem bytes de imagem.');
    final results = await Future.wait([
      _encodeWebp(raw, YahwehPerformanceV4.profileThumbEdge),
      _encodeWebp(raw, YahwehPerformanceV4.profileMediumEdge),
      _encodeWebp(raw, YahwehPerformanceV4.feedFullEdge),
    ]);
    return (thumb: results[0], medium: results[1], full: results[2]);
  }

  static Future<({
    String photoThumb,
    String photoMedium,
    String photoFull,
    String fullStoragePath,
  })> uploadProfileVariants({
    required String tenantId,
    required String memberDocId,
    required Uint8List thumbBytes,
    required Uint8List mediumBytes,
    required Uint8List fullBytes,
    void Function(double progress)? onProgress,
  }) async {
    final thumbPath = ChurchStorageLayout.memberProfileThumbWebpPath(
      tenantId,
      memberDocId,
    );
    final mediumPath = ChurchStorageLayout.memberProfileMediumWebpPath(
      tenantId,
      memberDocId,
    );
    final fullPath = ChurchStorageLayout.memberCanonicalProfilePhotoPath(
      tenantId,
      memberDocId,
    );

    void report(int i, double p) {
      onProgress?.call(((i + p) / 3).clamp(0.0, 1.0));
    }

    final urls = await Future.wait([
      FeedPostMediaUpload.uploadFeedPhotoBytes(
        storagePath: thumbPath,
        bytes: thumbBytes,
        onProgress: (p) => report(0, p),
      ),
      FeedPostMediaUpload.uploadFeedPhotoBytes(
        storagePath: mediumPath,
        bytes: mediumBytes,
        onProgress: (p) => report(1, p),
      ),
      FeedPostMediaUpload.uploadFeedPhotoBytes(
        storagePath: fullPath,
        bytes: fullBytes,
        onProgress: (p) => report(2, p),
      ),
    ]);

    return (
      photoThumb: urls[0],
      photoMedium: urls[1],
      photoFull: urls[2],
      fullStoragePath: fullPath,
    );
  }

  /// URL para listas / aniversariantes / chat hub.
  static String? listPhotoUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    final thumb =
        (data[YahwehPerformanceV4.profileThumbField] ?? '').toString().trim();
    if (thumb.isNotEmpty) return thumb;
    final pv = data['photoVariants'];
    if (pv is Map) {
      for (final k in const ['thumb_200', 'thumb', 'profile_thumb']) {
        final e = pv[k];
        final u = e is Map ? (e['url'] ?? e['downloadUrl']) : e;
        final s = '$u'.trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  /// URL para ecrã de perfil / carteirinha.
  static String? profilePhotoUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    final med =
        (data[YahwehPerformanceV4.profileMediumField] ?? '').toString().trim();
    if (med.isNotEmpty) return med;
    return listPhotoUrl(data);
  }
}
