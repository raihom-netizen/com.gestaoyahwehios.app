import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_corpo_admin_roles.dart';
import 'package:gestao_yahweh/core/church_department_leaders.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_role_badge.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Entrada unificada — líderes de departamento ou corpo administrativo.
class ChurchPanelLeaderEntry {
  const ChurchPanelLeaderEntry({
    required this.memberDocId,
    required this.displayName,
    required this.memberData,
    required this.subtitles,
    this.roles = const [],
    this.sortRank = 0,
  });

  final String memberDocId;
  final String displayName;
  final Map<String, dynamic> memberData;
  final List<String> subtitles;
  final List<String> roles;
  final int sortRank;

  String get subtitleLine =>
      subtitles.where((s) => s.trim().isNotEmpty).join(', ');
}

enum ChurchPanelLeadershipSection { departmentLeaders, corpoAdmin }

/// Carga rápida — `_panel_cache` → directory → Firestore directo (`igrejas/{churchId}`).
abstract final class ChurchPanelLeadershipLoadService {
  ChurchPanelLeadershipLoadService._();

  static Future<List<ChurchPanelLeaderEntry>> load({
    required String seedTenantId,
    required ChurchPanelLeadershipSection section,
    List<String> corpoAdminRoles = ChurchCorpoAdminRoles.defaultRoleKeys,
    PanelDashboardSnapshot? panelHint,
    MembersDirectorySnapshot? directoryHint,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) return const [];

    List<ChurchPanelLeaderEntry> fromPanel(PanelDashboardSnapshot panel) {
      if (section == ChurchPanelLeadershipSection.departmentLeaders) {
        return _fromPanelLeaders(panel.homeLeaders);
      }
      return _fromPanelCorpo(panel.homeCorpoAdmin);
    }

    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }

      final panel =
          panelHint ?? await PanelDashboardSnapshotService.readOnce(churchId);
      final cached = fromPanel(panel);
      if (cached.isNotEmpty) return cached;

      if (section == ChurchPanelLeadershipSection.departmentLeaders) {
        final computed = await _computeDepartmentLeaders(
          churchId,
          directoryHint: directoryHint,
        ).timeout(
          PanelResilientLoad.queryCap,
          onTimeout: () => const <ChurchPanelLeaderEntry>[],
        );
        if (computed.isEmpty) {
          unawaited(
            PanelDashboardSnapshotService.warmFromCallableIfStale(churchId),
          );
        }
        return computed;
      }

