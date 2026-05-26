import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot JSON leve no disco — abre painel/site antes da rede (complementa Firestore offline).
abstract final class YahwehLocalSnapshotStore {
  YahwehLocalSnapshotStore._();

  static String _key(String tenantId, String bucket) =>
      'yahweh_snap_${tenantId.trim()}_$bucket';

  static Future<void> saveJsonList(
    String tenantId,
    String bucket,
    List<Map<String, dynamic>> items,
  ) async {
    if (tenantId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(items);
      if (encoded.length > 400000) return;
      await prefs.setString(_key(tenantId, bucket), encoded);
      await prefs.setInt(
        '${_key(tenantId, bucket)}_ts',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> readJsonList(
    String tenantId,
    String bucket, {
    Duration maxAge = const Duration(hours: 12),
  }) async {
    if (tenantId.trim().isEmpty) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('${_key(tenantId, bucket)}_ts');
      if (ts != null &&
          DateTime.now().millisecondsSinceEpoch - ts >
              maxAge.inMilliseconds) {
        return const [];
      }
      final raw = prefs.getString(_key(tenantId, bucket));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
