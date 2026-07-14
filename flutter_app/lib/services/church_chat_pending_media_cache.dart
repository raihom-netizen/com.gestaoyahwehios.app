import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bytes de mídia do chat pendentes de envio — memória + disco (reenvio após fechar app).
abstract final class ChurchChatPendingMediaCache {
  ChurchChatPendingMediaCache._();

  static final Map<String, Uint8List> _memory = {};

  static String _key(String tenantId, String threadId, String localId) =>
      '${tenantId.trim()}|${threadId.trim()}|${localId.trim()}';

  static Future<Directory?> _dirFor(String localId) async {
    if (kIsWeb) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'chat_pending', localId.trim()));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> put({
    required String tenantId,
    required String threadId,
    required String localId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return;
    final key = _key(tenantId, threadId, localId);
    _memory[key] = bytes;
    final dir = await _dirFor(localId);
    if (dir == null) return;
    await File(p.join(dir.path, 'payload.bin')).writeAsBytes(bytes, flush: true);
  }

  static Future<Uint8List?> get({
    required String tenantId,
    required String threadId,
    required String localId,
  }) async {
    final key = _key(tenantId, threadId, localId);
    final mem = _memory[key];
    if (mem != null && mem.isNotEmpty) return mem;
    if (kIsWeb) return null;
    final dir = await _dirFor(localId);
    if (dir == null || !await dir.exists()) return null;
    final f = File(p.join(dir.path, 'payload.bin'));
    if (!await f.exists()) return null;
    try {
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) return null;
      _memory[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove({
    required String tenantId,
    required String threadId,
    required String localId,
  }) async {
    final key = _key(tenantId, threadId, localId);
    _memory.remove(key);
    if (kIsWeb) return;
    try {
      final dir = await _dirFor(localId);
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
