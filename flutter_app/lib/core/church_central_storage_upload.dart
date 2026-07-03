import 'dart:async';
import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Módulos canónicos — path base `igrejas/{churchId}/{modulo}/…`.
enum ChurchCentralUploadModule {
  avisos,
  eventos,
  membros,
  patrimonio,
  financeiro,
  chat,
  cadastro,
}

/// Resultado único: URL https + path Storage (gravar path + URL no Firestore).
class ChurchCentralUploadResult {
  const ChurchCentralUploadResult({
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

/// **Pilar central** — compressão → Storage → `getDownloadURL` → Firestore.
///
/// Usar em avisos, eventos, chat, membros, patrimônio, financeiro e cadastro.
/// Não criar uploads soltos na UI nem segundo serviço paralelo.
abstract final class ChurchCentralStorageUpload {
  ChurchCentralStorageUpload._();

  static const Duration kDefaultUploadTimeout = Duration(seconds: 60);

  static void _assertCanonicalPath(String path, String context) {
    LegacyPathGuard.assertCanonicalStoragePath(path, context: context);
  }

  static Future<ChurchCentralUploadResult> uploadImageAtPath({
    required String storagePath,
    required Uint8List rawBytes,
    required String logLabel,
    bool alreadyCompressed = false,
    bool compressForFeed = true,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
  }) async {
    _assertCanonicalPath(storagePath, logLabel);
    if (rawBytes.isEmpty) {
      throw StateError('Imagem vazia — selecione outro ficheiro.');
    }
    
    logFirebasePublishPhase(
      'storage_upload_start',
      '$logLabel path=${storagePath.trim()} bytes=${rawBytes.length}',
    );

    try {
      final ({Uint8List bytes, String mime}) processed;
      if (alreadyCompressed && !compressForFeed) {
        processed = (bytes: rawBytes, mime: 'image/jpeg');
      } else if (compressForFeed) {
        processed = await EcoFireImageProcess.processForFeedPhoto(rawBytes);
      } else {
        processed = (
          bytes: await MediaService.compressImageBytes(
            rawBytes,
            profile: MediaImageProfile.feed,
          ),
          mime: 'image/jpeg',
        );
      }

      final url = await DirectStorageUrlPublish.uploadBytes(
        storagePath: storagePath,
        bytes: processed.bytes,
        mimeType: processed.mime,
        onProgress: onProgress,
        requireAuth: requireAuth,
      ).timeout(
        kDefaultUploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload demorou demais. Verifique a rede e tente de novo.',
        ),
      );

      return ChurchCentralUploadResult(
        downloadUrl: sanitizeImageUrl(url),
        storagePath: storagePath.trim(),
        contentType: processed.mime,
        bytes: processed.bytes,
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'storage_upload_error',
        '$logLabel path=${storagePath.trim()}',
        error: e,
        stack: st,
      );
      unawaited(
        CrashlyticsService.record(
          e,
          st,
          reason: 'central_upload_$logLabel',
        ),
      );
      rethrow;
    }
  }

  /// Aviso — `igrejas/{id}/avisos/{postId}/capa_aviso.jpg` (+ galeria).
  static Future<ChurchCentralUploadResult> uploadAvisoPhoto({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List rawBytes,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) =>
      uploadImageAtPath(
        storagePath: ChurchStorageLayout.avisoPostPhotoPath(
          churchId,
          postId,
          slotIndex,
        ),
        rawBytes: rawBytes,
        logLabel: 'aviso_photo',
        alreadyCompressed: alreadyCompressed,
        onProgress: onProgress,
      );

  /// Evento — `igrejas/{id}/eventos/{postId}/…`.
  static Future<ChurchCentralUploadResult> uploadEventoPhoto({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List rawBytes,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) =>
      uploadImageAtPath(
        storagePath: ChurchStorageLayout.eventPostPhotoPath(
          churchId,
          postId,
          slotIndex,
        ),
        rawBytes: rawBytes,
        logLabel: 'evento_photo',
        alreadyCompressed: alreadyCompressed,
        onProgress: onProgress,
      );

  /// Membro — foto perfil.
  static Future<ChurchCentralUploadResult> uploadMemberProfilePhoto({
    required String churchId,
    required String storageFolderId,
    required Uint8List fullBytes,
    void Function(double progress)? onProgress,
  }) =>
      uploadImageAtPath(
        storagePath: ChurchStorageLayout.memberProfilePhotoPath(
          churchId,
          storageFolderId,
        ),
        rawBytes: fullBytes,
        logLabel: 'membro_profile',
        alreadyCompressed: true,
        compressForFeed: false,
        onProgress: onProgress,
      );

  /// Patrimônio — slot de galeria.
  static Future<ChurchCentralUploadResult> uploadPatrimonioPhoto({
    required String churchId,
    required String itemDocId,
    required int slotIndex,
    required Uint8List rawBytes,
    void Function(double progress)? onProgress,
  }) =>
      uploadImageAtPath(
        storagePath: ChurchStorageLayout.patrimonioPhotoPath(
          churchId,
          itemDocId,
          slotIndex,
        ),
        rawBytes: rawBytes,
        logLabel: 'patrimonio_photo',
        onProgress: onProgress,
      );

  /// Logo igreja — `configuracoes/logo_igreja.png`.
  static Future<ChurchCentralUploadResult> uploadChurchLogo({
    required String churchId,
    required Uint8List pngBytes,
    void Function(double progress)? onProgress,
  }) async {
    final path = ChurchStorageLayout.churchIdentityLogoPath(churchId);
    _assertCanonicalPath(path, 'church_logo');
    if (pngBytes.isEmpty) {
      throw StateError('Logo vazia — selecione outra imagem.');
    }
    logFirebasePublishPhase(
      'storage_upload_start',
      'church_logo path=${path.trim()} bytes=${pngBytes.length}',
    );
    try {
      final url = await DirectStorageUrlPublish.uploadBytes(
        storagePath: path,
        bytes: pngBytes,
        mimeType: 'image/png',
        onProgress: onProgress,
      );
      return ChurchCentralUploadResult(
        downloadUrl: sanitizeImageUrl(url),
        storagePath: path,
        contentType: 'image/png',
        bytes: pngBytes,
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'storage_upload_error',
        'church_logo path=${path.trim()}',
        error: e,
        stack: st,
      );
      unawaited(CrashlyticsService.record(e, st, reason: 'central_upload_logo'));
      rethrow;
    }
  }

  /// Financeiro — comprovante (imagem ou PDF).
  static Future<ChurchCentralUploadResult> uploadFinanceComprovante({
    required String churchId,
    required String lancamentoId,
    required Uint8List bytes,
    required String mimeType,
    DateTime? referenceDate,
    void Function(double progress)? onProgress,
  }) async {
    final mime = mimeType.toLowerCase();
    late final Uint8List uploadBytes;
    late final String uploadMime;
    if (mime.contains('pdf')) {
      uploadBytes = bytes;
      uploadMime = mimeType;
    } else {
      uploadBytes = await MediaOptimizationService.optimizeForReceipt(bytes);
      uploadMime = 'image/jpeg';
    }

    final ext = mime.contains('pdf') ? 'pdf' : 'jpg';
    final path = ChurchStorageLayout.financeComprovantePath(
      tenantId: churchId,
      lancamentoId: lancamentoId,
      referenceDate: referenceDate,
      ext: ext,
    );
    _assertCanonicalPath(path, 'finance_comprovante');

    logFirebasePublishPhase(
      'storage_upload_start',
      'finance_comprovante path=${path.trim()} mime=$uploadMime bytes=${uploadBytes.length}',
    );

    try {
      final url = await DirectStorageUrlPublish.uploadBytes(
        storagePath: path,
        bytes: uploadBytes,
        mimeType: uploadMime,
        onProgress: onProgress,
      );
      return ChurchCentralUploadResult(
        downloadUrl: sanitizeImageUrl(url),
        storagePath: path,
        contentType: uploadMime,
        bytes: uploadBytes,
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'storage_upload_error',
        'finance_comprovante path=${path.trim()}',
        error: e,
        stack: st,
      );
      unawaited(
        CrashlyticsService.record(e, st, reason: 'central_upload_finance'),
      );
      rethrow;
    }
  }

  /// Chat / genérico — path já resolvido em `igrejas/{id}/chat_media/…`.
  static Future<ChurchCentralUploadResult> uploadAtCanonicalPath({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    String logLabel = 'chat_media',
    void Function(double progress)? onProgress,
  }) async {
    _assertCanonicalPath(storagePath, logLabel);
    if (bytes.isEmpty) {
      throw StateError('Ficheiro vazio — selecione outro.');
    }
    try {
      final url = await DirectStorageUrlPublish.uploadBytes(
        storagePath: storagePath,
        bytes: bytes,
        mimeType: mimeType,
        onProgress: onProgress,
      );
      return ChurchCentralUploadResult(
        downloadUrl: sanitizeImageUrl(url),
        storagePath: storagePath.trim(),
        contentType: mimeType,
        bytes: bytes,
      );
    } catch (e, st) {
      unawaited(
        CrashlyticsService.record(e, st, reason: 'central_upload_$logLabel'),
      );
      rethrow;
    }
  }
}
