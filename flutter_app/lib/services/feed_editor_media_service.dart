import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Fotos do editor de avisos/eventos — path válido no mobile (evita publish vazio / OOM).
abstract final class FeedEditorMediaService {
  FeedEditorMediaService._();

  static String _extensionForXFile(XFile file) {
    final name = file.name.trim().toLowerCase();
    if (name.endsWith('.webp')) return 'webp';
    if (name.endsWith('.png')) return 'png';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'jpg';
    if (name.endsWith('.jpeg') || name.endsWith('.jpg')) return 'jpg';
    return 'webp';
  }

  /// Garante ficheiro temporário legível no disco (iOS/Android).
  static Future<String?> persistXFileToTemp(
    XFile file, {
    String prefix = 'gy_feed',
  }) async {
    if (kIsWeb) {
      final p = file.path.trim();
      return p.isNotEmpty ? p : null;
    }
    final trimmed = file.path.trim();
    if (trimmed.isNotEmpty) {
      final f = File(trimmed);
      if (await f.exists() && await f.length() > 0) return trimmed;
    }
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final ext = _extensionForXFile(file);
      final outPath =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final out = File(outPath);
      await out.writeAsBytes(bytes, flush: true);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// Paths existentes no disco (mobile) antes do publish síncrono.
  static List<String> existingValidPaths(List<String> paths) {
    if (kIsWeb) return const [];
    final out = <String>[];
    for (final raw in paths) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      final f = File(p);
      if (f.existsSync() && f.lengthSync() > 0) out.add(p);
    }
    return out;
  }
}
