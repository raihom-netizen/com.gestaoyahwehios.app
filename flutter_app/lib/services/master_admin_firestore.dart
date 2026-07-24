import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leituras e gravações estáveis do **Painel Master** (Firestore Web 11.x).
///
/// Todas as telas admin devem usar este serviço em vez de `FirebaseFirestore.instance` directo.
abstract final class MasterAdminFirestore {
  MasterAdminFirestore._();

  static FirebaseFirestore get db => firebaseDefaultFirestore;

  /// Listagem agregada de igrejas (painel master — não confundir com tenant do painel igreja).
  static Query<Map<String, dynamic>> churchesQuery({int? limit}) {
    Query<Map<String, dynamic>> q = db.collection('igrejas');
    if (limit != null) q = q.limit(limit);
    return q;
  }

  /// Arranque / troca de aba — rede pronta; token force só em gravação.
  static Future<void> ensureReady({bool refreshAuth = false}) async {
    if (refreshAuth) {
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: false);
    }
    await FirestoreWebGuard.ensureMasterPanelReady();
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> query(
    Query<Map<String, dynamic>> q, {
    required String cacheKey,
    int maxAttempts = 3,
  }) async {
    await ensureReady();
    // Sem runWithWebRecovery — getQuery já recupera; duplo retry piora assert Web.
    try {
      return await FirestoreReadResilience.getQuery(
        q,
        cacheKey: cacheKey,
        maxAttempts: maxAttempts.clamp(1, 3),
      );
    } catch (e) {
      if (FirestoreWebGuard.isTransientPanelReadError(e)) {
        final mem = FirestoreReadResilience.peekLastGoodQuery(cacheKey);
        if (mem != null) return mem;
        return const MergedFirestoreQuerySnapshot([]);
      }
      rethrow;
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> document(
    DocumentReference<Map<String, dynamic>> ref, {
    required String cacheKey,
    Source source = Source.serverAndCache,
  }) async {
    await ensureReady();
    try {
      return await ref
          .get(GetOptions(source: source))
          .timeout(const Duration(seconds: 18));
    } catch (e) {
      if (FirestoreWebGuard.isInternalAssertionError(e) ||
          FirestoreWebGuard.isClientTerminated(e) ||
          FirestoreWebGuard.isTransientPanelReadError(e)) {
        return FirestoreReadResilience.getDocument(
          ref,
          cacheKey: cacheKey,
        );
      }
      rethrow;
    }
  }

  static Future<T> write<T>(Future<T> Function() fn) async {
    await FirestoreWebGuard.prepareForPublishWrite();
    return FirestoreWebGuard.runWithWebRecovery(fn, maxAttempts: 4);
  }

  /// Stream resiliente para `StreamBuilder` no painel master (web).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchQuery(
    Query<Map<String, dynamic>> query, {
    bool broadcast = false,
  }) async* {
    await ensureReady();
    yield* FirestoreStreamUtils.queryWatchSafe(query, broadcast: broadcast);
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchDocument(
    DocumentReference<Map<String, dynamic>> ref, {
    bool broadcast = false,
  }) async* {
    await ensureReady();
    yield* FirestoreStreamUtils.documentWatchSafe(ref, broadcast: broadcast);
  }

  /// Mensagem amigável para UI (sem stack trace gigante).
  static String formatLoadError(Object e) =>
      formatFirebaseErrorForUser(e, logToCrashlytics: false);
}
