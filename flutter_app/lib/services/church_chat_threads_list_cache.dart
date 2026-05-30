import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot leve de `chat_threads` para abrir a lista «Conversas» sem skeleton.
abstract final class ChurchChatThreadsListCache {
  ChurchChatThreadsListCache._();

  static const int _maxDocs = 120;

  static String _key(String tenantId, String uid) =>
      'church_chat_threads_list_v1_${tenantId.trim()}_$uid';

  static Map<String, dynamic> _serializeData(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);
    for (final field in ['lastMessageAt', 'updatedAt', 'createdAt']) {
      final v = out[field];
      if (v is Timestamp) {
        out['${field}Ms'] = v.millisecondsSinceEpoch;
        out.remove(field);
      }
    }
    return out;
  }

  static Map<String, dynamic> _deserializeData(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final field in ['lastMessageAt', 'updatedAt', 'createdAt']) {
      final ms = out['${field}Ms'];
      if (ms is num) {
        out[field] = Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
        out.remove('${field}Ms');
      }
    }
    return out;
  }

  static Future<void> saveFromSnapshot(
    String tenantId,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final tid = tenantId.trim();
    if (uid.isEmpty || tid.isEmpty || snap.docs.isEmpty) return;

    final rows = <Map<String, dynamic>>[];
    for (final doc in snap.docs.take(_maxDocs)) {
      rows.add({
        'id': doc.id,
        'data': _serializeData(doc.data()),
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(tid, uid), jsonEncode(rows));
    } catch (_) {}
  }

  static Future<QuerySnapshot<Map<String, dynamic>>?> loadSnapshot(
    String tenantId, {
    String? uid,
  }) async {
    final u = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final tid = tenantId.trim();
    if (u.isEmpty || tid.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(tid, u));
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw);
      if (list is! List || list.isEmpty) return null;
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = (e['id'] ?? '').toString().trim();
        final dataRaw = e['data'];
        if (id.isEmpty || dataRaw is! Map) continue;
        docs.add(
          _CachedChatThreadDoc(
            id: id,
            data: _deserializeData(Map<String, dynamic>.from(dataRaw)),
          ),
        );
      }
      if (docs.isEmpty) return null;
      return MergedFirestoreQuerySnapshot(docs);
    } catch (_) {
      return null;
    }
  }
}

/// Documento só-leitura reconstruído do disco (lista estável ao abrir o hub).
// ignore: subtype_of_sealed_class
class _CachedChatThreadDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _CachedChatThreadDoc({required this.id, required Map<String, dynamic> data})
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
  SnapshotMetadata get metadata => const _CachedSnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('cached chat thread doc has no reference');
}

class _CachedSnapshotMetadata implements SnapshotMetadata {
  const _CachedSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
