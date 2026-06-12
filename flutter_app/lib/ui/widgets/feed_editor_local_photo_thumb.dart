import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'feed_editor_local_photo_thumb_stub.dart'
    if (dart.library.io) 'feed_editor_local_photo_thumb_io.dart';

/// Miniatura local no editor aviso/evento — Web usa bytes; mobile usa ficheiro.
Widget feedEditorLocalPhotoThumb({
  required Uint8List? webBytes,
  required String? mobilePath,
  required double size,
}) {
  if (webBytes != null) {
    return Image.memory(
      webBytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
  }
  return buildFeedEditorLocalPhotoThumbFromPath(
    path: mobilePath ?? '',
    size: size,
  );
}
