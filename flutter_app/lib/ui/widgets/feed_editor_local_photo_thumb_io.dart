import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';

Widget buildFeedEditorLocalPhotoThumbFromPath({
  required String path,
  required double size,
}) {
  if (path.trim().isEmpty) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey.shade300,
    );
  }
  return IosPublishImagePipeline.fileThumbnail(
    file: File(path),
    size: size,
  );
}
