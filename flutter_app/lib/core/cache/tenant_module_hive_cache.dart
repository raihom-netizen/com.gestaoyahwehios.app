import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_incremental_sync.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Banco local Hive — snapshots JSON por tenant/módulo (sobrevive a reinício).
abstract final class TenantModuleHiveCache {
  TenantModuleHiveCache._();

  static const _boxName = 'yahweh_tenant_modules_v1';
  static Box<String>? _box;

  static Future<void> init() async {
    if (kIsWeb) return;
    if (_box != null || Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
      return;
    }
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  static String _dataKey(String tenantId, String module) =>
      'd_${tenantId.trim()}_$module';

  static String _tsKey(String tenantId, String module) =>
      't_${tenantId.trim()}_$module';

  static Future<List<Map<String, dynamic>>> readDocs(
    String tenantId,
    String module, {
    Duration maxAge = const Duration(days: 30),
  }) async {
    if (kIsWeb) return const [];
    final tid = tenantId.trim();
    if (tid.isEmpty) return const [];
    await init();
    final box = _box;
    if (box == null) return const [];
    try {
      final ts = box.get(_tsKey(tid, module));
      if (ts != null) {
        final ms = int.tryParse(ts);
        if (ms != null &&
            DateTime.now().millisecondsSinceEpoch - ms >
                maxAge.inMilliseconds) {
          return const [];
        }
      }
      final raw = box.get(_dataKey(tid, module));
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

  static Future<DateTime?> readUpdatedAt(String tenantId, String module) async {
    if (kIsWeb) return null;
    await init();
    final ts = _box?.get(_tsKey(tenantId.trim(), module));
    if (ts == null) return null;
    final ms = int.tryParse(ts);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> saveDocs(
    String tenantId,
    String module,
    List<Map<String, dynamic>> docs,
  ) async {
    if (kIsWeb) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    await init();
    final box = _box;
    if (box == null) return;
    try {
      final encoded = jsonEncode(docs);
      if (encoded.length > 2000000) return;
      await box.put(_dataKey(tid, module), encoded);
      await box.put(
        _tsKey(tid, module),
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      await YahwehIncrementalSync.markSyncedNow(tid, module);
    } catch (_) {}
  }

  static Future<void> saveFromQuerySnapshot(
    String tenantId,
    String module,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final rows = snap.docs
        .map(
          (d) => <String, dynamic>{
            'id': d.id,
            'path': d.reference.path,
            'data': d.data(),
          },
        )
        .toList();
    await saveDocs(tenantId, module, rows);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> toQueryDocuments(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final row in rows) {
      final path = (row['path'] ?? '').toString();
      final id = (row['id'] ?? '').toString();
      final dataRaw = row['data'];
      if (path.isEmpty || dataRaw is! Map) continue;
      final ref = firebaseDefaultFirestore.doc(path);
      out.add(
        _HiveMapQueryDocumentSnapshot(
          reference: ref,
          docId: id.isEmpty ? ref.id : id,
          data: Map<String, dynamic>.from(dataRaw),
        ),
      );
    }
    return out;
  }

  static Future<void> clearModule(String tenantId, String module) async {
    if (kIsWeb) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    await init();
    final box = _box;
    if (box == null) return;
    try {
      await box.delete(_dataKey(tid, module));
      await box.delete(_tsKey(tid, module));
    } catch (_) {}
  }

  static Future<DateTime?> latestSyncForTenant(String tenantId) async {
    DateTime? latest;
    for (final mod in TenantModuleKeys.preloadOrder) {
      final t = await readUpdatedAt(tenantId, mod);
      if (t == null) continue;
      if (latest == null || t.isAfter(latest)) latest = t;
    }
    return latest;
  }
}

// ignore: subtype_of_sealed_class — snapshot Hive só para paint instantâneo.
class _HiveMapQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _HiveMapQueryDocumentSnapshot({
    required this.reference,
    required this.docId,
    required Map<String, dynamic> data,
  }) : _data = data;

  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final String docId;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  bool get exists => true;

  @override
  String get id => docId;

  @override
  SnapshotMetadata get metadata => const _HiveSnapshotMetadata();
}

class _HiveSnapshotMetadata implements SnapshotMetadata {
  const _HiveSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
