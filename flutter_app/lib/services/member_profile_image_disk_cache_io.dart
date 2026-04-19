import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:gestao_yahweh/core/media_cache_preferences.dart';

const _subDir = 'yahweh_member_profile_v1';
const _maxFileAge = Duration(days: 7);

String _fileNameForStableKey(String stableKey) {
  final digest = sha256.convert(utf8.encode(stableKey));
  return '${digest.toString()}.bin';
}

Future<Directory?> _dir() async {
  try {
    final base = await getApplicationCacheDirectory();
    final d = Directory(p.join(base.path, _subDir));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readMemberProfileImageDisk(String stableKey) async {
  if (kIsWeb || stableKey.isEmpty) return null;
  if (!await MediaCachePreferences.isMemberPhotoDiskCacheEnabled()) return null;
  try {
    final root = await _dir();
    if (root == null) return null;
    final f = File(p.join(root.path, _fileNameForStableKey(stableKey)));
    if (!await f.exists()) return null;
    final stat = await f.stat();
    if (DateTime.now().difference(stat.modified) > _maxFileAge) {
      try {
        await f.delete();
      } catch (_) {}
      return null;
    }
    final bytes = await f.readAsBytes();
    return bytes.length > 24 ? bytes : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeMemberProfileImageDisk(
    String stableKey, Uint8List bytes) async {
  if (kIsWeb || stableKey.isEmpty || bytes.length < 24) return;
  if (!await MediaCachePreferences.isMemberPhotoDiskCacheEnabled()) return;
  try {
    final root = await _dir();
    if (root == null) return;
    final f = File(p.join(root.path, _fileNameForStableKey(stableKey)));
    await f.writeAsBytes(bytes, flush: true);
  } catch (_) {}
}
