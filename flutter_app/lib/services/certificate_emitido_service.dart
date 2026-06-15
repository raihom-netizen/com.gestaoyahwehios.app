import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kIsWeb;

import 'package:gestao_yahweh/core/certificate_protocol_id.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_document_version_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Estado partilhado — abas «Painel de emissões» + «Histórico» (uma carga).
class CertificadosHistoricoState {
  const CertificadosHistoricoState({
    this.docs = const [],
    this.loading = false,
    this.error,
    this.loadedLimit = CertificateEmitidoService.kHistoricoPageSize,
    this.hasMore = false,
    this.readSource = '',
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool loading;
  final String? error;
  final int loadedLimit;
  final bool hasMore;
  final String readSource;

  CertificadosHistoricoState copyWith({
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    bool? loading,
    String? error,
    bool clearError = false,
    int? loadedLimit,
    bool? hasMore,
    String? readSource,
  }) {
    return CertificadosHistoricoState(
      docs: docs ?? this.docs,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      loadedLimit: loadedLimit ?? this.loadedLimit,
      hasMore: hasMore ?? this.hasMore,
      readSource: readSource ?? this.readSource,
    );
  }
}

/// Certificados emitidos: **dados completos** em `igrejas/{churchId}/certificados_emitidos/{id}`.
///
/// Histórico leve (legado): `igrejas/{churchId}/certificados_historico/{id}`.
/// Validação pública (QR): `igrejas/{churchId}/certificados_protocol_index/{id}`.
class CertificateEmitidoService {
  CertificateEmitidoService._();

  static const int kHistoricoPageSize = 50;
  static const int kHistoricoMaxFetch = 320;

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
        int limit,
      })> _historicoRam = {};

  static const Duration _historicoRamTtl = Duration(minutes: 8);

  static final Map<String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>
      _historicoInflight = {};

  static final Map<String, ValueNotifier<CertificadosHistoricoState>>
      _historicoNotifiers = {};

  static String _churchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static CollectionReference<Map<String, dynamic>> _emitidosCol(
    String tenantHint,
  ) =>
      ChurchUiCollections.certificados(_churchId(tenantHint));

  static DocumentReference<Map<String, dynamic>> _protocolIndexDoc(
    String tenantHint,
    String certId,
  ) =>
      ChurchUiCollections.certificadosProtocolIndex(_churchId(tenantHint))
          .doc(certId);

