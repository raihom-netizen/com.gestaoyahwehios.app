import 'package:image_picker/image_picker.dart';

/// Implementação web:
/// - o `image_picker` já recebe `maxWidth/maxHeight` e `imageQuality` no MediaHandlerService
/// - evitamos decode/encode via Dart para não aumentar demais o custo no build web
Future<XFile> processPickedImage(
  XFile picked, {
  required int quality,
  required int minWidth,
  required int minHeight,
}) async {
  return picked;
}
