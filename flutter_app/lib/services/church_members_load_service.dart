import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga de membros — `igrejas/{churchId}/membros`.
class ChurchMembersLoadResult {
  const ChurchMembersLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    required this.collectionPath,
    this.softError,
    this.fromCache = false,
    this.directoryEntries = const [],
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collectionPath;
  final String? softError;
  final bool fromCache;
  final List<MemberDirectoryEntry> directoryEntries;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty && directoryEntries.isEmpty;
  bool get hasHardError => softError != null && softError!.trim().isNotEmpty;
}

/// Carga canónica blindada — adapta-se ao Firestore actual (chaves UPPERCASE).
abstract final class ChurchMembersLoadService {
  ChurchMembersLoadService._();

  static const int kDefaultLimit = YahwehPerformanceV4.blindListPageSize;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String resolveChurchId(String hint) => _resolve(hint);

  static String cacheKey(String churchId, int limit) =>
      '${churchId.trim()}_membros_blind_$limit';

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId, {
    int limit = kDefaultLimit,
  }) =>
      _peekRam(_resolve(seedTenantId), limit);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRamAny(
    String seedTenantId,
  ) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;
    for (final limit in [120, kDefaultLimit, 80, 50, 30]) {
      final hit = _peekRam(churchId, limit);
      if (hit != null && hit.isNotEmpty) return hit;
    }
    final prefix = '${churchId}_membros_blind_';
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? best;
    for (final e in _ram.entries) {
      if (!e.key.startsWith(prefix) || e.value.docs.isEmpty) continue;
      if (best == null || e.value.docs.length > best.length) {
        best = e.value.docs;
      }
    }
    return best;
  }

  static Map<String, dynamic>? peekDocData(String seedTenantId, String docId) {
    final id = docId.trim();
    if (id.isEmpty) return null;
    final docs = peekRamAny(seedTenantId);
    if (docs == null) return null;
    for (final d in docs) {
      if (d.id == id) {
        return BlindMemberDoc.fromFirestore(id: d.id, data: d.data())
            .toMemberDataMap();
      }
    }
    return null;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRam(
    String churchId,
    int limit,
  ) {
    if (churchId.isEmpty) return null;
    final key = cacheKey(churchId, limit);
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
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByName(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final na = BlindMemberDoc.fromFirestore(id: a.id, data: a.data())
          .displayName
          .toLowerCase();
      final nb = BlindMemberDoc.fromFirestore(id: b.id, data: b.data())
          .displayName
          .toLowerCase();
      return na.compareTo(nb);
    });
    return sorted;
  }

  static Future<ChurchMembersLoadResult> load({
    required String seedTenantId,
    int limit = kDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchMembersLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        collectionPath: 'membros',
        softError: 'Igreja não identificada.',
      );
    }

    final path = 'igrejas/$churchId/membros';
    final ramKey = cacheKey(churchId, limit);
    final reference = ChurchUiCollections.membros(churchId);
    final capped =
        FirebasePerformanceLimits.capListLimit('membros', limit);

    if (!forceRefresh && !forceServer) {
      try {
        var directory = await MembersDirectorySnapshotService.readOnce(churchId);
        if (!directory.hasEntries) {
          directory = await MembersDirectorySnapshotService
              .warmFromCallableIfStale(churchId);
        }
        if (directory.hasEntries) {
          final merged = MembersDirectorySnapshotService.toMergedQuerySnapshot(
            churchId,
            directory,
          );
          final docs = _sortByName(
            merged.docs.take(capped).toList(),
          );
          _putRam(ramKey, docs);
          return ChurchMembersLoadResult(
            churchId: churchId,
            docs: docs,
            readSource: 'members_directory',
            collectionPath: path,
            fromCache: true,
            directoryEntries: directory.entries.take(capped).toList(),
          );
        }
      } catch (e, st) {
        debugPrint('ChurchMembersLoadService directory: $e\n$st');
      }

      final anyRam = peekRamAny(churchId);
      if (anyRam != null && anyRam.isNotEmpty) {
        final docs = _sortByName(anyRam);
        _putRam(ramKey, docs);
        unawaited(_refreshInBackground(
          churchId: churchId,
          ramKey: ramKey,
          limit: capped,
          reference: reference,
        ));
        return ChurchMembersLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'ram_any',
          collectionPath: path,
          fromCache: true,
        );
      }

      final ramHit = _peekRam(churchId, limit);
      if (ramHit != null) {
        return ChurchMembersLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      }

      try {
        final updatedAt = await TenantModuleHiveCache.readUpdatedAt(
          churchId,
          TenantModuleKeys.membros,
        ).timeout(const Duration(seconds: 3));
        if (updatedAt != null) {
          final hive = await TenantModuleHiveCache.readDocs(
            churchId,
            TenantModuleKeys.membros,
          );
          final docs = _sortByName(TenantModuleHiveCache.toQueryDocuments(hive));
          if (ChurchModuleFirestoreListRead.shouldServeHiveCache(docs)) {
            _putRam(ramKey, docs);
            return ChurchMembersLoadResult(
              churchId: churchId,
              docs: docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: ramKey,
        forceServer: forceServer,
        limit: capped,
      );
      _putRam(ramKey, docs);
      unawaited(_persistHive(churchId, docs));
      return ChurchMembersLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: path,
      );
    } catch (e, st) {
      lastError = e;
      debugPrint('ChurchMembersLoadService firestore: $e\n$st');
    }

    try {
      final repo = await ChurchRepository.membros.listCacheFirst(
        churchIdHint: churchId,
        limit: capped,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        final docs = _sortByName(repo.items);
        _putRam(ramKey, docs);
        return ChurchMembersLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          fromCache: repo.error == null && docs.isNotEmpty,
          softError: repo.error,
        );
      }
    } catch (e, st) {
      lastError ??= e;
      debugPrint('ChurchMembersLoadService repository: $e\n$st');
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchMembersLoadResult(
        churchId: churchId,
        docs: _sortByName(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = peekRamAny(churchId) ?? _peekRam(churchId, limit);
    if (ramFallback != null) {
      return ChurchMembersLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchMembersLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      collectionPath: path,
      softError: _humanizeError(lastError),
    );
  }

  static String? _humanizeError(Object? e) {
    if (e == null) return null;
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar membros. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required String ramKey,
    required int limit,
    required CollectionReference<Map<String, dynamic>> reference,
  }) async {
    try {
      final docs = await _loadFirestore(
        reference: reference,
        cacheKey: ramKey,
        forceServer: false,
        limit: limit,
      );
      _putRam(ramKey, docs);
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.membros,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFirestore({
    required CollectionReference<Map<String, dynamic>> reference,
    required String cacheKey,
    required bool forceServer,
    required int limit,
  }) =>
      FirestoreWebGuard.runWithWebRecovery(
        () => ChurchModuleFirestoreListRead.queryPlainFirst(
          reference: reference,
          cacheKey: cacheKey,
          limit: limit,
          forceServer: forceServer,
          orderByField: 'updatedAt',
          sortDocs: _sortByName,
        ),
        maxAttempts: 4,
      );

  static Future<void> invalidate(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    _ram.removeWhere((k, _) => k.startsWith(churchId));
    await TenantModuleHiveCache.clearModule(
      churchId,
      TenantModuleKeys.membros,
    );
  }
}
