import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_firestore_meta.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/services/media_service.dart';

export 'ecofire_firestore_meta.dart';
export 'ecofire_image_process.dart';
export 'ecofire_storage_upload.dart';

/// Pipeline EcoFire unificado: comprimir → Storage → URL.
abstract final class EcoFireMediaUpload {
  EcoFireMediaUpload._();

  static Future<({Uint8List bytes, String mime})> _prepareBytes(
    Uint8List bytes,
    String contentType, {
    EcoFireMediaProfile profile = EcoFireMediaProfile.feedPhoto,
  }) async {
    final ct = contentType.toLowerCase();
    if (!ct.startsWith('image/')) {
      return EcoFireImageProcess.passthrough(bytes, contentType);
    }
    if (ct == 'image/webp' && profile == EcoFireMediaProfile.document) {
      return (bytes: bytes, mime: contentType);
    }
    return switch (profile) {
      EcoFireMediaProfile.logo => EcoFireImageProcess.processForLogo(bytes),
      EcoFireMediaProfile.memberProfile =>
        EcoFireImageProcess.processForMemberProfile(bytes),
      EcoFireMediaProfile.memberThumb =>
        EcoFireImageProcess.processForMemberThumb(bytes),
      EcoFireMediaProfile.patrimonio =>
        EcoFireImageProcess.processForPatrimonio(bytes),
      EcoFireMediaProfile.chat => _chatCompress(bytes),
      EcoFireMediaProfile.document ||
      EcoFireMediaProfile.feedPhoto =>
        EcoFireImageProcess.processForFeedPhoto(bytes),
    };
  }

  static Future<({Uint8List bytes, String mime})> _chatCompress(
    Uint8List bytes,
  ) async {
    var out = await MediaService.compressImageBytes(
      bytes,
      profile: MediaImageProfile.chat,
    );
    return (bytes: out, mime: 'image/jpeg');
  }

  /// Upload genérico — qualquer path `igrejas/…`.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    EcoFireMediaProfile profile = EcoFireMediaProfile.feedPhoto,
    void Function(double progress)? onProgress,
  }) async {
    EcoFireFlow.log('UPLOAD $storagePath');
    final prepared = await _prepareBytes(bytes, contentType, profile: profile);
    return EcoFireStorageUpload.putData(
      storagePath: storagePath,
      bytes: prepared.bytes,
      mimeType: prepared.mime,
      onProgress: onProgress,
    );
  }

  /// Ficheiro local (Android/iOS).
  static Future<String> uploadFile({
    required String storagePath,
    required File file,
    required String contentType,
    EcoFireMediaProfile profile = EcoFireMediaProfile.feedPhoto,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('EcoFireMediaUpload.uploadFile só em mobile.');
    }
    final raw = await file.readAsBytes();
    return uploadBytes(
      storagePath: storagePath,
      bytes: raw,
      contentType: contentType,
      profile: profile,
      onProgress: onProgress,
    );
  }

  /// Metadados Firestore padrão (sem blob — só URL + path).
  static Map<String, dynamic> photoMetadata({
    required String downloadUrl,
    required String storagePath,
    String? thumbUrl,
    String? thumbPath,
  }) =>
      EcoFireFirestoreMeta.memberPhoto(
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        thumbUrl: thumbUrl,
        thumbPath: thumbPath,
      );

  /// Membro: full + thumb numa operação (padrão EcoFire save → URL → Firestore).
  static Future<({String url, String path, String? thumbUrl})> uploadMemberProfile(
    String churchId,
    String memberId,
    Uint8List rawBytes, {
    void Function(double progress)? onProgress,
  }) async {
    final full = await EcoFireImageProcess.processForMemberProfile(rawBytes);
    final thumb = await EcoFireImageProcess.processForMemberThumb(rawBytes);
    final result = await EcoFireStorageUpload.uploadMemberProfile(
      churchId: churchId,
      memberId: memberId,
      fullBytes: full.bytes,
      mimeType: full.mime,
      thumbBytes: thumb.bytes,
      onProgress: onProgress,
    );
    return (
      url: result.url,
      path: result.storagePath,
      thumbUrl: result.thumbUrl,
    );
  }

  /// Logo igreja — process + upload + metadados prontos para merge Firestore.
  static Future<Map<String, dynamic>> uploadChurchLogoMeta(
    String churchId,
    Uint8List rawBytes, {
    void Function(double progress)? onProgress,
  }) async {
    final processed = await EcoFireImageProcess.processForLogo(rawBytes);
    final up = await EcoFireStorageUpload.uploadChurchLogo(
      churchId: churchId,
      bytes: processed.bytes,
      mimeType: processed.mime,
      onProgress: onProgress,
    );
    return EcoFireFirestoreMeta.churchLogo(
      downloadUrl: up.url,
      storagePath: up.storagePath,
    );
  }

  /// Fallback URL a partir de path Storage (EcoFire AdminNetworkImage).
  static Future<String?> resolveDisplayUrl({
    String? httpsUrl,
    String? storagePath,
    String? churchId,
    String? memberId,
    String? churchName,
  }) async {
    final u = (httpsUrl ?? '').trim();
    if (u.startsWith('http')) return u;
    if (storagePath != null && storagePath.trim().isNotEmpty) {
      final fromPath =
          await EcoFireStorageUpload.downloadUrlFromStoragePath(storagePath);
      if (fromPath != null && fromPath.isNotEmpty) return fromPath;
    }
    if (churchId != null && memberId != null) {
      return EcoFireStorageUpload.memberPhotoFallback(churchId, memberId);
    }
    if (churchId != null) {
      return EcoFireStorageUpload.churchLogoFallback(
        churchId,
        churchName: churchName,
      );
    }
    return null;
  }
}
