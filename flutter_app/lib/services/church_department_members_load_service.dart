import 'dart:async';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Membro vinculado a um departamento — dados do doc `membros` + snapshot da subcoleção.
class ChurchDepartmentMemberRow {
  const ChurchDepartmentMemberRow({
    required this.memberDocId,
    required this.data,
    required this.memberRef,
  });

  final String memberDocId;
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> memberRef;

  String get displayName => BlindMemberDoc.fromFirestore(id: memberDocId, data: data)
      .displayName
      .trim();
}

class ChurchDepartmentMembersLoadResult {
  const ChurchDepartmentMembersLoadResult({
    required this.churchId,
    required this.departmentId,
    required this.members,
    required this.readSource,
    this.softError,
    this.fromCache = false,
  });

  final String churchId;
  final String departmentId;
  final List<ChurchDepartmentMemberRow> members;
  final String readSource;
  final String? softError;
  final bool fromCache;
}

class ChurchDepartmentMembersByDeptResult {
  const ChurchDepartmentMembersByDeptResult({
    required this.churchId,
    required this.byDepartmentId,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final Map<String, List<ChurchDepartmentMemberRow>> byDepartmentId;
  final String readSource;
  final String? softError;
}

/// Carga estável Departamentos ↔ Membros — paths `igrejas/{churchId}/…`.
///
/// **Hub:** só lê `membros_vinculados` + docs de membro por ID (nunca scan de 500).
abstract final class ChurchDepartmentMembersLoadService {
  ChurchDepartmentMembersLoadService._();

  static const int _kLinkedLimit = 200;
  static const int _kPickerLimit = YahwehPerformanceV4.defaultPageSize;

  static Duration get _queryCap => kIsWeb
      ? const Duration(seconds: 14)
      : ChurchPanelReadTimeouts.queryCap;

  static final Map<
      String,
      ({
        List<ChurchDepartmentMemberRow> rows,
        DateTime at,
      })> _linkedRam = {};

  static const Duration _linkedRamTtl = Duration(minutes: 15);

  static String _linkedRamKey(String churchId, String departmentId) =>
      '${churchId.trim()}|${departmentId.trim()}';

  static CollectionReference<Map<String, dynamic>> _linkedCol(
    String churchId,
    String departmentId,
  ) =>
      ChurchUiCollections.departamentos(churchId)
          .doc(departmentId.trim())
          .collection('membros_vinculados');

  static bool memberInDepartment(Map<String, dynamic> data, String departmentId) {
    final did = departmentId.trim();
    if (did.isEmpty) return false;
    final ids = <String>{};
    for (final raw in [
      ...(data['DEPARTAMENTOS'] as List? ?? const []),
      ...(data['departamentosIds'] as List? ?? const []),
    ]) {
      final s = raw.toString().trim();
      if (s.isNotEmpty) ids.add(s);
    }
    return ids.contains(did);
  }

  static Iterable<String> departmentIdsFromMemberData(Map<String, dynamic> data) sync* {
    for (final raw in [
      ...(data['DEPARTAMENTOS'] as List? ?? const []),
      ...(data['departamentosIds'] as List? ?? const []),
    ]) {
      final s = raw.toString().trim();
      if (s.isNotEmpty) yield s;
    }
  }

  static Map<String, dynamic> _mergeLinkedIntoMember(
    Map<String, dynamic> memberData,
    Map<String, dynamic>? linked,
  ) {
    final out = BlindMemberDoc.fromFirestore(
      id: '',
      data: memberData,
    ).toMemberDataMap();
    if (linked == null) return out;
    final nome = (linked['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty &&
        (out['NOME_COMPLETO'] ?? out['nome'] ?? '').toString().trim().isEmpty) {
      out['NOME_COMPLETO'] = nome;
      out['nome'] = nome;
    }
    final foto = (linked['fotoUrl'] ?? linked['fotoThumbUrl'] ?? '')
        .toString()
        .trim();
    if (foto.isNotEmpty && imageUrlFromMap(out).isEmpty) {
      out['fotoUrl'] = foto;
      out['fotoThumbUrl'] = linked['fotoThumbUrl'] ?? foto;
    }
    return out;
  }

  static ChurchDepartmentMemberRow _rowFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, dynamic>? linked,
  }) {
    final merged = _mergeLinkedIntoMember(doc.data() ?? const {}, linked);
    return ChurchDepartmentMemberRow(
      memberDocId: doc.id,
      data: merged,
      memberRef: doc.reference,
    );
  }

  static List<ChurchDepartmentMemberRow> _sortRows(
    List<ChurchDepartmentMemberRow> rows,
  ) {
    final sorted = List<ChurchDepartmentMemberRow>.from(rows);
    sorted.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return sorted;
  }

  static void _putLinkedRam(
    String churchId,
    String departmentId,
    List<ChurchDepartmentMemberRow> rows,
  ) {
    if (churchId.isEmpty || departmentId.isEmpty) return;
    _linkedRam[_linkedRamKey(churchId, departmentId)] = (
      rows: List.from(rows),
      at: DateTime.now(),
    );
  }

  /// Abertura instantânea do hub (RAM).
  static ChurchDepartmentMembersLoadResult? peekLinkedInstant(
    String seedTenantId,
    String departmentId,
  ) {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    final deptId = departmentId.trim();
    if (churchId.isEmpty || deptId.isEmpty) return null;
    final hit = _linkedRam[_linkedRamKey(churchId, deptId)];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _linkedRamTtl) {
      _linkedRam.remove(_linkedRamKey(churchId, deptId));
      return null;
    }
    return ChurchDepartmentMembersLoadResult(
      churchId: churchId,
      departmentId: deptId,
      members: hit.rows,
      readSource: 'ram',
      fromCache: true,
    );
  }

