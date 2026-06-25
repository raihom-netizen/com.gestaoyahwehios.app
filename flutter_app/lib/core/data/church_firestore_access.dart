import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/performance/firebase_query_audit.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// **Único** gateway Firestore da camada de dados.
///
/// Regras:
/// - Telas **nunca** chamam `FirebaseFirestore.instance` nem `.collection()`.
/// - Listagens de painel: preferir [listOnce] (`.get()`).
/// - [watchQuery] / [watchDocument]: **um** listener por controller; cancelar no dispose.
/// - Web: sem dezenas de `snapshots()` paralelos (INTERNAL ASSERTION SDK 11.x).
abstract final class ChurchFirestoreAccess {
  ChurchFirestoreAccess._();

  static final Map<String, StreamSubscription<dynamic>> _activeWatchers = {};

  static String resolveChurchId([String? hint]) =>
      ChurchContext.resolveChurchId(hint);

  static DocumentReference<Map<String, dynamic>> churchDoc(String churchId) =>
      firebaseDefaultFirestore
          .collection(ChurchDataPaths.rootCollection)
          .doc(churchId.trim());

  static CollectionReference<Map<String, dynamic>> collectionRef(
    String churchId,
    String sub,
  ) =>
      churchDoc(churchId).collection(sub.trim());

  static String collectionPath(String churchId, String sub) =>
      ChurchDataPaths.subcollection(churchId, sub);

  static WriteBatch batch() => firebaseDefaultFirestore.batch();

