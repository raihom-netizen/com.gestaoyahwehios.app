import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/network_media_quality_policy.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
/// Três tamanhos WebP (feed leve, chat thumb, tela cheia).
abstract final class MediaImageVariantsService {
  MediaImageVariantsService._();

  static const int webpQuality = YahwehPerformanceV4.webpQuality;
  static const int thumbEdge = 200;
  static const int mediumEdge = 800;
  static const int fullEdge = 1920;

  static const String tierThumb = 'thumb_200';
  static const String tierMedium = 'medium_800';
  static const String tierFull = 'full_1920';

  static Future<Uint8List> _encodeWebp(
    Uint8List raw, {
    required int minSide,
    int? quality,
  }) async {
    if (raw.isEmpty) return raw;
    final q = quality ?? await NetworkMediaQualityPolicy.webpQualityForCurrentNetwork();
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

  static Future<Uint8List> _encodeWebpFile(
    String path, {
    required int minSide,
    int? quality,
  }) async {
    if (kIsWeb) return Uint8List(0);
    final q = quality ?? await NetworkMediaQualityPolicy.webpQualityForCurrentNetwork();
    try {
      final out = await FlutterImageCompress.compressWithFile(
        path,
        quality: q,
        format: CompressFormat.webp,
        minWidth: minSide,
        minHeight: minSide,
      );
      if (out != null && out.isNotEmpty) return Uint8List.fromList(out);
    } catch (_) {}
    final f = File(path);
    if (await f.exists()) {
      return _encodeWebp(await f.readAsBytes(), minSide: minSide, quality: q);
    }
    return Uint8List(0);
  }

  /// Gera thumb / medium / full em WebP a partir de bytes ou path (mobile).
  static Future<({Uint8List thumb, Uint8List medium, Uint8List full})>
      encodeFeedWebpTiers({
    Uint8List? bytes,
    String? localPath,
  }) async {
    Uint8List source;
    if (bytes != null && bytes.isNotEmpty) {
      source = bytes;
    } else if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (!await f.exists()) {
        throw StateError('Ficheiro de imagem não encontrado.');
      }
      final results = await Future.wait([
        _encodeWebpFile(localPath, minSide: thumbEdge),
        _encodeWebpFile(localPath, minSide: mediumEdge),
        _encodeWebpFile(localPath, minSide: fullEdge),
      ]);
      return (thumb: results[0], medium: results[1], full: results[2]);
    } else {
      throw StateError('Sem dados de imagem para comprimir.');
    }
    final results = await Future.wait([
      _encodeWebp(source, minSide: thumbEdge),
      _encodeWebp(source, minSide: mediumEdge),
      _encodeWebp(source, minSide: fullEdge),
    ]);
    return (thumb: results[0], medium: results[1], full: results[2]);
  }

  /// Chat: só thumb leve + full (menos uploads que o feed).
  static Future<({Uint8List thumb, Uint8List full})> encodeChatWebpTiers({
    Uint8List? bytes,
    String? localPath,
  }) async {
    final tiers = await encodeFeedWebpTiers(bytes: bytes, localPath: localPath);
    return (thumb: tiers.thumb, full: tiers.full);
  }

  static Future<Map<String, dynamic>> _uploadTier(
    String storagePath,
    Uint8List bytes,
    void Function(double)? onProgress,
  ) async {
    final url = await FeedPostMediaUpload.uploadFeedPhotoBytes(
      storagePath: storagePath,
      bytes: bytes,
      onProgress: onProgress,
    );
    return {
      'url': url,
      'storagePath': storagePath,
      'contentType': 'image/webp',
    };
  }

  /// Sobe variantes em paralelo; devolve mapa Firestore + URL principal (full).
  static Future<({String primaryUrl, Map<String, dynamic> imageVariants})>
      uploadFeedTiers({
    required String thumbPath,
    required String mediumPath,
    required String fullPath,
    required Uint8List thumbBytes,
    required Uint8List mediumBytes,
    required Uint8List fullBytes,
    void Function(double progress)? onProgress,
  }) async {
    var slotProgress = 0.0;
    void reportSlot(int i, double p) {
      slotProgress = ((i + p) / 3).clamp(0.0, 1.0);
      onProgress?.call(slotProgress);
    }

    final uploaded = await Future.wait([
      _uploadTier(thumbPath, thumbBytes, (p) => reportSlot(0, p)),
      _uploadTier(mediumPath, mediumBytes, (p) => reportSlot(1, p)),
      _uploadTier(fullPath, fullBytes, (p) => reportSlot(2, p)),
    ]);

    final variants = <String, dynamic>{
      tierThumb: uploaded[0],
      tierMedium: uploaded[1],
      tierFull: uploaded[2],
    };
    final primary = (uploaded[2]['url'] ?? '').toString();
    return (primaryUrl: primary, imageVariants: variants);
  }

  /// Chat: thumb + full em paralelo.
  static Future<({String primaryUrl, String? thumbUrl})> uploadChatTiers({
    required String thumbPath,
    required String fullPath,
    required Uint8List thumbBytes,
    required Uint8List fullBytes,
    void Function(double progress)? onProgress,
  }) async {
    var slotProgress = 0.0;
    void reportSlot(int i, double p) {
      slotProgress = ((i + p) / 2).clamp(0.0, 1.0);
      onProgress?.call(slotProgress);
    }
    final results = await Future.wait([
      _uploadTier(thumbPath, thumbBytes, (p) => reportSlot(0, p)),
      _uploadTier(fullPath, fullBytes, (p) => reportSlot(1, p)),
    ]);
    return (
      primaryUrl: (results[1]['url'] ?? '').toString(),
      thumbUrl: (results[0]['url'] ?? '').toString(),
    );
  }
}
