import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

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

  static List<MasterChurchListItem>? _memCache;
  static DateTime? _memCachedAt;
  static const Duration _memTtl = Duration(minutes: 10);

  static DocumentReference<Map<String, dynamic>> get _indexRef =>
      FirebaseFirestore.instance
          .collection('config')
          .doc('master_churches_index');

  /// Contagem instantÃ¢nea para badge do header (sem await).
  static int peekCount() => _memCache?.length ?? 0;

  /// Lista em RAM â€” outras telas master reutilizam sem novo round-trip.
  static List<MasterChurchListItem>? peekMemory() => _memCache;

  static void invalidateMemory() {
    _memCache = null;
    _memCachedAt = null;
  }

  static void _storeMem(List<MasterChurchListItem> items) {
    if (items.isEmpty) return;
    _memCache = List<MasterChurchListItem>.unmodifiable(items);
    _memCachedAt = DateTime.now();
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

  /// Ãndice â†’ callable â†’ query directa (servidor). MemÃ³ria compartilhada entre telas.
  static Future<List<MasterChurchListItem>> loadFast({bool force = false}) async {
    await MasterAdminFirestore.ensureReady();
    if (force) invalidateMemory();

    if (!force &&
        _memCache != null &&
        _memCachedAt != null &&
        DateTime.now().difference(_memCachedAt!) < _memTtl) {
      return _memCache!;
    }

    // ApÃ³s licenÃ§a/bloqueio: ler documentos reais (Ã­ndice pode estar defasado).
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
      final db = FirebaseFirestore.instance;
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

