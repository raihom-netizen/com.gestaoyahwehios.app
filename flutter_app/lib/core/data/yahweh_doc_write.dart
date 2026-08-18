import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/utils/firestore_rest_read.dart'
    show firestoreRestDeleteDoc, firestoreRestSetDoc, firestoreRestUpdateDoc;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Escrita de documento à prova do SDK web envenenado.
///
/// O Firestore JS 12.x derruba o cliente inteiro com
/// `INTERNAL ASSERTION FAILED: Unexpected state` (WatchChangeAggregator /
/// PersistentListenStream). Depois disso **qualquer** `set/update/delete` do
/// SDK falha — e o módulo parece "não grava", "não exclui", "não edita".
///
/// Aqui a web grava por REST (canal `:commit`, imune à assertion) e só cai no
/// SDK se o REST falhar; no mobile/desktop segue o SDK normal com recuperação.
abstract final class YahwehDocWrite {
  YahwehDocWrite._();

  /// `set(..., merge: true)` por omissão — o padrão do sistema.
  static Future<void> set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    if (kIsWeb) {
      try {
        if (merge) {
          await firestoreRestUpdateDoc(ref.path, setFields: data);
        } else {
          await firestoreRestSetDoc(ref.path, data);
        }
        return;
      } catch (_) {
        // Cai no SDK (offline/fila local ou falha de rede no REST).
      }
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.set(data, SetOptions(merge: merge)),
      maxAttempts: 3,
    );
  }

  static Future<void> update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb) {
      try {
        await firestoreRestUpdateDoc(ref.path, setFields: data);
        return;
      } catch (_) {}
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.update(data),
      maxAttempts: 3,
    );
  }

  static Future<void> delete(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    if (kIsWeb) {
      try {
        await firestoreRestDeleteDoc(ref.path);
        return;
      } catch (_) {}
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.delete(),
      maxAttempts: 3,
    );
  }

  /// `collection.add(...)` — gera o id no cliente e grava pelo caminho seguro.
  static Future<DocumentReference<Map<String, dynamic>>> add(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data,
  ) async {
    final ref = col.doc();
    await set(ref, data, merge: false);
    return ref;
  }
}
