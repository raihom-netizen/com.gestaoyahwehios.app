import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
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
abstract final class ChurchDepartmentMembersLoadService {
  ChurchDepartmentMembersLoadService._();

  static const int _kLimit = 500;

  static Duration get _queryCap => kIsWeb
      ? const Duration(seconds: 16)
      : ChurchPanelReadTimeouts.queryCap;

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
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, dynamic>? linked,
  }) {
    final merged = _mergeLinkedIntoMember(doc.data(), linked);
    return ChurchDepartmentMemberRow(
      memberDocId: doc.id,
      data: merged,
      memberRef: doc.reference,
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadAllMemberDocs({
    required String churchId,
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final loaded = await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchMembersLoadService.load(
        seedTenantId: churchId,
        limit: _kLimit,
        forceRefresh: forceRefresh,
      ),
      maxAttempts: 4,
    ).timeout(_queryCap);
    if (loaded.docs.isNotEmpty) return loaded.docs;
    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram != null && ram.isNotEmpty) return ram;
    return ChurchModuleFirestoreListRead.queryPlainFirst(
      reference: ChurchUiCollections.membros(churchId),
      cacheKey: '${churchId.trim()}_dept_members_$_kLimit',
      limit: _kLimit,
      sortDocs: (docs) => docs,
    );
  }

  static Future<Map<String, Map<String, dynamic>>> _loadLinkedSnapshots({
    required String churchId,
    required String departmentId,
  }) async {
    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => _linkedCol(churchId, departmentId).limit(_kLimit).get(),
        maxAttempts: 3,
      ).timeout(_queryCap);
      return {
        for (final d in snap.docs)
          d.id: d.data(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Membros vinculados a um departamento (hub).
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

    String? softError;
    Map<String, Map<String, dynamic>> linked = const {};
    List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs = const [];

    try {
      linked = await _loadLinkedSnapshots(
        churchId: churchId,
        departmentId: deptId,
      );
    } catch (e) {
      softError ??= _humanize(e);
    }

    try {
      memberDocs = await _loadAllMemberDocs(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      softError ??= _humanize(e);
    }

    final rows = <ChurchDepartmentMemberRow>[];
    final seen = <String>{};

    for (final doc in memberDocs) {
      if (seen.contains(doc.id)) continue;
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
      final linkedSnap = linked[doc.id];
      if (!memberInDepartment(doc.data(), deptId) && linkedSnap == null) {
        continue;
      }
      seen.add(doc.id);
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

    rows.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return ChurchDepartmentMembersLoadResult(
      churchId: churchId,
      departmentId: deptId,
      members: rows,
      readSource: rows.isEmpty ? 'empty' : 'dept_members_merged',
      softError: rows.isEmpty ? softError : null,
      fromCache: !forceRefresh,
    );
  }

  /// Mapa deptId → membros (avatars na grelha de departamentos).
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
      memberDocs = await _loadAllMemberDocs(
        churchId: churchId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      softError = _humanize(e);
    }

    final byDept = <String, List<ChurchDepartmentMemberRow>>{};
    for (final doc in memberDocs) {
      if (!ChurchModuleFirestoreListRead.isActiveRecord(doc.data())) continue;
      final deptIds = <String>{};
      for (final raw in [
        ...(doc.data()['DEPARTAMENTOS'] as List? ?? const []),
        ...(doc.data()['departamentosIds'] as List? ?? const []),
      ]) {
        final s = raw.toString().trim();
        if (s.isNotEmpty) deptIds.add(s);
      }
      for (final did in deptIds) {
        byDept.putIfAbsent(did, () => []).add(_rowFromDoc(doc));
      }
    }

    for (final list in byDept.values) {
      list.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      if (list.length > 48) {
        list.removeRange(48, list.length);
      }
    }

    return ChurchDepartmentMembersByDeptResult(
      churchId: churchId,
      byDepartmentId: byDept,
      readSource: memberDocs.isEmpty ? 'empty' : 'grouped_members',
      softError: softError,
    );
  }

  /// Lista completa para picker «Vincular membros».
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
      memberDocs = await _loadAllMemberDocs(
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
    rows.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    return ChurchDepartmentMembersLoadResult(
      churchId: churchId,
      departmentId: '',
      members: rows,
      readSource: 'all_members',
      softError: softError,
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
