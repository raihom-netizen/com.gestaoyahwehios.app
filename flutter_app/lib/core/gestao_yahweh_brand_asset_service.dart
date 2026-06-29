import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:gestao_yahweh/ui/widgets/default_church_logo_asset.dart';

/// Bytes e paths únicos do escudo Gestão YAHWEH — PDF, push, notificações, share.
abstract final class GestaoYahwehBrandAssetService {
  GestaoYahwehBrandAssetService._();

  static Uint8List? _pngCache;

  static const List<String> _assetPaths = [
    kDefaultChurchLogoAssetPath,
    kGestaoYahwehBrandLogoAsset,
  ];

  /// PNG oficial para PDFs e payloads (memorizado em RAM).
  static Future<Uint8List> loadPngBytes() async {
    final hit = _pngCache;
    if (hit != null && hit.length > 32) return hit;
    for (final path in _assetPaths) {
      try {
        final data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List();
        if (bytes.length > 32) {
          _pngCache = bytes;
          return bytes;
        }
      } catch (_) {}
    }
    throw StateError('Logo Gestão YAHWEH ausente nos assets.');
  }

  static void invalidateCache() => _pngCache = null;
}
