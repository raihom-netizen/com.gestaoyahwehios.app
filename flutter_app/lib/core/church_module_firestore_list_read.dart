import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leitura canónica de listas tenant — **Web = Android = iOS**.
///
/// - Path: `igrejas/{churchId}/{subcoleção}` via [CollectionReference] do [ChurchRepository].
/// - **Plain `limit` primeiro** — `orderBy` exclui documentos sem o campo indexado.
/// - Filtro `ativo: true` **no cliente** quando pedido (payload real usa boolean; legado sem campo = activo).
abstract final class ChurchModuleFirestoreListRead {
  ChurchModuleFirestoreListRead._();

  /// Só servir cache Hive quando há documentos — evita Web presa em snapshot vazio obsoleto.
  static bool shouldServeHiveCache(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.isNotEmpty;

  /// Campo de controlo de produção: `ativo: true` / `active: true` (boolean). Sem campo = activo (legado).
  static bool isActiveRecord(Map<String, dynamic> data) {
    if (data.containsKey('active')) {
      final v = data['active'];
      if (v is bool) return v;
      if (v == null) return true;
      final s = v.toString().trim().toLowerCase();
      return s == 'true' || s == '1';
    }
    if (!data.containsKey('ativo')) return true;
    final v = data['ativo'];
    if (v is bool) return v;
    if (v == null) return true;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// Feed mural (avisos/eventos) — `ativo` + `publicado` ou `status: publicado`.
  static bool isPublishedFeedRecord(Map<String, dynamic> data) {
    if (!isActiveRecord(data)) return false;
    if (data.containsKey('publicado')) {
      final pub = data['publicado'];
      if (pub is bool) return pub;
      if (pub == null) return true;
      return pub == true || pub.toString().trim().toLowerCase() == 'true';
    }
    final status = data['status']?.toString().trim().toLowerCase();
    if (status == null || status.isEmpty) return true;
    return status == 'publicado';
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> filterActiveRecords(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.where((d) => isActiveRecord(d.data())).toList(growable: false);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>
      filterPublishedFeedRecords(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.where((d) => isPublishedFeedRecord(d.data())).toList(growable: false);

  /// Query robusta: plain → orderBy (fallback) → plain retry.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryPlainFirst({
    required CollectionReference<Map<String, dynamic>> reference,
    required String cacheKey,
    required int limit,
    bool forceServer = false,
    List<String> legacyFallbackSubcollections = const [],
    String? orderByField,
    bool orderDescending = false,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    )? sortDocs,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Query<Map<String, dynamic>> plain(CollectionReference<Map<String, dynamic>> c) =>
        c.limit(limit);

    Query<Map<String, dynamic>>? ordered(
      CollectionReference<Map<String, dynamic>> c,
    ) {
      final field = orderByField?.trim();
      if (field == null || field.isEmpty) return null;
      return c.orderBy(field, descending: orderDescending).limit(limit);
    }

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> tryRead(
      CollectionReference<Map<String, dynamic>> ref,
      String keyBase,
    ) async {
      if (!forceServer) {
        try {
          final plainCache = await plain(ref)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 3));
          if (plainCache.docs.isNotEmpty) {
            return _finalize(plainCache.docs, sortDocs);
          }
        } catch (_) {}

        final oq = ordered(ref);
        if (oq != null) {
          try {
            final cacheSnap = await oq
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(seconds: 3));
            if (cacheSnap.docs.isNotEmpty) {
              return _finalize(cacheSnap.docs, sortDocs);
            }
          } catch (_) {}
        }
      }

      Future<QuerySnapshot<Map<String, dynamic>>> readServer() async {
        try {
          final plainSnap = await FirestoreReadResilience.getQuery(
            plain(ref),
            cacheKey: '${keyBase}_plain',
            maxAttempts: kIsWeb ? 4 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          );
          if (plainSnap.docs.isNotEmpty) return plainSnap;
        } catch (_) {}

        final oq = ordered(ref);
        if (oq != null) {
          try {
            return await FirestoreReadResilience.getQuery(
              oq,
              cacheKey: keyBase,
              maxAttempts: kIsWeb ? 5 : 3,
              attemptTimeout: ChurchPanelReadTimeouts.attempt,
            );
          } catch (_) {}
        }

        return FirestoreReadResilience.getQuery(
          plain(ref),
          cacheKey: '${keyBase}_plain_retry',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: ChurchPanelReadTimeouts.attempt,
        );
      }

      final snap = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(
              readServer,
              maxAttempts: 3,
            ).timeout(const Duration(seconds: 18))
          : await readServer().timeout(ChurchPanelReadTimeouts.warmCap);
      return _finalize(snap.docs, sortDocs);
    }

    final primaryDocs = await tryRead(reference, cacheKey);
    if (primaryDocs.isNotEmpty || legacyFallbackSubcollections.isEmpty) {
      return primaryDocs;
    }

    final parts = reference.path.split('/');
    if (parts.length < 4 || parts[0] != 'igrejas') {
      return primaryDocs;
    }
    final churchId = parts[1];
    final currentSub = parts[2];
    for (final rawSub in legacyFallbackSubcollections) {
      final sub = rawSub.trim();
      if (sub.isEmpty || sub == currentSub) continue;
      final legacyRef = reference.firestore
          .collection('igrejas')
          .doc(churchId)
          .collection(sub);
      final docs = await tryRead(legacyRef, '${cacheKey}_legacy_$sub');
      if (docs.isNotEmpty) return docs;
    }
    return primaryDocs;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _finalize(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    )? sortDocs,
  ) {
    if (sortDocs == null) return docs;
    return sortDocs(docs);
  }
}
