import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/transactional_media_publish_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Resultado canónico: ficheiro no Storage + URL https para Firestore.
class ChurchCanonicalUploadResult {
  const ChurchCanonicalUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
    required this.bytes,
  });

  final String downloadUrl;
  final String storagePath;
  final String contentType;
  final Uint8List bytes;
}

/// Núcleo único — compressão (quando imagem) → EcoFire Storage → campos Firestore.
///
/// Usar em todos os módulos (membros, avisos, eventos, patrimônio, master,
/// cultos fixos, cadastro público) em vez de `putData` solto na UI.
abstract final class ChurchCanonicalMediaPublish {
  ChurchCanonicalMediaPublish._();

  static void _assertPath(String storagePath, {required String context}) {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw ArgumentError('storagePath vazio ($context).');
    }
    LegacyPathGuard.assertCanonicalStoragePath(path, context: context);
  }

  /// Imagem: gate → comprimir → upload → URL https.
  static Future<ChurchCanonicalUploadResult> compressAndUploadImage({
    required Uint8List rawBytes,
    required String storagePath,
    required YahwehMediaModule gateModule,
    String logLabel = 'canonical_image',
    MediaImageProfile profile = MediaImageProfile.feed,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    _assertPath(storagePath, context: logLabel);
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outro ficheiro.');
    }
    final ok = await YahwehModuleMediaGate.prepareForPublishUpload(
      module: gateModule,
      logLabel: logLabel,
      requireAuth: requireAuth,
    );
    if (!ok) {
      throw StateError('Firebase indisponível para enviar mídia.');
    }

    final upload = await TransactionalMediaPublishPipeline.compressAndUpload(
      rawBytes: rawBytes,
      storagePath: storagePath,
      contentType: MediaService.contentTypeForProfile(
        profile,
        await MediaService.compressImageBytes(rawBytes, profile: profile),
      ),
      module: TransactionalMediaModule.strict,
      onProgress: onProgress == null
          ? null
          : (phase, p) {
              if (phase == TransactionalMediaPhase.uploading) {
                onProgress(p);
              }
            },
    );

    return ChurchCanonicalUploadResult(
      downloadUrl: sanitizeImageUrl(upload.downloadUrl),
      storagePath: upload.storagePath,
      contentType: upload.contentType,
      bytes: upload.compressedBytes,
    );
  }

  /// PDF / vídeo / binário — sem compressão; mesmo gate EcoFire.
  static Future<ChurchCanonicalUploadResult> uploadBinary({
    required Uint8List bytes,
    required String storagePath,
    required String contentType,
    required YahwehMediaModule gateModule,
    String logLabel = 'canonical_binary',
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    _assertPath(storagePath, context: logLabel);
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    final ok = await YahwehModuleMediaGate.prepareForPublishUpload(
      module: gateModule,
      logLabel: logLabel,
      requireAuth: requireAuth,
      withPhotos: false,
    );
    if (!ok) {
      throw StateError('Firebase indisponível para enviar mídia.');
    }

    final url = await EcoFireStorageUpload.putData(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: contentType,
      onProgress: onProgress,
    );

    return ChurchCanonicalUploadResult(
      downloadUrl: sanitizeImageUrl(url),
      storagePath: storagePath.trim(),
      contentType: contentType,
      bytes: bytes,
    );
  }

  /// Membro — path Storage + URLs https (painel, site, cadastro público).
  static Map<String, dynamic> memberProfileFields({
    required String downloadUrl,
    required String storagePath,
    String? thumbStoragePath,
  }) =>
      ChurchCanonicalMediaContract.memberProfileWritePatch(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        thumbStoragePath: thumbStoragePath,
      );

  /// Master — capa de igreja cliente em destaque (`marketing_clientes`).
  static Map<String, dynamic> marketingClienteCapaFields({
    required String downloadUrl,
    required String storagePath,
  }) =>
      ChurchCanonicalMediaContract.marketingClienteCapaWritePatch(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
      );

  /// Culto / evento fixo (`event_templates`).
  static Map<String, dynamic> eventTemplateCoverFields({
    required String downloadUrl,
    required String storagePath,
  }) =>
      ChurchCanonicalMediaContract.eventTemplateCoverWritePatch(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
      );

  /// Galeria institucional Master (`app_public/institutional_gallery`).
  static Map<String, dynamic> divulgacaoAssetFields({
    required String downloadUrl,
    required String storagePath,
    required String kind,
  }) =>
      ChurchCanonicalMediaContract.divulgacaoAssetWritePatch(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        kind: kind,
      );
}
