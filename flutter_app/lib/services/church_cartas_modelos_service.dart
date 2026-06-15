import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Modelos de cartas — `igrejas/{churchId}/cartas_modelos` (máx. 100).
abstract final class ChurchCartasModelosService {
  ChurchCartasModelosService._();

  static const int kMaxModelos = 100;
  static const int kHistoryFetchLimit = 320;

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static CollectionReference<Map<String, dynamic>> modelosCol(String churchId) =>
      ChurchUiCollections.cartasModelos(churchId);

  static CollectionReference<Map<String, dynamic>> historicoCol(String churchId) =>
      ChurchUiCollections.transferencias(churchId);

  static DateTime? _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['updatedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static DateTime? _updatedAt(Map<String, dynamic> data) {
    final raw = data['updatedAt'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByUpdatedDesc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _updatedAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _updatedAt(b.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return sorted;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortByCreatedDesc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final ta = _createdAt(a.data()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = _createdAt(b.data()) ??
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

  /// Histórico — leitura resiliente (orderBy + fallback plain).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadHistorico({
    required String seedTenantId,
  }) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) {
      throw StateError('Igreja não identificada.');
    }
    await _ensureWebReady();
    final ref = historicoCol(churchId);
    try {
      return await FirestoreWebGuard.runWithWebRecovery(() async {
        try {
          final snap = await ref
              .orderBy('createdAt', descending: true)
              .limit(kHistoryFetchLimit)
              .get(const GetOptions(source: Source.serverAndCache));
          return snap.docs;
        } catch (e) {
          debugPrint('cartas historico orderBy fallback: $e');
          final snap = await ref
              .limit(kHistoryFetchLimit)
              .get(const GetOptions(source: Source.serverAndCache));
          return _sortByCreatedDesc(snap.docs);
        }
      }, maxAttempts: 4);
    } catch (e, st) {
      debugPrint('cartas historico load: $e\n$st');
      rethrow;
    }
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchHistorico(String seedTenantId) async* {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) {
      throw StateError('Igreja não identificada.');
    }
    await _ensureWebReady();
    final ref = historicoCol(churchId);
    final ordered =
        ref.orderBy('createdAt', descending: true).limit(kHistoryFetchLimit);

    await for (final snap in ordered.watchBootstrap()) {
      if (snap.docs.isNotEmpty) {
        yield snap.docs;
        continue;
      }
      yield await loadHistorico(seedTenantId: seedTenantId);
    }
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filterHistoricoByRange({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    return docs.where((d) {
      final ts = d.data()['createdAt'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return !dt.isBefore(rangeStart) && !dt.isAfter(rangeEnd);
    }).toList();
  }

  /// Modelos — stream reativo por tipo de carta.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadModelos({
    required String seedTenantId,
    String? kind,
  }) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) return const [];
    await _ensureWebReady();
    final ref = modelosCol(churchId);
    try {
      return await FirestoreWebGuard.runWithWebRecovery(() async {
        try {
          final snap = await ref
              .orderBy('updatedAt', descending: true)
              .limit(kMaxModelos)
              .get(const GetOptions(source: Source.serverAndCache));
          var docs = snap.docs;
          if (kind != null && kind.trim().isNotEmpty) {
            docs = docs
                .where((d) => (d.data()['kind'] ?? '').toString() == kind)
                .toList();
          }
          return docs;
        } catch (e) {
          debugPrint('cartas modelos orderBy fallback: $e');
          final snap = await ref
              .limit(kMaxModelos)
              .get(const GetOptions(source: Source.serverAndCache));
          var docs = _sortByUpdatedDesc(snap.docs);
          if (kind != null && kind.trim().isNotEmpty) {
            docs = docs
                .where((d) => (d.data()['kind'] ?? '').toString() == kind)
                .toList();
          }
          return docs;
        }
      }, maxAttempts: 4);
    } catch (e, st) {
      debugPrint('cartas modelos load: $e\n$st');
      rethrow;
    }
  }

  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchModelos(
    String seedTenantId,
    String kind,
  ) async* {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) {
      yield const [];
      return;
    }
    await _ensureWebReady();
    final ref = modelosCol(churchId);
    final filtered = ref
        .where('kind', isEqualTo: kind)
        .orderBy('updatedAt', descending: true)
        .limit(kMaxModelos);

    await for (final snap in filtered.watchBootstrap()) {
      if (snap.docs.isNotEmpty) {
        yield snap.docs;
        continue;
      }
      yield await loadModelos(seedTenantId: seedTenantId, kind: kind);
    }
  }

  static Future<int> countModelos(String seedTenantId) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) return 0;
    await _ensureWebReady();
    final snap = await FirestoreWebGuard.runWithWebRecovery(
      () => modelosCol(churchId).limit(kMaxModelos + 1).get(
            const GetOptions(source: Source.serverAndCache),
          ),
      maxAttempts: 3,
    );
    return snap.docs.length;
  }

  static Future<String> saveModelo({
    required String seedTenantId,
    required Map<String, dynamic> payload,
    String? docId,
  }) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) {
      throw StateError('Igreja não identificada.');
    }
    await _ensureWebReady();
    if (docId == null || docId.trim().isEmpty) {
      final total = await countModelos(seedTenantId);
      if (total >= kMaxModelos) {
        throw StateError(
          'Limite de $kMaxModelos modelos atingido. Exclua modelos antigos antes de guardar outro.',
        );
      }
    }
    final data = Map<String, dynamic>.from(payload)
      ..['churchId'] = churchId
      ..['updatedAt'] = FieldValue.serverTimestamp();
    if (docId == null || docId.trim().isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    final ref = docId != null && docId.trim().isNotEmpty
        ? modelosCol(churchId).doc(docId.trim())
        : modelosCol(churchId).doc();
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.set(data, SetOptions(merge: true)),
      maxAttempts: 4,
    );
    return ref.id;
  }

  static Future<void> deleteModelo({
    required String seedTenantId,
    required String docId,
  }) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty) return;
    await _ensureWebReady();
    await FirestoreWebGuard.runWithWebRecovery(
      () => modelosCol(churchId).doc(docId.trim()).delete(),
      maxAttempts: 4,
    );
  }

  /// Migra favoritos legados em `config/cartas.modelosNuvem` → subcoleção.
  static Future<void> migrateLegacyFromConfig({
    required String seedTenantId,
    required Map<String, dynamic> modelosNuvem,
  }) async {
    final churchId = resolveChurchId(seedTenantId);
    if (churchId.isEmpty || modelosNuvem.isEmpty) return;
    final existing = await countModelos(seedTenantId);
    if (existing > 0) return;

    const keys = ['apresentacao', 'transferencia', 'agradecimento'];
    for (final kind in keys) {
      final list = modelosNuvem[kind];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final texto = (m['texto'] ?? '').toString().trim();
        if (texto.isEmpty) continue;
        try {
          final total = await countModelos(seedTenantId);
          if (total >= kMaxModelos) return;
          await saveModelo(
            seedTenantId: seedTenantId,
            payload: {
              'kind': kind,
              'nome': (m['nome'] ?? 'Modelo').toString().trim(),
              'texto': texto,
              'favorito': m['favorito'] == true,
            },
          );
        } catch (_) {}
      }
    }
  }
}
