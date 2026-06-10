import 'dart:typed_data';

import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Pipeline único de imagens — **Web = Android = iOS**.
///
/// Compressão, crop e formato antes do upload; paths Storage via [ChurchStorageLayout].
abstract final class YahwehUnifiedImagePipeline {
  YahwehUnifiedImagePipeline._();

  /// Membro — full 512×512 WebP + thumb 200×200 WebP.
  static Future<({Uint8List thumb, Uint8List full})> encodeMemberProfileTiers(
    Uint8List raw,
  ) async {
    if (raw.isEmpty) throw StateError('Sem bytes de imagem.');
    final results = await Future.wait([
      EcoFireImageProcess.processForMemberThumb(raw),
      EcoFireImageProcess.processForMemberProfile(raw),
    ]);
    return (thumb: results[0].bytes, full: results[1].bytes);
  }

  static Future<Uint8List> prepareMemberFull(Uint8List raw) async =>
      (await EcoFireImageProcess.processForMemberProfile(raw)).bytes;

  static Future<Uint8List> prepareMemberThumb(Uint8List raw) async =>
      (await EcoFireImageProcess.processForMemberThumb(raw)).bytes;

  static Future<Uint8List> prepareFeedPhoto(Uint8List raw) async =>
      (await EcoFireImageProcess.processForFeedPhoto(raw)).bytes;

  static Future<Uint8List> preparePatrimonio(Uint8List raw) async =>
      (await EcoFireImageProcess.processForPatrimonio(raw)).bytes;

  static Future<Uint8List> prepareLogo(Uint8List raw) async =>
      (await EcoFireImageProcess.processForLogo(raw)).bytes;

  /// Extensão canónica para fotos de feed/mural/eventos (sempre WebP).
  static String feedPhotoFileName([String base = 'foto']) => '$base.webp';

  /// MIME canónico para fotos comprimidas pelo pipeline.
  static String mimeForProfileWebp() => 'image/webp';

  static int get memberFullEdge => YahwehPerformanceV4.profileFullEdge;
  static int get memberThumbEdge => YahwehPerformanceV4.profileThumbEdge;
  static int get feedMaxEdge => YahwehPerformanceV4.uploadMaxEdgePx;
}
