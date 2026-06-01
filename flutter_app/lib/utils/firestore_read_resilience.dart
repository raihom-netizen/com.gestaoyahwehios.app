import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leituras Firestore estáveis (padrão Controle Total): cache local → rede com retry → último snapshot bom.
class FirestoreReadResilience {
  FirestoreReadResilience._();

  static final Map<String, QuerySnapshot<Map<String, dynamic>>> _lastGoodByKey =
      {};

  static bool isTransient(Object error) {
    if (FirestoreWebGuard.isClientTerminated(error)) return true;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
        case 'aborted':
        case 'cancelled':
        case 'resource-exhausted':
        case 'internal':
        case 'unknown':
          return true;
      }
    }
    if (FirestoreWebGuard.isInternalAssertionError(error)) return true;
    final s = error.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('network') ||
        s.contains('offline') ||
        s.contains('unreachable') ||
        s.contains('connection reset') ||
        s.contains('host lookup') ||
        s.contains('channel-error') ||
        s.contains('client is offline') ||
        s.contains('timeout') ||
        s.contains('internal assertion') ||
        s.contains('unexpected state') ||
        s.contains('watchchangeaggregator') ||
        s.contains('persistentlistenstream');
  }

  static final Map<String, DocumentSnapshot<Map<String, dynamic>>>
      _lastDocByKey = {};

  /// Documento único (ex.: `igrejas/{id}`) — cache → rede com retry.
  static Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
    DocumentReference<Map<String, dynamic>> ref, {
    required String cacheKey,
    int maxAttempts = 3,
    Duration attemptTimeout = const Duration(seconds: 16),
  }) async {
    final key = cacheKey.trim();
    DocumentSnapshot<Map<String, dynamic>>? localSnap;
    try {
      localSnap = await ref
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));
      if (localSnap.exists && key.isNotEmpty) {
        _lastDocByKey[key] = localSnap;
      }
    } catch (_) {}

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 220 + attempt * 280),
          );
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
            force: attempt > 1,
          );
        }
        final snap = await ref.get().timeout(attemptTimeout);
        if (key.isNotEmpty) _lastDocByKey[key] = snap;
        return snap;
      } catch (e) {
        lastError = e;
        if (!isTransient(e)) break;
      }
    }

    if (localSnap != null && localSnap.exists) return localSnap;
    if (key.isNotEmpty) {
      final mem = _lastDocByKey[key];
      if (mem != null && mem.exists) return mem;
    }
    throw lastError ?? StateError('firestore_document_failed');
  }

  /// [cacheKey] identifica o tenant/coleção para reutilizar o último resultado em falha de rede.
  static Future<QuerySnapshot<Map<String, dynamic>>> getQuery(
    Query<Map<String, dynamic>> query, {
    required String cacheKey,
    int maxAttempts = 5,
    Duration attemptTimeout = const Duration(seconds: 22),
  }) async {
    final key = cacheKey.trim();
    QuerySnapshot<Map<String, dynamic>>? localSnap;
    try {
      localSnap = await query
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));
      if (localSnap.docs.isNotEmpty && key.isNotEmpty) {
        _lastGoodByKey[key] = localSnap;
      }
    } catch (_) {}

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 220 + attempt * 280),
          );
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(
            force: attempt > 1,
          );
          if (kIsWeb && attempt >= 1) {
            try {
              await FirestoreWebGuard.recoverFirestoreWebSession(
                allowHardReconnect: attempt >= 2 &&
                    lastError != null &&
                    FirestoreWebGuard.isClientTerminated(lastError!),
              );
            } catch (_) {}
          }
        }
        final snap = kIsWeb
            ? await firestoreQueryGetReliable(query).timeout(attemptTimeout)
            : await query.get().timeout(attemptTimeout);
        if (key.isNotEmpty) _lastGoodByKey[key] = snap;
        return snap;
      } catch (e) {
        lastError = e;
        if (!isTransient(e)) break;
      }
    }

    if (localSnap != null && localSnap.docs.isNotEmpty) return localSnap;
    if (key.isNotEmpty) {
      final mem = _lastGoodByKey[key];
      if (mem != null) return mem;
    }
    throw lastError ?? StateError('firestore_query_failed');
  }

  static void forgetKey(String cacheKey) {
    _lastGoodByKey.remove(cacheKey.trim());
  }
}
