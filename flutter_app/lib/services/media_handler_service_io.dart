import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/media_upload_limits.dart' show kStorageRulesMaxFeedImageBytes;

/// Mobile: picker → bytes → `compressWithList` → XFile em temp da app.
///
/// Paridade Web (putData). **Proibido:** `compressAndGetFile` / path efémero do Photo Picker.
Future<XFile> processPickedImage(
  XFile picked, {
  required int quality,
  required int minWidth,
  required int minHeight,
}) async {
  Uint8List raw;
  try {
    raw = await picked.readAsBytes();
  } catch (_) {
    raw = Uint8List(0);
  }
  if (raw.isEmpty) {
    throw StateError(
      'Não foi possível preparar a imagem. Escolha outra foto.',
    );
  }

  Uint8List out = raw;
  var compressed = false;
  try {
    final result = await FlutterImageCompress.compressWithList(
      raw,
      quality: quality.clamp(1, 100),
      minWidth: minWidth,
      minHeight: minHeight,
      format: CompressFormat.jpeg,
    );
    if (result.isNotEmpty) {
      out = Uint8List.fromList(result);
      compressed = true;
    }
  } catch (_) {
    // 1ª compressão falhou (ex.: HEIC/OOM) — nova tentativa mais agressiva
    // antes de aceitar enviar o ficheiro original sem compressão.
    try {
      final result = await FlutterImageCompress.compressWithList(
        raw,
        quality: 50,
        minWidth: (minWidth * 0.75).round(),
        minHeight: (minHeight * 0.75).round(),
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty) {
        out = Uint8List.fromList(result);
        compressed = true;
      }
    } catch (_) {}
  }

  // Nunca subir um ficheiro cru gigante em silêncio: se a compressão falhou
  // nas duas tentativas e o original excede o teto das regras do Storage,
  // falhar aqui com mensagem clara em vez de deixar o upload rejeitar depois.
  if (!compressed && out.length > kStorageRulesMaxFeedImageBytes) {
    final mb = (out.length / (1024 * 1024)).toStringAsFixed(1);
    throw StateError(
      'Não foi possível comprimir esta imagem e o ficheiro original é '
      'grande demais para enviar ($mb MB). Tente outra foto.',
    );
  }

  final dir = await getTemporaryDirectory();
  final targetPath = p.join(
    dir.path,
    'gy_${DateTime.now().millisecondsSinceEpoch}_processed.jpg',
  );
  await File(targetPath).writeAsBytes(out, flush: true);
  return XFile(targetPath, mimeType: 'image/jpeg');
}
