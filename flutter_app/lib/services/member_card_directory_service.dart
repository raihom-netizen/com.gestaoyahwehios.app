import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';

/// Signatário de carteirinha / certificado (pastor, gestor, etc.).
class MemberCardSignatory {
  const MemberCardSignatory({
    required this.memberId,
    required this.nome,
    required this.cargo,
    this.cpf,
    this.assinaturaUrl,
  });

  final String memberId;
  final String nome;
  final String cargo;
  final String? cpf;
  final String? assinaturaUrl;

  static MemberCardSignatory? fromMap(String id, Map<String, dynamic> d) {
    final nome = (d['nome'] ?? d['NOME_COMPLETO'] ?? '').toString().trim();
    if (nome.isEmpty) return null;
    final url =
        (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
    return MemberCardSignatory(
      memberId: (d['memberId'] ?? id).toString(),
      nome: nome,
      cargo: (d['cargo'] ?? '').toString().trim().isNotEmpty
          ? (d['cargo'] ?? '').toString().trim()
          : signatoryCargoDisplayLabel(d),
      cpf: (d['cpf'] ?? '').toString().trim().isEmpty
          ? null
          : (d['cpf'] ?? '').toString().trim(),
      assinaturaUrl: url.isEmpty ? null : url,
    );
  }

  Map<String, dynamic> toFirestoreIndexEntry() => {
        'memberId': memberId,
        'nome': nome,
        'cargo': cargo,
        if (cpf != null) 'cpf': cpf,
        if (assinaturaUrl != null) 'assinaturaUrl': assinaturaUrl,
      };
}

/// Item leve para listas / pickers de emissão em lote.
class MemberCardListEntry {
  const MemberCardListEntry({
    required this.id,
    required this.name,
    required this.data,
    this.photoUrl,
  });

  final String id;
  final String name;
  final Map<String, dynamic> data;
  final String? photoUrl;
}

/// Leituras do módulo Cartão membro — `igrejas/{churchId}/membros` (padrão Membros).
abstract final class MemberCardDirectoryService {
  MemberCardDirectoryService._();

  static const _signatoryCacheDoc = 'carteira_signatories';
  static const _cacheMaxAge = Duration(hours: 12);

  static final Map<String, Future<List<MemberCardListEntry>>> _membersInflight =
      {};

  static DocumentReference<Map<String, dynamic>> _signatoryCacheRef(
    String churchId,
  ) =>
      ChurchRepository.churchDoc(churchId)
          .collection('config')
          .doc(_signatoryCacheDoc);

