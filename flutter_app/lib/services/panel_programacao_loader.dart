import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Resultado resiliente da programação no painel (agenda + cultos fixos).
class PanelProgramacaoLoadOutcome {
  final List<Map<String, dynamic>> items;
  final bool fromStaleRamCache;
  final bool fromDiskCache;
  final Object? error;

  const PanelProgramacaoLoadOutcome({
    required this.items,
    this.fromStaleRamCache = false,
    this.fromDiskCache = false,
    this.error,
  });

  bool get showSoftStaleHint =>
      (fromStaleRamCache || fromDiskCache) && items.isNotEmpty;
  bool get showHardError => items.isEmpty && error != null;
}

/// Cache RAM + disco + leituras Firestore cache-first (padrão Controle Total).
abstract final class PanelProgramacaoLoader {
  PanelProgramacaoLoader._();

  static final Map<String, _RamEntry> _ram = {};
  static const Duration _ramTtl = Duration(minutes: 12);
  static const Duration _diskMaxAge = Duration(days: 7);

  static String _ramKey(String tenantId, int rangeDays) =>
      '${ChurchPanelTenant.resolve(tenantId)}|$rangeDays';

  static String _diskBucket(int rangeDays) => 'panel_programacao_$rangeDays';

  static List<Map<String, dynamic>>? peekRam(String tenantId, int rangeDays) {
    final e = _ram[_ramKey(tenantId, rangeDays)];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _ramTtl) return null;
    return List<Map<String, dynamic>>.from(e.items);
  }

  static void rememberRam(
    String tenantId,
    int rangeDays,
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) return;
    final copy = items.map(_deserializeForUi).toList();
    _ram[_ramKey(tenantId, rangeDays)] = _RamEntry(
      List<Map<String, dynamic>>.from(copy),
      DateTime.now(),
    );
    unawaited(_persistDisk(tenantId, rangeDays, copy));
  }

  /// Hidrata RAM a partir do disco — 1.º frame do painel sem skeleton longo.
  static Future<void> hydrateRamFromDisk(String tenantId, int rangeDays) async {
    if (peekRam(tenantId, rangeDays) != null) return;
    final disk = await readDisk(tenantId, rangeDays);
    if (disk.isEmpty) return;
    _ram[_ramKey(tenantId, rangeDays)] = _RamEntry(
      List<Map<String, dynamic>>.from(disk),
      DateTime.now(),
    );
  }

  static Future<List<Map<String, dynamic>>> readDisk(
    String tenantId,
    int rangeDays,
  ) async {
    final raw = await YahwehLocalSnapshotStore.readJsonList(
      tenantId,
      _diskBucket(rangeDays),
      maxAge: _diskMaxAge,
    );
    if (raw.isEmpty) return const [];
    return raw.map(_deserializeForUi).toList();
  }

  static Future<void> _persistDisk(
    String tenantId,
    int rangeDays,
    List<Map<String, dynamic>> items,
  ) async {
    final serial = items.map(_serializeForDisk).toList();
    await YahwehLocalSnapshotStore.saveJsonList(
      tenantId,
      _diskBucket(rangeDays),
      serial,
    );
  }

  static Map<String, dynamic> _serializeForDisk(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    copy.remove('_doc');
    final st = copy['startAt'];
    if (st is Timestamp) {
      copy['startAtMs'] = st.millisecondsSinceEpoch;
      copy.remove('startAt');
    }
    return copy;
  }

  static Map<String, dynamic> _deserializeForUi(Map<String, dynamic> m) {
    final copy = Map<String, dynamic>.from(m);
    final ms = copy.remove('startAtMs');
    if (ms is num && !copy.containsKey('startAt')) {
      copy['startAt'] = Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
    }
    return copy;
  }

  /// Executa [loader] com bootstrap CT, timeout generoso, RAM/disco stale — sem cartão vermelho à toa.
  static Future<PanelProgramacaoLoadOutcome> loadResilient({
    required String tenantId,
    required int rangeDays,
    required Future<List<Map<String, dynamic>>> Function() loader,
  }) async {
    final tid = ChurchPanelTenant.resolve(tenantId);
    final staleRam = peekRam(tid, rangeDays);
    final staleDisk = staleRam == null ? await readDisk(tid, rangeDays) : null;

    try {
      await ensureFirebaseReadyForPanelRead().catchError((_) {});
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded().catchError((_) {});
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      List<Map<String, dynamic>> items = const [];
      try {
        items = await loader().timeout(const Duration(seconds: 42));
      } catch (_) {}
      if (items.isNotEmpty) {
        rememberRam(tid, rangeDays, items);
        return PanelProgramacaoLoadOutcome(items: items);
      }
      return _outcomeOnFailure(staleRam, staleDisk, null);
    } on TimeoutException catch (e) {
      return _outcomeOnFailure(staleRam, staleDisk, e);
    } catch (e) {
      return _outcomeOnFailure(staleRam, staleDisk, e);
    }
  }

  static PanelProgramacaoLoadOutcome _outcomeOnFailure(
    List<Map<String, dynamic>>? staleRam,
    List<Map<String, dynamic>>? staleDisk,
    Object? error,
  ) {
    if (staleRam != null && staleRam.isNotEmpty) {
      return PanelProgramacaoLoadOutcome(
        items: staleRam,
        fromStaleRamCache: true,
        error: error,
      );
    }
    if (staleDisk != null && staleDisk.isNotEmpty) {
      return PanelProgramacaoLoadOutcome(
        items: staleDisk,
        fromDiskCache: true,
        error: error,
      );
    }
    if (error != null) {
      return PanelProgramacaoLoadOutcome(items: const [], error: error);
    }
    return const PanelProgramacaoLoadOutcome(items: []);
  }

  /// Query Firestore: cache → servidor (FirestoreReadResilience no caminho crítico).
  static Future<QuerySnapshot<Map<String, dynamic>>> queryCacheFirst(
    Query<Map<String, dynamic>> query, {
    String? cacheKey,
    Duration serverTimeout = const Duration(seconds: 18),
  }) async {
    if (cacheKey != null && cacheKey.trim().isNotEmpty) {
      try {
        return await FirestoreReadResilience.getQuery(
          query,
          cacheKey: cacheKey.trim(),
          maxAttempts: 4,
          attemptTimeout: serverTimeout,
        );
      } catch (_) {}
    }

    QuerySnapshot<Map<String, dynamic>>? cached;
    try {
      cached = await query
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 6));
      if (cached.docs.isNotEmpty) {
        unawaited(_serverRefresh(query, serverTimeout));
        return cached;
      }
    } catch (_) {}

    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await query.get().timeout(serverTimeout);
      } catch (e) {
        last = e;
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    }

    if (cached != null) return cached;
    try {
      return await query.get(const GetOptions(source: Source.cache));
    } catch (_) {
      if (last != null && FirestoreStreamUtils.isPermissionDenied(last)) {
        return const MergedFirestoreQuerySnapshot([]);
      }
      if (last != null) throw last!;
      return const MergedFirestoreQuerySnapshot([]);
    }
  }

  static Future<void> _serverRefresh(
    Query<Map<String, dynamic>> query,
    Duration timeout,
  ) async {
    try {
      await query.get().timeout(timeout);
    } catch (_) {}
  }
}

class _RamEntry {
  final List<Map<String, dynamic>> items;
  final DateTime at;
  const _RamEntry(this.items, this.at);
}
