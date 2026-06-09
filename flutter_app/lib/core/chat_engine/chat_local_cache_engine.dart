import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache offline — conversa abre instantâneo, sync em segundo plano.
abstract final class ChatLocalCacheEngine {
  ChatLocalCacheEngine._();

  static const int _maxMessages = 90;
  static const Duration _prefsTtl = Duration(days: 14);

  static String _moduleKey(String chatId) => 'chat_msgs_$chatId';

  static String _prefsKey(String churchId, String chatId) =>
      'chat_engine_cache_v2_${churchId.trim()}_$chatId';

  static Map<String, dynamic> _serialize(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    for (final f in ['createdAt', 'deliveredAt', 'updatedAt']) {
      final v = out[f];
      if (v is Timestamp) {
        out['${f}Ms'] = v.millisecondsSinceEpoch;
        out.remove(f);
      }
    }
    return out;
  }

  static Map<String, dynamic> _deserialize(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final f in ['createdAt', 'deliveredAt', 'updatedAt']) {
      final ms = out['${f}Ms'];
      if (ms is num) {
        out[f] = Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
        out.remove('${f}Ms');
      }
    }
    return out;
  }

  static Future<void> saveMessagesPage({
    required String churchId,
    required String chatId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) async {
    if (churchId.trim().isEmpty || chatId.trim().isEmpty || docs.isEmpty) {
      return;
    }
    final rows = docs.take(_maxMessages).map((d) {
      return {'id': d.id, 'data': _serialize(d.data())};
    }).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey(churchId, chatId),
        jsonEncode({
          'savedAtMs': DateTime.now().millisecondsSinceEpoch,
          'rows': rows,
        }),
      );
    } catch (_) {}
    try {
      await TenantModuleHiveCache.saveDocs(
        churchId,
        _moduleKey(chatId),
        rows
            .map((r) => {
                  'id': r['id'],
                  ...Map<String, dynamic>.from(r['data'] as Map),
                })
            .toList(),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadMessagesPage({
    required String churchId,
    required String chatId,
  }) async {
    final fromPrefs = await _loadFromPrefs(churchId, chatId);
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    final hiveRows = await TenantModuleHiveCache.readDocs(
      churchId,
      _moduleKey(chatId),
      maxAge: _prefsTtl,
    );
    if (hiveRows.isEmpty) return const [];
    return _docsFromRows(hiveRows);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>?>
      _loadFromPrefs(String churchId, String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(churchId, chatId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt = decoded['savedAtMs'];
      if (savedAt is num &&
          DateTime.now().millisecondsSinceEpoch - savedAt.toInt() >
              _prefsTtl.inMilliseconds) {
        return null;
      }
      final rows = decoded['rows'];
      if (rows is! List || rows.isEmpty) return null;
      final list = <Map<String, dynamic>>[];
      for (final e in rows) {
        if (e is! Map) continue;
        final id = (e['id'] ?? '').toString();
        final data = e['data'];
        if (id.isEmpty || data is! Map) continue;
        list.add({'id': id, ..._deserialize(Map<String, dynamic>.from(data))});
      }
      return _docsFromRows(list);
    } catch (_) {
      return null;
    }
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _docsFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final row in rows) {
      final id = (row['id'] ?? row['messageId'] ?? '').toString();
      if (id.isEmpty) continue;
      final data = Map<String, dynamic>.from(row)..remove('id');
      docs.add(_CachedChatMessageDoc(id: id, data: data));
    }
    return docs;
  }

  static Future<void> clearConversationLocal({
    required String churchId,
    required String chatId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey(churchId, chatId));
    } catch (_) {}
    try {
      await TenantModuleHiveCache.clearModule(churchId, _moduleKey(chatId));
    } catch (_) {}
  }
}

/// Documento reconstruído do cache local (offline-first).
// ignore: subtype_of_sealed_class
class _CachedChatMessageDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _CachedChatMessageDoc({required this.id, required Map<String, dynamic> data})
      : _data = data;

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  bool get exists => true;

  @override
  SnapshotMetadata get metadata => const _CachedMsgMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('cached message has no live reference');
}

class _CachedMsgMetadata implements SnapshotMetadata {
  const _CachedMsgMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
