import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_repository.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';

/// Storage canónico — **só** `igrejas/{churchId}/…` (Android / iOS / Web).
abstract final class ChurchStorageService {
  ChurchStorageService._();

  static const Duration kUploadTimeout = Duration(seconds: 15);

  static String churchId([String? shellHint]) => ChurchRepository.churchId(shellHint);

  static String churchRoot([String? shellHint]) =>
      ChurchStorageLayout.churchRoot(churchId(shellHint));

  static String configuracoes([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegConfiguracoes}';

  static String membrosRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegMembros}';

  static String avisosRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegAvisos}';

  static String eventosRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegEventos}';

  static String patrimonioRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegPatrimonio}';

  static String chatMediaRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegChatMedia}';

  static String financeiroRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/financeiro';

  static String certificadosRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegCertificadosMidia}';

  static String carteirinhasRoot([String? shellHint]) =>
      '${churchRoot(shellHint)}/${ChurchStorageLayout.kSegCartaoMembro}';

  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw StateError('storagePath vazio.');
    }
    if (!path.startsWith('igrejas/')) {
      throw StateError(
        'Storage fora do layout canónico: $path — use igrejas/{churchId}/…',
      );
    }
    await UnifiedUploadService.uploadImage(
      storagePath: path,
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
      maxAttempts: 3,
    ).timeout(kUploadTimeout);
    await ChurchStorageMetadataVerify.assertExists(path);
    return path;
  }

  static String churchLogoPath([String? shellHint]) =>
      ChurchStorageLayout.churchIdentityLogoPath(churchId(shellHint));

  /// URL só para exibição — **nunca** gravar no Firestore após upload.
  static Future<String?> displayUrl(String? storagePath) =>
      StorageMediaService.downloadUrlFromPathOrUrl(storagePath);

  /// Logo institucional — lê `logoPath` do mapa ou fallback canónico.
  static Future<String?> logoDisplayUrl({
    Map<String, dynamic>? churchData,
    String? churchIdHint,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) return null;
    final path = (churchData?['logoPath'] ?? churchData?['logo_path'] ?? '')
        .toString()
        .trim();
    final effective =
        path.isNotEmpty ? path : ChurchStorageLayout.churchIdentityLogoPath(id);
    return displayUrl(effective);
  }
}