  static ValueNotifier<CertificadosHistoricoState> historicoNotifier(
    String tenantHint,
  ) {
    final key = _churchId(tenantHint);
    return _historicoNotifiers.putIfAbsent(
      key,
      () {
        final peek = peekHistoricoRam(tenantHint);
        if (peek != null && peek.isNotEmpty) {
          return ValueNotifier(
            CertificadosHistoricoState(
              docs: peek,
              loadedLimit: kHistoricoPageSize,
              hasMore: peek.length >= kHistoricoPageSize,
              readSource: 'ram',
            ),
          );
        }
        return ValueNotifier(
          const CertificadosHistoricoState(loading: true),
        );
      },
    );
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekHistoricoRam(
    String tenantHint,
  ) {
    final key = _churchId(tenantHint);
    if (key.isEmpty) return null;
    final hit = _historicoRam[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _historicoRamTtl) {
      _historicoRam.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void invalidateHistoricoCache(String tenantHint) {
    final key = _churchId(tenantHint);
    if (key.isEmpty) return;
    _historicoRam.remove(key);
    final n = _historicoNotifiers[key];
    if (n != null) {
      n.value = const CertificadosHistoricoState(loading: false);
    }
  }

  static DateTime? _dataEmissao(Map<String, dynamic> d) {
    final raw = d['dataEmissao'] ?? d['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByDataEmissaoDesc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _dataEmissao(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _dataEmissao(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  static Future<void> _ensureWebReady() async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchEmitidosPage({
    required String churchId,
    required int limit,
  }) async {
    await _ensureWebReady();
    final col = ChurchUiCollections.certificados(churchId);
    return FirestoreWebGuard.runWithWebRecovery(() async {
      try {
        final snap = await col
            .orderBy('dataEmissao', descending: true)
            .limit(limit)
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs;
      } catch (e) {
        debugPrint(
          'certificados_emitidos orderBy(dataEmissao) fallback ($churchId): $e',
        );
        final snap = await col
            .limit(kHistoricoMaxFetch)
            .get(const GetOptions(source: Source.serverAndCache));
        return _sortByDataEmissaoDesc(snap.docs).take(limit).toList();
      }
    }, maxAttempts: 4);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchHistoricoLegadoPage({
    required String churchId,
    required int limit,
  }) async {
    await _ensureWebReady();
    final col = ChurchUiCollections.certificadosHistorico(churchId);
    return FirestoreWebGuard.runWithWebRecovery(() async {
      try {
        final snap = await col
            .orderBy('dataEmissao', descending: true)
            .limit(limit)
            .get(const GetOptions(source: Source.serverAndCache));
        return snap.docs;
      } catch (e) {
        debugPrint(
          'certificados_historico orderBy(dataEmissao) fallback ($churchId): $e',
        );
        final snap = await col
            .limit(kHistoricoMaxFetch)
            .get(const GetOptions(source: Source.serverAndCache));
        return _sortByDataEmissaoDesc(snap.docs).take(limit).toList();
      }
    }, maxAttempts: 4);
  }

  /// Histórico no painel — `igrejas/{churchId}/certificados_emitidos` (+ fallback histórico).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadHistorico(
    String tenantHint, {
    int limit = kHistoricoPageSize,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(tenantHint);
    if (churchId.isEmpty) return const [];

    final capped = limit.clamp(1, kHistoricoMaxFetch);

    if (!forceRefresh) {
      final hit = _historicoRam[churchId];
      if (hit != null &&
          DateTime.now().difference(hit.at) < _historicoRamTtl &&
          hit.limit >= capped) {
        return hit.docs.take(capped).toList();
      }
    }

    final inflightKey = '$churchId|$capped';
    if (!forceRefresh) {
      final pending = _historicoInflight[inflightKey];
      if (pending != null) return pending;
    }

    final future = _loadHistoricoImpl(churchId, capped);
    _historicoInflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _historicoInflight.remove(inflightKey);
    }
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadHistoricoImpl(String churchId, int limit) async {
    Object? lastError;
    StackTrace? lastSt;

    try {
      final docs = await _fetchEmitidosPage(churchId: churchId, limit: limit);
      if (docs.isNotEmpty) {
        _historicoRam[churchId] = (
          docs: List.from(docs),
          at: DateTime.now(),
          limit: limit,
        );
        return docs;
      }
    } catch (e, st) {
      lastError = e;
      lastSt = st;
      debugPrint('certificados_emitidos load ($churchId): $e\n$st');
    }

    try {
      final docs =
          await _fetchHistoricoLegadoPage(churchId: churchId, limit: limit);
      if (docs.isNotEmpty) {
        _historicoRam[churchId] = (
          docs: List.from(docs),
          at: DateTime.now(),
          limit: limit,
        );
        return docs;
      }
    } catch (e, st) {
      lastError = e;
      lastSt = st;
      debugPrint('certificados_historico load ($churchId): $e\n$st');
    }

    if (lastError != null) {
      throw lastError is Exception
          ? lastError
          : Exception(lastError.toString());
    }
    if (lastSt != null) {
      debugPrint('certificados historico empty ($churchId)');
    }
    return const [];
  }

  /// Atualiza o estado partilhado das abas Painel/Histórico.
  static Future<void> refreshHistoricoPanel(
    String tenantHint, {
    bool forceRefresh = false,
    int? limit,
  }) async {
    final churchId = _churchId(tenantHint);
    if (churchId.isEmpty) {
      historicoNotifier(tenantHint).value = const CertificadosHistoricoState(
        error: 'Igreja não identificada.',
      );
      return;
    }

    final notifier = historicoNotifier(tenantHint);
    final targetLimit = (limit ?? notifier.value.loadedLimit)
        .clamp(kHistoricoPageSize, kHistoricoMaxFetch);

    if (!forceRefresh &&
        notifier.value.docs.isNotEmpty &&
        notifier.value.loadedLimit >= targetLimit &&
        notifier.value.error == null) {
      return;
    }

    notifier.value = notifier.value.copyWith(
      loading: notifier.value.docs.isEmpty,
      clearError: true,
      loadedLimit: targetLimit,
    );

    try {
      final docs = await loadHistorico(
        tenantHint,
        limit: targetLimit,
        forceRefresh: forceRefresh,
      );
      notifier.value = CertificadosHistoricoState(
        docs: docs,
        loading: false,
        loadedLimit: targetLimit,
        hasMore:
            docs.length >= targetLimit && targetLimit < kHistoricoMaxFetch,
        readSource: 'emitidos',
      );
    } catch (e, st) {
      debugPrint('refreshHistoricoPanel ($churchId): $e\n$st');
      notifier.value = notifier.value.copyWith(
        loading: false,
        error: e.toString(),
      );
    }
  }

  static Future<void> loadMoreHistoricoPanel(String tenantHint) async {
    final notifier = historicoNotifier(tenantHint);
    if (notifier.value.loading || !notifier.value.hasMore) return;
    final next = (notifier.value.loadedLimit + kHistoricoPageSize)
        .clamp(kHistoricoPageSize, kHistoricoMaxFetch);
    await refreshHistoricoPanel(tenantHint, limit: next, forceRefresh: true);
  }

  /// Query legada (preferir [refreshHistoricoPanel] na UI web/mobile).
  static Query<Map<String, dynamic>> historicoQuery(String tenantHint) {
    return _emitidosCol(tenantHint)
        .orderBy('dataEmissao', descending: true)
        .limit(kHistoricoPageSize);
  }

  static Future<Query<Map<String, dynamic>>> historicoQueryResolved(
    String tenantHint,
  ) async {
    return historicoQuery(_churchId(tenantHint));
  }

  /// Grava protocolo e devolve o [certificadoId] (UUID) para o QR.
  static Future<String> registerEmissao({
    required String tenantId,
    required Map<String, dynamic> snapshot,
    String? certificadoId,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw ArgumentError('tenantId vazio');
    }
    final op = _churchId(tid);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Utilizador não autenticado');
    }
    final id = (certificadoId ?? '').trim();
    final certificadoIdResolved =
        id.isNotEmpty ? id : generateCertificateProtocolId();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    final fp = ChurchDocumentVersionService.fingerprintFromMap(snapshot);
    final existing = snapshot[ChurchDocumentVersionService.pdfPathField];
    final pdfPath = (existing ?? '').toString().trim();
    final version = pdfPath.isNotEmpty
        ? ChurchDocumentVersionService.nextVersion(
            snapshot,
            ChurchDocumentVersionService.pdfVersionField,
          )
        : 1;

    final payload = <String, dynamic>{
      ...snapshot,
      'certificadoId': certificadoIdResolved,
      'tenantId': op,
      'churchId': op,
      'emitidoPorUid': uid,
      'emitidoPorEmail': email,
      'dataEmissao': FieldValue.serverTimestamp(),
      if (pdfPath.isNotEmpty) ...ChurchDocumentVersionService.afterGenerate(
            version: version,
            storagePath: pdfPath,
            fingerprint: fp,
            versionField: ChurchDocumentVersionService.pdfVersionField,
            pathField: ChurchDocumentVersionService.pdfPathField,
          ),
    };

    final batch = firebaseDefaultFirestore.batch();
    batch.set(_emitidosCol(op).doc(certificadoIdResolved), payload);
    batch.set(_protocolIndexDoc(op, certificadoIdResolved), {
      'createdAt': FieldValue.serverTimestamp(),
      'tenantId': op,
      'churchId': op,
    });
    await batch.commit();
    invalidateHistoricoCache(op);
    unawaited(refreshHistoricoPanel(op, forceRefresh: true));
    return certificadoIdResolved;
  }

  /// Várias emissões num único batch (ex.: PDF único em lote).
  static Future<List<String>> registerEmissaoBatch({
    required String tenantId,
    required List<Map<String, dynamic>> snapshots,
    List<String>? certificadoIds,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) throw ArgumentError('tenantId vazio');
    final op = _churchId(tid);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('Utilizador não autenticado');
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (snapshots.isEmpty) return [];

    /// Firestore limita 500 operações por batch; cada emissão = 2 sets.
    const chunkSize = 200;
    final ids = <String>[];
    for (var offset = 0; offset < snapshots.length; offset += chunkSize) {
      final end = offset + chunkSize > snapshots.length
          ? snapshots.length
          : offset + chunkSize;
      final batch = firebaseDefaultFirestore.batch();
      for (var i = offset; i < end; i++) {
        final snapshot = snapshots[i];
        final preset = certificadoIds != null && i < certificadoIds.length
            ? certificadoIds[i].trim()
            : '';
        final certificadoId =
            preset.isNotEmpty ? preset : generateCertificateProtocolId();
        ids.add(certificadoId);
        final payload = <String, dynamic>{
          ...snapshot,
          'certificadoId': certificadoId,
          'tenantId': op,
          'churchId': op,
          'emitidoPorUid': uid,
          'emitidoPorEmail': email,
          'dataEmissao': FieldValue.serverTimestamp(),
        };
        batch.set(_emitidosCol(op).doc(certificadoId), payload);
        batch.set(_protocolIndexDoc(op, certificadoId), {
          'createdAt': FieldValue.serverTimestamp(),
          'tenantId': op,
          'churchId': op,
        });
      }
      await batch.commit();
    }
    invalidateHistoricoCache(op);
    unawaited(refreshHistoricoPanel(op, forceRefresh: true));
    return ids;
  }

  /// Leitura pública (validação QR): índice → documento na igreja; fallback raiz legado.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getPublic(
    String certificadoId,
  ) async {
    final id = certificadoId.trim();
    if (id.isEmpty) {
      return firebaseDefaultFirestore
          .collection('certificados_emitidos')
          .doc('__invalid__')
          .get();
    }

    try {
      final cg = await firebaseDefaultFirestore
          .collectionGroup('certificados_protocol_index')
          .where(FieldPath.documentId, isEqualTo: id)
          .limit(1)
          .get();
      if (cg.docs.isNotEmpty) {
        final idxDoc = cg.docs.first;
        final tid = idxDoc.reference.parent.parent?.id ?? '';
        if (tid.isNotEmpty) {
          final doc = await _emitidosCol(tid).doc(id).get();
          if (doc.exists) return doc;
        }
      }
    } catch (e) {
      debugPrint('getPublic collectionGroup index: $e');
    }

    final idxRoot = await firebaseDefaultFirestore
        .collection('certificados_protocol_index')
        .doc(id)
        .get();
    final idxRootData = idxRoot.data();
    if (idxRoot.exists && idxRootData != null) {
      final tid = (idxRootData['tenantId'] ?? idxRootData['churchId'] ?? '')
          .toString()
          .trim();
      if (tid.isNotEmpty) {
        final doc = await _emitidosCol(tid).doc(id).get();
        if (doc.exists) return doc;
      }
    }

    return firebaseDefaultFirestore.collection('certificados_emitidos').doc(id).get();
  }

  /// Reemissão no painel: leitura directa em `igrejas/{churchId}/certificados_emitidos`.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getForTenant(
    String tenantId,
    String certificadoId,
  ) async {
    final id = certificadoId.trim();
    final tid = tenantId.trim();
    if (id.isEmpty || tid.isEmpty) {
      return firebaseDefaultFirestore
          .collection('certificados_emitidos')
          .doc('__invalid__')
          .get();
    }
    final op = _churchId(tid);
    final local = await _emitidosCol(op).doc(id).get();
    if (local.exists) return local;
    return getPublic(id);
  }
}