  static List<MemberCardListEntry> _docsToEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int effectiveLimit,
  ) {
    final out = <MemberCardListEntry>[];
    for (final d in docs) {
      if (out.length >= effectiveLimit) break;
      final blind = BlindMemberDoc.fromFirestore(id: d.id, data: d.data());
      if (blind.displayName.trim().isEmpty) continue;
      out.add(
        MemberCardListEntry(
          id: blind.id,
          name: blind.displayName,
          data: blind.toMemberDataMap(),
          photoUrl: blind.photoUrl ?? blind.photoThumbUrl,
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// `igrejas/{churchId}` — mesmo resolve que [members_page] / shell.
  static String resolveChurchId(String tenantHint) {
    final resolved = ChurchPanelTenant.resolve(tenantHint.trim());
    final churchId = ChurchRepository.churchId(resolved);
    return churchId.isNotEmpty ? churchId : resolved;
  }

  static List<MemberCardListEntry> _directoryEntriesToList(
    List<MemberDirectoryEntry> entries,
    int effectiveLimit,
  ) {
    final out = <MemberCardListEntry>[];
    for (final e in entries) {
      if (out.length >= effectiveLimit) break;
      final url = (e.photoUrl ?? e.photoThumbUrl ?? '').trim();
      out.add(
        MemberCardListEntry(
          id: e.memberDocId,
          name: e.displayName,
          data: e.toMemberDataMap(),
          photoUrl: url.isNotEmpty ? url : null,
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static bool _isTargetIdConflict(Object e) =>
      FirestoreWebGuard.isTargetIdConflict(e);

  /// Lista completa — `igrejas/{churchId}/membros` via [ChurchMembersLoadService].
  static Future<List<MemberCardListEntry>> loadMembers({
    required String tenantId,
    int limit = YahwehPerformanceV4.adminExportBatchLimit,
    bool forceRefresh = false,
  }) {
    final churchId = resolveChurchId(tenantId);
    final effectiveLimit = limit <= 0
        ? YahwehPerformanceV4.adminExportBatchLimit
        : limit.clamp(1, YahwehPerformanceV4.adminExportBatchLimit);
    final inflightKey = '${churchId.trim()}|$effectiveLimit|$forceRefresh';

    if (!forceRefresh) {
      final pending = _membersInflight[inflightKey];
      if (pending != null) return pending;
    }

    final future = _loadMembersImpl(
      churchId: churchId,
      effectiveLimit: effectiveLimit,
      forceRefresh: forceRefresh,
    );
    _membersInflight[inflightKey] = future;
    future.whenComplete(() => _membersInflight.remove(inflightKey));
    return future;
  }

  static Future<List<MemberCardListEntry>> _loadMembersImpl({
    required String churchId,
    required int effectiveLimit,
    required bool forceRefresh,
  }) async {
    if (churchId.isEmpty) {
      throw Exception(
        'Igreja não identificada. Path esperado: igrejas/{churchId}/membros',
      );
    }

    if (!forceRefresh) {
      final instant = peekMembersSync(churchId, limit: effectiveLimit);
      if (instant != null && instant.isNotEmpty) return instant;
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Future<List<MemberCardListEntry>> fromGateway({bool refresh = false}) async {
      final result = await ChurchMembersLoadService.load(
        seedTenantId: churchId,
        limit: effectiveLimit,
        forceRefresh: refresh || forceRefresh,
      ).timeout(ChurchPanelReadTimeouts.queryCap);

      if (result.docs.isNotEmpty) {
        return _docsToEntries(result.docs, effectiveLimit);
      }
      if (result.directoryEntries.isNotEmpty) {
        final out = _directoryEntriesToList(
          result.directoryEntries,
          effectiveLimit,
        );
        if (out.isNotEmpty) return out;
      }

      final err = result.softError?.trim();
      if (err != null && err.isNotEmpty) {
        throw Exception('$err\nPath: igrejas/$churchId/membros');
      }
      return const [];
    }

    try {
      final loaded = await fromGateway();
      if (loaded.isNotEmpty) return loaded;
    } catch (e) {
      if (!_isTargetIdConflict(e)) rethrow;
    }

    if (kIsWeb) {
      try {
        await FirestoreWebGuard.recoverFirestoreWebSession(
          allowHardReconnect: true,
        );
      } catch (_) {}
      try {
        final retry = await fromGateway(refresh: true);
        if (retry.isNotEmpty) return retry;
      } catch (_) {}
    }

    final plain = await _loadPlainMembersOnce(churchId, effectiveLimit);
    if (plain.isNotEmpty) return plain;

    final cached = peekMembersSync(churchId, limit: effectiveLimit);
    if (cached != null && cached.isNotEmpty) return cached;

    throw Exception(
      'Não foi possível carregar membros.\nPath: igrejas/$churchId/membros',
    );
  }

  /// Plain `limit` — evita paginação paralela que dispara «Target ID already exists» na Web.
  static Future<List<MemberCardListEntry>> _loadPlainMembersOnce(
    String churchId,
    int maxTotal,
  ) async {
    if (churchId.isEmpty || maxTotal <= 0) return const [];
    final ref = ChurchUiCollections.membros(churchId);
    final cacheKey = 'member_card_plain_${churchId}_$maxTotal';
    try {
      final docs = await ChurchModuleFirestoreListRead.queryPlainFirst(
        reference: ref,
        cacheKey: cacheKey,
        limit: maxTotal,
        sortDocs: (list) {
          final sorted =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(list);
          sorted.sort(
            (a, b) => (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? '')
                .toString()
                .toLowerCase()
                .compareTo(
                  (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? '')
                      .toString()
                      .toLowerCase(),
                ),
          );
          return sorted;
        },
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (docs.isNotEmpty) {
        return _docsToEntries(docs, maxTotal);
      }
    } catch (_) {}

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        ChurchDataPaths.membros,
        moduleLabel: 'CartaoMembro',
        limit: maxTotal,
        cacheKey: cacheKey,
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      if (snap.docs.isNotEmpty) {
        return _docsToEntries(snap.docs, maxTotal);
      }
    } catch (_) {}

    final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey);
    if (mem != null && mem.docs.isNotEmpty) {
      return _docsToEntries(mem.docs, maxTotal);
    }
    return const [];
  }

  /// Lista instantânea (RAM partilhada com Membros) — zero rede.
  static List<MemberCardListEntry>? peekMembersSync(
    String tenantId, {
    int limit = YahwehPerformanceV4.adminExportBatchLimit,
  }) {
    final churchId = resolveChurchId(tenantId);
    if (churchId.isEmpty) return null;
    final effectiveLimit = limit <= 0
        ? YahwehPerformanceV4.adminExportBatchLimit
        : limit.clamp(1, YahwehPerformanceV4.adminExportBatchLimit);

    final dirMem = MembersDirectorySnapshotService.peekMemory(churchId);
    if (dirMem != null && dirMem.hasEntries) {
      return _directoryEntriesToList(dirMem.entries, effectiveLimit);
    }

    final ram = ChurchMembersLoadService.peekRamAny(churchId);
    if (ram == null || ram.isEmpty) return null;
    return _docsToEntries(ram, effectiveLimit);
  }

  static bool _cacheFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt.toDate()) < _cacheMaxAge;
  }

  static List<MemberCardSignatory> _parseSignatoryCache(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return const [];
    final raw = data['items'];
    if (raw is! List) return const [];
    final out = <MemberCardSignatory>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['memberId'] ?? '').toString();
      final s = MemberCardSignatory.fromMap(id, m);
      if (s == null) continue;
      if (!memberCanSignChurchDocuments({
        'CARGO': s.cargo,
        'FUNCAO': s.cargo,
        'FUNCOES': [s.cargo],
      })) {
        continue;
      }
      out.add(s);
    }
    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  static List<MemberCardSignatory> _entriesToSignatories(
    List<ChurchSignatoryEntry> entries,
  ) {
    return entries
        .map(
          (e) => MemberCardSignatory(
            memberId: e.memberId,
            nome: e.nome,
            cargo: e.cargo,
            cpf: e.cpfDigits,
            assinaturaUrl: e.assinaturaUrl,
          ),
        )
        .toList();
  }

  /// Signatários — `igrejas/{churchId}/config/carteira_signatories` + CF opcional.
  static Future<List<MemberCardSignatory>> loadSignatories(
    String tenantId, {
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(
      ChurchPanelTenant.resolve(tenantId.trim()),
    );
    if (churchId.isEmpty) return const [];

    if (!forceRefresh) {
      try {
        final cache = await _signatoryCacheRef(churchId).get();
        final data = cache.data();
        if (cache.exists && _cacheFresh(data?['updatedAt'] as Timestamp?)) {
          final parsed = _parseSignatoryCache(data);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {}
    }

    try {
      final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '')
          .httpsCallable('refreshCarteiraSignatoriesIndex');
      final res = await fn
          .call<Map<dynamic, dynamic>>({'tenantId': churchId})
          .timeout(const Duration(seconds: 25));
      final items = res.data['items'];
      if (items is List && items.isNotEmpty) {
        final parsed = _parseSignatoryCache({'items': items});
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    final entries = await ChurchSignatoryLoadService.loadEligible(
      seedTenantId: churchId,
    );
    final list = _entriesToSignatories(entries);
    if (list.isNotEmpty) {
      unawaited(_writeSignatoryCache(churchId, list));
    }
    return list;
  }

  static Future<void> _writeSignatoryCache(
    String churchId,
    List<MemberCardSignatory> list,
  ) async {
    try {
      await _signatoryCacheRef(churchId).set({
        'items': list.map((e) => e.toFirestoreIndexEntry()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'client',
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

