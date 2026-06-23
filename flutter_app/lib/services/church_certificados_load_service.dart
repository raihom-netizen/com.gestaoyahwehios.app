import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
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

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

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

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _fromDirectory(
    MembersDirectorySnapshot dir,
  ) {
    return dir.entries
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
    String churchId,
  ) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final cacheKey = '${churchId}_certificados_membros_$kAllMembersLimit';
    Future<QuerySnapshot<Map<String, dynamic>>> read() =>
        FirestoreReadResilience.getQuery(
          ChurchUiCollections.membros(churchId).limit(kAllMembersLimit),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 18)
              : const Duration(seconds: 12),
        );

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            read,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await read().timeout(ChurchPanelReadTimeouts.queryCap);
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
    final legacySnap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readLegacyMembers,
            maxAttempts: 4,
          ).timeout(ChurchPanelReadTimeouts.queryCap)
        : await readLegacyMembers().timeout(ChurchPanelReadTimeouts.queryCap);
    return legacySnap.docs;
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

    if (!forceRefresh) {
      final ram = peekRam(churchId);
      if (ram != null && ram.isNotEmpty) {
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: ram,
          readSource: 'ram',
        );
      }
    }

    Object? lastError;

    try {
      final docs = await _loadMembrosCollection(churchId);
      if (docs.isNotEmpty) {
        final sorted = _sortByNome(docs);
        putRam(churchId, sorted);
        return ChurchCertificadosLoadResult(
          churchId: churchId,
          docs: sorted,
          readSource: 'membros_collection',
        );
      }
    } catch (e, st) {
      lastError = e;
      debugPrint('ChurchCertificadosLoadService membros_collection: $e\n$st');
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
        final docs = _sortByNome(snap.docs);
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
      if (dir.hasEntries) {
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
        final docs = _sortByNome(snap.docs);
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
        docs: _sortByNome(mem.docs),
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
