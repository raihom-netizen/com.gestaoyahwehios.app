import 'dart:async';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
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

/// Carga estável Departamentos ? Membros ? paths `igrejas/{churchId}/?`.
///
/// **Hub:** só lê `membros_vinculados` + docs de membro por ID (nunca scan de 500).
abstract final class ChurchDepartmentMembersLoadService {
  ChurchDepartmentMembersLoadService._();

  static const int _kLinkedLimit = 200;

  /// Picker de «Vincular membros» / «Escolher líder» precisa da igreja INTEIRA:
  /// com `defaultPageSize` (20) uma igreja de 59 membros mostrava só 20 e o
  /// gestor não encontrava o irmão que queria vincular. Mesmo teto da lista
  /// de membros (500) — é uma tela de seleção, não uma lista paginada.
  static const int _kPickerLimit = 500;

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

  /// IDs de departamento da ficha do membro — **sem repetir**.
  ///
  /// Toda ficha guarda a MESMA lista em `DEPARTAMENTOS` e em
  /// `departamentosIds` (compatibilidade). Este gerador concatenava as duas e
  /// devolvia cada id DUAS vezes; como `_groupRowsByDepartment` faz um `add`
  /// por id devolvido, cada membro entrava duplicado no departamento — era a
  /// duplicação vista no hub (Maelly 2×, Maria Laura 2×, Paulo 2×…).
  static Iterable<String> departmentIdsFromMemberData(Map<String, dynamic> data) sync* {
    final vistos = <String>{};
    for (final raw in [
      ...(data['DEPARTAMENTOS'] as List? ?? const []),
      ...(data['departamentosIds'] as List? ?? const []),
    ]) {
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      if (!vistos.add(s)) continue;
      yield s;
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

  /// Identidade da PESSOA (não do documento): a base tem membros com dois
  /// docs — um legado por CPF e outro canónico por UID — e o hub listava a
  /// mesma pessoa duas vezes. Ordem: authUid > CPF > e-mail > nome.
  static String _personKey(ChurchDepartmentMemberRow r) {
    final d = r.data;
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (d[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final uid = pick(['authUid', 'AUTH_UID', 'uid', 'userUid']);
    if (uid.isNotEmpty) return 'uid:${uid.toLowerCase()}';
    final cpf = pick(['CPF', 'cpf']).replaceAll(RegExp(r'\D'), '');
    if (cpf.length == 11) return 'cpf:$cpf';
    final email = pick(['EMAIL', 'email']).toLowerCase();
    if (email.isNotEmpty) return 'mail:$email';
    final nome =
        r.displayName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (nome.isNotEmpty) return 'nome:$nome';
    return 'doc:${r.memberDocId}';
  }

  /// Quanto mais campos preenchidos, melhor o documento — na duplicata fica
  /// o mais completo (o que costuma ter foto e ficha cheia).
  static int _rowRichness(ChurchDepartmentMemberRow r) {
    var score = r.data.entries.where((e) {
      final v = e.value;
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is Iterable) return v.isNotEmpty;
      return true;
    }).length;
    // Doc keyado por UID do Firebase Auth é o canónico (o legado é o CPF).
    if (r.memberDocId.length >= 20 &&
        !RegExp(r'^\d+$').hasMatch(r.memberDocId)) {
      score += 5;
    }
    return score;
  }

  /// Nome normalizado (sem acento/duplo espaço) — última rede do dedupe.
  static String _normalizedName(ChurchDepartmentMemberRow r) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final lower = r.displayName.toLowerCase().trim();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Ordena por nome **e remove a mesma pessoa repetida**.
  ///
  /// Dois passes porque `membros_vinculados` guarda um "stub" só com nome e
  /// foto: ele não tem UID nem CPF, então nunca casava com o doc real do
  /// membro pela chave de identidade — e a pessoa aparecia duas vezes.
  static List<ChurchDepartmentMemberRow> _sortRows(
    List<ChurchDepartmentMemberRow> rows,
  ) {
    // 1) identidade forte (uid / cpf / e-mail / nome)
    final best = <String, ChurchDepartmentMemberRow>{};
    for (final r in rows) {
      final key = _personKey(r);
      final atual = best[key];
      if (atual == null || _rowRichness(r) > _rowRichness(atual)) {
        best[key] = r;
      }
    }

    // 2) mesmo nome → fica só o registo mais completo (mata o stub)
    final porNome = <String, ChurchDepartmentMemberRow>{};
    for (final r in best.values) {
      final nome = _normalizedName(r);
      if (nome.isEmpty) continue;
      final atual = porNome[nome];
      if (atual == null || _rowRichness(r) > _rowRichness(atual)) {
        porNome[nome] = r;
      }
    }
    final semNome = best.values.where((r) => _normalizedName(r).isEmpty);

    final sorted = [...porNome.values, ...semNome];
    sorted.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
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

  /// Prefill do hub a partir da grelha / picker (evita "Carregando?" na abertura).
  static void seedLinkedFromRows({
    required String seedTenantId,
    required String departmentId,
    required List<ChurchDepartmentMemberRow> rows,
  }) {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    final deptId = departmentId.trim();
    if (churchId.isEmpty || deptId.isEmpty || rows.isEmpty) return;
    _putLinkedRam(churchId, deptId, rows);
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
      await FirestoreWebGuard.ensurePanelReadReady()
          .timeout(ChurchPanelReadTimeouts.readReadyCap)
          .catchError((_) {});
    }

    // Cache local primeiro (cap curto — não segurar o hub).
    try {
      final cacheSnap = await col
          .limit(_kLinkedLimit)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 1200));
      if (cacheSnap.docs.isNotEmpty) {
        return {for (final d in cacheSnap.docs) d.id: d.data()};
      }
    } catch (_) {}

    try {
      final snap = await col.limit(_kLinkedLimit).get().timeout(
        kIsWeb ? const Duration(seconds: 5) : _queryCap,
      );
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return const {};
    }
  }

  /// Filtra membros já em RAM (sem rede) — abertura instantânea do hub.
  static List<ChurchDepartmentMemberRow> _rowsFromMembersRam(
    String churchId,
    String departmentId,
  ) {
    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram == null || ram.isEmpty) return const [];
    final rows = <ChurchDepartmentMemberRow>[];
    for (final d in ram) {
      final data = d.data();
      if (!ChurchModuleFirestoreListRead.isActiveRecord(data)) continue;
      if (!memberInDepartment(data, departmentId)) continue;
      rows.add(_rowFromDoc(d));
    }
    return _sortRows(rows);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _queryMembersWithDeptId({
    required String churchId,
    required String departmentId,
    required String cacheKeyBase,
    bool bothFields = false,
  }) async {
    final col = ChurchUiCollections.membros(churchId);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    Future<void> mergeQuery(
      Query<Map<String, dynamic>> q,
      String subKey,
    ) async {
      try {
        final snap = await FirestoreReadResilience.getQuery(
          q,
          cacheKey: '${cacheKeyBase}_$subKey',
          maxAttempts: 2,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 5)
              : ChurchPanelReadTimeouts.attempt,
        ).timeout(kIsWeb ? const Duration(seconds: 6) : const Duration(seconds: 10));
        for (final d in snap.docs) {
          byId[d.id] = d;
        }
      } catch (_) {}
    }

    // Path rápido: só `departamentosIds` (campo canónico).
    await mergeQuery(
      col
          .where('departamentosIds', arrayContains: departmentId)
          .limit(_kLinkedLimit),
      'dept_ids_lc',
    );

    // Compat legado só se ainda vazio ou pedido explícito.
    if (bothFields || byId.isEmpty) {
      await mergeQuery(
        col
            .where('DEPARTAMENTOS', arrayContains: departmentId)
            .limit(_kLinkedLimit),
        'dept_ids_uc',
      );
    }

    return byId.values.toList();
  }

