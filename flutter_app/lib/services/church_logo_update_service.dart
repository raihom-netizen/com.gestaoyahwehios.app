import 'dart:async' show unawaited, TimeoutException;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/utils/church_logo_png_encode.dart';

/// Logo institucional — path canónico `igrejas/{churchId}/configuracoes/logo_igreja.png`.
///
/// Padrão Controle Total: bytes compactos → um `putData` → URL → Firestore,
/// sem travar em 90% à espera de assert/metadata.
abstract final class ChurchLogoUpdateService {
  ChurchLogoUpdateService._();

  static const Duration kLogoPublishTimeout = Duration(seconds: 75);

  /// Maior lado — alinhado ao CT (~1600px), não 4K (lento / trava upload).
  static const int kLogoMaxSidePx = 1600;

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static String storagePathHint(String churchIdHint) {
    final cid = resolveChurchId(churchIdHint);
    return ChurchStorageLayout.churchIdentityLogoPath(cid);
  }

  static Future<ChurchLogoPublishResult> publishLogoStrict({
    required String churchIdHint,
    required Uint8List rawBytes,
    String? previousStoragePath,
    void Function(double progress)? onProgress,
  }) async {
    final cid = resolveChurchId(churchIdHint);
    if (cid.isEmpty) {
      throw StateError('Igreja não identificada para enviar a logo.');
    }
    if (rawBytes.isEmpty) {
      throw StateError('Imagem da logo vazia — selecione outra.');
    }

    try {
      return await _publishLogoStrictImpl(
        cid: cid,
        rawBytes: rawBytes,
        previousStoragePath: previousStoragePath,
        onProgress: onProgress,
      ).timeout(kLogoPublishTimeout);
    } on TimeoutException {
      throw StateError(
        'Tempo esgotado ao enviar a logo. Verifique a rede e tente de novo.',
      );
    }
  }

  static Future<ChurchLogoPublishResult> _publishLogoStrictImpl({
    required String cid,
    required Uint8List rawBytes,
    String? previousStoragePath,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);
    final png = await encodeChurchLogoAsPngInIsolate(
      rawBytes,
      maxSide: kLogoMaxSidePx,
    );
    onProgress?.call(0.15);

    final identityPath = ChurchStorageLayout.churchIdentityLogoPath(cid);
    // putData: 15% → 92% (nunca “grudar” em 90% no fim do bytes).
    final uploaded = await ChurchCentralStorageUpload.uploadChurchLogo(
      churchId: cid,
      pngBytes: png,
      onProgress: (p) => onProgress?.call(0.15 + p.clamp(0.0, 1.0) * 0.77),
      skipEnsureReady: true,
    );
    onProgress?.call(0.94);

    final cacheRevision = YahwehMediaCacheBust.freshRevisionMs();
    await ChurchBrandService.persistLogoPath(
      churchId: cid,
      storagePath: identityPath,
      downloadUrl: uploaded.downloadUrl,
      cacheRevision: cacheRevision,
      skipStorageAssert: true,
    );
    onProgress?.call(0.98);

    final url = uploaded.downloadUrl;
    final displayUrl = YahwehMediaCacheBust.apply(url, cacheRevision);
    unawaited(CachedNetworkImage.evictFromCache(url));
    unawaited(CachedNetworkImage.evictFromCache(displayUrl));
    AppStorageImageService.instance
        .invalidateStoragePrefix('igrejas/$cid/logo');
    AppStorageImageService.instance
        .invalidateStoragePrefix('igrejas/$cid/branding');
    AppStorageImageService.instance
        .invalidateStoragePrefix('igrejas/$cid/configuracoes');
    FirebaseStorageService.invalidateChurchLogoCache(cid);
    AppStorageImageService.instance.invalidate(
      storagePath: identityPath,
      imageUrl: url,
    );
    AppStorageImageService.instance.invalidate(
      storagePath: identityPath,
      imageUrl: displayUrl,
    );

    final prev = (previousStoragePath ?? '').trim();
    if (prev.isNotEmpty && prev != identityPath) {
      unawaited(FirebaseStorageCleanupService.deleteByUrlPathOrGs(prev));
    }
    unawaited(
      FirebaseStorageCleanupService.deleteByUrlPathOrGs(
        ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(cid),
      ),
    );
    unawaited(
      FirebaseStorageCleanupService.deleteLegacyChurchLogoMediaUnderTenant(cid),
    );
    FirebaseStorageCleanupService.scheduleCleanupAfterChurchConfigImageUpload(
      tenantId: cid,
    );

    onProgress?.call(1.0);
    return ChurchLogoPublishResult(
      downloadUrl: displayUrl,
      storagePath: identityPath,
      pngBytes: png,
      cacheRevision: cacheRevision,
    );
  }

  static Future<void> removeLogoStrict({
    required String churchIdHint,
    Map<String, dynamic>? tenantData,
    String? storagePath,
    String? downloadUrl,
  }) =>
      ChurchCanonicalMediaDeleteService.removeChurchLogoStrict(
        churchId: resolveChurchId(churchIdHint),
        tenantData: tenantData,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
      );
}

final class ChurchLogoPublishResult {
  const ChurchLogoPublishResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.pngBytes,
    required this.cacheRevision,
  });

  final String downloadUrl;
  final String storagePath;
  final Uint8List pngBytes;
  final int cacheRevision;
}
