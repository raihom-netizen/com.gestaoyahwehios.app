import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/optimistic_firestore_write.dart';
import 'package:gestao_yahweh/core/prayer_orando_membros_denorm.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
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
    this.fromCache = false,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String readSource;
  final String collectionPath;
  final String? softError;
  final bool fromCache;

  QuerySnapshot<Map<String, dynamic>> get snapshot =>
      MergedFirestoreQuerySnapshot(docs);

  bool get isEmpty => docs.isEmpty;
  bool get hasHardError => softError != null && softError!.trim().isNotEmpty;
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

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

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
  }) =>
      _peekRam(cacheKey(_resolve(seedTenantId), respondidaFilter, limit));

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? _peekRam(
    String key,
  ) {
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

  static void putRam(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool? respondidaFilter,
    int limit = kDefaultLimit,
  }) {
    final id = _resolve(churchId);
    if (id.isEmpty || docs.isEmpty) return;
    final allKey = cacheKey(id, null, limit);
    final sorted = _sortByCreatedAt(docs);
    _putRam(allKey, sorted.length > limit ? sorted.sublist(0, limit) : sorted);
    final filtered = _filterRespondida(sorted, respondidaFilter);
    _putRam(
      cacheKey(id, respondidaFilter, limit),
      filtered.length > limit ? filtered.sublist(0, limit) : filtered,
    );
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
    final allKey = cacheKey(churchId, null, limit);

    if (!forceRefresh && !forceServer) {
      final ramHit = _peekRam(ramKey);
      if (ramHit != null) {
        unawaited(_refreshInBackground(
          churchId: churchId,
          respondidaFilter: respondidaFilter,
          ramKey: ramKey,
          allKey: allKey,
          limit: limit,
        ));
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: ramHit,
          readSource: 'ram',
          collectionPath: path,
          fromCache: true,
        );
      }

      final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
      if (mem != null) {
        final docs = _sortByCreatedAt(mem.docs);
        _putRam(ramKey, docs);
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'firestore_mem',
          collectionPath: path,
          fromCache: true,
        );
      }

      final allRam = _peekRam(allKey);
      if (allRam != null && respondidaFilter != null) {
        final filtered = _sortByCreatedAt(
          _filterRespondida(allRam, respondidaFilter),
        );
        if (filtered.isNotEmpty) {
          _putRam(ramKey, filtered);
          unawaited(_refreshInBackground(
            churchId: churchId,
            respondidaFilter: respondidaFilter,
            ramKey: ramKey,
            allKey: allKey,
            limit: limit,
          ));
          return ChurchPedidosOracaoLoadResult(
            churchId: churchId,
            docs: filtered.length > limit
                ? filtered.sublist(0, limit)
                : filtered,
            readSource: 'ram_all_filtered',
            collectionPath: path,
            fromCache: true,
          );
        }
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          churchId,
          TenantModuleKeys.pedidosOracao,
        ).timeout(const Duration(seconds: 2));
        if (hive.isNotEmpty) {
          final allDocs =
              _sortByCreatedAt(TenantModuleHiveCache.toQueryDocuments(hive));
          if (allDocs.isNotEmpty) {
            _putRam(allKey, allDocs);
            var docs = _filterRespondida(allDocs, respondidaFilter);
            docs = _sortByCreatedAt(docs);
            _putRam(ramKey, docs);
            unawaited(_refreshInBackground(
              churchId: churchId,
              respondidaFilter: respondidaFilter,
              ramKey: ramKey,
              allKey: allKey,
              limit: limit,
            ));
            return ChurchPedidosOracaoLoadResult(
              churchId: churchId,
              docs: docs.length > limit ? docs.sublist(0, limit) : docs,
              readSource: 'hive',
              collectionPath: path,
              fromCache: true,
            );
          }
        }
      } catch (_) {}

      try {
        final cacheSnap = await ChurchUiCollections.pedidosOracao(churchId)
            .limit(limit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheSnap.docs.isNotEmpty) {
          final allDocs = _sortByCreatedAt(cacheSnap.docs);
          _putRam(allKey, allDocs);
          var docs = _filterRespondida(allDocs, respondidaFilter);
          docs = _sortByCreatedAt(docs);
          _putRam(ramKey, docs);
          unawaited(_refreshInBackground(
            churchId: churchId,
            respondidaFilter: respondidaFilter,
            ramKey: ramKey,
            allKey: allKey,
            limit: limit,
          ));
          return ChurchPedidosOracaoLoadResult(
            churchId: churchId,
            docs: docs.length > limit ? docs.sublist(0, limit) : docs,
            readSource: 'firestore_cache',
            collectionPath: path,
            fromCache: true,
          );
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
      _putRam(ramKey, docs);
      if (respondidaFilter == null) {
        _putRam(allKey, docs);
        unawaited(_persistHive(churchId, docs));
      }
      return ChurchPedidosOracaoLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: forceServer ? 'server' : 'firestore_full',
        collectionPath: path,
      );
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        churchId,
        'pedidosOracao',
        moduleLabel: 'Pedidos de Oração',
        limit: limit,
        cacheKey: '${ramKey}_direct',
      ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
      var docs = _filterRespondida(snap.docs, respondidaFilter);
      docs = _sortByCreatedAt(docs);
      _putRam(ramKey, docs);
      if (respondidaFilter == null) {
        _putRam(allKey, _sortByCreatedAt(snap.docs));
        unawaited(_persistHive(churchId, snap.docs));
      }
      return ChurchPedidosOracaoLoadResult(
        churchId: churchId,
        docs: docs,
        readSource: 'direct_list',
        collectionPath: path,
      );
    } catch (e) {
      lastError ??= e;
    }

    try {
      final repo = await ChurchRepository.pedidosOracao.listCacheFirst(
        churchIdHint: churchId,
        limit: limit,
        firestoreCacheKey: ramKey,
      );
      if (repo.items.isNotEmpty || repo.error == null) {
        var docs = _filterRespondida(repo.items, respondidaFilter);
        docs = _sortByCreatedAt(docs);
        _putRam(ramKey, docs);
        return ChurchPedidosOracaoLoadResult(
          churchId: churchId,
          docs: docs,
          readSource: 'repository_cache_first',
          collectionPath: path,
          fromCache: repo.error == null && docs.isNotEmpty,
          softError: repo.error,
        );
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(ramKey);
    if (mem != null) {
      return ChurchPedidosOracaoLoadResult(
        churchId: churchId,
        docs: _sortByCreatedAt(mem.docs),
        readSource: 'fallback_mem',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    final ramFallback = _peekRam(ramKey) ?? _peekRam(allKey);
    if (ramFallback != null) {
      return ChurchPedidosOracaoLoadResult(
        churchId: churchId,
        docs: ramFallback,
        readSource: 'ram_fallback',
        collectionPath: path,
        fromCache: true,
        softError: _humanizeError(lastError),
      );
    }

    return ChurchPedidosOracaoLoadResult(
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
      return 'Tempo esgotado ao carregar pedidos de oração. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }

  static Future<void> _refreshInBackground({
    required String churchId,
    required bool? respondidaFilter,
    required String ramKey,
    required String allKey,
    required int limit,
  }) async {
    try {
      final docs = await _loadFirestore(
        churchId: churchId,
        respondidaFilter: null,
        cacheKey: allKey,
        forceServer: false,
        limit: limit,
      );
      if (docs.isEmpty) return;
      _putRam(allKey, docs);
      _putRam(
        ramKey,
        _sortByCreatedAt(_filterRespondida(docs, respondidaFilter)),
      );
      await _persistHive(churchId, docs);
    } catch (_) {}
  }

  static Future<void> _persistHive(
    String churchId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return;
    try {
      await TenantModuleHiveCache.saveFromQuerySnapshot(
        churchId,
        TenantModuleKeys.pedidosOracao,
        MergedFirestoreQuerySnapshot(docs),
      );
    } catch (_) {}
  }

  static Future<void> persistAfterLoad(
    ChurchPedidosOracaoLoadResult result,
  ) async {
    if (result.churchId.isEmpty || result.docs.isEmpty) return;
    putRam(result.churchId, result.docs);
    await _persistHive(result.churchId, result.docs);
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
        final cacheSnap = await col
            .limit(limit)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 5));
        if (cacheSnap.docs.isNotEmpty) {
          return _sortByCreatedAt(
            _filterRespondida(cacheSnap.docs, respondidaFilter),
          );
        }
      } catch (_) {}
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> plainLoad() async {
      final plain = await FirestoreReadResilience.getQuery(
        col.limit(limit),
        cacheKey: '${cacheKey}_plain',
        maxAttempts: kIsWeb ? 4 : 3,
        attemptTimeout: ChurchPanelReadTimeouts.attempt,
      );
      return _sortByCreatedAt(_filterRespondida(plain.docs, respondidaFilter));
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readServer() async {
      // Prefer plain load + client filter (avoids compound index hangs on web).
      if (respondidaFilter != null) {
        try {
          return await plainLoad();
        } catch (_) {}
      }
      try {
        final snap = await FirestoreReadResilience.getQuery(
          ordered(),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
        return _sortByCreatedAt(snap.docs);
      } catch (_) {
        return plainLoad();
      }
    }

    if (kIsWeb) {
      try {
        final plain = await FirestoreWebGuard.runWithWebRecovery(
          plainLoad,
          maxAttempts: 4,
        ).timeout(
        kIsWeb ? const Duration(seconds: 14) : ChurchPanelReadTimeouts.queryCap,
      );
        if (plain.isNotEmpty) return plain;
      } catch (_) {}
    }

    final docs = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(const Duration(seconds: 14))
        : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);

    if (docs.isEmpty) {
      try {
        return await plainLoad();
      } catch (_) {}
    }
    return docs;
  }

  static void removeFromRam(String seedTenantId, Iterable<String> docIds) {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return;
    final ids = docIds.toSet();
    for (final key in _ram.keys.toList()) {
      if (!key.startsWith('${churchId}_pedidos_oracao_')) continue;
      final hit = _ram[key];
      if (hit == null) continue;
      _ram[key] = (
        docs: hit.docs.where((d) => !ids.contains(d.id)).toList(),
        at: DateTime.now(),
      );
    }
  }

  /// Gravação rápida — OptimisticFirestoreWrite + stamp tenant.
  static Future<String> savePedido({
    required String churchId,
    required Map<String, dynamic> payload,
    String? existingDocId,
  }) async {
    final cid = _resolve(churchId);
    if (cid.isEmpty) throw StateError('Igreja não identificada.');

    final col = ChurchUiCollections.pedidosOracao(cid);
    final data = ChurchTenantFields.stamp(cid, payload);

    if (existingDocId != null && existingDocId.trim().isNotEmpty) {
      final id = existingDocId.trim();
      await OptimisticFirestoreWrite.update(
        ref: col.doc(id),
        data: data,
        module: OfflineModules.pedidosOracao,
        tenantId: cid,
      );
      return id;
    }

    final docRef = col.doc();
    final create = Map<String, dynamic>.from(data)
      ..putIfAbsent('orandoCount', () => 0)
      ..putIfAbsent('orandoUids', () => <String>[])
      ..putIfAbsent(PrayerOrandoMembrosDenorm.field, () => <Map<String, dynamic>>[])
      ..putIfAbsent('respondida', () => false)
      ..['createdAt'] = FieldValue.serverTimestamp();

    await OptimisticFirestoreWrite.set(
      ref: docRef,
      data: create,
      module: OfflineModules.pedidosOracao,
      tenantId: cid,
    );
    return docRef.id;
  }

  static Future<({String nome, String fotoUrl})> resolveOrandoMemberProfile({
    required String churchId,
    required String uid,
    String? nomeHint,
    String? fotoHint,
  }) async {
    var nome = (nomeHint ?? '').trim();
    var foto = (fotoHint ?? '').trim();
    if (nome.isEmpty || foto.isEmpty) {
      try {
        final directory =
            await MembersDirectorySnapshotService.readOnce(churchId);
        for (final e in directory.entries) {
          if (e.authUid != uid) continue;
          if (nome.isEmpty) nome = e.displayName.trim();
          if (foto.isEmpty) {
            foto = (e.photoThumbUrl ?? e.photoUrl ?? '').trim();
          }
          break;
        }
      } catch (_) {}
    }
    if (nome.isEmpty) nome = 'Membro';
    return (nome: nome, fotoUrl: foto);
  }

  /// Reconstrói `orandoMembros` a partir de UIDs + Members Directory.
  static Future<List<Map<String, dynamic>>> rebuildOrandoMembrosFromUids({
    required String churchId,
    required List<String> uids,
    List<Map<String, dynamic>>? existingMembros,
  }) async {
    final cid = _resolve(churchId);
    final uidSet = uids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (uidSet.isEmpty) return const [];

    final prevByUid = <String, Map<String, dynamic>>{};
    for (final m in PrayerOrandoMembrosDenorm.parseList(existingMembros)) {
      final uid = (m['uid'] ?? '').toString();
      if (uid.isNotEmpty) prevByUid[uid] = m;
    }

    MembersDirectorySnapshot? directory;
    try {
      directory = await MembersDirectorySnapshotService.readOnce(cid);
    } catch (_) {}

    final out = <Map<String, dynamic>>[];
    for (final uid in uidSet) {
      final prev = prevByUid[uid];
      var nome = (prev?['nome'] ?? '').toString().trim();
      var foto = (prev?['fotoUrl'] ?? '').toString().trim();
      if (directory != null) {
        for (final e in directory.entries) {
          if (e.authUid != uid) continue;
          if (nome.isEmpty) nome = e.displayName.trim();
          if (foto.isEmpty) foto = (e.photoThumbUrl ?? e.photoUrl ?? '').trim();
          break;
        }
      }
      if (nome.isEmpty) nome = 'Membro';
      out.add(PrayerOrandoMembrosDenorm.entry(
        uid: uid,
        nome: nome,
        fotoUrl: foto,
      ));
    }
    return out;
  }

  /// Remove um intercessor (self ou líder).
  static Future<void> removeOrandoMember({
    required String churchId,
    required String docId,
    required String targetUid,
    List<Map<String, dynamic>>? currentOrandoMembros,
  }) =>
      toggleOrando(
        churchId: churchId,
        docId: docId,
        uid: targetUid,
        removing: true,
        currentOrandoMembros: currentOrandoMembros,
      );

  /// Remove o mesmo intercessor de vários pedidos.
  static Future<int> removeOrandoMemberFromPedidos({
    required String seedTenantId,
    required String targetUid,
    required Iterable<({String docId, List<Map<String, dynamic>> membros})>
        targets,
  }) async {
    final uid = targetUid.trim();
    if (uid.isEmpty) return 0;
    var count = 0;
    for (final t in targets) {
      final membros = PrayerOrandoMembrosDenorm.parseList(t.membros);
      if (!PrayerOrandoMembrosDenorm.uidsFromMembros(membros).contains(uid)) {
        continue;
      }
      await removeOrandoMember(
        churchId: seedTenantId,
        docId: t.docId,
        targetUid: uid,
        currentOrandoMembros: membros,
      );
      count++;
    }
    unawaited(invalidate(seedTenantId));
    return count;
  }

  /// Limpa todos os intercessores de um pedido.
  static Future<void> clearOrandoFromPedido({
    required String churchId,
    required String docId,
  }) async {
    final cid = _resolve(churchId);
    await OptimisticFirestoreWrite.update(
      ref: ChurchUiCollections.pedidosOracao(cid).doc(docId.trim()),
      data: {
        'orandoUids': <String>[],
        'orandoCount': 0,
        PrayerOrandoMembrosDenorm.field: <Map<String, dynamic>>[],
      },
      module: OfflineModules.pedidosOracao,
      tenantId: cid,
    );
  }

  /// Limpa intercessores de vários pedidos (lote).
  static Future<int> clearOrandoFromPedidos({
    required String seedTenantId,
    required Iterable<String> docIds,
  }) async {
    final ids = docIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (ids.isEmpty) return 0;
    for (final id in ids) {
      await clearOrandoFromPedido(churchId: seedTenantId, docId: id);
    }
    unawaited(invalidate(seedTenantId));
    return ids.length;
  }

  static Future<void> toggleOrando({
    required String churchId,
    required String docId,
    required String uid,
    required bool removing,
    String? memberNome,
    String? memberFotoUrl,
    List<Map<String, dynamic>>? currentOrandoMembros,
  }) async {
    final cid = _resolve(churchId);
    final ref = ChurchUiCollections.pedidosOracao(cid).doc(docId.trim());
    var membros = PrayerOrandoMembrosDenorm.parseList(currentOrandoMembros);

    if (removing) {
      membros = PrayerOrandoMembrosDenorm.removeUid(membros, uid);
      await OptimisticFirestoreWrite.update(
        ref: ref,
        data: {
          'orandoUids': FieldValue.arrayRemove([uid]),
          'orandoCount': membros.length,
          PrayerOrandoMembrosDenorm.field: membros,
        },
        module: OfflineModules.pedidosOracao,
        tenantId: cid,
      );
      return;
    }

    final profile = await resolveOrandoMemberProfile(
      churchId: cid,
      uid: uid,
      nomeHint: memberNome,
      fotoHint: memberFotoUrl,
    );
    membros = PrayerOrandoMembrosDenorm.upsert(
      membros,
      uid: uid,
      nome: profile.nome,
      fotoUrl: profile.fotoUrl,
    );
    await OptimisticFirestoreWrite.update(
      ref: ref,
      data: {
        'orandoUids': FieldValue.arrayUnion([uid]),
        'orandoCount': membros.length,
        PrayerOrandoMembrosDenorm.field: membros,
      },
      module: OfflineModules.pedidosOracao,
      tenantId: cid,
    );
  }

  static Future<void> marcarRespondida({
    required String churchId,
    required String docId,
  }) async {
    final cid = _resolve(churchId);
    await OptimisticFirestoreWrite.update(
      ref: ChurchUiCollections.pedidosOracao(cid).doc(docId.trim()),
      data: {'respondida': true},
      module: OfflineModules.pedidosOracao,
      tenantId: cid,
    );
  }

  /// Exclui pedidos em batch (chunks de 450).
  static Future<int> deletePedidos({
    required String seedTenantId,
    required Iterable<String> docIds,
  }) async {
    final churchId = _resolve(seedTenantId);
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty || churchId.isEmpty) return 0;

    const chunkSize = 450;
    final col = ChurchUiCollections.pedidosOracao(churchId);

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final slice = ids.sublist(i, end);
      final batch = ChurchRepository.batch();
      for (final id in slice) {
        batch.delete(col.doc(id));
      }
      await runFirestorePublishWithRecovery(
        () => batch.commit(),
        maxAttempts: kIsWeb ? 3 : 2,
      );
    }

    removeFromRam(churchId, ids);
    unawaited(invalidate(seedTenantId));
    return ids.length;
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
