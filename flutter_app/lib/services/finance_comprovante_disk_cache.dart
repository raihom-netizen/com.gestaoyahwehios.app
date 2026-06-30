import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cache em disco para PDFs de comprovantes financeiros — abertura instantânea na 2.ª vez.
abstract final class FinanceComprovanteDiskCache {
  FinanceComprovanteDiskCache._();

  static const Duration _ttl = Duration(days: 30);
  static const int _maxRamEntries = 24;

  static final Map<String, _RamHit> _ram = {};

  static String keyFor({required String storagePath, String url = ''}) {
    final raw = storagePath.trim().isNotEmpty
        ? storagePath.trim()
        : url.trim();
    return sha256.convert(raw.codeUnits).toString();
  }

  static Future<Uint8List?> getBytes(String cacheKey) async {
    final k = cacheKey.trim();
    if (k.isEmpty) return null;

    final hit = _ram[k];
    if (hit != null && !hit.isExpired) return hit.bytes;

    if (kIsWeb) return null;
    final file = await _fileFor(k);
    if (!await file.exists()) return null;
    try {
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > _ttl) {
        await file.delete().catchError((_) => file);
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      _putRam(k, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> putBytes(String cacheKey, Uint8List bytes) async {
    final k = cacheKey.trim();
    if (k.isEmpty || bytes.isEmpty) return;
    _putRam(k, bytes);
    if (kIsWeb) return;
    try {
      final file = await _fileFor(k);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  static void _putRam(String key, Uint8List bytes) {
    if (_ram.length >= _maxRamEntries) {
      _ram.remove(_ram.keys.first);
    }
    _ram[key] = _RamHit(bytes: bytes, at: DateTime.now());
  }

  static Future<File> _fileFor(String cacheKey) async {
    final dir = await getTemporaryDirectory();
    return File(p.join(dir.path, 'finance_pdf_cache', '$cacheKey.bin'));
  }
}

class _RamHit {
  _RamHit({required this.bytes, required this.at});

  final Uint8List bytes;
  final DateTime at;

  bool get isExpired =>
      DateTime.now().difference(at) > FinanceComprovanteDiskCache._ttl;
}
