import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/services/church_instant_upload_pipeline.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_service.dart';

/// Módulos cobertos pelo prepare/upload único (padrão avisos/eventos).
abstract final class ChurchPhotoModules {
  static const aviso = 'aviso';
  static const evento = 'evento';
  static const membro = 'membro';
  static const patrimonio = 'patrimonio';
  static const fornecedor = 'fornecedor';
  static const financeiro = 'financeiro';
  static const logo = 'logo';
  static const master = 'master';
  static const chat = 'chat';
}

/// **Pipeline único de fotos** — Web = Android = iOS.
///
/// 1. [prepareBytes] — 1 compressão por módulo (rápida, tetos estáveis)
/// 2. [ChurchMediaUploadFacade.ensureReady]
/// 3. [uploadPrepared] / [prepareAndUpload] → Storage putData → URL
///
/// Use em: membros, patrimônio, fornecedores, financeiro, logo, cadastro
/// público, painel master, avisos e eventos.
abstract final class ChurchUnifiedPhotoUpload {
  ChurchUnifiedPhotoUpload._();

  /// Compressão única alinhada ao módulo (mesmo motor dos avisos/eventos).
  static Future<Uint8List> prepareBytes(
    Uint8List raw, {
    required String module,
    String? localPath,
  }) async {
    final m = module.trim().toLowerCase();
    if (raw.isEmpty && (localPath == null || localPath.isEmpty)) {
      return raw;
    }

    // Feed mural — já tem política própria no Instant.
    if (m == ChurchPhotoModules.aviso ||
        m == ChurchPhotoModules.evento ||
        m == 'noticia' ||
        m == 'noticias') {
      return ChurchInstantUploadPipeline.prepareImageBytes(
        raw,
        localPath: localPath,
        postType: m == 'noticias' || m == 'noticia' ? 'aviso' : m,
      );
    }

    // Patrimônio — mesmo teto JPEG do editor (rápido, sem reencode duplo).
    if (m == ChurchPhotoModules.patrimonio) {
      final base = await ChurchInstantUploadPipeline.prepareImageBytes(
        raw,
        localPath: localPath,
        postType: 'patrimonio',
      );
      return ImageHelper.compressPatrimonioPhotoForUpload(base);
    }

    // Membro / chat — perfil leve (~420 KB).
    if (m == ChurchPhotoModules.membro || m == ChurchPhotoModules.chat) {
      final base = await ChurchInstantUploadPipeline.prepareImageBytes(
        raw,
        localPath: localPath,
        postType: 'membro',
      );
      return ImageHelper.compressImageUnderMaxBytes(
        base,
        maxBytes: ImageHelper.memberPhotoMaxUploadBytes,
      );
    }

    // Fornecedor / financeiro — comprovante (print/foto), JPEG compacto.
    if (m == ChurchPhotoModules.fornecedor ||
        m == ChurchPhotoModules.financeiro) {
      final base = await ChurchInstantUploadPipeline.prepareImageBytes(
        raw,
        localPath: localPath,
        postType: m,
      );
      if (base.length <= kEventoAvisoFeedTargetMaxBytes &&
          base.length >= 2 &&
          base[0] == 0xFF &&
          base[1] == 0xD8) {
        return base;
      }
      return ImageHelper.compressImageUnderMaxBytes(
        base,
        maxBytes: kEventoAvisoFeedTargetMaxBytes,
      );
    }

    // Logo / master — qualidade um pouco maior (até ~800 KB).
    if (m == ChurchPhotoModules.logo || m == ChurchPhotoModules.master) {
      final base = await ChurchInstantUploadPipeline.prepareImageBytes(
        raw,
        localPath: localPath,
        postType: m,
      );
      return ImageHelper.compressImageUnderMaxBytes(
        base,
        maxBytes: 800 * 1024,
      );
    }

    return ChurchInstantUploadPipeline.prepareImageBytes(
      raw,
      localPath: localPath,
      postType: m,
    );
  }

  /// Upload de bytes **já preparados** (não recomprime).
  static Future<ChurchCentralUploadResult> uploadPrepared({
    required Uint8List preparedBytes,
    required String storagePath,
    String logLabel = 'unified_photo',
    String mimeType = 'image/jpeg',
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    if (preparedBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outra foto.');
    }
    await ChurchMediaUploadFacade.ensureReady(requireAuth: requireAuth);
    return ChurchCentralStorageUpload.uploadAtCanonicalPath(
      storagePath: storagePath,
      bytes: preparedBytes,
      mimeType: mimeType,
      logLabel: logLabel,
      onProgress: onProgress,
      skipEnsureReady: true,
    );
  }

  /// Prepare + upload num passo (padrão definitivo para fotos).
  static Future<ChurchCentralUploadResult> prepareAndUpload({
    required Uint8List rawBytes,
    required String module,
    required String storagePath,
    String? localPath,
    String logLabel = 'unified_photo',
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.05);
    final prepared = await prepareBytes(
      rawBytes,
      module: module,
      localPath: localPath,
    );
    onProgress?.call(0.18);
    return uploadPrepared(
      preparedBytes: prepared,
      storagePath: storagePath,
      logLabel: logLabel,
      requireAuth: requireAuth,
      onProgress: (p) => onProgress?.call(0.18 + p.clamp(0.0, 1.0) * 0.82),
    );
  }

  /// PDF/binário — sem compressão de imagem; mesmo gate Storage.
  static Future<ChurchCentralUploadResult> uploadBinary({
    required Uint8List bytes,
    required String storagePath,
    required String mimeType,
    String logLabel = 'unified_binary',
    bool requireAuth = true,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    await ChurchMediaUploadFacade.ensureReady(requireAuth: requireAuth);
    return ChurchCentralStorageUpload.uploadAtCanonicalPath(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: mimeType,
      logLabel: logLabel,
      onProgress: onProgress,
      skipEnsureReady: true,
    );
  }

  /// Perfil MediaService alinhado ao módulo (quando o caller usa MediaService).
  static MediaImageProfile mediaProfileFor(String module) {
    switch (module.trim().toLowerCase()) {
      case ChurchPhotoModules.patrimonio:
        return MediaImageProfile.patrimonio;
      case ChurchPhotoModules.membro:
      case ChurchPhotoModules.chat:
        return MediaImageProfile.chat;
      case ChurchPhotoModules.logo:
      case ChurchPhotoModules.master:
        return MediaImageProfile.feed;
      default:
        return MediaImageProfile.feed;
    }
  }
}
