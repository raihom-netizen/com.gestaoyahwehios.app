import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
  try {
    final compressed = await FlutterImageCompress.compressWithList(
      raw,
      quality: quality.clamp(1, 100),
      minWidth: minWidth,
      minHeight: minHeight,
      format: CompressFormat.jpeg,
    );
    if (compressed.isNotEmpty) {
      out = Uint8List.fromList(compressed);
    }
  } catch (_) {}

  final dir = await getTemporaryDirectory();
  final targetPath = p.join(
    dir.path,
    'gy_${DateTime.now().millisecondsSinceEpoch}_processed.jpg',
  );
  await File(targetPath).writeAsBytes(out, flush: true);
  return XFile(targetPath, mimeType: 'image/jpeg');
}
