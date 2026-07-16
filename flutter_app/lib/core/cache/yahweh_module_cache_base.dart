import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot genérico — docs + metadados de leitura (padrão WISDOMAPP cache-first).
class YahwehModuleLoadSnapshot {
  const YahwehModuleLoadSnapshot({
    required this.docs,
    required this.readSource,
    this.softError,
    this.fromCache = false,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String? softError;
  final bool fromCache;

  static const empty = YahwehModuleLoadSnapshot(docs: [], readSource: 'empty');
}

typedef YahwehModuleLoader = Future<YahwehModuleLoadSnapshot> Function(
  String churchId, {
  bool forceServer,
});

/// Base ChangeNotifier — RAM + SharedPreferences (Web/mobile) + dedupe `_inFlight`.
class YahwehModuleCacheBase extends ChangeNotifier {
  YahwehModuleCacheBase({
    required this.prefsKeyPrefix,
    required this.loader,
  });

  final String prefsKeyPrefix;
  final YahwehModuleLoader loader;

  String _churchId = '';
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];
  bool _refreshing = false;
  Future<void>? _inFlight;
  String _signature = '';
  String _readSource = '';
  String? _softError;

  String get churchId => _churchId;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
  String get readSource => _readSource;
  String? get softError => _softError;
  bool get isRefreshing => _refreshing;
  bool get showInitialLoading => _refreshing && _docs.isEmpty;

  String _prefsKey(String churchId) =>
      '${prefsKeyPrefix}_${churchId.trim()}_v1';

  String _signatureFor(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return 'empty';
    final buf = StringBuffer();
    for (final d in docs.take(64)) {
      buf.write(d.id);
      buf.write(':');
      buf.write((d.data()['updatedAt'] ?? d.data()['createdAt'] ?? '').toString());
      buf.write('|');
    }
    return buf.toString();
  }

  void _notifyIfChanged(String sig) {
    if (sig == _signature && !_refreshing) return;
    _signature = sig;
    notifyListeners();
  }

  /// Restaura JSON do disco — instantâneo antes da rede (Web + mobile).
  Future<void> warmUp(String churchId) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    _churchId = cid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(cid));
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List || list.isEmpty) return;
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final row in list) {
        if (row is! Map) continue;
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final dataRaw = row['data'];
        if (dataRaw is! Map) continue;
        docs.add(
          _CachedQueryDocumentSnapshot(
            id: id,
            data: Map<String, dynamic>.from(dataRaw),
          ),
        );
      }
      if (docs.isEmpty) return;
      _docs = docs;
      _readSource = 'prefs';
      _notifyIfChanged(_signatureFor(docs));
    } catch (_) {}
  }

  Future<void> ensureLoaded(
    String churchId, {
    bool forceServer = false,
  }) {
    if (_inFlight != null && !forceServer) return _inFlight!;
    _inFlight = _load(churchId, forceServer: forceServer)
        .whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<void> _load(String churchId, {required bool forceServer}) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    _churchId = cid;
    final hadLocal = _docs.isNotEmpty;
    if (!hadLocal) {
      _refreshing = true;
      _notifyIfChanged(_signature);
    }
    try {
      final snap = await loader(cid, forceServer: forceServer);
      _docs = snap.docs;
      _readSource = snap.readSource;
      _softError = snap.softError;
      if (snap.docs.isNotEmpty) {
        unawaited(_persist(cid, snap.docs));
      }
      _notifyIfChanged(_signatureFor(snap.docs));
    } catch (e) {
      _softError = e.toString();
      if (!hadLocal) _notifyIfChanged('error:$e');
    } finally {
      _refreshing = false;
      _notifyIfChanged(_signatureFor(_docs));
    }
  }

  Future<void> _persist(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = docs.take(120).map((d) {
        return <String, dynamic>{'id': d.id, 'data': d.data()};
      }).toList();
      await prefs.setString(_prefsKey(churchId), safeJsonEncode(payload));
    } catch (_) {}
  }

  void applyDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    String readSource = 'push',
  }) {
    if (docs.isEmpty) return;
    _docs = docs;
    _readSource = readSource;
    _notifyIfChanged(_signatureFor(docs));
    if (_churchId.isNotEmpty) {
      unawaited(_persist(_churchId, docs));
    }
  }

  void invalidate(String churchId) {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    if (_churchId == cid) {
      _docs = const [];
      _signature = '';
      _readSource = '';
      _softError = null;
      notifyListeners();
    }
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey(cid));
      } catch (_) {}
    }());
  }
}

/// Doc sintético para reidratar lista a partir de SharedPreferences.
class _CachedQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _CachedQueryDocumentSnapshot({required this.id, required Map<String, dynamic> data})
      : _data = Map<String, dynamic>.from(data);

  @override
  final String id;

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  SnapshotMetadata get metadata => const _CachedSnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('Cached snapshot has no live reference');

  @override
  bool get exists => true;

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  dynamic get(Object field) => _data[field];
}

class _CachedSnapshotMetadata implements SnapshotMetadata {
  const _CachedSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