  static Future<void> _prepareRead() async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
  }

  /// Leitura única — **padrão obrigatório** para listas de módulo (Web/Android/iOS).
  static Future<QuerySnapshot<Map<String, dynamic>>> listOnce({
    required String module,
    required String churchId,
    required String subcollectionName,
    int limit = 120,
    String? cacheKey,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) return const MergedFirestoreQuerySnapshot([]);
    final capped = FirebasePerformanceLimits.capListLimit(subcollectionName, limit);
    await _prepareRead();
    final path = collectionPath(id, subcollectionName);
    final key = cacheKey ?? 'data_${id}_${subcollectionName}_$capped';
    final sw = Stopwatch()..start();
    try {
      final snap = await ChurchModuleFirestoreAudit.traceQuery(
        module: module,
        churchId: id,
        path: path,
        run: () => FirestoreWebGuard.runWithWebRecovery(
          () => FirestoreReadResilience.getQuery(
            ChurchFirestoreAccess
                .collectionRef(id, subcollectionName)
                .limit(capped),
            cacheKey: key,
            maxAttempts: kIsWeb ? 2 : 3,
            attemptTimeout: ChurchPanelReadTimeouts.attempt,
          ),
          maxAttempts: kIsWeb ? 2 : 2,
        ),
      ).timeout(ChurchPanelReadTimeouts.queryCap);
      FirebaseQueryAudit.record(
        module: module,
        path: path,
        kind: 'list',
        durationMs: sw.elapsedMilliseconds,
        docCount: snap.docs.length,
        limit: capped,
      );
      return snap;
    } catch (e) {
      FirebaseQueryAudit.record(
        module: module,
        path: path,
        kind: 'list',
        durationMs: sw.elapsedMilliseconds,
        limit: capped,
        error: '$e',
      );
      rethrow;
    }
  }

  /// Contagem agregada — auditoria (sequencial na Web, sem paralelismo).
  static Future<int> countOnce({
    required String module,
    required String churchId,
    required String subcollectionName,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) return 0;
    await _prepareRead();
    final path = collectionPath(id, subcollectionName);
    return ChurchModuleFirestoreAudit.traceQuery(
      module: module,
      churchId: id,
      path: path,
      run: () => FirestoreWebGuard.runWithWebRecovery(
        () async {
          final snap = await collectionRef(id, subcollectionName)
              .count()
              .get();
          return snap.count ?? 0;
        },
        maxAttempts: kIsWeb ? 3 : 2,
      ),
    );
  }

  /// Documento único — `.get()` com retry.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getDocument({
    required String module,
    required String churchId,
    required String subcollectionName,
    required String docId,
    String? cacheKey,
  }) async {
    final id = churchId.trim();
    await _prepareRead();
    final path = '${collectionPath(id, subcollectionName)}/$docId';
    return ChurchModuleFirestoreAudit.traceQuery(
      module: module,
      churchId: id,
      path: path,
      run: () => FirestoreWebGuard.runWithWebRecovery(
        () => FirestoreReadResilience.getDocument(
          collectionRef(id, subcollectionName).doc(docId),
          cacheKey: cacheKey ?? 'data_doc_${id}_${subcollectionName}_$docId',
        ),
        maxAttempts: kIsWeb ? 4 : 2,
      ),
    );
  }

  /// Doc raiz `igrejas/{churchId}`.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getChurchRoot({
    required String churchId,
  }) async {
    final id = churchId.trim();
    await _prepareRead();
    return ChurchModuleFirestoreAudit.traceQuery(
      module: 'Cadastro Igreja',
      churchId: id,
      path: ChurchDataPaths.churchRoot(id),
      run: () => FirestoreWebGuard.runWithWebRecovery(
        () => firestoreDocumentGetReliable(churchDoc(id)),
        maxAttempts: kIsWeb ? 4 : 2,
      ),
    );
  }

  static Future<void> setDocument({
    required String module,
    required String churchId,
    required String subcollectionName,
    required String docId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
    final ref = collectionRef(churchId, subcollectionName).doc(docId);
    final payload = ChurchTenantFields.stamp(
      churchId.trim(),
      Map<String, dynamic>.from(data),
    );
    await ChurchModuleFirestoreAudit.traceQuery(
      module: module,
      churchId: churchId,
      path: ref.path,
      run: () => ref.set(payload, SetOptions(merge: merge)),
    );
  }

  static Future<void> addDocument({
    required String module,
    required String churchId,
    required String subcollectionName,
    required Map<String, dynamic> data,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
    final col = collectionRef(churchId, subcollectionName);
    final payload = ChurchTenantFields.stamp(
      churchId.trim(),
      Map<String, dynamic>.from(data),
    );
    await ChurchModuleFirestoreAudit.traceQuery(
      module: module,
      churchId: churchId,
      path: col.path,
      run: () => col.add(payload),
    );
  }

  static Future<void> deleteDocument({
    required String module,
    required String churchId,
    required String subcollectionName,
    required String docId,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
    }
    final ref = collectionRef(churchId, subcollectionName).doc(docId);
    await ChurchModuleFirestoreAudit.traceQuery(
      module: module,
      churchId: churchId,
      path: ref.path,
      run: () => ref.delete(),
    );
  }

  /// Listener único por [watchKey] — cancelar com [cancelWatch] no dispose.
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchQuery({
    required String watchKey,
    required String module,
    required String churchId,
    required String subcollectionName,
    required void Function(QuerySnapshot<Map<String, dynamic>> snap) onData,
    void Function(Object error)? onError,
    int limit = 120,
  }) {
    cancelWatch(watchKey);
    final id = churchId.trim();
    final query = collectionRef(id, subcollectionName).limit(limit);
    Stream<QuerySnapshot<Map<String, dynamic>>> stream;
    if (kIsWeb) {
      // Web: polling leve via one-shot reemitido — evita snapshots() no painel.
      stream = _webPollingStream(
        watchKey: watchKey,
        fetch: () => listOnce(
          module: module,
          churchId: id,
          subcollectionName: subcollectionName,
          limit: limit,
        ),
      );
    } else {
      stream = query.snapshots();
    }
    final sub = stream.listen(
      onData,
      onError: (e) {
        debugPrint('ChurchFirestoreAccess.watch[$watchKey]: $e');
        onError?.call(e);
      },
    );
    _activeWatchers[watchKey] = sub;
    return sub;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _webPollingStream({
    required String watchKey,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() fetch,
  }) async* {
    while (true) {
      try {
        yield await fetch();
      } catch (e) {
        debugPrint('ChurchFirestoreAccess.poll[$watchKey]: $e');
        yield const MergedFirestoreQuerySnapshot([]);
      }
      await Future<void>.delayed(const Duration(seconds: 8));
    }
  }

  static void cancelWatch(String watchKey) {
    final sub = _activeWatchers.remove(watchKey);
    if (sub != null) unawaited(sub.cancel());
  }

  static void cancelAllWatches() {
    for (final key in _activeWatchers.keys.toList()) {
      cancelWatch(key);
    }
  }

  static int get activeWatchCount => _activeWatchers.length;
}
