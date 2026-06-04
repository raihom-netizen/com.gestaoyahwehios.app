import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// Mídia compatível com **Flutter Web** — nunca depender de `dart:io` [File] na UI.
///
/// - Seleção: [XFile] (`image_picker`, `file_picker` com `withData: true` na web).
/// - Upload: `readAsBytes()` → `putData` / [StorageService.uploadBytes].
abstract final class WebSafeMedia {
  WebSafeMedia._();

  /// Lê bytes do picker — funciona em Android, iOS e Web.
  static Future<Uint8List> readBytes(XFile file) => file.readAsBytes();

  /// Preferir bytes em cache (preview instantâneo); senão [XFile].
  static Future<Uint8List> resolveBytes({
    XFile? file,
    Uint8List? cachedBytes,
  }) async {
    if (cachedBytes != null && cachedBytes.isNotEmpty) return cachedBytes;
    if (file != null) return file.readAsBytes();
    throw StateError(
      'WebSafeMedia: forneça XFile ou Uint8List (obrigatório na Web).',
    );
  }

  /// `true` quando o upload deve usar `putData` (sempre na Web).
  static bool get usePutDataOnly => kIsWeb;
}
