import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/feed_editor_media_service.dart';
import 'package:path_provider/path_provider.dart';

/// Garante ficheiro legível no disco antes do upload do Chat (Android Photo Picker).
abstract final class ChurchChatLocalFileService {
  ChurchChatLocalFileService._();

  static Future<String?> materializeXFile(
    XFile file, {
    String prefix = 'gy_chat',
    bool video = false,
  }) async {
    if (kIsWeb) {
      final p = file.path.trim();
      return p.isNotEmpty ? p : null;
    }
    if (video) {
      return FeedEditorMediaService.persistVideoXFileToTemp(
        file,
        prefix: prefix,
      );
    }
    return FeedEditorMediaService.persistXFileToTemp(file, prefix: prefix);
  }

  static Future<String?> materializePlatformFile(
    PlatformFile file, {
    String prefix = 'gy_chat',
  }) async {
    if (kIsWeb) {
      final p = file.path?.trim() ?? '';
      return p.isNotEmpty ? p : null;
    }
    final path = file.path?.trim() ?? '';
    if (path.isNotEmpty) {
      final f = File(path);
      if (await f.exists() && await f.length() > 0) return path;
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final name = file.name.trim();
      var ext = 'bin';
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) {
        ext = name.substring(dot + 1).toLowerCase();
      }
      final outPath =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final out = File(outPath);
      await out.writeAsBytes(bytes, flush: true);
      if (await out.length() > 0) return outPath;
    } catch (_) {}
    return null;
  }

  static Future<String?> materializeLocalPath(
    String path, {
    String prefix = 'gy_chat',
  }) async {
    if (kIsWeb) return path.trim().isNotEmpty ? path.trim() : null;
    final p = path.trim();
    if (p.isEmpty) return null;
    final f = File(p);
    if (await f.exists() && await f.length() > 0) return p;
    return null;
  }
}
