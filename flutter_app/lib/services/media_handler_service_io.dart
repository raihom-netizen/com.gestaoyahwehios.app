import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Implementação mobile: comprime a imagem com FlutterImageCompress (Full HD, qualidade 90).
Future<XFile> processPickedImage(
  XFile picked, {
  required int quality,
  required int minWidth,
  required int minHeight,
}) async {
  final dir = await getTemporaryDirectory();
  final targetPath = p.join(
    dir.path,
    '${DateTime.now().millisecondsSinceEpoch}_processed.jpg',
  );
  final result = await FlutterImageCompress.compressAndGetFile(
    picked.path,
    targetPath,
    quality: quality.clamp(1, 100),
    minWidth: minWidth,
    minHeight: minHeight,
  );
  if (result != null && File(result.path).existsSync()) {
    return XFile(result.path);
  }
  return picked;
}
