import 'package:flutter/material.dart';

Widget buildFeedEditorLocalPhotoThumbFromPath({
  required String path,
  required double size,
}) {
  return Container(
    width: size,
    height: size,
    color: Colors.grey.shade300,
    child: Icon(Icons.image_outlined, size: size * 0.35, color: Colors.grey.shade600),
  );
}
