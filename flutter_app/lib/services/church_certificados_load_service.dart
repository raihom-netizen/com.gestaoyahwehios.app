import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/ui/widgets/member_display_name_utils.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/services/church_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Doc sintético — lista Certificados a partir do directory cache.
// ignore: subtype_of_sealed_class
class ChurchCertificadosMemberDoc
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  ChurchCertificadosMemberDoc({
    required this.id,
    required Map<String, dynamic> data,
  }) : _data = data;

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
  SnapshotMetadata get metadata => const _CertLoadSnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('certificados synthetic doc');
}

class _CertLoadSnapshotMetadata implements SnapshotMetadata {
  const _CertLoadSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}

/// Resultado — todos os membros `igrejas/{churchId}/membros` para emissão.
class ChurchCertificadosLoadResult {
  const ChurchCertificadosLoadResult({
    required this.churchId,
    required this.docs,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String? softError;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
}

/// Carga canónica — lista completa de membros (sem cap 20) para certificados.
abstract final class ChurchCertificadosLoadService {
  ChurchCertificadosLoadService._();

  /// Limite alto — igrejas piloto (~59) e médias; evita paginação «Carregar mais».
  static const int kAllMembersLimit = 800;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _ram = {};

  static const Duration _ramTtl = Duration(minutes: 20);

  static String _resolve(String hint) => ChurchPanelTenant.forFirestore(hint.trim());

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekRam(
    String seedTenantId,
  ) {
    final key = _resolve(seedTenantId);
    if (key.isEmpty) return null;
    final hit = _ram[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void putRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = churchId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _ram[key] = (docs: List.from(docs), at: DateTime.now());
  }

  /// Total canónico — `_dashboard_cache/main` ou `members_directory.totalCount`.
  static Future<int> expectedMemberTotal(String churchId) async {
    final id = churchId.trim();
    if (id.isEmpty) return 0;

    final dirMem = MembersDirectorySnapshotService.peekMemory(id);
    if (dirMem != null && dirMem.totalCount > 0) {
      return dirMem.totalCount;
    }

    try {
      final dash = await ChurchDashboardCacheService.load(churchIdHint: id)
          .timeout(const Duration(seconds: 6));
      if (dash != null && dash.totalMembros > 0) {
        return dash.totalMembros;
      }
    } catch (_) {}

    try {
      final dir = await MembersDirectorySnapshotService.readOnce(id)
          .timeout(const Duration(seconds: 8));
      if (dir.totalCount > 0) return dir.totalCount;
      if (dir.isCompleteForStats && dir.entries.isNotEmpty) {
        return dir.entries.length;
      }
    } catch (_) {}

    return 0;
  }

  /// Lista incompleta (ex.: 20 do cache da lista paginada vs 61 no painel).
  static bool isRosterIncomplete({
    required int loadedCount,
    required int expectedTotal,
  }) {
    if (loadedCount <= 0) return true;
    if (expectedTotal > 0) return loadedCount < expectedTotal;
    // Sem total conhecido: suspeita de página parcial típica (20/30).
    return loadedCount <= YahwehPerformanceV4.defaultPageSize;
  }

  static bool isRosterCompleteForTenant({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String churchId,
    int? expectedTotal,
  }) {
    if (docs.isEmpty || churchId.trim().isEmpty) return false;
    final expected = expectedTotal ?? 0;
    if (expected > 0) {
      return docs.length >= expected;
    }
    final dir = MembersDirectorySnapshotService.peekMemory(churchId.trim());
    if (dir != null && dir.totalCount > 0) {
      return docs.length >= dir.totalCount;
    }
    return !isRosterIncomplete(loadedCount: docs.length, expectedTotal: 0);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByNome(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
          .toString()
          .toLowerCase();
      return na.compareTo(nb);
    });
    return sorted;
  }

  /// Rol completo — igual aba «Todos» em Membros (só exclui ficha sem nome).
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _rollMembersForCertificados(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .where((d) => memberDataHasValidName(d.data()))
          .toList();

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _fromDirectory(
    MembersDirectorySnapshot dir,
  ) {
    return dir.entries
        .where((e) => isRealMemberDisplayName(e.displayName))
        .map(
          (e) => ChurchCertificadosMemberDoc(
            id: e.memberDocId,
            data: e.toMemberDataMap(),
          ),
        )
        .toList();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadMembrosCollection(
    String churchId, {
    bool forceServer = false,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final cacheKey = '${churchId}_certificados_membros_$kAllMembersLimit';
    final col = ChurchUiCollections.membros(churchId).limit(kAllMembersLimit);

    if (forceServer) {
      Future<QuerySnapshot<Map<String, dynamic>>> readServer() => col.get(
            const GetOptions(source: Source.server),
          );
      final snap = await readServer().timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) return snap.docs;
    }

    Future<QuerySnapshot<Map<String, dynamic>>> read() =>
        FirestoreReadResilience.getQuery(
          col,
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 18)
              : const Duration(seconds: 12),
        );

    final snap = await read().timeout(ChurchPanelReadTimeouts.queryCap);
    if (snap.docs.isNotEmpty) return snap.docs;

    Future<QuerySnapshot<Map<String, dynamic>>> readLegacyMembers() =>
        FirestoreReadResilience.getQuery(
          ChurchUiCollections.churchDoc(churchId)
              .collection('members')
              .limit(kAllMembersLimit),
          cacheKey: '${cacheKey}_legacy_members',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 18)
              : const Duration(seconds: 12),
        );
    final legacySnap = await readLegacyMembers().timeout(ChurchPanelReadTimeouts.queryCap);
    return legacySnap.docs;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFullRoster(
    String churchId, {
    bool forceRefresh = false,
  }) async {
    final expected = await expectedMemberTotal(churchId);

    var docs = await _loadMembrosCollection(
      churchId,
      forceServer: forceRefresh,
    );
    if (isRosterIncomplete(loadedCount: docs.length, expectedTotal: expected)) {
      final fromServer = await _loadMembrosCollection(
        churchId,
        forceServer: true,
      );
      if (fromServer.length > docs.length) {
        docs = fromServer;
      }
    }

    if (isRosterIncomplete(loadedCount: docs.length, expectedTotal: expected)) {
      try {
        final snap = await IgrejaDirectFirestoreReads.listSubcollection(
          churchId,
          'membros',
          moduleLabel: 'Certificados',
          limit: kAllMembersLimit,
          cacheKey: '${churchId}_certificados_membros_srv_$kAllMembersLimit',
        ).timeout(ChurchPanelReadTimeouts.queryCap);
        if (snap.docs.length > docs.length) {
          docs = snap.docs;
        }
      } catch (e, st) {
        debugPrint('ChurchCertificadosLoadService full roster direct: $e\n$st');
      }
    }

    return docs;
  }

  static Future<ChurchCertificadosLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchCertificadosLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    if (forceRefresh) {
      _ram.remove(churchId);
    }

    final expectedTotal = await expectedMemberTotal(churchId);

    if (!forceRefresh) {
      final ram = peekRam(churchId);
      if (ram != null &&
          ram.isNotEmpty &&
          !isRosterIncomplete(
            loadedCount: ram.length,
            expectedTotal: expectedTotal,
          )) {
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: ram,
          readSource: 'ram',
        );
      }
    }

    Object? lastError;

    // Lista completa — nunca aceitar directory parcial (20) quando totalCount = 61.
    try {
      final docs = await _loadFullRoster(
        churchId,
        forceRefresh: forceRefresh,
      );
      if (docs.isNotEmpty) {
        final sorted = _sortByNome(_rollMembersForCertificados(docs));
        if (!isRosterIncomplete(
          loadedCount: sorted.length,
          expectedTotal: expectedTotal,
        )) {
          putRam(churchId, sorted);
        }
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: sorted,
          readSource: forceRefresh ? 'membros_collection_force' : 'membros_collection',
        );
      }
    } catch (e, st) {
      lastError = e;
      debugPrint('ChurchCertificadosLoadService membros_collection: $e\n$st');
    }

    try {
      final membersResult = await ChurchMembersLoadService.load(
        seedTenantId: churchId,
        limit: kAllMembersLimit,
        forceRefresh: forceRefresh,
        forceServer: forceRefresh,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (membersResult.docs.isNotEmpty &&
          !isRosterIncomplete(
            loadedCount: membersResult.docs.length,
            expectedTotal: expectedTotal,
          )) {
        final docs = _sortByNome(_rollMembersForCertificados(membersResult.docs));
        putRam(churchId, docs);
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: membersResult.readSource.startsWith('members_directory')
              ? 'members_load_directory'
              : 'members_load_service',
          softError: docs.isEmpty ? membersResult.softError : null,
        );
      }
    } catch (e, st) {
      lastError ??= e;
      debugPrint('ChurchCertificadosLoadService members_load: $e\n$st');
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'membros',
        moduleLabel: 'Certificados',
        limit: kAllMembersLimit,
        cacheKey: '${churchId}_certificados_membros_$kAllMembersLimit',
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        final docs = _sortByNome(_rollMembersForCertificados(snap.docs));
        putRam(churchId, docs);
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'direct_list',
        );
      }
    } catch (e, st) {
      lastError ??= e;
      debugPrint('ChurchCertificadosLoadService direct_list: $e\n$st');
    }

    try {
      final dir = await MembersDirectorySnapshotService.readOnce(churchId);
      final dirComplete = dir.hasEntries &&
          (dir.totalCount <= 0 || dir.entries.length >= dir.totalCount);
      if (dirComplete) {
        final docs = _sortByNome(_fromDirectory(dir));
        putRam(churchId, docs);
        unawaited(
          MembersDirectorySnapshotService.warmFromCallableIfStale(churchId),
        );
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'members_directory',
        );
      }
    } catch (e, st) {
      lastError ??= e;
      debugPrint('ChurchCertificadosLoadService members_directory: $e\n$st');
    }

    try {
      final snap = await ChurchTenantResilientReads.membrosRecent(
        churchId,
        limit: kAllMembersLimit,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        final docs = _sortByNome(_rollMembersForCertificados(snap.docs));
        putRam(churchId, docs);
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'membros_recent',
        );
      }
    } catch (e, st) {
      lastError ??= e;
      debugPrint('ChurchCertificadosLoadService membros_recent: $e\n$st');
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(
      '${churchId}_certificados_membros_$kAllMembersLimit',
    );
    if (mem != null && mem.docs.isNotEmpty) {
      return ChurchCertificadosLoadResult(
        churchId: churchId,
        docs: _sortByNome(_rollMembersForCertificados(mem.docs)),
        readSource: 'fallback_mem',
        softError: lastError?.toString(),
      );
    }

    return ChurchCertificadosLoadResult(
      churchId: churchId,
      docs: const [],
      readSource: 'empty',
      softError: lastError is TimeoutException
          ? 'Tempo esgotado ao carregar membros.'
          : lastError?.toString(),
    );
  }

  static void invalidate(String seedTenantId) {
    final id = _resolve(seedTenantId);
    if (id.isEmpty) return;
    _ram.remove(id);
  }
}
