import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:gestao_yahweh/core/yahweh_cache_managers.dart';
import 'package:gestao_yahweh/services/member_profile_image_isolate.dart';

class ImageHelper {
  static const int _fallbackMinWidth = 800;
  static const int _fallbackMinHeight = 600;
  static const int _fallbackQuality = 75;

  /// Teto recomendado para foto de perfil antes do Firebase Storage (~1 MB).
  static const int memberPhotoMaxUploadBytes = 1024 * 1024;

  static bool _bytesLookLikeWebp(Uint8List list) {
    return list.length >= 12 &&
        list[0] == 0x52 &&
        list[1] == 0x49 &&
        list[2] == 0x46 &&
        list[3] == 0x46 &&
        list[8] == 0x57 &&
        list[9] == 0x45 &&
        list[10] == 0x42 &&
        list[11] == 0x50;
  }

  /// Reduz WebP até caber em [maxBytes] (foto de perfil já em WebP de alta resolução).
  static Future<Uint8List> compressWebpUnderMaxBytes(
    Uint8List list, {
    int maxBytes = memberPhotoMaxUploadBytes,
  }) async {
    if (list.isEmpty) return list;
    var current = list;
    var quality = 88;
    for (var i = 0; i < 22; i++) {
      if (current.length <= maxBytes) return current;
      try {
        final next = await FlutterImageCompress.compressWithList(
          current,
          quality: quality,
          format: CompressFormat.webp,
        );
        if (next.isEmpty) break;
        current = Uint8List.fromList(next);
        if (current.length <= maxBytes) return current;
      } catch (_) {
        break;
      }
      quality = (quality - 6).clamp(40, 95);
    }
    return current;
  }

  /// Uma passagem JPEG, lado máx. [kMemberProfileMaxEdgePx] (800px), quality [kMemberProfileJpegQuality].
  /// Roda em [compute] (isolate) em plataformas nativas para não bloquear a UI; na web executa inline.
  /// Entrada WebP (fluxo 4K + recorte) só é limitada por tamanho — sem reconverter para JPEG.
  static Future<Uint8List> compressMemberProfileForUpload(
      Uint8List list) async {
    if (list.isEmpty) return list;
    if (_bytesLookLikeWebp(list)) {
      if (list.length <= memberPhotoMaxUploadBytes) return list;
      return compressWebpUnderMaxBytes(list);
    }
    if (kIsWeb) {
      return compressMemberProfileForUploadIsolate(list);
    }
    return compute(compressMemberProfileForUploadIsolate, list);
  }

  /// Comprime em JPEG até o tamanho ficar em torno de [maxBytes] (várias passadas).
  static Future<Uint8List> compressImageUnderMaxBytes(
    Uint8List list, {
    int maxBytes = memberPhotoMaxUploadBytes,
  }) async {
    if (list.isEmpty) return list;
    Uint8List current = list;
    var quality = 78;
    var minSide = 1600;
    for (var i = 0; i < 22; i++) {
      if (current.length <= maxBytes) return current;
      try {
        final next = await FlutterImageCompress.compressWithList(
          current,
          minWidth: minSide,
          minHeight: minSide,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (next.isEmpty) break;
        current = Uint8List.fromList(next);
        if (current.length <= maxBytes) return current;
      } catch (_) {
        break;
      }
      quality = (quality - 5).clamp(25, 95);
      if (quality <= 32) {
        minSide = (minSide * 9 ~/ 10).clamp(400, 2000);
      }
    }
    return current;
  }

  /// Patrimônio: WebP 80% antes do upload (paralelo no painel); boa nitidez em etiquetas/texto.
  static const int kPatrimonioWebpQuality = 80;

  static Future<Uint8List> compressPatrimonioPhotoForUpload(Uint8List list) async {
    if (list.isEmpty) return list;
    try {
      final result = await FlutterImageCompress.compressWithList(
        list,
        minWidth: 2400,
        minHeight: 2400,
        quality: kPatrimonioWebpQuality,
        format: CompressFormat.webp,
      );
      if (result.isNotEmpty) return Uint8List.fromList(result);
    } catch (_) {}
    try {
      final result = await FlutterImageCompress.compressWithList(
        list,
        quality: kPatrimonioWebpQuality,
        format: CompressFormat.webp,
      );
      if (result.isNotEmpty) return Uint8List.fromList(result);
    } catch (_) {}
    return list;
  }

  /// Compressao padrao para uploads de fotos.
  static Future<Uint8List> compressImage(
    Uint8List list, {
    int minWidth = _fallbackMinWidth,
    int minHeight = _fallbackMinHeight,
    int quality = _fallbackQuality,
  }) async {
    if (list.isEmpty) return list;
    try {
      final result = await FlutterImageCompress.compressWithList(
        list,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty) {
        return Uint8List.fromList(result);
      }
    } catch (_) {}
    return list;
  }

  /// Retorna bytes de imagem com cache local e fallback para a logo do sistema.
  static Future<Uint8List> getBytesFromUrl(
    String? url, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return _fallbackLogoBytes();
    try {
      final file =
          await YahwehCacheManagers.images.getSingleFile(u).timeout(timeout);
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {}
    return _fallbackLogoBytes();
  }

  /// Igual a [getBytesFromUrl], mas **sem** substituir por logo (PDF/carteirinha: omitir foto se falhar).
  static Future<Uint8List?> getBytesFromUrlOrNull(
    String? url, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    try {
      final file =
          await YahwehCacheManagers.images.getSingleFile(u).timeout(timeout);
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {}
    return null;
  }

  static Future<Uint8List> _fallbackLogoBytes() async {
    final byteData = await rootBundle.load('assets/LOGO_GESTAO_YAHWEH.png');
    return byteData.buffer.asUint8List();
  }
}
