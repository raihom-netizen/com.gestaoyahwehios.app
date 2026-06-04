import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Utilitários para streams Firestore — evita crash «Bad state: Stream has already
/// been listened to» e reduz ruído em Crashlytics por `permission-denied` transitório.
class FirestoreStreamUtils {
  FirestoreStreamUtils._();

  static bool isStreamAlreadyListened(Object error) {
    final s = error.toString().toLowerCase();
    return s.contains('stream has already been listened') ||
        (s.contains('bad state') && s.contains('listened'));
  }

  static bool isPermissionDenied(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    final s = error.toString().toLowerCase();
    return s.contains('permission-denied') || s.contains('permission_denied');
  }

  /// Rede instável / Firestore temporariamente indisponível — não derrubar o painel.
  static bool isTransientNetworkError(Object error) {
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

  /// Permite vários [StreamBuilder] no mesmo stream (ex.: departamentos no dashboard).
  static Stream<QuerySnapshot<Map<String, dynamic>>> broadcastQuery(
    Stream<QuerySnapshot<Map<String, dynamic>>> source,
  ) {
    return source.asBroadcastStream();
  }

  static void _scheduleWebRecovery(Object error) {
    if (!FirestoreWebGuard.isInternalAssertionError(error) &&
        !FirestoreWebGuard.isClientTerminated(error) &&
        !isTransientNetworkError(error)) {
      return;
    }
    unawaited(
      FirestoreWebGuard.recoverFirestoreWebSession(
        allowHardReconnect: FirestoreWebGuard.isInternalAssertionError(error) ||
            FirestoreWebGuard.isClientTerminated(error),
      ),
    );
  }

  /// Emite **uma vez** via `.get()` — painel/chat web sem `snapshots()`.
  static Stream<QuerySnapshot<Map<String, dynamic>>> oneShotQueryFromFuture(
    Future<QuerySnapshot<Map<String, dynamic>>> Function() fetch, {
    bool broadcast = true,
  }) async* {
    try {
      yield await FirestoreWebGuard.runWithWebRecovery(fetch);
    } catch (_) {
      yield const MergedFirestoreQuerySnapshot([]);
    }
  }

  /// Query com 1.º snapshot via `.get()` (cache) — evita spinner infinito na web.
  ///
  /// Web: **só** `.get()` — dezenas de `snapshots()` paralelos disparam
  /// `INTERNAL ASSERTION FAILED` no Firestore JS 11.x.
  static Stream<QuerySnapshot<Map<String, dynamic>>> queryWatchBootstrap(
    Query<Map<String, dynamic>> query, {
    bool broadcast = true,
  }) async* {
    try {
      yield await FirestoreWebGuard.runWithWebRecovery(() async {
        try {
          return await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          return await query.get().timeout(const Duration(seconds: 14));
        }
      });
    } catch (_) {
      yield const MergedFirestoreQuerySnapshot([]);
    }
    if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) return;
    yield* resilientQuery(query.snapshots(), broadcast: broadcast);
  }

  /// Documento com 1.º snapshot via `.get()` — pintura instantânea no painel master.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> documentWatchBootstrap(
    DocumentReference<Map<String, dynamic>> ref, {
    bool broadcast = true,
  }) async* {
    try {
      yield await FirestoreWebGuard.runWithWebRecovery(() async {
        try {
          return await ref
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          return await ref.get().timeout(const Duration(seconds: 14));
        }
      });
    } catch (_) {
      yield _emptyDocumentSnapshot;
    }
    if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) return;
    yield* resilientDocument(ref.snapshots(), broadcast: broadcast);
  }

  /// Em falha transitória, emite snapshot vazio e agenda recuperação Web.
  static Stream<QuerySnapshot<Map<String, dynamic>>> resilientQuery(
    Stream<QuerySnapshot<Map<String, dynamic>>> source, {
    bool broadcast = true,
  }) {
    final wired = source.transform<QuerySnapshot<Map<String, dynamic>>>(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          if (isPermissionDenied(error) ||
              isStreamAlreadyListened(error) ||
              isTransientNetworkError(error)) {
            _scheduleWebRecovery(error);
            sink.add(const MergedFirestoreQuerySnapshot([]));
            return;
          }
          sink.addError(error, stackTrace);
        },
      ),
    );
    return broadcast ? wired.asBroadcastStream() : wired;
  }

  /// Documento único (`DocumentReference.snapshots`) — ex.: `_panel_cache`.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> resilientDocument(
    Stream<DocumentSnapshot<Map<String, dynamic>>> source, {
    bool broadcast = true,
  }) {
    final wired = source.transform<DocumentSnapshot<Map<String, dynamic>>>(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          if (isPermissionDenied(error) ||
              isStreamAlreadyListened(error) ||
              isTransientNetworkError(error)) {
            _scheduleWebRecovery(error);
            sink.add(_emptyDocumentSnapshot);
            return;
          }
          sink.addError(error, stackTrace);
        },
      ),
    );
    return broadcast ? wired.asBroadcastStream() : wired;
  }

  static final DocumentSnapshot<Map<String, dynamic>> _emptyDocumentSnapshot =
      _EmptyDocumentSnapshot();

  /// Atualiza o token JWT antes de queries sensíveis a regras (claims desatualizados).
  static Future<void> refreshAuthTokenIfNeeded({bool force = false}) async {
    await FirebaseAuthTokenGuard.refreshIfStale(force: force);
  }
}

/// Snapshot vazio para fallback UI quando regras bloqueiam leitura momentânea.
class MergedFirestoreQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  const MergedFirestoreQuerySnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => const [];

  @override
  SnapshotMetadata get metadata =>
      docs.isNotEmpty ? docs.first.metadata : const _EmptySnapshotMetadata();

  @override
  int get size => docs.length;
}

class _EmptySnapshotMetadata implements SnapshotMetadata {
  const _EmptySnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;
}

// ignore: subtype_of_sealed_class — placeholder só para permission-denied em cache doc.
class _EmptyDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  Map<String, dynamic>? data() => null;

  @override
  dynamic get(Object field) => null;

  @override
  dynamic operator [](Object field) => null;

  @override
  bool get exists => false;

  @override
  String get id => '';

  @override
  SnapshotMetadata get metadata => const _EmptySnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('empty document snapshot has no reference');
}
