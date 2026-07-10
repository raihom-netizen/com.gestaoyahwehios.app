import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_modules_removed.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leitura de avisos activos — painel, carrossel e site público.
abstract final class ChurchAvisosLoadService {
  ChurchAvisosLoadService._();

  static const int kPanelCarouselLimit = 12;
  static const int kModuleListLimit = 80;

  static const List<String> _legacySubcollections = ['mural_avisos'];

  static final Map<
      String,
      ({
        List<ChurchAvisoItem> items,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 15);

  static String _churchId(String hint) {
    final raw = hint.trim();
    if (raw.isEmpty) return '';
    final mapped = TenantResolverService.mapLegacySeedToCanonical(raw);
    if (mapped != null && mapped.isNotEmpty) return mapped;
    if (RegExp(r'^igreja_[a-z0-9_]+$').hasMatch(raw)) return raw;
    return ChurchRepository.churchId(raw);
  }

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_avisos_active_$limit';

  static List<ChurchAvisoItem> _mapDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required DateTime now,
    int? max,
  }) {
    final out = docs
        .map(ChurchAvisoItem.fromDoc)
        .where((a) => ChurchAvisosService.isActive(a, now: now))
        .toList();
    if (max != null && out.length > max) {
      return out.sublist(0, max);
    }
    return out;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool ascending = false,
  }) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      final da = ta is Timestamp ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final db = tb is Timestamp ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return ascending ? da.compareTo(db) : db.compareTo(da);
    });
    return sorted;
  }

  static List<ChurchAvisoItem> sortItemsByDate(
    List<ChurchAvisoItem> items, {
    bool ascending = true,
  }) {
    final copy = List<ChurchAvisoItem>.from(items);
    copy.sort((a, b) {
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ascending ? da.compareTo(db) : db.compareTo(da);
    });
    return copy;
  }

  static Future<void> invalidate(String churchIdHint) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith('${churchId.trim()}_avisos'));
    for (final limit in [kPanelCarouselLimit, kModuleListLimit, 20, 60, 80]) {
      final key = cacheKey(churchId, limit);
      FirestoreReadResilience.forgetKey(key);
      FirestoreReadResilience.forgetKey('${key}_plain');
      FirestoreReadResilience.forgetKey('${key}_plain_retry');
      FirestoreReadResilience.forgetKey('${key}_legacy_mural_avisos');
      FirestoreReadResilience.forgetKey('${key}_legacy_mural_avisos_plain');
    }
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.avisos,
    );
  }

  /// Remove um aviso das caches RAM/Hive sem esperar rede.
  static void evictDocFromCaches(String churchIdHint, String docId) {
    final churchId = _churchId(churchIdHint);
    final id = docId.trim();
    if (churchId.isEmpty || id.isEmpty) return;

    for (final entry in _ram.entries.toList()) {
      if (!entry.key.startsWith('${churchId.trim()}_avisos')) continue;
      final filtered =
          entry.value.items.where((item) => item.id != id).toList();
      _ram[entry.key] = (items: filtered, at: DateTime.now());
    }
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterPublishedSorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      _sortByCreatedAt(
        ChurchModuleFirestoreListRead.filterPublishedFeedRecords(docs),
      );

  static Future<void> _ensureFirebaseForRead() async {
    await ensureFirebaseReadyForPanelRead();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryDocs({
    required String churchId,
    required int limit,
    bool forceServer = false,
  }) async {
    final cap = limit.clamp(20, 60);
    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.avisos(churchId),
      cacheKey: cacheKey(churchId, cap),
      limit: cap,
      forceServer: forceServer,
      orderByField: 'createdAt',
      orderDescending: true,
      legacyFallbackSubcollections: _legacySubcollections,
      sortDocs: _filterPublishedSorted,
    );
  }

  static Future<List<ChurchAvisoItem>> loadActive({
    required String churchIdHint,
    int limit = kPanelCarouselLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    if (!kChurchAvisosModuleEnabled) return const [];

    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    unawaited(
      ChurchAvisosService.purgeExpired(churchIdHint: churchId).catchError((_) {}),
    );

    final ramKey = cacheKey(churchId, limit);

    if (!forceRefresh && !forceServer) {
      final hit = _ram[ramKey];
      if (hit != null && DateTime.now().difference(hit.at) <= _ramTtl) {
        unawaited(_refreshInBackground(churchId: churchId, limit: limit, ramKey: ramKey));
        return hit.items.length > limit
            ? hit.items.sublist(0, limit)
            : hit.items;
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final now = DateTime.now();
        final items = _mapDocs(_filterPublishedSorted(mem.docs), now: now, max: limit);
        _putRam(ramKey, items);
        return items;
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.avisos,
        ).timeout(const Duration(seconds: 2));
        if (hive.isNotEmpty) {
          final docs = TenantModuleHiveCache.toQueryDocuments(hive);
          final published = _filterPublishedSorted(docs);
          if (published.isNotEmpty) {
            final now = DateTime.now();
            final items = _mapDocs(published, now: now, max: limit);
            _putRam(ramKey, items);
            unawaited(_refreshInBackground(
              churchId: churchId,
              limit: limit,
              ramKey: ramKey,
            ));
            return items;
          }
        }
      } catch (_) {}
    }

    try {
      await _ensureFirebaseForRead();
    } catch (_) {
      final hit = _ram[ramKey];
      if (hit != null) return hit.items;
      return const [];
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final docs = await FirestoreWebGuard.runWithWebRecovery(
        () => _queryDocs(
          churchId: churchId,
          limit: limit,
          forceServer: forceServer,
        ),
        maxAttempts: 4,
      ).timeout(ChurchPanelReadTimeouts.queryCap);

      final now = DateTime.now();
      final items = _mapDocs(docs, now: now, max: limit);
      _putRam(ramKey, items);
      unawaited(
        TenantModuleHiveCache.saveDocs(
          churchId,
          TenantModuleKeys.avisos,
          docs
              .map(
                (d) => <String, dynamic>{
                  'id': d.id,
                  'path': d.reference.path,
                  'data': d.data(),
                },
              )
              .toList(),
        ).catchError((_) {}),
      );
      return items;
    } catch (_) {
      final hit = _ram[ramKey];
      if (hit != null) return hit.items;
      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null && mem.docs.isNotEmpty) {
        final now = DateTime.now();
        return _mapDocs(_filterPublishedSorted(mem.docs), now: now, max: limit);
      }
      rethrow;
    }
  }

  static void _putRam(String key, List<ChurchAvisoItem> items) {
    if (items.isEmpty) return;
    _ram[key] = (items: List.from(items), at: DateTime.now());
  }

  /// Cache RAM imediato (UI sem esperar rede) — padrão Membros/Eventos.
  static List<ChurchAvisoItem>? peekRam(String churchIdHint, {int? limit}) {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return null;
    final lim = limit ?? kModuleListLimit;
    final hit = _ram[cacheKey(churchId, lim)];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) return null;
    final items = hit.items;
    if (limit != null && items.length > limit) {
      return items.sublist(0, limit);
    }
    return List.from(items);
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required int limit,
    required String ramKey,
  }) async {
    try {
      final items = await loadActive(
        churchIdHint: churchId,
        limit: limit,
        forceRefresh: true,
        forceServer: true,
      );
      if (items.isNotEmpty) _putRam(ramKey, items);
    } catch (_) {}
  }

  /// Web: polling — **proibido** `.snapshots()` (Firestore JS 12.x INTERNAL ASSERTION).
  static Stream<List<ChurchAvisoItem>> watchActive({
    required String churchIdHint,
    int limit = kPanelCarouselLimit,
  }) {
    return Stream<List<ChurchAvisoItem>>.multi((controller) async {
      Timer? timer;
      Future<void> emit({bool forceServer = false}) async {
        if (controller.isClosed) return;
        try {
          controller.add(
            await loadActive(
              churchIdHint: churchIdHint,
              limit: limit,
              forceRefresh: forceServer,
              forceServer: forceServer,
            ),
          );
        } catch (_) {}
      }

      await emit();
      timer = Timer.periodic(const Duration(seconds: 45), (_) => emit(forceServer: true));
      controller.onCancel = () => timer?.cancel();
    });
  }
}