      final computed = await _computeCorpoAdmin(
        churchId,
        corpoAdminRoles: corpoAdminRoles,
        directoryHint: directoryHint,
      ).timeout(
        PanelResilientLoad.queryCap,
        onTimeout: () => const <ChurchPanelLeaderEntry>[],
      );
      if (computed.isEmpty) {
        unawaited(
          PanelDashboardSnapshotService.warmFromCallableIfStale(churchId),
        );
      }
      return computed;
    } catch (e, st) {
      debugPrint('ChurchPanelLeadershipLoadService.load: $e\n$st');
      if (panelHint != null) {
        final fallback = fromPanel(panelHint);
        if (fallback.isNotEmpty) return fallback;
      }
      try {
        final panel = await PanelDashboardSnapshotService.readOnce(churchId);
        final fallback = fromPanel(panel);
        if (fallback.isNotEmpty) return fallback;
      } catch (_) {}
      return const [];
    }
  }

  /// Entradas imediatas a partir do `_panel_cache` (sem rede).
  static List<ChurchPanelLeaderEntry> fromPanelSnapshot({
    required PanelDashboardSnapshot panel,
    required ChurchPanelLeadershipSection section,
  }) {
    if (section == ChurchPanelLeadershipSection.departmentLeaders) {
      return _fromPanelLeaders(panel.homeLeaders);
    }
    return _fromPanelCorpo(panel.homeCorpoAdmin);
  }

  static List<ChurchPanelLeaderEntry> _fromPanelLeaders(
    List<PanelHomeMemberLite> list,
  ) {
    return list
        .where((e) => e.memberDocId.trim().isNotEmpty)
        .map(
          (lite) => ChurchPanelLeaderEntry(
            memberDocId: lite.memberDocId,
            displayName: lite.displayName.trim().isEmpty
                ? 'Líder'
                : lite.displayName.trim(),
            memberData: lite.toMemberDataMap(),
            subtitles: lite.deptNames,
            roles: lite.corpoRoles,
            sortRank: 100,
          ),
        )
        .toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }

  static List<ChurchPanelLeaderEntry> _fromPanelCorpo(
    List<PanelHomeMemberLite> list,
  ) {
    final out = list
        .where((e) => e.memberDocId.trim().isNotEmpty)
        .map((lite) {
          final roles = lite.corpoRoles;
          return ChurchPanelLeaderEntry(
            memberDocId: lite.memberDocId,
            displayName: lite.displayName.trim().isEmpty
                ? 'Membro'
                : lite.displayName.trim(),
            memberData: lite.toMemberDataMap(),
            subtitles: roles.map(churchRoleDisplayLabel).toList(),
            roles: roles,
            sortRank: ChurchCorpoAdminRoles.memberSortRank(roles),
          );
        })
        .toList();
    out.sort((a, b) {
      if (a.sortRank != b.sortRank) return b.sortRank.compareTo(a.sortRank);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return out;
  }

  static Future<MembersDirectorySnapshot?> _resolveDirectory(
    String churchId,
    MembersDirectorySnapshot? hint,
  ) async {
    if (hint != null && hint.hasEntries) return hint;
    final peek = MembersDirectorySnapshotService.peekMemory(churchId);
    if (peek != null && peek.hasEntries) return peek;
    final read = await MembersDirectorySnapshotService.readOnce(churchId);
    if (read.hasEntries) return read;
    return MembersDirectorySnapshotService.warmFromCallableIfStale(churchId);
  }

  static Future<List<ChurchPanelLeaderEntry>> _computeDepartmentLeaders(
    String churchId, {
    MembersDirectorySnapshot? directoryHint,
  }) async {
    final deptSnap = await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchTenantResilientReads.departamentos(
        churchId,
        limit: 120,
      ),
      maxAttempts: 4,
    );
    if (deptSnap.docs.isEmpty) return const [];

    final directory = await _resolveDirectory(churchId, directoryHint);
    final membersByCpf = <String, MemberDirectoryEntry>{};
    final memberDocIdByCpf = <String, String>{};
    final authUidToCpf = <String, String>{};

    void absorbMember(MemberDirectoryEntry e) {
      final cpfRaw = (e.cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
      var cpf = cpfRaw;
      if (cpf.length < 9) {
        final idDigits = e.memberDocId.replaceAll(RegExp(r'\D'), '');
        if (idDigits.length >= 9 && idDigits.length <= 11) cpf = idDigits;
      }
      if (cpf.length < 9 || cpf.length > 11) return;
      final key = ChurchDepartmentLeaders.canonicalCpfDigits(cpf);
      membersByCpf[key] = e;
      memberDocIdByCpf[key] = e.memberDocId;
      final uid = (e.authUid ?? '').trim();
      if (uid.length >= 8) authUidToCpf[uid] = key;
    }

    if (directory != null) {
      for (final e in directory.entries) {
        absorbMember(e);
      }
    }

    if (membersByCpf.isEmpty) {
      final memSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchTenantResilientReads.membrosRecent(churchId, limit: 400),
        maxAttempts: 4,
      );
      for (final doc in memSnap.docs) {
        final data = doc.data();
        final nome =
            (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? doc.id)
                .toString();
        final cpf =
            (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        final url = sanitizeImageUrl(imageUrlFromMap(data));
        absorbMember(
          MemberDirectoryEntry(
            memberDocId: doc.id,
            displayName: nome,
            photoUrl: url.isEmpty ? null : url,
            authUid: (data['authUid'] ?? data['firebaseUid'] ?? '').toString(),
            cpfDigits: cpf.length == 11 ? cpf : null,
            funcao: (data['FUNCAO'] ?? data['funcao'] ?? '').toString(),
            funcoes: (data['FUNCOES'] is List)
                ? (data['FUNCOES'] as List).map((x) => x.toString()).toList()
                : const [],
            telefone: (data['TELEFONES'] ?? data['telefone'] ?? '').toString(),
          ),
        );
      }
    }

    final leaderToDepts = <String, List<String>>{};
    final leaderToMember = <String, MemberDirectoryEntry>{};

    for (final dept in deptSnap.docs) {
      final data = dept.data();
      final deptName =
          (data['name'] ?? data['nome'] ?? dept.id).toString().trim();
      for (final cpf in ChurchDepartmentLeaders.cpfsFromDepartmentData(data)) {
        leaderToDepts.putIfAbsent(cpf, () => []).add(deptName);
        final m = membersByCpf[cpf];
        if (m != null) leaderToMember[cpf] = m;
      }
      for (final uid
          in ChurchDepartmentLeaders.leaderUidsFromDepartmentData(data)) {
        final cpfKey = authUidToCpf[uid];
        if (cpfKey == null || cpfKey.isEmpty) continue;
        leaderToDepts.putIfAbsent(cpfKey, () => []).add(deptName);
        final m = membersByCpf[cpfKey];
        if (m != null) leaderToMember[cpfKey] = m;
      }
    }

    final out = <ChurchPanelLeaderEntry>[];
    for (final e in leaderToDepts.entries) {
      final cpf = e.key;
      final depts = e.value
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final member = leaderToMember[cpf];
      final docId = member?.memberDocId ?? memberDocIdByCpf[cpf] ?? '';
      final data = member?.toMemberDataMap() ??
          <String, dynamic>{
            'NOME_COMPLETO':
                depts.isNotEmpty ? 'Líder — ${depts.first}' : 'Líder',
            if (cpf.length == 11) 'CPF': cpf,
          };
      final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? 'Líder')
          .toString()
          .trim();
      out.add(
        ChurchPanelLeaderEntry(
          memberDocId: docId.isEmpty ? cpf : docId,
          displayName: nome.isEmpty ? 'Líder' : nome,
          memberData: data,
          subtitles: depts,
          sortRank: 100,
        ),
      );
    }
    out.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  static Future<List<ChurchPanelLeaderEntry>> _computeCorpoAdmin(
    String churchId, {
    required List<String> corpoAdminRoles,
    MembersDirectorySnapshot? directoryHint,
  }) async {
    final directory = await _resolveDirectory(churchId, directoryHint);
    final out = <ChurchPanelLeaderEntry>[];

    void tryMember(String docId, Map<String, dynamic> data) {
      final roles = ChurchCorpoAdminRoles.rolesFromMember(data, corpoAdminRoles);
      if (roles.isEmpty) return;
      final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? '')
          .toString()
          .trim();
      out.add(
        ChurchPanelLeaderEntry(
          memberDocId: docId,
          displayName: nome.isEmpty ? 'Membro' : nome,
          memberData: data,
          subtitles: roles.map(churchRoleDisplayLabel).toList(),
          roles: roles,
          sortRank: ChurchCorpoAdminRoles.memberSortRank(roles),
        ),
      );
    }

    if (directory != null && directory.hasEntries) {
      for (final e in directory.entries) {
        tryMember(e.memberDocId, e.toMemberDataMap());
      }
    } else {
      final memSnap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchTenantResilientReads.membrosRecent(churchId, limit: 400),
        maxAttempts: 4,
      );
      for (final doc in memSnap.docs) {
        tryMember(doc.id, doc.data());
      }
    }

    out.sort((a, b) {
      if (a.sortRank != b.sortRank) return b.sortRank.compareTo(a.sortRank);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return out;
  }
}
