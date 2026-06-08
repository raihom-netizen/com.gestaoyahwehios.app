import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

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

/// Leituras rápidas — carteirinha (membros paginados + índice de signatários).
abstract final class MemberCardDirectoryService {
  MemberCardDirectoryService._();

  static const _signatoryCacheDoc = 'carteira_signatories';
  static const _cacheMaxAge = Duration(hours: 12);

  static const _roleQueryKeys = [
    'gestor',
    'pastor',
    'pastora',
    'secretario',
    'secretaria',
    'tesoureiro',
    'lider',
  ];

  static CollectionReference<Map<String, dynamic>> _membros(String operationalTenantId) =>
      ChurchOperationalPaths.churchDoc(operationalTenantId.trim())
          .collection('membros');

  static DocumentReference<Map<String, dynamic>> _signatoryCacheRef(
          String operationalTenantId) =>
      ChurchOperationalPaths.churchDoc(operationalTenantId.trim())
          .collection('config')
          .doc(_signatoryCacheDoc);

  /// Lista paginada (cache SWR) — substitui `.get()` ilimitado / limit 500.
  static Future<List<MemberCardListEntry>> loadMembers({
    required String tenantId,
    int limit = YahwehPerformanceV4.memberCardListPageSize,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const [];

    // Leitura instantânea — `_panel_cache/members_directory` (1 doc).
    final effectiveLimit = limit <= 0
        ? YahwehPerformanceV4.adminExportBatchLimit
        : limit.clamp(1, YahwehPerformanceV4.adminExportBatchLimit);

    try {
      final dir = await MembersDirectorySnapshotService.readOnce(tid);
      if (dir.hasEntries) {
        final out = <MemberCardListEntry>[];
        for (final e in dir.entries) {
          if (out.length >= effectiveLimit) break;
          final data = e.toMemberDataMap();
          final url = (e.photoUrl ?? '').trim();
          out.add(MemberCardListEntry(
            id: e.memberDocId,
            name: e.displayName,
            data: data,
            photoUrl: url.isNotEmpty ? url : null,
          ));
        }
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (out.isNotEmpty) {
          unawaited(MembersDirectorySnapshotService.warmFromCallableIfStale(tid));
          return out;
        }
      }
    } catch (_) {}

    final snap = await ChurchTenantResilientReads.membrosRecent(
      tid,
      limit: effectiveLimit,
    );
    final out = <MemberCardListEntry>[];
    for (final d in snap.docs) {
      final data = Map<String, dynamic>.from(d.data());
      final name =
          (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? d.id)
              .toString();
      final url = imageUrlFromMap(data);
      out.add(MemberCardListEntry(
        id: d.id,
        name: name,
        data: data,
        photoUrl: url.isNotEmpty ? url : null,
      ));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static bool _cacheFresh(Timestamp? updatedAt) {
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt.toDate()) < _cacheMaxAge;
  }

  static List<MemberCardSignatory> _parseSignatoryCache(
      Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['items'];
    if (raw is! List) return const [];
    final out = <MemberCardSignatory>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = (m['memberId'] ?? '').toString();
      final s = MemberCardSignatory.fromMap(id, m);
      if (s != null) out.add(s);
    }
    out.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return out;
  }

  /// Signatários — cache Firestore → Cloud Function → consultas por cargo.
  static Future<List<MemberCardSignatory>> loadSignatories(
    String tenantId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      try {
        final cache = await _signatoryCacheRef(tenantId).get();
        final data = cache.data();
        if (cache.exists &&
            _cacheFresh(data?['updatedAt'] as Timestamp?)) {
          final parsed = _parseSignatoryCache(data);
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {}
    }

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('refreshCarteiraSignatoriesIndex');
      final res = await fn.call<Map<dynamic, dynamic>>({'tenantId': tenantId});
      final items = res.data['items'];
      if (items is List && items.isNotEmpty) {
        return _parseSignatoryCache({'items': items});
      }
    } catch (_) {}

    return _loadSignatoriesClientFallback(tenantId);
  }

  static Future<List<MemberCardSignatory>> _loadSignatoriesClientFallback(
      String tenantId) async {
    final col = _membros(tenantId);
    final byId = <String, MemberCardSignatory>{};

    Future<void> absorb(QuerySnapshot<Map<String, dynamic>> snap) async {
      for (final doc in snap.docs) {
        if (byId.containsKey(doc.id)) continue;
        final d = doc.data();
        if (!memberCanSignChurchDocuments(d)) continue;
        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
        if (nome.isEmpty) continue;
        final url =
            (d['assinaturaUrl'] ?? d['assinatura_url'] ?? '').toString().trim();
        byId[doc.id] = MemberCardSignatory(
          memberId: doc.id,
          nome: nome,
          cargo: signatoryCargoDisplayLabel(d),
          cpf: null,
          assinaturaUrl: url.isEmpty ? null : url,
        );
      }
    }

    await Future.wait(
      _roleQueryKeys.map((role) async {
        try {
          final snap = await col
              .where('FUNCOES', arrayContains: role)
              .limit(YahwehPerformanceV4.memberCardSignatoryQueryLimit)
              .get();
          await absorb(snap);
        } catch (_) {}
      }),
    );

    try {
      final flagged = await col
          .where('certificadoSignatario', isEqualTo: true)
          .limit(YahwehPerformanceV4.memberCardSignatoryQueryLimit)
          .get();
      await absorb(flagged);
    } catch (_) {}

    if (byId.isEmpty) {
      try {
        final snap = await col
            .limit(YahwehPerformanceV4.memberCardSignatoryQueryLimit * 2)
            .get();
        await absorb(snap);
      } catch (_) {}
    }

    final list = byId.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    if (list.isNotEmpty) {
      unawaited(_writeSignatoryCache(tenantId, list));
    }
    return list;
  }

  static Future<void> _writeSignatoryCache(
    String tenantId,
    List<MemberCardSignatory> list,
  ) async {
    try {
      await _signatoryCacheRef(tenantId).set({
        'items': list.map((e) => e.toFirestoreIndexEntry()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'client',
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
