import 'package:flutter/material.dart';

/// Web / sem filesystem local.
Future<String?> materializeTdlibLocalPath({
  String? path,
  List<int>? bytes,
  String fileName = 'anexo.bin',
}) async {
  final p = (path ?? '').trim();
  return p.isEmpty ? null : p;
}

bool tdlibLocalPhotoExists(String? path) => false;

Widget? tdlibCircleAvatarFromLocalPath({
  required String? path,
  required double radius,
  required Color backgroundColor,
}) =>
    null;
