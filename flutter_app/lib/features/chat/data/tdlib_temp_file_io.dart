import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Garante um path local absoluto legível pelo TDLib (`inputFileLocal`).
Future<String?> materializeTdlibLocalPath({
  String? path,
  List<int>? bytes,
  String fileName = 'anexo.bin',
}) async {
  final p = (path ?? '').trim();
  if (p.isNotEmpty) {
    final f = File(p);
    if (await f.exists()) return f.absolute.path;
  }
  if (bytes == null || bytes.isEmpty) return null;
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
  final out = File(
    '${dir.path}/yh_tdlib_${DateTime.now().millisecondsSinceEpoch}_$safe',
  );
  await out.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  return out.absolute.path;
}

bool tdlibLocalPhotoExists(String? path) {
  final p = (path ?? '').trim();
  if (p.isEmpty) return false;
  try {
    return File(p).existsSync();
  } catch (_) {
    return false;
  }
}

Widget? tdlibCircleAvatarFromLocalPath({
  required String? path,
  required double radius,
  required Color backgroundColor,
}) {
  final p = (path ?? '').trim();
  if (!tdlibLocalPhotoExists(p)) return null;
  return CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: FileImage(File(p)),
  );
}
