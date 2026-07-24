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
    final dpr = WidgetsBinding.instance.platformDispatcher.views.isNotEmpty
        ? WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio
        : 2.0;
    final cache = (size * dpr).round().clamp(64, 720);
    return Image.memory(
      webBytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: cache,
      cacheHeight: cache,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
  }
  return buildFeedEditorLocalPhotoThumbFromPath(
    path: mobilePath ?? '',
    size: size,
  );
}
