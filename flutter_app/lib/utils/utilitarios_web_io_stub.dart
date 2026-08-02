import 'dart:typed_data';

/// Stub: compartilhamento/download web (plataformas nativas).
Future<bool> utilitariosWebShareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async =>
    false;

void utilitariosWebDownloadFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {}
