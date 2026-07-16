import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Campos canónicos de fotos do patrimônio — delega a [ChurchCanonicalMediaContract].
abstract final class PatrimonioPhotoFields {
  PatrimonioPhotoFields._();

  static List<String> get slotUrlKeys =>
      ChurchCanonicalMediaContract.patrimonioUrlSlotKeys;

  static List<String> get slotPathKeys =>
      ChurchCanonicalMediaContract.patrimonioPathSlotKeys;

  static int get maxPhotos => ChurchCanonicalMediaContract.patrimonioMaxPhotos;

  static List<String> get legacyKeysToDelete =>
      ChurchCanonicalMediaContract.patrimonioLegacyKeysToDelete;

  static void stripLegacyPhotoFields(
    Map<String, dynamic> payload, {
    bool allowDeleteSentinels = true,
  }) =>
      ChurchCanonicalMediaContract.patrimonioStripLegacyFields(
        payload,
        allowDeleteSentinels: allowDeleteSentinels,
      );

  static void applyIndexedSlots(
    Map<String, dynamic> payload,
    List<String> slotUrls,
    List<String> slotPaths, {
    int? cacheRevision,
    bool allowDeleteSentinels = true,
  }) =>
      ChurchCanonicalMediaContract.patrimonioApplyIndexedSlots(
        payload,
        slotUrls,
        slotPaths,
        cacheRevision: cacheRevision,
        allowDeleteSentinels: allowDeleteSentinels,
      );

  /// Grava listas ordenadas (foto01 = urls[0]) — slots canónicos apenas.
  static void applyToPayload(
    Map<String, dynamic> payload,
    List<String> urls,
    List<String> paths, {
    bool allowDeleteSentinels = true,
  }) {
    final cleanUrls = urls
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .take(maxPhotos)
        .toList();
    final cleanPaths =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    applyIndexedSlots(
      payload,
      cleanUrls,
      cleanPaths,
      allowDeleteSentinels: allowDeleteSentinels,
    );
  }

  static List<String> urlsFromData(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.patrimonioImageUrls(data);

  static List<String> pathsFromData(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.patrimonioStoragePaths(data);
}