  static Future<Map<String, DocumentSnapshot<Map<String, dynamic>>>>
      _resolveMemberDocsByIds({
    required String churchId,
    required Set<String> memberIds,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> prefilled = const {},
    bool serverFetch = true,
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
      ).timeout(const Duration(milliseconds: 800));
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
    const chunkSize = 20;

    Future<void> fetchChunk(Iterable<String> ids, {required bool cacheOnly}) async {
      final cap = Duration(milliseconds: cacheOnly ? 900 : 3500);
      await Future.wait(ids.map((id) async {
        try {
          final snap = await col.doc(id).get(
            GetOptions(source: cacheOnly ? Source.cache : Source.server),
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

    if (!serverFetch) return found;

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
        // Picker de departamento = igreja inteira (sem o teto de página de 50).
        fullList: true,
      ).timeout(_queryCap);
      if (loaded.docs.isNotEmpty) return loaded.docs;
    } catch (_) {}

    // `queryPlainFirst` vai por REST no web — é o único caminho que sobrevive
    // ao SDK Firestore derrubado por INTERNAL ASSERTION. Num `forceRefresh`
    // ele vem ANTES da RAM: cair na RAM aqui devolvia a lista parcial que o
    // utilizador já estava a ver e a revalidação não corrigia nada.
    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (!forceRefresh && ram != null && ram.isNotEmpty) return ram;

    final rest = await ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.membros(churchId),
      cacheKey: '${churchId.trim()}_dept_picker_$_kPickerLimit',
      limit: _kPickerLimit,
      sortDocs: (docs) => docs,
    );
    if (rest.isNotEmpty) return rest;
    return (ram != null && ram.isNotEmpty)
        ? ram
        : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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

  /// Membros vinculados a um departamento (hub) ? **cache/RAM primeiro**, rede em background.
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

      // Abertura instantânea: membros já em RAM filtrados pelo dept.
      final fromRam = _rowsFromMembersRam(churchId, deptId);
      if (fromRam.isNotEmpty) {
        _putLinkedRam(churchId, deptId, fromRam);
        unawaited(_refreshLinkedInBackground(churchId, deptId));
        return ChurchDepartmentMembersLoadResult(
          churchId: churchId,
          departmentId: deptId,
          members: fromRam,
          readSource: 'members_ram',
          fromCache: true,
        );
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

    // Subcoleção com stubs (nome/foto) — pintar UI sem esperar N gets de membro.
    if (linked.isNotEmpty && !forceRefresh) {
      final memberIds = linked.keys.toSet();
      Map<String, DocumentSnapshot<Map<String, dynamic>>> memberDocs = const {};
      try {
        memberDocs = await _resolveMemberDocsByIds(
          churchId: churchId,
          memberIds: memberIds,
          serverFetch: false,
        );
      } catch (_) {}
      final rows = _buildLinkedRows(
        churchId: churchId,
        deptId: deptId,
        linked: linked,
        memberDocs: memberDocs,
      );
      if (rows.isNotEmpty) {
        _putLinkedRam(churchId, deptId, rows);
        unawaited(_refreshLinkedInBackground(churchId, deptId));
        return ChurchDepartmentMembersLoadResult(
          churchId: churchId,
          departmentId: deptId,
          members: rows,
          readSource: 'linked_stubs_fast',
          fromCache: true,
        );
      }
    }

    final memberIds = linked.keys.toSet();
    List<QueryDocumentSnapshot<Map<String, dynamic>>> fromQuery = const [];
    if (memberIds.isEmpty || forceRefresh) {
      fromQuery = await _queryMembersWithDeptId(
        churchId: churchId,
        departmentId: deptId,
        cacheKeyBase: cacheKey,
      );
      memberIds.addAll(fromQuery.map((d) => d.id));
    }

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
        serverFetch: true,
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

  /// Mapa deptId ? membros (avatars na grelha) ? cache-first, limite 120.
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

  /// Lista para picker ?Vincular membros? ? cache-first (20?120), sem scan 500.
  static Future<ChurchDepartmentMembersLoadResult> loadAllForPicker({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchDepartmentMembersLoadResult(
        churchId: '',
        departmentId: '',
        members: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    if (!forceRefresh) {
      final ram = ChurchMembersLoadService.peekRamAny(churchId);
      if (ram != null && ram.isNotEmpty) {
        final rows = <ChurchDepartmentMemberRow>[];
        for (final doc in ram) {
          if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
          rows.add(_rowFromDoc(doc));
        }
        if (rows.isNotEmpty) {
          unawaited(_refreshPickerMembersInBackground(churchId));
          return ChurchDepartmentMembersLoadResult(
            churchId: churchId,
            departmentId: '',
            members: _sortRows(rows),
            readSource: 'picker_ram',
            fromCache: true,
          );
        }
      }
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

  static Future<void> _refreshPickerMembersInBackground(String churchId) async {
    try {
      await _loadMemberDocsCacheFirst(churchId: churchId, forceRefresh: true);
    } catch (_) {}
  }

  static String? _humanize(Object e) {
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar membros. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}?';
    return s;
  }
}
