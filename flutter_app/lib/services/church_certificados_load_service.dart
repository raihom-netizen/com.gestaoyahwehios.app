import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
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

  static String _resolve(String hint) => ChurchPanelTenant.resolve(hint.trim());

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
    } catch (e) {
      lastError = e;
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
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
    } catch (e) {
      lastError ??= e;
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
    } catch (e) {
      lastError ??= e;
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
