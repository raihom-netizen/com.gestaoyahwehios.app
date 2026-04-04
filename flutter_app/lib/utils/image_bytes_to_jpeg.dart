import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Converte/comprime para JPEG (melhor compatibilidade e caminho fixo `.jpg` no Storage).
Future<Uint8List> ensureJpegBytes(
  Uint8List raw, {
  int quality = 92,
  int? minWidth,
  int? minHeight,
}) async {
  if (raw.isEmpty) return raw;
  try {
    final out = await FlutterImageCompress.compressWithList(
      raw,
      quality: quality,
      format: CompressFormat.jpeg,
      minWidth: minWidth ?? 1920,
      minHeight: minHeight ?? 1080,
    );
    if (out.isNotEmpty) return Uint8List.fromList(out);
  } catch (e) {
    debugPrint('ensureJpegBytes: $e');
  }
  return raw;
}
