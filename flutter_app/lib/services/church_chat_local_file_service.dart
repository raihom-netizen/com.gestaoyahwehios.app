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
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final persisted = await _writeBytesToChatTemp(
        bytes,
        fileName: file.name,
        prefix: prefix,
      );
      if (persisted != null) return persisted;
    }
    final path = file.path?.trim() ?? '';
    if (path.isNotEmpty) {
      final f = File(path);
      if (await f.exists() && await f.length() > 0) {
        // Nunca confiar no cache efémero do file_picker — copiar para temp da app.
        return _copyPathToChatTemp(path, fileName: file.name, prefix: prefix);
      }
    }
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
    if (await f.exists() && await f.length() > 0) {
      return _copyPathToChatTemp(p, prefix: prefix);
    }
    return null;
  }

  static Future<String?> _writeBytesToChatTemp(
    List<int> bytes, {
    required String fileName,
    required String prefix,
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final dir = await getTemporaryDirectory();
      final ext = _extensionFromName(fileName);
      final outPath =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final out = File(outPath);
      await out.writeAsBytes(bytes, flush: true);
      if (await out.length() > 0) return outPath;
    } catch (_) {}
    return null;
  }

  static Future<String?> _copyPathToChatTemp(
    String sourcePath, {
    String? fileName,
    required String prefix,
  }) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists() || await src.length() <= 0) return null;
      final dir = await getTemporaryDirectory();
      final ext = _extensionFromName(fileName ?? sourcePath);
      final outPath =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await src.copy(outPath);
      final out = File(outPath);
      if (await out.exists() && await out.length() > 0) return outPath;
    } catch (_) {}
    return null;
  }

  static String _extensionFromName(String name) {
    final trimmed = name.trim();
    var ext = 'bin';
    final dot = trimmed.lastIndexOf('.');
    if (dot > 0 && dot < trimmed.length - 1) {
      ext = trimmed.substring(dot + 1).toLowerCase();
    } else if (trimmed.contains('.')) {
      ext = trimmed.split('.').last.toLowerCase();
    }
    return ext.isEmpty ? 'bin' : ext;
  }
}
