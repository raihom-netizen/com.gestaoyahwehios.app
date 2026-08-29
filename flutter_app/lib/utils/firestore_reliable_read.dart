import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/data/yahweh_rest_first.dart';

import 'firestore_retry.dart';
import 'firestore_rest_read.dart';
import 'firestore_web_guard.dart';

/// Leituras `.get()` na mesma coleção com `snapshots()` ativos — na Web o SDK pode
/// disparar `INTERNAL ASSERTION` no agregador de watch (Controle Total).
Future<QuerySnapshot<Map<String, dynamic>>> firestoreQueryGetReliable(
  Query<Map<String, dynamic>> query,
) {
  return runFirestoreWithRetry(() async {
    // Web: só `Source.server`. Cada `.get()` do SDK JS abre um alvo de listen;
    // `serverAndCache` + 6 tentativas por fonte chegava a 12 alvos numa única
    // leitura falhada — era o que empurrava o targetId para os milhares e
    // rebentava no `WatchChangeAggregator` (INTERNAL ASSERTION).
    final sources = <Source>[Source.server];
    final maxAttempts = kIsWeb ? 2 : 6;

    Object? lastError;
    for (final src in sources) {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          return await query.get(GetOptions(source: src));
        } catch (e) {
          lastError = e;
          if (!FirestoreWebGuard.isInternalAssertionError(e) &&
              !FirestoreWebGuard.isClientTerminated(e)) {
            rethrow;
          }
          if (kIsWeb && attempt >= 1) {
            await FirestoreWebGuard.recoverFirestoreWebSession(
              allowHardReconnect: FirestoreWebGuard.isClientTerminated(e),
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (1 << attempt)),
          );
        }
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  });
}

/// Documento único — mesma blindagem que [firestoreQueryGetReliable] na web.
Future<DocumentSnapshot<Map<String, dynamic>>> firestoreDocumentGetReliable(
  DocumentReference<Map<String, dynamic>> ref,
) {
  // Web/desktop: REST puro — não abre alvo de listen nenhum (ver
  // [[project_web_rest_gateway_total_fix]]).
  if (YahwehRestFirst.prefer) {
    return runFirestoreWithRetry(() => firestoreRestGetDocSnap(ref.path));
  }
  return runFirestoreWithRetry(() async {
    final sources = <Source>[Source.server];

    Object? lastError;
    for (final src in sources) {
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          return await ref.get(GetOptions(source: src));
        } catch (e) {
          lastError = e;
          if (!FirestoreWebGuard.isInternalAssertionError(e) &&
              !FirestoreWebGuard.isClientTerminated(e)) {
            rethrow;
          }
          if (kIsWeb && attempt >= 1) {
            await FirestoreWebGuard.recoverFirestoreWebSession(
              allowHardReconnect: FirestoreWebGuard.isClientTerminated(e),
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 120 * (1 << attempt)),
          );
        }
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  });
}
