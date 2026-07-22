import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Igreja leve para o Painel Master (Lista Igrejas).
class MasterChurchListItem {
  const MasterChurchListItem({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  factory MasterChurchListItem.fromMap(String id, Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    if (!map.containsKey('nome') && map.containsKey('name')) {
      map['nome'] = map['name'];
    }
    return MasterChurchListItem(id: id, data: map);
  }
}

abstract final class MasterChurchesListService {
  MasterChurchesListService._();

  static final _functions =
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '');

  static const _prefsKey = 'master_churches_index_v1';

  static List<MasterChurchListItem>? _memCache;
  static DateTime? _memCachedAt;
  static const Duration _memTtl = Duration(minutes: 10);

  static DocumentReference<Map<String, dynamic>> get _indexRef =>
      firebaseDefaultFirestore
          .collection('config')
          .doc('master_churches_index');

  /// Contagem instantânea para badge do header (sem await).
  static int peekCount() => _memCache?.length ?? 0;

  /// Lista em RAM — outras telas master reutilizam sem novo round-trip.
  static List<MasterChurchListItem>? peekMemory() => _memCache;

  static void invalidateMemory() {
    _memCache = null;
    _memCachedAt = null;
  }

  static void _storeMem(List<MasterChurchListItem> items) {
    if (items.isEmpty) return;
    _memCache = List<MasterChurchListItem>.unmodifiable(items);
    _memCachedAt = DateTime.now();
    unawaited(_persistLocal(items));
  }

  static Future<void> _persistLocal(List<MasterChurchListItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = items
          .take(200)
          .map((e) => <String, dynamic>{'id': e.id, 'data': e.data})
          .toList();
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (_) {}
  }

  /// Prefs locais — Master funciona offline (padrão CT).
  static Future<List<MasterChurchListItem>> readAnyLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <MasterChurchListItem>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = (m['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final dataRaw = m['data'];
        final data = dataRaw is Map
            ? Map<String, dynamic>.from(dataRaw)
            : (Map<String, dynamic>.from(m)..remove('id'));
        out.add(MasterChurchListItem.fromMap(id, data));
      }
      if (out.isNotEmpty) {
        _memCache = List<MasterChurchListItem>.unmodifiable(out);
        _memCachedAt = DateTime.now();
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static int _indexTotal(Map<String, dynamic>? raw) {
    if (raw == null) return 0;
    final t = raw['total'];
    if (t is num) return t.toInt();
    return int.tryParse('$t') ?? 0;
  }

  static List<MasterChurchListItem> _parseChurches(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return const [];
    final list = raw['churches'];
    if (list is! List) return const [];
    final out = <MasterChurchListItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      m.remove('id');
      out.add(MasterChurchListItem.fromMap(id, m));
    }
    return out;
  }

  static Future<List<MasterChurchListItem>> readFirestoreIndex({
    bool forceServer = false,
  }) async {
    Future<DocumentSnapshot<Map<String, dynamic>>> fetch(Source source) {
      return _indexRef
          .get(GetOptions(source: source))
          .timeout(Duration(seconds: forceServer ? 14 : 8));
    }

    if (!forceServer) {
      try {
        final cached = await fetch(Source.cache);
        final parsed = _parseChurches(cached.data());
        if (parsed.isNotEmpty) {
          _storeMem(parsed);
          return parsed;
        }
        final totalCached = _indexTotal(cached.data());
        if (totalCached > 0) {
          forceServer = true;
        }
      } catch (_) {}
    }

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => fetch(forceServer ? Source.server : Source.serverAndCache),
      );
      final parsed = _parseChurches(snap.data());
      if (parsed.isNotEmpty) {
        _storeMem(parsed);
        return parsed;
      }
      final total = _indexTotal(snap.data());
      if (total > 0 && !forceServer) {
        return readFirestoreIndex(forceServer: true);
      }
    } catch (_) {
      if (!forceServer) {
        return readFirestoreIndex(forceServer: true);
      }
    }
    return const [];
  }

  static Future<List<MasterChurchListItem>> warmFromCallable() async {
    try {
      final callable = _functions.httpsCallable(
        'getMasterChurchesList',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      final res = await FirestoreWebGuard.runWithWebRecovery(
        () => callable.call<Map<String, dynamic>>({}),
      );
      final data = res.data;
      final churches = data['churches'];
      if (churches is List) {
        final out = <MasterChurchListItem>[];
        for (final e in churches) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final id = (m['id'] ?? '').toString().trim();
          if (id.isEmpty) continue;
          m.remove('id');
          out.add(MasterChurchListItem.fromMap(id, m));
        }
        if (out.isNotEmpty) _storeMem(out);
        return out;
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('getMasterChurchesList: $e');
      }
    }
    return const [];
  }

  /// Índice → callable → query directa (servidor). Memória compartilhada entre telas.
  static Future<List<MasterChurchListItem>> loadFast({bool force = false}) async {
    if (force) invalidateMemory();

    if (!force &&
        _memCache != null &&
        _memCachedAt != null &&
        DateTime.now().difference(_memCachedAt!) < _memTtl) {
      return _memCache!;
    }

    // Offline: prefs → Firestore cache — sem bloquear.
    if (!AppConnectivityService.instance.isOnline) {
      final local = await readAnyLocal();
      if (local.isNotEmpty) return local;
      return readFirestoreIndex(forceServer: false);
    }

    await MasterAdminFirestore.ensureReady();

    if (!force) {
      final local = await readAnyLocal();
      if (local.isNotEmpty) {
        unawaited(() async {
          try {
            await readFirestoreIndex(forceServer: false);
          } catch (_) {}
        }());
        return local;
      }
    }

    // Após licença/bloqueio: ler documentos reais (índice pode estar defasado).
    if (force) {
      final direct = await _loadDirectFallback(forceServer: true);
      if (direct.isNotEmpty) return direct;
    }

    var indexed = await readFirestoreIndex(forceServer: force);
    if (indexed.isNotEmpty) return indexed;

    final warmed = await warmFromCallable();
    if (warmed.isNotEmpty) return warmed;

    indexed = await readFirestoreIndex(forceServer: true);
    if (indexed.isNotEmpty) return indexed;

    final direct = await _loadDirectFallback(forceServer: true);
    if (direct.isNotEmpty) return direct;

    return await _loadDirectFallback(forceServer: false);
  }

  static Future<List<MasterChurchListItem>> _loadDirectFallback({
    bool forceServer = false,
  }) async {
    return FirestoreWebGuard.runWithWebRecovery(() async {
      final db = firebaseDefaultFirestore;
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await db
            .collection('igrejas')
            .limit(80)
            .get(
              GetOptions(
                source: forceServer ? Source.server : Source.serverAndCache,
              ),
            )
            .timeout(const Duration(seconds: 14));
      } catch (_) {
        snap = await db
            .collection('igrejas')
            .limit(80)
            .get()
            .timeout(const Duration(seconds: 14));
      }
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final na = '${a.data()['nome'] ?? a.data()['name'] ?? a.id}'
              .toLowerCase();
          final nb = '${b.data()['nome'] ?? b.data()['name'] ?? b.id}'
              .toLowerCase();
          return na.compareTo(nb);
        });
      final out = docs
          .map((d) => MasterChurchListItem(id: d.id, data: d.data()))
          .toList();
      if (out.isNotEmpty) _storeMem(out);
      return out;
    });
  }
}

