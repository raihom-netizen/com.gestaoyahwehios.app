import 'dart:io' show File;

import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/core/yahweh_heavy_work.dart';

/// Leitura segura — limite de tamanho + isolate (evita OOM na UI).
Future<List<int>> churchChatReadFileBytes(String path) async {
  final f = File(path);
  if (!await f.exists()) return <int>[];
  final len = await f.length();
  if (len > SafeImageBytes.maxRawReadBytes) {
    throw StateError(
      'Ficheiro demasiado grande (${len ~/ (1024 * 1024)} MB). '
      'Para fotos use o fluxo de compressão do chat.',
    );
  }
  return YahwehHeavyWork.readFileBytes(path);
}

Future<void> churchChatDeleteFileQuiet(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
