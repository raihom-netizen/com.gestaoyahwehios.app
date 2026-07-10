import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leituras Firestore estáveis (padrão Controle Total): cache local → rede com retry → último snapshot bom.
class FirestoreReadResilience {
  FirestoreReadResilience._();

  static Source _networkSourceForPlatform() =>
      kIsWeb ? Source.server : Source.serverAndCache;

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
        s.contains('persistentlistenstream') ||
        s.contains('target id already exists') ||
        s.contains('already-exists');
  }

  static final Map<String, DocumentSnapshot<Map<String, dynamic>>>
      _lastDocByKey = {};

  /// Documento único (ex.: `igrejas/{id}`) — cache → rede com retry.
  /// Cache hit: devolve já + refresh em background (cadastro/painel rápidos).
  static Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
    DocumentReference<Map<String, dynamic>> ref, {
    required String cacheKey,
    int maxAttempts = 3,
    Duration? attemptTimeout,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final perAttempt = attemptTimeout ??
        (kIsWeb ? const Duration(seconds: 12) : const Duration(seconds: 16));
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

    if (localSnap != null && localSnap.exists) {
      _refreshDocumentInBackground(
        ref,
        cacheKey: key,
        attemptTimeout: perAttempt,
      );
      return localSnap;
    }

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 220 + attempt * 280),
          );
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: false);
          if (kIsWeb && attempt >= 1) {
            try {
              await FirestoreWebGuard.recoverFirestoreWebSession(
                allowHardReconnect: attempt >= 2 &&
                    lastError != null &&
                    (FirestoreWebGuard.isClientTerminated(lastError!) ||
                        FirestoreWebGuard.isInternalAssertionError(lastError!)),
              );
            } catch (_) {}
          }
        }
        final snap = await ref
            .get(GetOptions(source: _networkSourceForPlatform()))
            .timeout(perAttempt);
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

  static final Set<String> _bgDocRefreshInFlight = {};

  static void _refreshDocumentInBackground(
    DocumentReference<Map<String, dynamic>> ref, {
    required String cacheKey,
    required Duration attemptTimeout,
  }) {
    final key = cacheKey.trim();
    if (key.isEmpty || _bgDocRefreshInFlight.contains(key)) return;
    _bgDocRefreshInFlight.add(key);
    Future<void>(() async {
      try {
        final snap = await ref
            .get(GetOptions(source: _networkSourceForPlatform()))
            .timeout(attemptTimeout);
        if (snap.exists) {
          _lastDocByKey[key] = snap;
        }
      } catch (_) {
      } finally {
        _bgDocRefreshInFlight.remove(key);
      }
    });
  }

  /// [cacheKey] identifica o tenant/coleção para reutilizar o último resultado em falha de rede.
  ///
  /// Controle Total / SWR: se o cache local já tem docs, devolve **já** e actualiza
  /// a rede em background (evita bloquear Agenda/Membros/Eventos na Web).
  static Future<QuerySnapshot<Map<String, dynamic>>> getQuery(
    Query<Map<String, dynamic>> query, {
    required String cacheKey,
    int maxAttempts = kIsWeb ? 2 : 5,
    Duration? attemptTimeout,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final perAttempt =
        attemptTimeout ?? ChurchPanelReadTimeouts.attempt;
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

    // Cache hit → UI imediata; rede em background (padrão Membros / Controle Total).
    if (localSnap != null && localSnap.docs.isNotEmpty) {
      _refreshQueryInBackground(
        query,
        cacheKey: key,
        attemptTimeout: perAttempt,
      );
      return localSnap;
    }

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 220 + attempt * 280),
          );
          await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: false);
          if (kIsWeb && attempt >= 1) {
            try {
              await FirestoreWebGuard.recoverFirestoreWebSession(
                allowHardReconnect: attempt >= 2 &&
                    lastError != null &&
                    (FirestoreWebGuard.isClientTerminated(lastError!) ||
                        FirestoreWebGuard.isInternalAssertionError(lastError!)),
              );
            } catch (_) {}
          }
        }
        final snap = await query
            .get(GetOptions(source: _networkSourceForPlatform()))
            .timeout(perAttempt);
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

  static final Set<String> _bgRefreshInFlight = {};

  static void _refreshQueryInBackground(
    Query<Map<String, dynamic>> query, {
    required String cacheKey,
    required Duration attemptTimeout,
  }) {
    final key = cacheKey.trim();
    if (key.isEmpty || _bgRefreshInFlight.contains(key)) return;
    _bgRefreshInFlight.add(key);
    Future<void>(() async {
      try {
        final snap = await query
            .get(GetOptions(source: _networkSourceForPlatform()))
            .timeout(attemptTimeout);
        if (snap.docs.isNotEmpty) {
          _lastGoodByKey[key] = snap;
        }
      } catch (_) {
        // Silencioso — UI já tem cache.
      } finally {
        _bgRefreshInFlight.remove(key);
      }
    });
  }

  /// Último snapshot bom em memória (web/mobile) — exibir feed enquanto a rede atualiza.
  static QuerySnapshot<Map<String, dynamic>>? peekLastGoodQuery(
    String cacheKey,
  ) {
    final key = cacheKey.trim();
    if (key.isEmpty) return null;
    final mem = _lastGoodByKey[key];
    if (mem != null && mem.docs.isNotEmpty) return mem;
    return null;
  }

  static void forgetKey(String cacheKey) {
    _lastGoodByKey.remove(cacheKey.trim());
  }
}
