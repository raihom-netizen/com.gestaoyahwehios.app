import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Fotos pendentes de publicação no mural (avisos/eventos) — memória + disco.
/// Permite pré-visualização instantânea e reenvio se o upload em background falhar.
abstract final class MuralPostPendingMediaCache {
  MuralPostPendingMediaCache._();

  static final Map<String, List<Uint8List>> _memory = {};

  static String _key(String tenantId, String postId) =>
      '${tenantId.trim()}|${postId.trim()}';

  static Future<Directory?> _dirFor(String postId) async {
    if (kIsWeb) return null;
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'mural_pending', postId.trim()));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> put({
    required String tenantId,
    required String postId,
    required List<Uint8List> images,
  }) async {
    if (images.isEmpty) return;
    final key = _key(tenantId, postId);
    _memory[key] = List<Uint8List>.from(images);
    final dir = await _dirFor(postId);
    if (dir == null) return;
    unawaited(_writeDisk(dir, images));
  }

  static Future<void> _writeDisk(Directory dir, List<Uint8List> images) async {
    for (var i = 0; i < images.length; i++) {
      try {
        await File(p.join(dir.path, '$i.bin')).writeAsBytes(images[i], flush: true);
      } catch (_) {}
    }
  }

  static Future<List<Uint8List>?> get({
    required String tenantId,
    required String postId,
  }) async {
    final key = _key(tenantId, postId);
    final mem = _memory[key];
    if (mem != null && mem.isNotEmpty) {
      return List<Uint8List>.from(mem);
    }
    if (kIsWeb) return null;
    final dir = await _dirFor(postId);
    if (dir == null || !await dir.exists()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.bin'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return null;
    final out = <Uint8List>[];
    for (final f in files) {
      out.add(await f.readAsBytes());
    }
    _memory[key] = out;
    return out;
  }

  static Future<void> remove({
    required String tenantId,
    required String postId,
  }) async {
    final key = _key(tenantId, postId);
    _memory.remove(key);
    if (kIsWeb) return;
    final dir = await _dirFor(postId);
    if (dir == null) return;
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
