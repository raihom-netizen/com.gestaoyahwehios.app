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

  /// Vídeo da galeria (Android Photo Picker): copia em stream para temp sem carregar tudo em RAM.
  static Future<String?> persistVideoXFileToTemp(
    XFile file, {
    String prefix = 'gy_video',
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
      final dir = await getTemporaryDirectory();
      final name = file.name.trim().toLowerCase();
      var ext = 'mp4';
      if (name.endsWith('.mov')) {
        ext = 'mov';
      } else if (name.endsWith('.m4v')) {
        ext = 'm4v';
      } else if (name.endsWith('.webm')) {
        ext = 'webm';
      }
      final outPath =
          '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final out = File(outPath);
      final sink = out.openWrite();
      await sink.addStream(file.openRead());
      await sink.close();
      if (await out.length() > 0) return outPath;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Garante ficheiro temporário legível no disco (iOS/Android).
  ///
  /// **Nunca** devolve o path efémero do Photo Picker — copia sempre para temp
  /// da app (URIs/content:// expiram antes do encode em avisos/eventos).
  static Future<String?> persistXFileToTemp(
    XFile file, {
    String prefix = 'gy_feed',
  }) async {
    if (kIsWeb) {
      final p = file.path.trim();
      return p.isNotEmpty ? p : null;
    }
    final dir = await getTemporaryDirectory();
    final ext = _extensionForXFile(file);
    final outPath =
        '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        final out = File(outPath);
        await out.writeAsBytes(bytes, flush: true);
        if (await out.length() > 0) return out.path;
      }
    } catch (_) {}

    try {
      final out = File(outPath);
      final sink = out.openWrite();
      await sink.addStream(file.openRead());
      await sink.close();
      if (await out.length() > 0) return out.path;
    } catch (_) {}

    try {
      final trimmed = file.path.trim();
      if (trimmed.isNotEmpty) {
        final src = File(trimmed);
        if (await src.exists() && await src.length() > 0) {
          await src.copy(outPath);
          if (File(outPath).existsSync() && File(outPath).lengthSync() > 0) {
            return outPath;
          }
        }
      }
    } catch (_) {}

    return null;
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
