import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Escritas Firestore offline-first (mobile): aceita na fila local e não espera o servidor.
///
/// Padrão alinhado a [ScaleEntrySaveService] / Financeiro — evita timeout/erro
/// quando não há internet; ao reconectar, `waitForPendingWrites` + sync do shell.
class FirestoreOfflineWrite {
  FirestoreOfflineWrite._();

  static const Duration kLocalWait = Duration(milliseconds: 2200);

  /// `set` com timeout curto; em timeout/erro, enfileira sem bloquear a UI.
  static Future<void> set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    SetOptions? options,
    Duration localWait = kLocalWait,
  }) async {
    try {
      await ref.set(data, options).timeout(localWait);
    } on TimeoutException {
      unawaited(ref.set(data, options));
    } catch (_) {
      unawaited(ref.set(data, options));
    }
  }

  /// `update` offline-first.
  static Future<void> update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    Duration localWait = kLocalWait,
  }) async {
    try {
      await ref.update(data).timeout(localWait);
    } on TimeoutException {
      unawaited(ref.update(data));
    } catch (_) {
      unawaited(ref.update(data));
    }
  }

  /// `delete` offline-first.
  static Future<void> delete(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration localWait = kLocalWait,
  }) async {
    try {
      await ref.delete().timeout(localWait);
    } on TimeoutException {
      unawaited(ref.delete());
    } catch (_) {
      unawaited(ref.delete());
    }
  }

  /// `add` com ID estável (doc gerado localmente) — melhor para fila offline.
  static Future<DocumentReference<Map<String, dynamic>>> add(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data, {
    Duration localWait = kLocalWait,
  }) async {
    final ref = col.doc();
    await set(ref, data, localWait: localWait);
    return ref;
  }

  /// Commit de batch com fallback por documento (set/update/delete).
  static Future<void> commitBatch(
    WriteBatch batch, {
    required List<FirestoreOfflineBatchOp> ops,
    Duration localWait = kLocalWait,
  }) async {
    if (ops.isEmpty) return;
    try {
      await batch.commit().timeout(localWait);
      return;
    } on TimeoutException {
      // Fila local — gravação assíncrona por doc.
    } catch (_) {}

    for (final op in ops) {
      switch (op.kind) {
        case FirestoreOfflineBatchKind.set:
          await set(op.ref, op.data!, options: op.setOptions, localWait: localWait);
        case FirestoreOfflineBatchKind.update:
          await update(op.ref, op.data!, localWait: localWait);
        case FirestoreOfflineBatchKind.delete:
          await delete(op.ref, localWait: localWait);
      }
    }
  }

  /// Atalho: vários `set` em fatias (até [batchLimit]).
  static Future<void> setMany({
    required List<({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data})>
        items,
    int batchLimit = 450,
    Duration localWait = kLocalWait,
  }) async {
    if (items.isEmpty) return;
    for (var i = 0; i < items.length; i += batchLimit) {
      final slice = items.skip(i).take(batchLimit).toList();
      final batch = FirebaseFirestore.instance.batch();
      final ops = <FirestoreOfflineBatchOp>[];
      for (final item in slice) {
        batch.set(item.ref, item.data);
        ops.add(FirestoreOfflineBatchOp.set(item.ref, item.data));
      }
      await commitBatch(batch, ops: ops, localWait: localWait);
    }
  }

  /// Atalho: vários `delete` em fatias.
  static Future<void> deleteMany({
    required List<DocumentReference<Map<String, dynamic>>> refs,
    int batchLimit = 450,
    Duration localWait = kLocalWait,
  }) async {
    if (refs.isEmpty) return;
    for (var i = 0; i < refs.length; i += batchLimit) {
      final slice = refs.skip(i).take(batchLimit).toList();
      final batch = FirebaseFirestore.instance.batch();
      final ops = <FirestoreOfflineBatchOp>[];
      for (final ref in slice) {
        batch.delete(ref);
        ops.add(FirestoreOfflineBatchOp.delete(ref));
      }
      await commitBatch(batch, ops: ops, localWait: localWait);
    }
  }

  /// Atalho: vários `update` em fatias.
  static Future<void> updateMany({
    required List<({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data})>
        items,
    int batchLimit = 450,
    Duration localWait = kLocalWait,
  }) async {
    if (items.isEmpty) return;
    for (var i = 0; i < items.length; i += batchLimit) {
      final slice = items.skip(i).take(batchLimit).toList();
      final batch = FirebaseFirestore.instance.batch();
      final ops = <FirestoreOfflineBatchOp>[];
      for (final item in slice) {
        batch.update(item.ref, item.data);
        ops.add(FirestoreOfflineBatchOp.update(item.ref, item.data));
      }
      await commitBatch(batch, ops: ops, localWait: localWait);
    }
  }
}

enum FirestoreOfflineBatchKind { set, update, delete }

class FirestoreOfflineBatchOp {
  const FirestoreOfflineBatchOp._(this.kind, this.ref, this.data, this.setOptions);

  factory FirestoreOfflineBatchOp.set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    SetOptions? options,
  }) =>
      FirestoreOfflineBatchOp._(FirestoreOfflineBatchKind.set, ref, data, options);

  factory FirestoreOfflineBatchOp.update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) =>
      FirestoreOfflineBatchOp._(FirestoreOfflineBatchKind.update, ref, data, null);

  factory FirestoreOfflineBatchOp.delete(DocumentReference<Map<String, dynamic>> ref) =>
      FirestoreOfflineBatchOp._(FirestoreOfflineBatchKind.delete, ref, null, null);

  final FirestoreOfflineBatchKind kind;
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic>? data;
  final SetOptions? setOptions;
}