  static void invalidateLinkedRam(String seedTenantId, String departmentId) {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) return;
    _linkedRam.remove(_linkedRamKey(churchId, departmentId.trim()));
  }

  static Future<Map<String, Map<String, dynamic>>> _loadLinkedSnapshots({
    required String churchId,
    required String departmentId,
  }) async {
    final col = _linkedCol(churchId, departmentId);
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final cacheSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => col
            .limit(_kLinkedLimit)
            .get(const GetOptions(source: Source.cache)),
        maxAttempts: 2,
      ).timeout(const Duration(seconds: 3));
      if (cacheSnap.docs.isNotEmpty) {
        return {for (final d in cacheSnap.docs) d.id: d.data()};
      }
    } catch (_) {}

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => col.limit(_kLinkedLimit).get(),
        maxAttempts: 3,
      ).timeout(_queryCap);
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return const {};
    }
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _queryMembersWithDeptId({
    required String churchId,
    required String departmentId,
    required String cacheKeyBase,
  }) async {
    final col = ChurchUiCollections.membros(churchId);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> mergeQuery(
      Query<Map<String, dynamic>> q,
      String subKey,
    ) async {
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => FirestoreReadResilience.getQuery(
            q,
            cacheKey: '${cacheKeyBase}_$subKey',
            maxAttempts: kIsWeb ? 3 : 2,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          ),
          maxAttempts: 3,
        ).timeout(const Duration(seconds: 10));
        for (final d in snap.docs) {
          byId[d.id] = d;
        }
      } catch (_) {}
    }

    await Future.wait([
      mergeQuery(
        col
            .where('departamentosIds', arrayContains: departmentId)
            .limit(_kLinkedLimit),
        'dept_ids_lc',
      ),
      mergeQuery(
        col
            .where('DEPARTAMENTOS', arrayContains: departmentId)
            .limit(_kLinkedLimit),
        'dept_ids_uc',
      ),
    ]);

    return byId.values.toList();
  }

  static Future<Map<String, DocumentSnapshot<Map<String, dynamic>>>>
      _resolveMemberDocsByIds({
    required String churchId,
    required Set<String> memberIds,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> prefilled = const {},
  }) async {
    if (memberIds.isEmpty) return const {};

    final found = <String, DocumentSnapshot<Map<String, dynamic>>>{
      for (final e in prefilled.entries)
        if (memberIds.contains(e.key)) e.key: e.value,
    };

    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram != null) {
      for (final d in ram) {
        if (memberIds.contains(d.id) && !found.containsKey(d.id)) {
          found[d.id] = d;
        }
      }
    }

    if (found.length >= memberIds.length) return found;

    try {
      final hive = await TenantModuleHiveCache.readDocs(
        churchId,
        TenantModuleKeys.membros,
      ).timeout(const Duration(seconds: 2));
      if (hive.isNotEmpty) {
        for (final d in TenantModuleHiveCache.toQueryDocuments(hive)) {
          if (memberIds.contains(d.id) && !found.containsKey(d.id)) {
            found[d.id] = d;
          }
        }
      }
    } catch (_) {}

    var missing = memberIds.difference(found.keys.toSet());
    if (missing.isEmpty) return found;

    final col = ChurchUiCollections.membros(churchId);
    const chunkSize = 12;

    Future<void> fetchChunk(Iterable<String> ids, {required bool cacheOnly}) async {
      final cap = Duration(seconds: cacheOnly ? 3 : 8);
      await Future.wait(ids.map((id) async {
        try {
          final snap = await FirestoreWebGuard.runWithWebRecovery(
            () => col.doc(id).get(
              GetOptions(source: cacheOnly ? Source.cache : Source.server),
            ),
            maxAttempts: 2,
          ).timeout(cap);
          if (snap.exists) found[id] = snap;
        } catch (_) {}
      }));
    }

    final missingList = missing.toList();
    for (var i = 0; i < missingList.length; i += chunkSize) {
      final slice = missingList.sublist(
        i,
        min(i + chunkSize, missingList.length),
      );
      await fetchChunk(slice, cacheOnly: true);
    }

    missing = memberIds.difference(found.keys.toSet());
    if (missing.isEmpty) return found;

    final serverList = missing.toList();
    for (var i = 0; i < serverList.length; i += chunkSize) {
      final slice = serverList.sublist(
        i,
        min(i + chunkSize, serverList.length),
      );
      await fetchChunk(slice, cacheOnly: false);
    }

    return found;
  }

  static List<ChurchDepartmentMemberRow> _buildLinkedRows({
    required String churchId,
    required String deptId,
    required Map<String, Map<String, dynamic>> linked,
    required Map<String, DocumentSnapshot<Map<String, dynamic>>> memberDocs,
  }) {
    final rows = <ChurchDepartmentMemberRow>[];
    final seen = <String>{};

    for (final entry in memberDocs.entries) {
      final doc = entry.value;
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data() ?? const {})) {
        continue;
      }
      final linkedSnap = linked[entry.key];
      if (!memberInDepartment(doc.data() ?? const {}, deptId) &&
          linkedSnap == null) {
        continue;
      }
      seen.add(entry.key);
      rows.add(_rowFromDoc(doc, linked: linkedSnap));
    }

    for (final entry in linked.entries) {
      if (seen.contains(entry.key)) continue;
      final ref = ChurchUiCollections.membros(churchId).doc(entry.key);
      final stub = _mergeLinkedIntoMember(const {}, entry.value);
      rows.add(ChurchDepartmentMemberRow(
        memberDocId: entry.key,
        data: stub,
        memberRef: ref,
      ));
      seen.add(entry.key);
    }

    return _sortRows(rows);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadMemberDocsCacheFirst({
    required String churchId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final ram = ChurchMembersLoadService.peekRamAny(churchId);
      if (ram != null && ram.isNotEmpty) return ram;
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final loaded = await ChurchMembersLoadService.load(
        seedTenantId: churchId,
        limit: _kPickerLimit,
        forceRefresh: forceRefresh,
      ).timeout(_queryCap);
      if (loaded.docs.isNotEmpty) return loaded.docs;
    } catch (_) {}

    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram != null && ram.isNotEmpty) return ram;

    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.membros(churchId),
      cacheKey: '${churchId.trim()}_dept_picker_$_kPickerLimit',
      limit: _kPickerLimit,
      sortDocs: (docs) => docs,
    );
  }

  static Future<void> _refreshLinkedInBackground(
    String churchId,
    String departmentId,
  ) async {
    try {
      await loadLinked(
        seedTenantId: churchId,
        departmentId: departmentId,
        forceRefresh: true,
      );
    } catch (_) {}
  }

  /// Membros vinculados a um departamento (hub) — **sem scan completo de membros**.
  static Future<ChurchDepartmentMembersLoadResult> loadLinked({
    required String seedTenantId,
    required String departmentId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    final deptId = departmentId.trim();
    if (churchId.isEmpty || deptId.isEmpty) {
      return ChurchDepartmentMembersLoadResult(
        churchId: churchId,
        departmentId: deptId,
        members: const [],
        readSource: 'empty_id',
        softError: 'Igreja ou departamento não identificado.',
      );
    }

    if (!forceRefresh) {
      final instant = peekLinkedInstant(churchId, deptId);
      if (instant != null) {
        unawaited(_refreshLinkedInBackground(churchId, deptId));
        return instant;
      }
    }

    String? softError;
    final cacheKey = '${churchId.trim()}_dept_linked_$deptId';

    Map<String, Map<String, dynamic>> linked = const {};
    try {
      linked = await _loadLinkedSnapshots(
        churchId: churchId,
        departmentId: deptId,
      );
    } catch (e) {
      softError ??= _humanize(e);
    }

    final memberIds = linked.keys.toSet();
    final fromQuery = await _queryMembersWithDeptId(
      churchId: churchId,
      departmentId: deptId,
      cacheKeyBase: cacheKey,
    );
    memberIds.addAll(fromQuery.map((d) => d.id));

    if (memberIds.isEmpty) {
      final ram = ChurchMembersLoadService.peekRamAny(churchId);
      if (ram != null) {
        for (final d in ram) {
          if (memberInDepartment(d.data(), deptId)) {
            memberIds.add(d.id);
          }
        }
      }
    }

    final prefilled = {for (final d in fromQuery) d.id: d};
    Map<String, DocumentSnapshot<Map<String, dynamic>>> memberDocs = const {};
    try {
      memberDocs = await _resolveMemberDocsByIds(
        churchId: churchId,
        memberIds: memberIds,
        prefilled: prefilled,
      );
    } catch (e) {
      softError ??= _humanize(e);
    }

    final rows = _buildLinkedRows(
      churchId: churchId,
      deptId: deptId,
      linked: linked,
      memberDocs: memberDocs,
    );

    _putLinkedRam(churchId, deptId, rows);

    return ChurchDepartmentMembersLoadResult(
      churchId: churchId,
      departmentId: deptId,
      members: rows,
      readSource: rows.isEmpty ? 'empty' : 'dept_linked_fast',
      softError: rows.isEmpty ? softError : null,
      fromCache: !forceRefresh,
    );
  }

  static Map<String, List<ChurchDepartmentMemberRow>> groupRowsByDepartmentPublic(
    Iterable<ChurchDepartmentMemberRow> rows,
  ) =>
      _groupRowsByDepartment(rows);

  static Map<String, List<ChurchDepartmentMemberRow>> _groupRowsByDepartment(
    Iterable<ChurchDepartmentMemberRow> rows,
  ) {
    final byDept = <String, List<ChurchDepartmentMemberRow>>{};
    for (final row in rows) {
      if (!ChurchModuleFirestoreListRead.isActiveRecord(row.data)) continue;
      for (final did in departmentIdsFromMemberData(row.data)) {
        byDept.putIfAbsent(did, () => []).add(row);
      }
    }
    for (final list in byDept.values) {
      if (list.length > 48) list.removeRange(48, list.length);
      list.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }
    return byDept;
  }

  /// Mapa deptId → membros (avatars na grelha) — cache-first, limite 120.
  static Future<ChurchDepartmentMembersByDeptResult> loadGroupedByDepartment({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchDepartmentMembersByDeptResult(
        churchId: '',
        byDepartmentId: {},
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    String? softError;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs = const [];
    try {
      memberDocs = await _loadMemberDocsCacheFirst(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      softError = _humanize(e);
    }

    final rows = <ChurchDepartmentMemberRow>[];
    for (final doc in memberDocs) {
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
      rows.add(_rowFromDoc(doc));
    }

    return ChurchDepartmentMembersByDeptResult(
      churchId: churchId,
      byDepartmentId: _groupRowsByDepartment(rows),
      readSource: memberDocs.isEmpty ? 'empty' : 'grouped_cache_first',
      softError: softError,
    );
  }

  /// Lista para picker «Vincular membros» — cache-first (20–120), sem scan 500.
  static Future<ChurchDepartmentMembersLoadResult> loadAllForPicker({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchDepartmentMembersLoadResult(
        churchId: '',
        departmentId: '',
        members: const [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    String? softError;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs = const [];
    try {
      memberDocs = await _loadMemberDocsCacheFirst(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      softError = _humanize(e);
    }

    final rows = <ChurchDepartmentMemberRow>[];
    for (final doc in memberDocs) {
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
      rows.add(_rowFromDoc(doc));
    }

    return ChurchDepartmentMembersLoadResult(
      churchId: churchId,
      departmentId: '',
      members: _sortRows(rows),
      readSource: 'picker_cache_first',
      softError: rows.isEmpty ? softError : null,
      fromCache: !forceRefresh,
    );
  }

  static String? _humanize(Object e) {
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar membros. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }
}
