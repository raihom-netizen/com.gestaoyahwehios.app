import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Utilitários para streams Firestore — evita crash «Bad state: Stream has already
/// been listened to» e reduz ruído em Crashlytics por `permission-denied` transitório.
class FirestoreStreamUtils {
  FirestoreStreamUtils._();

  static bool isPermissionDenied(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    final s = error.toString().toLowerCase();
    return s.contains('permission-denied') || s.contains('permission_denied');
  }

  /// Permite vários [StreamBuilder] no mesmo stream (ex.: departamentos no dashboard).
  static Stream<QuerySnapshot<Map<String, dynamic>>> broadcastQuery(
    Stream<QuerySnapshot<Map<String, dynamic>>> source,
  ) {
    return source.asBroadcastStream();
  }

  /// Em `permission-denied`, emite snapshot vazio em vez de derrubar o painel.
  static Stream<QuerySnapshot<Map<String, dynamic>>> resilientQuery(
    Stream<QuerySnapshot<Map<String, dynamic>>> source, {
    bool broadcast = true,
  }) {
    final wired = source.transform<QuerySnapshot<Map<String, dynamic>>>(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) => sink.add(data),
        handleError: (error, stackTrace, sink) {
          if (isPermissionDenied(error)) {
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
          if (isPermissionDenied(error)) {
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
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(force);
    } catch (_) {}
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
