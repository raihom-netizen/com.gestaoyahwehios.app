import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Resultado resiliente da programação no painel (agenda + cultos fixos).
class PanelProgramacaoLoadOutcome {
  final List<Map<String, dynamic>> items;
  final bool fromStaleRamCache;
  final Object? error;

  const PanelProgramacaoLoadOutcome({
    required this.items,
    this.fromStaleRamCache = false,
    this.error,
  });

  bool get showSoftStaleHint => fromStaleRamCache && items.isNotEmpty;
  bool get showHardError => items.isEmpty && error != null;
}

/// Cache RAM + leituras Firestore cache-first (padrão Controle Total).
abstract final class PanelProgramacaoLoader {
  PanelProgramacaoLoader._();

  static final Map<String, _RamEntry> _ram = {};
  static const Duration _ramTtl = Duration(minutes: 12);

  static String _ramKey(String tenantId, int rangeDays) =>
      '${tenantId.trim()}|$rangeDays';

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
    _ram[_ramKey(tenantId, rangeDays)] = _RamEntry(
      List<Map<String, dynamic>>.from(items),
      DateTime.now(),
    );
  }

  /// Executa [loader] com token refresh, timeout, retries implícitos no Firestore e RAM stale.
  static Future<PanelProgramacaoLoadOutcome> loadResilient({
    required String tenantId,
    required int rangeDays,
    required Future<List<Map<String, dynamic>>> Function() loader,
  }) async {
    final stale = peekRam(tenantId, rangeDays);
    try {
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded();
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}
      final items = await loader().timeout(const Duration(seconds: 28));
      rememberRam(tenantId, rangeDays, items);
      return PanelProgramacaoLoadOutcome(items: items);
    } on TimeoutException catch (e) {
      return _outcomeOnFailure(stale, e);
    } catch (e) {
      return _outcomeOnFailure(stale, e);
    }
  }

  static PanelProgramacaoLoadOutcome _outcomeOnFailure(
    List<Map<String, dynamic>>? stale,
    Object error,
  ) {
    if (stale != null && stale.isNotEmpty) {
      return PanelProgramacaoLoadOutcome(
        items: stale,
        fromStaleRamCache: true,
        error: error,
      );
    }
    return PanelProgramacaoLoadOutcome(items: const [], error: error);
  }

  /// Query Firestore: cache → servidor (até 3 tentativas) → cache vazio.
  static Future<QuerySnapshot<Map<String, dynamic>>> queryCacheFirst(
    Query<Map<String, dynamic>> query, {
    Duration serverTimeout = const Duration(seconds: 18),
  }) async {
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
