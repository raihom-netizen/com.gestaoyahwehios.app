import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firestore_retry.dart';
import 'firestore_web_guard.dart';

/// Leituras `.get()` na mesma coleção com `snapshots()` ativos — na Web o SDK pode
/// disparar `INTERNAL ASSERTION` no agregador de watch (Controle Total).
Future<QuerySnapshot<Map<String, dynamic>>> firestoreQueryGetReliable(
  Query<Map<String, dynamic>> query,
) {
  return runFirestoreWithRetry(() async {
    final sources = kIsWeb
        ? <Source>[Source.serverAndCache, Source.server]
        : <Source>[Source.server];

    Object? lastError;
    for (final src in sources) {
      for (var attempt = 0; attempt < 6; attempt++) {
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
  return runFirestoreWithRetry(() async {
    final sources = kIsWeb
        ? <Source>[Source.serverAndCache, Source.server]
        : <Source>[Source.server];

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
