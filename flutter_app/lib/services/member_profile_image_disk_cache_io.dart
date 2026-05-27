import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/media_cache_preferences.dart';
import 'package:gestao_yahweh/services/yahweh_media_bytes_disk_cache.dart';

Future<Uint8List?> readMemberProfileImageDisk(String stableKey) async {
  if (kIsWeb || stableKey.isEmpty) return null;
  if (!await MediaCachePreferences.isMemberPhotoDiskCacheEnabled()) return null;
  return readYahwehMediaBytesDisk(stableKey);
}

Future<void> writeMemberProfileImageDisk(
  String stableKey,
  Uint8List bytes,
) async {
  if (kIsWeb || stableKey.isEmpty || bytes.length < 24) return;
  if (!await MediaCachePreferences.isMemberPhotoDiskCacheEnabled()) return;
  await writeYahwehMediaBytesDisk(stableKey, bytes);
}
