import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga pedidos de oração — `igrejas/{churchId}/pedidosOracao`.
class ChurchPedidosOracaoLoadResult {
  const ChurchPedidosOracaoLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collectionPath,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collectionPath;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica — Firestore `igrejas/{id}/pedidosOracao`.
abstract final class ChurchPedidosOracaoLoadService {
  ChurchPedidosOracaoLoadService._();

  static const int kDefaultLimit = 300;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

  static String _filterSuffix(bool? respondidaFilter) {
    if (respondidaFilter == true) return 'respondidas';
    if (respondidaFilter == false) return 'pendentes';
    return 'all';
  }

  static String cacheKey(String churchId, bool? respondidaFilter, int limit) =>
      '${churchId.trim()}_pedidos_oracao_${_filterSuffix(respondidaFilter)}_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    bool? respondidaFilter,
    int limit = kDefaultLimit,
  }) {
    final key = cacheKey(_resolve(seedTenantId), respondidaFilter, limit);
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void _putRam(
    String key,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return;
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static DateTime? _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _createdAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _createdAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterRespondida(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool? respondidaFilter,
  ) {
    if (respondidaFilter == null) return docs;
    return docs.where((d) {
      final r = d.data()['respondida'];
      return respondidaFilter ? r == true : r == false;
    }).toList();
  }

  static Future<ChurchPedidosOracaoLoadResult> load({
    required String seedTenantId,
    bool? respondidaFilter,
    int limit = kDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchPedidosOracaoLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'pedidosOracao',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/pedidosOracao';
    final ramKey = cacheKey(churchId, respondidaFilter, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = peekRam(churchId, respondidaFilter: respondidaFilter, limit: limit);
      if (ramHit != null && ramHit.isNotEmpty) {
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final docs = _sortByCreatedAt(mem.docs);
        _putRam(ramKey, docs);
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
        );
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.pedidosOracao,
        ).timeout(const Duration(seconds: 4));
        if (hive.isNotEmpty) {
          var docs = _filterRespondida(
            TenantModuleHiveCache.toQueryDocuments(hive),
            respondidaFilter,
          );
          docs = _sortByCreatedAt(docs);
          if (docs.isNotEmpty) {
            _putRam(ramKey, docs);
            return ChurchPedidosOracaoLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        respondidaFilter: respondidaFilter,
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: limit,
      );
      if (docs.isNotEmpty) {
        _putRam(ramKey, docs);
        unawaited(_persistHive(churchId, docs, respondidaFilter));
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: forceServer ? 'server' : 'firestore_full',
          collectionPath: path,
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'pedidosOracao',
        moduleLabel: 'Pedidos de Oração',
        limit: limit,
        cacheKey: ramKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        var docs = _filterRespondida(snap.docs, respondidaFilter);
        docs = _sortByCreatedAt(docs);
        if (docs.isNotEmpty) {
          _putRam(ramKey, docs);
          unawaited(_persistHive(churchId, docs, respondidaFilter));
          return ChurchPedidosOracaoLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'direct_list',
            collectionPath: path,
          );
        }
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchPedidosOracaoLoadResult(
        churchId: churchId,
        docs: _sortByCreatedAt(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        softError: lastError?.toString(),
      );
    }

    return ChurchPedidosOracaoLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar pedidos de oração.'
          : lastError?.toString(),
    );
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool? respondidaFilter,
  ) async {
    if (respondidaFilter != null) return;
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.pedidosOracao,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required String churchId,
    required bool? respondidaFilter,
    required String cacheKey,
    required bool forceServer,
    required int limit,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final col = ChurchUiCollections.pedidosOracao(churchId);

    Query<Map<String, dynamic>> ordered() {
      if (respondidaFilter == true) {
        return col
            .where('respondida', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(limit);
      }
      if (respondidaFilter == false) {
        return col
            .where('respondida', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .limit(limit);
      }
      return col.orderBy('createdAt', descending: true).limit(limit);
    }

    if (!forceServer) {
      try {
        final cacheSnap = await ordered()
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByCreatedAt(cacheSnap.docs);
        }
      } catch (_) {}
    }

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
      try {
        return await FirestoreReadResilience.getQuery(
          ordered(),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      } catch (_) {
        final plain = await FirestoreReadResilience.getQuery(
          col.limit(limit),
          cacheKey: '${cacheKey}_plain',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        final filtered = _filterRespondida(plain.docs, respondidaFilter);
        return MergedFirestoreQuerySnapshot(_sortByCreatedAt(filtered));
      }
    }

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);

    return _sortByCreatedAt(snap.docs);
  }

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.pedidosOracao,
    );
  }
}
